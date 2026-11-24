const { prisma } = require('../../config/database')
const env = require('../../config/env')
const { getRate, round2 } = require('../../utils/rates')
const { expireUnpaidReservations } = require('../../utils/cron')
const { normalizeHotelSettings } = require('../../utils/hotelSettings')
const { emitRealtimeEvent } = require('../../utils/eventBus')
const { z } = require('zod')
const dayjs = require('dayjs')

const EXTENSION_PREFIX = 'EXTENSION_OF:'
const ROOM_SERVICE_PREFIX = 'ROOM_SERVICE_OF:'

function parseRoomServiceNote(notes) {
  if (!notes || typeof notes !== 'string' || !notes.startsWith(ROOM_SERVICE_PREFIX)) {
    return null
  }
  const rest = notes.slice(ROOM_SERVICE_PREFIX.length)
  const sepIdx = rest.indexOf('|')
  if (sepIdx === -1) {
    return { parentReservationId: rest, items: [], guestNote: '' }
  }
  const parentReservationId = rest.slice(0, sepIdx)
  try {
    const parsed = JSON.parse(rest.slice(sepIdx + 1))
    return {
      parentReservationId,
      items: Array.isArray(parsed.items) ? parsed.items : [],
      guestNote: parsed.guestNote || '',
    }
  } catch (_) {
    return { parentReservationId, items: [], guestNote: '' }
  }
}

const createReservationSchema = z.object({
  roomId: z.string().uuid(),
  checkIn: z.string().datetime(),
  durationHours: z.number().int().min(1).max(72),
  gateway: z.enum(['PAGO_MOVIL', 'ZELLE', 'BINANCE_PAY', 'CASH']),
})

const extendReservationSchema = z.object({
  extraHours: z.number().int().min(1).max(24),
  gateway: z.enum(['PAGO_MOVIL', 'ZELLE', 'BINANCE_PAY', 'CASH']).default('PAGO_MOVIL'),
})

const roomServiceOrderSchema = z.object({
  items: z
    .array(
      z.object({
        id: z.string().min(1),
        qty: z.number().int().min(1).max(10).default(1),
      })
    )
    .min(1, 'Selecciona al menos un producto'),
  guestNote: z.string().max(180).optional(),
  gateway: z.enum(['PAGO_MOVIL', 'ZELLE', 'BINANCE_PAY', 'CASH']).default('PAGO_MOVIL'),
})

/**
 * Si existen pagos abiertos simultáneos en el mismo hotel con el mismo monto base en Bs,
 * suma céntimos únicos (+0.01 .. +0.99) para habilitar conciliación "Cero Clics" sin ambigüedad.
 */
async function allocateUniqueAmountVes(tx, hotelId, baseAmountVes) {
  const openPayments = await tx.payment.findMany({
    where: {
      status: { in: ['PENDING', 'PENDING_REVIEW'] },
      OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
      reservation: { room: { hotelId } },
      amountVes: {
        gte: baseAmountVes,
        lte: round2(baseAmountVes + 0.99),
      },
    },
    select: { amountVes: true },
  })

  const usedAmounts = new Set(
    openPayments.map(p => round2(Number(p.amountVes)).toFixed(2))
  )

  for (let cents = 0; cents <= 99; cents++) {
    const candidate = round2(baseAmountVes + cents / 100)
    if (!usedAmounts.has(candidate.toFixed(2))) {
      return candidate
    }
  }

  return baseAmountVes
}

