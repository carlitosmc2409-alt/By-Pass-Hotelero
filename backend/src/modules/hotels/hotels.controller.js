const { prisma } = require('../../config/database')
const env = require('../../config/env')
const { generateHotelBridgeToken, generateHotelIotToken } = require('../../utils/crypto')
const { listHotelDevices } = require('../../utils/iotRegistry')
const { getRate } = require('../../utils/rates')
const { normalizeHotelSettings, sanitizeStaffList } = require('../../utils/hotelSettings')
const { parseRoomServiceNote, ROOM_SERVICE_PREFIX } = require('../reservations/reservations.controller')
const bcrypt = require('bcryptjs')
const { v4: uuidv4 } = require('uuid')
const { z } = require('zod')

const paymentInfoSchema = z.object({
  bank: z.string().min(4).max(4),
  bankName: z.string().min(2).max(100).optional(),
  phone: z.string().min(10).max(20),
  idNumber: z.string().min(5).max(25),
  holderName: z.string().min(2).max(120).optional(),
  fallbackExchangeRate: z.number().positive().optional(),
}).optional()

const createHotelSchema = z.object({
  name: z.string().min(2).max(100),
  address: z.string().min(5),
  city: z.string().min(2),
  phone: z.string().optional(),
  description: z.string().optional(),
  latitude: z.number().optional(),
  longitude: z.number().optional(),
  paymentInfo: paymentInfoSchema,
})

const updateHotelSchema = createHotelSchema.partial()

const operationsSchema = z.object({
  faac: z
    .object({
      enabled: z.boolean().optional(),
      model: z.string().min(2).max(120).optional(),
      entryDeviceId: z.string().min(2).max(80).optional(),
      exitDeviceId: z.string().min(2).max(80).optional(),
      contactType: z.string().max(80).optional(),
      pulseDurationMs: z.number().int().min(200).max(10000).optional(),
      exitGraceMinutes: z.number().int().min(0).max(120).optional(),
      relayWebhookUrl: z.string().max(250).optional(),
    })
    .optional(),
  roomServiceMenu: z
    .array(
      z.object({
        id: z.string().min(1).max(60),
        name: z.string().min(2).max(100),
        category: z.string().min(2).max(40).default('SNACKS'),
        priceUsd: z.number().positive(),
        description: z.string().max(200).optional(),
        available: z.boolean().default(true),
      })
    )
    .optional(),
})

const createStaffSchema = z.object({
  name: z.string().min(2).max(80),
  alias: z
    .string()
    .min(2)
    .max(40)
    .regex(/^[a-zA-Z0-9._-]+$/, 'El alias solo puede contener letras, números, puntos o guiones'),
  pin: z.string().min(4, 'El PIN debe tener al menos 4 caracteres').max(20),
})

// POST /api/v1/hotels
async function handleCreate(request, reply) {
  const data = createHotelSchema.parse(request.body)
  const slug = data.name.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '') + '-' + Date.now()

  const hotel = await prisma.hotel.create({
    data: { ...data, ownerId: request.user.id, slug },
  })
  return reply.status(201).send(hotel)
}

// GET /api/v1/hotels  — lista pública de hoteles activos (para app del huésped, incluye rooms sin N+1)
async function handleListPublic(request, reply) {
  const { city, page = 1, limit = 20 } = request.query
  const skip = (page - 1) * limit

  const where = {
    status: 'ACTIVE',
    ...(city && { city: { contains: city, mode: 'insensitive' } }),
  }

  const [hotels, total] = await prisma.$transaction([
    prisma.hotel.findMany({
      where,
      select: {
        id: true,
        name: true,
        slug: true,
        address: true,
        city: true,
        latitude: true,
        longitude: true,
        coverPhoto: true,
        description: true,
        settings: true,
        rooms: {
          where: { status: { in: ['AVAILABLE', 'OCCUPIED'] } },
          select: {
            id: true,
            name: true,
            type: true,
            pricePerHour: true,
            pricePerNight: true,
            currency: true,
            amenities: true,
            photos: true,
            status: true,
            maxGuests: true,
          },
          orderBy: { sortOrder: 'asc' },
        },
        _count: { select: { rooms: true } },
      },
      skip,
      take: Number(limit),
    }),
    prisma.hotel.count({ where }),
  ])

  const formatted = hotels.map(({ settings, ...h }) => {
    const norm = normalizeHotelSettings(settings)
    return {
      ...h,
      faacEnabled: norm.faac.enabled !== false,
    }
  })

  return reply.send({ data: formatted, total, page: Number(page), limit: Number(limit) })
}

