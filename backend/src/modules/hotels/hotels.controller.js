const { prisma } = require('../../config/database')
const { generateHotelBridgeToken } = require('../../utils/crypto')
const { getRate } = require('../../utils/rates')
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

// POST /api/v1/hotels
async function handleCreate(request, reply) {
  const data = createHotelSchema.parse(request.body)
  const slug = data.name.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '') + '-' + Date.now()

  const hotel = await prisma.hotel.create({
    data: { ...data, ownerId: request.user.id, slug },
  })
  return reply.status(201).send(hotel)
}

// GET /api/v1/hotels  — lista pública de hoteles activos (para app del huésped)
async function handleListPublic(request, reply) {
  const { city, lat, lng, page = 1, limit = 20 } = request.query
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
        address: true,
        city: true,
        latitude: true,
        longitude: true,
        coverPhoto: true,
        description: true,
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

  return reply.send({ data: hotels, total, page: Number(page), limit: Number(limit) })
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
  return reply.send(hotel)
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

  const [approvedToday, approvedMonth, pendingPayments, recentBankEvents, recentReservations] =
    await prisma.$transaction([
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
            },
          },
        },
      }),
    ])

  const sumUsd = list => list.reduce((acc, p) => acc + Number(p.amount || 0), 0)
  const sumVes = list => list.reduce((acc, p) => acc + Number(p.amountVes || 0), 0)

  const roomsFormatted = hotel.rooms.map(r => {
    const activeRes = r.reservations[0] || null
    const { reservations, ...roomRest } = r
    return {
      ...roomRest,
      pricePerHour: Number(r.pricePerHour),
      pricePerNight: Number(r.pricePerNight),
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

  return reply.send({
    hotel: {
      id: hotel.id,
      name: hotel.name,
      address: hotel.address,
      city: hotel.city,
      status: hotel.status,
      paymentInfo: hotel.paymentInfo,
      bdvBridgeToken: generateHotelBridgeToken(hotel.id),
      currentExchangeRate,
    },
    metrics: {
      totalRooms: roomsFormatted.length,
      availableRooms: roomsFormatted.filter(r => r.status === 'AVAILABLE').length,
      occupiedRooms: roomsFormatted.filter(r => r.status === 'OCCUPIED').length,
      cleaningRooms: roomsFormatted.filter(r => r.status === 'CLEANING').length,
      revenueTodayUsd: Math.round(sumUsd(approvedToday) * 100) / 100,
      revenueTodayVes: Math.round(sumVes(approvedToday) * 100) / 100,
      approvedCountToday: approvedToday.length,
      revenueMonthUsd: Math.round(sumUsd(approvedMonth) * 100) / 100,
      revenueMonthVes: Math.round(sumVes(approvedMonth) * 100) / 100,
      pendingReviewCount: pendingPayments,
    },
    rooms: roomsFormatted,
    recentBankEvents: recentBankEvents.map(ev => ({
      ...ev,
      amountVes: Number(ev.amountVes),
    })),
    recentReservations: recentReservations.map(res => ({
      ...res,
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
  handleListOwner,
  handleUpdate,
  handleOwnerDashboard,
}