// POST /api/v1/reservations  — el huésped crea una reserva
async function handleCreate(request, reply) {
  const { roomId, checkIn, durationHours, gateway } = createReservationSchema.parse(request.body)

  await expireUnpaidReservations()

  const checkInDate = dayjs(checkIn)
  const checkOutDate = checkInDate.add(durationHours, 'hour')

  const room = await prisma.room.findUnique({
    where: { id: roomId },
    include: { hotel: { select: { id: true, name: true, paymentInfo: true } } },
  })
  if (!room || room.status !== 'AVAILABLE') {
    return reply.status(409).send({ message: 'Habitación no disponible' })
  }

  const totalAmount = durationHours >= 24
    ? Number(room.pricePerNight)
    : Number(room.pricePerHour) * durationHours

  const fallbackRate = room.hotel.paymentInfo?.fallbackExchangeRate
  const exchangeRate = await getRate({ fallbackRate })
  const baseAmountVes = round2(totalAmount * exchangeRate)
  const expiresAt = dayjs().add(env.PAYMENT_HOLD_MINUTES, 'minute').toDate()

  const result = await prisma.$transaction(async (tx) => {
    // Bloqueo pesimista a nivel de fila en PostgreSQL para evitar carreras de reserva simultáneas
    try {
      await tx.$executeRaw`SELECT id FROM rooms WHERE id = ${roomId}::uuid FOR UPDATE`
    } catch (_) {}

    const currentRoom = await tx.room.findUnique({
      where: { id: roomId },
      select: { status: true },
    })
    if (!currentRoom || currentRoom.status !== 'AVAILABLE') {
      const err = new Error('Habitación no disponible')
      err.statusCode = 409
      throw err
    }

    // Verificación atómica de solapamiento dentro de la transacción
    const conflict = await tx.reservation.findFirst({
      where: {
        roomId,
        status: { in: ['ACTIVE', 'PENDING_PAYMENT', 'PAYMENT_PENDING_REVIEW'] },
        OR: [
          { notes: null },
          { NOT: { notes: { startsWith: ROOM_SERVICE_PREFIX } } },
        ],
        AND: [
          { checkIn: { lt: checkOutDate.toDate() } },
          { checkOut: { gt: checkInDate.toDate() } },
        ],
      },
    })

    if (conflict) {
      const err = new Error('La habitación ya está reservada en ese horario')
      err.statusCode = 409
      throw err
    }

    const amountVes = await allocateUniqueAmountVes(tx, room.hotel.id, baseAmountVes)

    const reservation = await tx.reservation.create({
      data: {
        guestId: request.user.id,
        roomId,
        checkIn: checkInDate.toDate(),
        checkOut: checkOutDate.toDate(),
        durationHours,
        totalAmount,
        currency: room.currency,
        status: 'PENDING_PAYMENT',
      },
    })

    const payment = await tx.payment.create({
      data: {
        reservationId: reservation.id,
        gateway,
        amount: totalAmount,
        currency: room.currency,
        amountVes,
        exchangeRate,
        expiresAt,
        status: 'PENDING',
      },
    })

    return { reservation, payment, amountVes }
  })

  emitRealtimeEvent({
    hotelId: room.hotel.id,
    guestId: request.user.id,
    reservationId: result.reservation.id,
    type: 'RESERVATION_CREATED',
    payload: {
      reservationId: result.reservation.id,
      roomName: room.name,
      durationHours,
      totalAmount,
      amountVes: result.amountVes,
    },
  })

  return reply.status(201).send({
    reservationId: result.reservation.id,
    paymentId: result.payment.id,
    totalAmount,
    currency: room.currency,
    amountVes: result.amountVes,
    exchangeRate,
    paymentExpiresAt: expiresAt,
    receptorPagoMovil: room.hotel.paymentInfo,
    checkIn: checkInDate.toDate(),
    checkOut: checkOutDate.toDate(),
    message: 'Reserva creada. Realiza el Pago Móvil por el monto exacto en Bs y se verificará al instante.',
  })
}