// GET /api/v1/hotels/:id  — detalle público de un hotel
async function handleGetPublic(request, reply) {
  const hotel = await prisma.hotel.findUnique({
    where: { id: request.params.id, status: 'ACTIVE' },
    include: {
      rooms: {
        where: { status: { in: ['AVAILABLE', 'OCCUPIED'] } },
        select: {
          id: true,
          name: true,
          type: true,
          pricePerHour: true,
          pricePerNight: true,
          currency: true,
          amenities: true,
          photos: true,
          status: true,
          maxGuests: true,
        },
        orderBy: { sortOrder: 'asc' },
      },
    },
  })

  if (!hotel) return reply.status(404).send({ message: 'Hotel no encontrado' })

  const norm = normalizeHotelSettings(hotel.settings)
  const { settings, ...publicHotel } = hotel
  return reply.send({
    ...publicHotel,
    faac: {
      enabled: norm.faac.enabled !== false,
      model: norm.faac.model,
      entryDeviceId: norm.faac.entryDeviceId,
      exitDeviceId: norm.faac.exitDeviceId,
    },
    roomServiceMenu: norm.roomServiceMenu.filter(m => m.available !== false),
  })
}

// GET /api/v1/hotels/:id/menu  — catálogo discreto Room Service + configuración pública FAAC
async function handleGetMenu(request, reply) {
  const hotel = await prisma.hotel.findUnique({
    where: { id: request.params.id },
    select: { id: true, name: true, settings: true, paymentInfo: true },
  })
  if (!hotel) return reply.status(404).send({ message: 'Hotel no encontrado' })

  const norm = normalizeHotelSettings(hotel.settings)
  const currentExchangeRate = await getRate({
    fallbackRate: hotel.paymentInfo?.fallbackExchangeRate,
  }).catch(() => null)

  return reply.send({
    hotelId: hotel.id,
    hotelName: hotel.name,
    currentExchangeRate,
    faac: {
      enabled: norm.faac.enabled !== false,
      model: norm.faac.model,
      entryDeviceId: norm.faac.entryDeviceId,
      exitDeviceId: norm.faac.exitDeviceId,
      exitGraceMinutes: norm.faac.exitGraceMinutes,
    },
    items: norm.roomServiceMenu.filter(m => m.available !== false),
  })
}

// GET /api/v1/hotels/my  — hoteles del propietario autenticado
async function handleListOwner(request, reply) {
  const hotels = await prisma.hotel.findMany({
    where: { ownerId: request.user.id },
    include: {
      _count: { select: { rooms: true } },
    },
    orderBy: { createdAt: 'desc' },
  })
  return reply.send(hotels)
}

// PUT /api/v1/hotels/:id
async function handleUpdate(request, reply) {
  const data = updateHotelSchema.parse(request.body)
  const hotel = await prisma.hotel.findUnique({ where: { id: request.params.id } })

  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso a este hotel' })
  }

  const updated = await prisma.hotel.update({
    where: { id: request.params.id },
    data,
  })
  return reply.send(updated)
}

// PUT /api/v1/hotels/:id/operations  — actualiza Barreras FAAC y/o Menú Room Service
async function handleUpdateOperations(request, reply) {
  const data = operationsSchema.parse(request.body)
  const hotel = await prisma.hotel.findUnique({ where: { id: request.params.id } })

  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso a este hotel' })
  }

  const current = normalizeHotelSettings(hotel.settings)
  const nextSettings = {
    ...current,
    ...(data.faac ? { faac: { ...current.faac, ...data.faac } } : {}),
    ...(data.roomServiceMenu ? { roomServiceMenu: data.roomServiceMenu } : {}),
  }

  await prisma.hotel.update({
    where: { id: hotel.id },
    data: { settings: nextSettings },
  })

  return reply.send({
    message: 'Configuración operativa actualizada',
    faac: nextSettings.faac,
    roomServiceMenu: nextSettings.roomServiceMenu,
  })
}

