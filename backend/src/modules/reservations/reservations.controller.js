const { prisma } = require('../../config/database')
const env = require('../../config/env')
const { getRate, round2 } = require('../../utils/rates')
const { expireUnpaidReservations } = require('../../utils/cron')
const { z } = require('zod')
const dayjs = require('dayjs')

const EXTENSION_PREFIX = 'EXTENSION_OF:'

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

/**
 * Si existen pagos abiertos simultáneos en el mismo hotel con el mismo monto base en Bs,
 * suma céntimos únicos (+0.01 .. +0.99) para habilitar conciliación "Cero Clics" sin ambigüedad.
 * Si no hay colisión activa, mantiene el monto exacto redondeado (.00).
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

  // Liberar de inmediato cualquier reserva impaga vencida antes de evaluar disponibilidad
  await expireUnpaidReservations()

  const checkInDate = dayjs(checkIn)
  const checkOutDate = checkInDate.add(durationHours, 'hour')

  // Verificar que la habitación existe y está disponible
  const room = await prisma.room.findUnique({
    where: { id: roomId },
    include: { hotel: { select: { id: true, name: true, paymentInfo: true } } },
  })
  if (!room || room.status !== 'AVAILABLE') {
    return reply.status(409).send({ message: 'Habitación no disponible' })
  }

  // Verificar que no hay reservas activas o en espera vigente solapadas
  const conflict = await prisma.reservation.findFirst({
    where: {
      roomId,
      status: { in: ['ACTIVE', 'PENDING_PAYMENT', 'PAYMENT_PENDING_REVIEW'] },
      AND: [
        { checkIn: { lt: checkOutDate.toDate() } },
        { checkOut: { gt: checkInDate.toDate() } },
      ],
    },
  })

  if (conflict) {
    return reply.status(409).send({ message: 'La habitación ya está reservada en ese horario' })
  }

  // Calcular precio en USD y bloquear monto equivalente en Bolívares
  const totalAmount = durationHours >= 24
    ? Number(room.pricePerNight)
    : Number(room.pricePerHour) * durationHours

  const fallbackRate = room.hotel.paymentInfo?.fallbackExchangeRate
  const exchangeRate = await getRate({ fallbackRate })
  const baseAmountVes = round2(totalAmount * exchangeRate)
  const expiresAt = dayjs().add(env.PAYMENT_HOLD_MINUTES, 'minute').toDate()

  // Crear reserva + pago en transacción con asignación de céntimos únicos si hay concurrencia
  const result = await prisma.$transaction(async (tx) => {
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

  const conflict = await prisma.reservation.findFirst({
    where: {
      roomId: parent.roomId,
      id: { not: parent.id },
      status: { in: ['ACTIVE', 'PENDING_PAYMENT', 'PAYMENT_PENDING_REVIEW'] },
      AND: [
        { checkIn: { lt: extEnd.toDate() } },
        { checkOut: { gt: extStart.toDate() } },
      ],
    },
  })

  if (conflict) {
    return reply.status(409).send({
      message: 'No es posible extender: existe otra solicitud o reserva en el horario siguiente',
    })
  }

  const room = parent.room
  const extraAmountUsd = extraHours >= 24
    ? Number(room.pricePerNight)
    : Number(room.pricePerHour) * extraHours

  const fallbackRate = room.hotel.paymentInfo?.fallbackExchangeRate
  const exchangeRate = await getRate({ fallbackRate })
  const baseAmountVes = round2(extraAmountUsd * exchangeRate)
  const expiresAt = dayjs().add(env.PAYMENT_HOLD_MINUTES, 'minute').toDate()

  const result = await prisma.$transaction(async (tx) => {
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

// GET /api/v1/reservations/my  — reservas del huésped (incluye activas, pendientes e historial)
async function handleListGuest(request, reply) {
  await expireUnpaidReservations()

  const reservations = await prisma.reservation.findMany({
    where: {
      guestId: request.user.id,
      OR: [
        { notes: null },
        { NOT: { notes: { startsWith: EXTENSION_PREFIX } } },
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
    reservations.map(r => ({
      ...r,
      isExtension: Boolean(r.notes?.startsWith(EXTENSION_PREFIX)),
      parentReservationId: r.notes?.startsWith(EXTENSION_PREFIX)
        ? r.notes.slice(EXTENSION_PREFIX.length)
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
    }))
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

  return reply.send({
    ...reservation,
    isExtension: Boolean(reservation.notes?.startsWith(EXTENSION_PREFIX)),
    parentReservationId: reservation.notes?.startsWith(EXTENSION_PREFIX)
      ? reservation.notes.slice(EXTENSION_PREFIX.length)
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
  handleCreate,
  handleExtend,
  handleListGuest,
  handleGetOne,
  handleListByHotel,
}