// POST /api/v1/reservations/:id/extend  — extender horas de una estadía activa sin salir de la habitación
async function handleExtend(request, reply) {
  const { extraHours, gateway } = extendReservationSchema.parse(request.body)

  await expireUnpaidReservations()

  const parent = await prisma.reservation.findUnique({
    where: { id: request.params.id },
    include: {
      room: {
        include: {
          hotel: { select: { id: true, name: true, paymentInfo: true } },
        },
      },
    },
  })

  if (!parent) {
    return reply.status(404).send({ message: 'Reserva activa no encontrada' })
  }
  if (parent.guestId !== request.user.id) {
    return reply.status(403).send({ message: 'Acceso denegado a esta reserva' })
  }
  if (parent.status !== 'ACTIVE') {
    return reply.status(400).send({ message: 'Solo puedes extender una estadía activa' })
  }

  const extStart = dayjs(parent.checkOut)
  const extEnd = extStart.add(extraHours, 'hour')

  const room = parent.room
  const extraAmountUsd = extraHours >= 24
    ? Number(room.pricePerNight)
    : Number(room.pricePerHour) * extraHours

  const fallbackRate = room.hotel.paymentInfo?.fallbackExchangeRate
  const exchangeRate = await getRate({ fallbackRate })
  const baseAmountVes = round2(extraAmountUsd * exchangeRate)
  const expiresAt = dayjs().add(env.PAYMENT_HOLD_MINUTES, 'minute').toDate()

  const result = await prisma.$transaction(async (tx) => {
    // Bloqueo pesimista a nivel de fila para evitar extensiones o reservas concurrentes solapadas
    try {
      await tx.$executeRaw`SELECT id FROM rooms WHERE id = ${room.id}::uuid FOR UPDATE`
    } catch (_) {}

    // Verificación atómica de solapamiento dentro de la transacción
    const conflict = await tx.reservation.findFirst({
      where: {
        roomId: parent.roomId,
        id: { not: parent.id },
        status: { in: ['ACTIVE', 'PENDING_PAYMENT', 'PAYMENT_PENDING_REVIEW'] },
        OR: [
          { notes: null },
          { NOT: { notes: { startsWith: ROOM_SERVICE_PREFIX } } },
        ],
        AND: [
          { checkIn: { lt: extEnd.toDate() } },
          { checkOut: { gt: extStart.toDate() } },
        ],
      },
    })

    if (conflict) {
      const err = new Error('No es posible extender: existe otra solicitud o reserva en el horario siguiente')
      err.statusCode = 409
      throw err
    }

    const amountVes = await allocateUniqueAmountVes(tx, room.hotel.id, baseAmountVes)

    const extReservation = await tx.reservation.create({
      data: {
        guestId: request.user.id,
        roomId: room.id,
        checkIn: extStart.toDate(),
        checkOut: extEnd.toDate(),
        durationHours: extraHours,
        totalAmount: extraAmountUsd,
        currency: room.currency,
        status: 'PENDING_PAYMENT',
        notes: `${EXTENSION_PREFIX}${parent.id}`,
      },
    })

    const payment = await tx.payment.create({
      data: {
        reservationId: extReservation.id,
        gateway,
        amount: extraAmountUsd,
        currency: room.currency,
        amountVes,
        exchangeRate,
        expiresAt,
        status: 'PENDING',
      },
    })

    return { extReservation, payment, amountVes }
  })

  return reply.status(201).send({
    reservationId: result.extReservation.id,
    parentReservationId: parent.id,
    isExtension: true,
    extraHours,
    paymentId: result.payment.id,
    totalAmount: extraAmountUsd,
    currency: room.currency,
    amountVes: result.amountVes,
    exchangeRate,
    paymentExpiresAt: expiresAt,
    receptorPagoMovil: room.hotel.paymentInfo,
    checkIn: extStart.toDate(),
    checkOut: extEnd.toDate(),
    message: `Extensión de +${extraHours}h iniciada. Transfiere el monto exacto en Bs para ampliar tu llave QR.`,
  })
}