// POST /api/v1/hotels/:id/staff  — crear credencial para personal de limpieza (CLEANING)
async function handleCreateStaff(request, reply) {
  const { name, alias, pin } = createStaffSchema.parse(request.body)
  const hotel = await prisma.hotel.findUnique({ where: { id: request.params.id } })

  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso a este hotel' })
  }

  const current = normalizeHotelSettings(hotel.settings)
  const normalizedAlias = alias.trim().toLowerCase()
  if (current.cleaningStaff.some(s => String(s.alias).toLowerCase() === normalizedAlias)) {
    return reply.status(409).send({ message: 'Ya existe un integrante con ese alias en este hotel' })
  }

  const pinHash = await bcrypt.hash(pin, env.BCRYPT_ROUNDS)
  const member = {
    id: uuidv4(),
    name: name.trim(),
    alias: normalizedAlias,
    pinHash,
    active: true,
    createdAt: new Date().toISOString(),
  }

  const nextSettings = {
    ...current,
    cleaningStaff: [...current.cleaningStaff, member],
  }

  await prisma.hotel.update({
    where: { id: hotel.id },
    data: { settings: nextSettings },
  })

  return reply.status(201).send({
    message: 'Personal operativo creado exitosamente',
    hotelCode: hotel.slug,
    staff: sanitizeStaffList(nextSettings.cleaningStaff),
  })
}

// DELETE /api/v1/hotels/:id/staff/:staffId
async function handleDeleteStaff(request, reply) {
  const { id, staffId } = request.params
  const hotel = await prisma.hotel.findUnique({ where: { id } })

  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso a este hotel' })
  }

  const current = normalizeHotelSettings(hotel.settings)
  const nextList = current.cleaningStaff.filter(s => s.id !== staffId)

  await prisma.hotel.update({
    where: { id: hotel.id },
    data: { settings: { ...current, cleaningStaff: nextList } },
  })

  return reply.send({
    message: 'Credencial revocada',
    staff: sanitizeStaffList(nextList),
  })
}

async function fetchPendingRoomServiceDeliveries(hotelId) {
  const paidOrders = await prisma.reservation.findMany({
    where: {
      room: { hotelId },
      notes: { startsWith: ROOM_SERVICE_PREFIX },
      payment: { status: 'APPROVED' },
    },
    orderBy: { createdAt: 'desc' },
    take: 30,
    select: {
      id: true,
      notes: true,
      createdAt: true,
      room: { select: { id: true, name: true, floorNumber: true } },
      payment: { select: { metadata: true } },
    },
  })

  return paidOrders
    .map(o => {
      const parsed = parseRoomServiceNote(o.notes)
      const meta = (o.payment?.metadata && typeof o.payment.metadata === 'object')
        ? o.payment.metadata
        : {}
      const deliveryStatus = meta.deliveryStatus || 'PENDING_DELIVERY'
      return {
        orderId: o.id,
        roomId: o.room.id,
        roomName: o.room.name,
        floorNumber: o.room.floorNumber,
        items: (parsed?.items || meta.items || []).map(it => ({
          id: it.id,
          name: it.name,
          qty: it.qty,
        })),
        guestNote: parsed?.guestNote || meta.guestNote || '',
        deliveryStatus,
        deliveredAt: meta.deliveredAt || null,
        createdAt: o.createdAt,
      }
    })
    .filter(o => o.deliveryStatus !== 'DELIVERED_PASATURNO')
}

