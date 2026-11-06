const { prisma } = require('../../config/database')
const { z } = require('zod')
const dayjs = require('dayjs')

const createReservationSchema = z.object({
  roomId: z.string().uuid(),
  checkIn: z.string().datetime(),
  durationHours: z.number().int().min(1).max(72),
  gateway: z.enum(['PAGO_MOVIL', 'ZELLE', 'BINANCE_PAY', 'CASH']),
})

// POST /api/v1/reservations  — el huésped crea una reserva
async function handleCreate(request, reply) {
  const { roomId, checkIn, durationHours, gateway } = createReservationSchema.parse(request.body)

  const checkInDate = dayjs(checkIn)
  const checkOutDate = checkInDate.add(durationHours, 'hour')

  // Verificar que la habitación existe y está disponible
  const room = await prisma.room.findUnique({ where: { id: roomId } })
  if (!room || room.status !== 'AVAILABLE') {
    return reply.status(409).send({ message: 'Habitación no disponible' })
  }

  // Verificar que no hay reservas activas solapadas
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

  // Calcular precio
  const totalAmount = durationHours >= 24
    ? room.pricePerNight
    : Number(room.pricePerHour) * durationHours

  // Crear reserva + pago en transacción
  const result = await prisma.$transaction(async (tx) => {
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
        status: 'PENDING',
      },
    })

    return { reservation, payment }
  })

  return reply.status(201).send({
    reservationId: result.reservation.id,
    paymentId: result.payment.id,
    totalAmount,
    currency: room.currency,
    checkIn: checkInDate.toDate(),
    checkOut: checkOutDate.toDate(),
    message: 'Reserva creada. Procede con el pago para confirmar.',
  })
}

// GET /api/v1/reservations/my  — reservas del huésped
async function handleListGuest(request, reply) {
  const reservations = await prisma.reservation.findMany({
    where: { guestId: request.user.id },
    include: {
      room: { include: { hotel: { select: { name: true, city: true } } } },
      payment: { select: { status: true, gateway: true, amount: true } },
    },
    orderBy: { createdAt: 'desc' },
  })
  return reply.send(reservations)
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

  // Solo el huésped dueño o el propietario del hotel pueden ver
  const isGuest = reservation.guestId === request.user.id
  const isOwner = request.user.role === 'OWNER'

  if (!isGuest && !isOwner) {
    return reply.status(403).send({ message: 'Acceso denegado' })
  }

  return reply.send(reservation)
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

module.exports = { handleCreate, handleListGuest, handleGetOne, handleListByHotel }