// POST /api/v1/reservations/:id/room-service  — pedido anónimo a la habitación (entrega por esclusa/pasaplatos)
async function handleCreateRoomServiceOrder(request, reply) {
  const { items: requestedItems, guestNote, gateway } = roomServiceOrderSchema.parse(request.body)

  await expireUnpaidReservations()

  const parent = await prisma.reservation.findUnique({
    where: { id: request.params.id },
    include: {
      room: {
        include: {
          hotel: { select: { id: true, name: true, paymentInfo: true, settings: true } },
        },
      },
    },
  })

  if (!parent) {
    return reply.status(404).send({ message: 'Estadía activa no encontrada' })
  }
  if (parent.guestId !== request.user.id) {
    return reply.status(403).send({ message: 'Acceso denegado a esta estadía' })
  }
  if (parent.status !== 'ACTIVE') {
    return reply.status(400).send({ message: 'Solo puedes pedir consumos durante una estadía activa' })
  }

  const settings = normalizeHotelSettings(parent.room.hotel.settings)
  const menuById = new Map(
    settings.roomServiceMenu
      .filter(m => m.available !== false)
      .map(m => [String(m.id), m])
  )

  const resolvedItems = []
  let totalAmountUsd = 0
  for (const reqItem of requestedItems) {
    const found = menuById.get(String(reqItem.id))
    if (!found) {
      return reply.status(400).send({ message: `Producto no disponible: ${reqItem.id}` })
    }
    const unitPrice = round2(Number(found.priceUsd))
    const lineTotal = round2(unitPrice * reqItem.qty)
    totalAmountUsd = round2(totalAmountUsd + lineTotal)
    resolvedItems.push({
      id: found.id,
      name: found.name,
      qty: reqItem.qty,
      unitPriceUsd: unitPrice,
      subtotalUsd: lineTotal,
    })
  }

  const fallbackRate = parent.room.hotel.paymentInfo?.fallbackExchangeRate
  const exchangeRate = await getRate({ fallbackRate })
  const baseAmountVes = round2(totalAmountUsd * exchangeRate)
  const expiresAt = dayjs().add(env.PAYMENT_HOLD_MINUTES, 'minute').toDate()
  const now = new Date()

  const encodedPayload = JSON.stringify({
    items: resolvedItems,
    guestNote: guestNote || '',
  })

  const result = await prisma.$transaction(async (tx) => {
    const amountVes = await allocateUniqueAmountVes(tx, parent.room.hotel.id, baseAmountVes)

    const orderReservation = await tx.reservation.create({
      data: {
        guestId: request.user.id,
        roomId: parent.roomId,
        checkIn: now,
        checkOut: now,
        durationHours: 0,
        totalAmount: totalAmountUsd,
        currency: parent.room.currency,
        status: 'PENDING_PAYMENT',
        notes: `${ROOM_SERVICE_PREFIX}${parent.id}|${encodedPayload}`,
      },
    })

    const payment = await tx.payment.create({
      data: {
        reservationId: orderReservation.id,
        gateway,
        amount: totalAmountUsd,
        currency: parent.room.currency,
        amountVes,
        exchangeRate,
        expiresAt,
        status: 'PENDING',
        metadata: {
          isRoomService: true,
          parentReservationId: parent.id,
          roomName: parent.room.name,
          items: resolvedItems,
          guestNote: guestNote || '',
          deliveryStatus: 'AWAITING_PAYMENT',
        },
      },
    })

    return { orderReservation, payment, amountVes }
  })

  return reply.status(201).send({
    reservationId: result.orderReservation.id,
    parentReservationId: parent.id,
    isRoomService: true,
    items: resolvedItems,
    paymentId: result.payment.id,
    totalAmount: totalAmountUsd,
    currency: parent.room.currency,
    amountVes: result.amountVes,
    exchangeRate,
    paymentExpiresAt: expiresAt,
    receptorPagoMovil: parent.room.hotel.paymentInfo,
    checkIn: parent.checkIn,
    checkOut: parent.checkOut,
    message: 'Pedido discreto creado. Paga el monto exacto en Bs y lo dejaremos en la esclusa/pasaplatos sin tocar tu puerta.',
  })
}