// GET /api/v1/hotels/:id/cleaning-board  — tablero operativo CERO FINANZAS para rol CLEANING u OWNER
async function handleCleaningBoard(request, reply) {
  const { id } = request.params
  const hotel = await prisma.hotel.findUnique({
    where: { id },
    include: {
      rooms: {
        orderBy: { sortOrder: 'asc' },
        include: {
          reservations: {
            where: { status: 'ACTIVE' },
            orderBy: { checkIn: 'desc' },
            take: 1,
            select: {
              checkOut: true,
            },
          },
        },
      },
    },
  })

  if (!hotel) return reply.status(404).send({ message: 'Hotel no encontrado' })

  const isOwner = request.user.role === 'OWNER' && hotel.ownerId === request.user.id
  const isCleaning = request.user.role === 'CLEANING' && request.user.hotelId === hotel.id
  if (!isOwner && !isCleaning) {
    return reply.status(403).send({ message: 'Sin permiso para ver el tablero operativo de este hotel' })
  }

  const nowMs = Date.now()
  const rooms = hotel.rooms.map(r => {
    const active = r.reservations[0] || null
    let minutesRemaining = null
    if (active?.checkOut) {
      minutesRemaining = Math.max(
        0,
        Math.ceil((new Date(active.checkOut).getTime() - nowMs) / 60000)
      )
    }
    return {
      id: r.id,
      name: r.name,
      type: r.type,
      floorNumber: r.floorNumber,
      status: r.status,
      minutesRemaining,
      expiringSoon: minutesRemaining !== null && minutesRemaining <= 15,
      updatedAt: r.updatedAt,
    }
  })

  const pendingDeliveries = await fetchPendingRoomServiceDeliveries(id)

  return reply.send({
    hotel: {
      id: hotel.id,
      name: hotel.name,
    },
    summary: {
      cleaningCount: rooms.filter(r => r.status === 'CLEANING').length,
      availableCount: rooms.filter(r => r.status === 'AVAILABLE').length,
      occupiedCount: rooms.filter(r => r.status === 'OCCUPIED').length,
      expiringSoonCount: rooms.filter(r => r.expiringSoon).length,
      pendingDeliveriesCount: pendingDeliveries.length,
    },
    rooms,
    pendingDeliveries,
  })
}