// GET /api/v1/reservations/:id/orders  — pedidos Room Service de una estadía activa
async function handleListRoomServiceOrders(request, reply) {
  const parent = await prisma.reservation.findUnique({
    where: { id: request.params.id },
  })
  if (!parent) return reply.status(404).send({ message: 'Reserva no encontrada' })
  if (parent.guestId !== request.user.id && request.user.role !== 'OWNER') {
    return reply.status(403).send({ message: 'Acceso denegado' })
  }

  const orders = await prisma.reservation.findMany({
    where: {
      notes: { startsWith: `${ROOM_SERVICE_PREFIX}${parent.id}|` },
    },
    include: { payment: true },
    orderBy: { createdAt: 'desc' },
  })

  return reply.send(
    orders.map(o => {
      const parsed = parseRoomServiceNote(o.notes)
      const meta = (o.payment?.metadata && typeof o.payment.metadata === 'object')
        ? o.payment.metadata
        : {}
      return {
        orderId: o.id,
        status: o.status,
        paymentId: o.payment?.id || null,
        paymentStatus: o.payment?.status || 'PENDING',
        deliveryStatus: meta.deliveryStatus || (o.payment?.status === 'APPROVED' ? 'PENDING_DELIVERY' : 'AWAITING_PAYMENT'),
        deliveredAt: meta.deliveredAt || null,
        totalAmount: Number(o.totalAmount),
        amountVes: o.payment?.amountVes ? Number(o.payment.amountVes) : null,
        items: parsed?.items || meta.items || [],
        guestNote: parsed?.guestNote || meta.guestNote || '',
        createdAt: o.createdAt,
      }
    })
  )
}

// PATCH /api/v1/reservations/:orderId/deliver-order  — Camarera u Owner marca pedido dejado en esclusa/pasaplatos
async function handleDeliverRoomServiceOrder(request, reply) {
  const order = await prisma.reservation.findUnique({
    where: { id: request.params.orderId },
    include: {
      payment: true,
      room: { include: { hotel: true } },
    },
  })

  if (!order || !order.notes?.startsWith(ROOM_SERVICE_PREFIX)) {
    return reply.status(404).send({ message: 'Pedido de habitación no encontrado' })
  }

  const isOwner = request.user.role === 'OWNER' && order.room.hotel.ownerId === request.user.id
  const isCleaning = request.user.role === 'CLEANING' && request.user.hotelId === order.room.hotelId
  if (!isOwner && !isCleaning) {
    return reply.status(403).send({ message: 'Sin permiso para gestionar entregas de este hotel' })
  }

  if (!order.payment || order.payment.status !== 'APPROVED') {
    return reply.status(400).send({ message: 'El pedido aún no tiene pago confirmado' })
  }

  const parsed = parseRoomServiceNote(order.notes)
  const prevMeta = (order.payment.metadata && typeof order.payment.metadata === 'object')
    ? order.payment.metadata
    : {}
  const deliveredAt = new Date().toISOString()

  await prisma.payment.update({
    where: { id: order.payment.id },
    data: {
      metadata: {
        ...prevMeta,
        deliveryStatus: 'DELIVERED_PASATURNO',
        deliveredAt,
        deliveredByRole: request.user.role,
      },
    },
  })

  const safeSummary = {
    orderId: order.id,
    roomName: order.room.name,
    items: parsed?.items || prevMeta.items || [],
    deliveryStatus: 'DELIVERED_PASATURNO',
    deliveredAt,
  }

  emitRealtimeEvent({
    hotelId: order.room.hotelId,
    guestId: order.guestId,
    reservationId: parsed?.parentReservationId || order.id,
    type: 'ROOM_SERVICE_DELIVERED',
    payload: safeSummary,
    cleaningSafePayload: safeSummary,
  })

  return reply.send({
    message: `Pedido entregado en esclusa de Habitación ${order.room.name}. El huésped fue notificado silenciosamente.`,
    ...safeSummary,
  })
}

// GET /api/v1/reservations/my  — reservas del huésped (excluye sub-registros internos pagados de extensión/consumo)
async function handleListGuest(request, reply) {
  await expireUnpaidReservations()

  const reservations = await prisma.reservation.findMany({
    where: {
      guestId: request.user.id,
      OR: [
        { notes: null },
        {
          AND: [
            { NOT: { notes: { startsWith: EXTENSION_PREFIX } } },
            { NOT: { notes: { startsWith: ROOM_SERVICE_PREFIX } } },
          ],
        },
        { status: { in: ['PENDING_PAYMENT', 'PAYMENT_PENDING_REVIEW'] } },
      ],
    },
    include: {
      room: {
        include: {
          hotel: {
            select: { id: true, name: true, city: true, address: true, paymentInfo: true },
          },
        },
      },
      payment: {
        select: {
          id: true,
          status: true,
          gateway: true,
          gatewayRef: true,
          amount: true,
          amountVes: true,
          exchangeRate: true,
          expiresAt: true,
        },
      },
    },
    orderBy: { createdAt: 'desc' },
    take: 30,
  })

  return reply.send(
    reservations.map(r => {
      const rs = parseRoomServiceNote(r.notes)
      const isExt = Boolean(r.notes?.startsWith(EXTENSION_PREFIX))
      return {
        ...r,
        isExtension: isExt,
        isRoomService: Boolean(rs),
        parentReservationId: isExt
          ? r.notes.slice(EXTENSION_PREFIX.length)
          : rs
            ? rs.parentReservationId
            : null,
        totalAmount: Number(r.totalAmount),
        room: {
          ...r.room,
          pricePerHour: Number(r.room.pricePerHour),
          pricePerNight: Number(r.room.pricePerNight),
        },
        payment: r.payment
          ? {
              ...r.payment,
              amount: Number(r.payment.amount),
              amountVes: r.payment.amountVes ? Number(r.payment.amountVes) : null,
              exchangeRate: r.payment.exchangeRate ? Number(r.payment.exchangeRate) : null,
            }
          : null,
      }
    })
  )
}

// GET /api/v1/reservations/:id
async function handleGetOne(request, reply) {
  const reservation = await prisma.reservation.findUnique({
    where: { id: request.params.id },
    include: {
      room: { include: { hotel: true } },
      payment: true,
      accessToken: { select: { validFrom: true, validUntil: true, isActive: true } },
    },
  })

  if (!reservation) return reply.status(404).send({ message: 'Reserva no encontrada' })

  const isGuest = reservation.guestId === request.user.id
  const isOwner = request.user.role === 'OWNER'

  if (!isGuest && !isOwner) {
    return reply.status(403).send({ message: 'Acceso denegado' })
  }

  const rs = parseRoomServiceNote(reservation.notes)
  const isExt = Boolean(reservation.notes?.startsWith(EXTENSION_PREFIX))

  return reply.send({
    ...reservation,
    isExtension: isExt,
    isRoomService: Boolean(rs),
    parentReservationId: isExt
      ? reservation.notes.slice(EXTENSION_PREFIX.length)
      : rs
        ? rs.parentReservationId
        : null,
  })
}

// GET /api/v1/reservations/hotel/:hotelId  — para el propietario
async function handleListByHotel(request, reply) {
  const { hotelId } = request.params
  const hotel = await prisma.hotel.findUnique({ where: { id: hotelId } })

  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso a este hotel' })
  }

  const reservations = await prisma.reservation.findMany({
    where: { room: { hotelId } },
    include: {
      room: { select: { name: true } },
      payment: true,
    },
    orderBy: { checkIn: 'desc' },
    take: 100,
  })

  return reply.send(reservations)
}

module.exports = {
  EXTENSION_PREFIX,
  ROOM_SERVICE_PREFIX,
  parseRoomServiceNote,
  handleCreate,
  handleExtend,
  handleCreateRoomServiceOrder,
  handleListRoomServiceOrders,
  handleDeliverRoomServiceOrder,
  handleListGuest,
  handleGetOne,
  handleListByHotel,
}