// GET /api/v1/hotels/:id/dashboard  — vista integral en tiempo real para el propietario
async function handleOwnerDashboard(request, reply) {
  const { id } = request.params
  const hotel = await prisma.hotel.findUnique({
    where: { id },
    include: {
      rooms: {
        orderBy: { sortOrder: 'asc' },
        include: {
          reservations: {
            where: { status: 'ACTIVE' },
            orderBy: { checkIn: 'desc' },
            take: 1,
            select: {
              id: true,
              checkIn: true,
              checkOut: true,
              durationHours: true,
              totalAmount: true,
            },
          },
        },
      },
    },
  })

  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso a este hotel' })
  }

  const now = new Date()
  const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1)

  const [
    approvedToday,
    approvedMonth,
    pendingPayments,
    recentBankEvents,
    recentReservations,
    recentAccessLogs,
  ] = await prisma.$transaction([
    prisma.payment.findMany({
      where: {
        status: 'APPROVED',
        confirmedAt: { gte: startOfDay },
        reservation: { room: { hotelId: id } },
      },
      select: { amount: true, amountVes: true },
    }),
    prisma.payment.findMany({
      where: {
        status: 'APPROVED',
        confirmedAt: { gte: startOfMonth },
        reservation: { room: { hotelId: id } },
      },
      select: { amount: true, amountVes: true },
    }),
    prisma.payment.count({
      where: {
        status: { in: ['PENDING', 'PENDING_REVIEW'] },
        reservation: { room: { hotelId: id } },
      },
    }),
    prisma.bankEvent.findMany({
      where: { hotelId: id },
      orderBy: { receivedAt: 'desc' },
      take: 20,
    }),
    prisma.reservation.findMany({
      where: { room: { hotelId: id } },
      orderBy: { createdAt: 'desc' },
      take: 30,
      select: {
        id: true,
        checkIn: true,
        checkOut: true,
        durationHours: true,
        totalAmount: true,
        currency: true,
        status: true,
        notes: true,
        createdAt: true,
        room: { select: { id: true, name: true, type: true } },
        payment: {
          select: {
            id: true,
            gateway: true,
            gatewayRef: true,
            amount: true,
            amountVes: true,
            status: true,
            confirmedBy: true,
            confirmedAt: true,
            metadata: true,
          },
        },
      },
    }),
    prisma.accessLog.findMany({
      where: {
        accessToken: { reservation: { room: { hotelId: id } } },
      },
      orderBy: { createdAt: 'desc' },
      take: 15,
      select: {
        id: true,
        event: true,
        deviceId: true,
        metadata: true,
        createdAt: true,
        accessToken: {
          select: {
            reservation: { select: { room: { select: { name: true } } } },
          },
        },
      },
    }),
  ])

  const sumUsd = list => list.reduce((acc, p) => acc + Number(p.amount || 0), 0)
  const sumVes = list => list.reduce((acc, p) => acc + Number(p.amountVes || 0), 0)

  const nowMs = Date.now()
  const roomsFormatted = hotel.rooms.map(r => {
    const activeRes = r.reservations[0] || null
    const { reservations, ...roomRest } = r
    let minutesRemaining = null
    if (activeRes?.checkOut) {
      minutesRemaining = Math.max(
        0,
        Math.ceil((new Date(activeRes.checkOut).getTime() - nowMs) / 60000)
      )
    }
    return {
      ...roomRest,
      pricePerHour: Number(r.pricePerHour),
      pricePerNight: Number(r.pricePerNight),
      minutesRemaining,
      expiringSoon: minutesRemaining !== null && minutesRemaining <= 15,
      activeReservation: activeRes
        ? {
            ...activeRes,
            totalAmount: Number(activeRes.totalAmount),
          }
        : null,
    }
  })

  const currentExchangeRate = await getRate({
    fallbackRate: hotel.paymentInfo?.fallbackExchangeRate,
  }).catch(() => null)

  const normSettings = normalizeHotelSettings(hotel.settings)
  const pendingDeliveries = await fetchPendingRoomServiceDeliveries(id)

  return reply.send({
    hotel: {
      id: hotel.id,
      name: hotel.name,
      slug: hotel.slug,
      address: hotel.address,
      city: hotel.city,
      status: hotel.status,
      paymentInfo: hotel.paymentInfo,
      bdvBridgeToken: generateHotelBridgeToken(hotel.id),
      iotHardwareToken: generateHotelIotToken(hotel.id),
      currentExchangeRate,
      faac: normSettings.faac,
      roomServiceMenu: normSettings.roomServiceMenu,
      cleaningStaff: sanitizeStaffList(normSettings.cleaningStaff),
    },
    iotDevices: listHotelDevices(id),
    metrics: {
      totalRooms: roomsFormatted.length,
      availableRooms: roomsFormatted.filter(r => r.status === 'AVAILABLE').length,
      occupiedRooms: roomsFormatted.filter(r => r.status === 'OCCUPIED').length,
      cleaningRooms: roomsFormatted.filter(r => r.status === 'CLEANING').length,
      expiringSoonRooms: roomsFormatted.filter(r => r.expiringSoon).length,
      pendingDeliveriesCount: pendingDeliveries.length,
      revenueTodayUsd: Math.round(sumUsd(approvedToday) * 100) / 100,
      revenueTodayVes: Math.round(sumVes(approvedToday) * 100) / 100,
      approvedCountToday: approvedToday.length,
      revenueMonthUsd: Math.round(sumUsd(approvedMonth) * 100) / 100,
      revenueMonthVes: Math.round(sumVes(approvedMonth) * 100) / 100,
      pendingReviewCount: pendingPayments,
    },
    rooms: roomsFormatted,
    pendingDeliveries,
    recentAccessLogs: recentAccessLogs.map(l => ({
      id: l.id,
      event: l.event,
      deviceId: l.deviceId,
      roomName: l.accessToken?.reservation?.room?.name || 'N/D',
      metadata: l.metadata,
      createdAt: l.createdAt,
    })),
    recentBankEvents: recentBankEvents.map(ev => ({
      ...ev,
      amountVes: Number(ev.amountVes),
    })),
    recentReservations: recentReservations.map(({ notes, ...res }) => ({
      ...res,
      kind: notes?.startsWith(ROOM_SERVICE_PREFIX)
        ? 'ROOM_SERVICE'
        : notes?.startsWith('EXTENSION_OF:')
          ? 'EXTENSION'
          : 'STAY',
      totalAmount: Number(res.totalAmount),
      payment: res.payment
        ? {
            ...res.payment,
            amount: Number(res.payment.amount),
            amountVes: res.payment.amountVes ? Number(res.payment.amountVes) : null,
            autoVerified: Boolean(res.payment.confirmedBy?.startsWith('system:bank-event:')),
          }
        : null,
    })),
  })
}

module.exports = {
  handleCreate,
  handleListPublic,
  handleGetPublic,
  handleGetMenu,
  handleListOwner,
  handleUpdate,
  handleUpdateOperations,
  handleCreateStaff,
  handleDeleteStaff,
  handleCleaningBoard,
  handleOwnerDashboard,
}
