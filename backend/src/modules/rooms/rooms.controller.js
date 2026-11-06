const { prisma } = require('../../config/database')
const { z } = require('zod')

const createRoomSchema = z.object({
  hotelId: z.string().uuid(),
  name: z.string().min(1).max(50),
  description: z.string().optional(),
  type: z.enum(['STANDARD', 'DELUXE', 'SUITE', 'PREMIUM']).default('STANDARD'),
  floorNumber: z.number().int().min(1).default(1),
  pricePerHour: z.number().positive(),
  pricePerNight: z.number().positive(),
  currency: z.string().default('USD'),
  amenities: z.array(z.string()).default([]),
  maxGuests: z.number().int().min(1).max(10).default(2),
  sortOrder: z.number().int().default(0),
})

const updateRoomSchema = createRoomSchema.omit({ hotelId: true }).partial()

// POST /api/v1/rooms
async function handleCreate(request, reply) {
  const data = createRoomSchema.parse(request.body)

  // Verificar que el hotel es del propietario
  const hotel = await prisma.hotel.findUnique({ where: { id: data.hotelId } })
  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso a este hotel' })
  }

  const room = await prisma.room.create({ data })
  return reply.status(201).send(room)
}

// GET /api/v1/rooms/:id
async function handleGetOne(request, reply) {
  const room = await prisma.room.findUnique({
    where: { id: request.params.id },
    include: { hotel: { select: { name: true, city: true, address: true } } },
  })
  if (!room) return reply.status(404).send({ message: 'Habitación no encontrada' })
  return reply.send(room)
}

// PUT /api/v1/rooms/:id
async function handleUpdate(request, reply) {
  const data = updateRoomSchema.parse(request.body)
  const room = await prisma.room.findUnique({
    where: { id: request.params.id },
    include: { hotel: true },
  })

  if (!room || room.hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso' })
  }

  const updated = await prisma.room.update({
    where: { id: request.params.id },
    data,
  })
  return reply.send(updated)
}

// PATCH /api/v1/rooms/:id/status
async function handleUpdateStatus(request, reply) {
  const { status } = z.object({
    status: z.enum(['AVAILABLE', 'CLEANING', 'MAINTENANCE', 'DISABLED']),
  }).parse(request.body)

  const room = await prisma.room.findUnique({
    where: { id: request.params.id },
    include: { hotel: true },
  })

  if (!room || room.hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso' })
  }

  const updated = await prisma.$transaction(async (tx) => {
    if (room.status === 'OCCUPIED') {
      const activeReservations = await tx.reservation.findMany({
        where: { roomId: room.id, status: 'ACTIVE' },
        select: { id: true },
      })
      if (activeReservations.length > 0) {
        const ids = activeReservations.map(r => r.id)
        await tx.reservation.updateMany({
          where: { id: { in: ids } },
          data: { status: 'COMPLETED' },
        })
        await tx.accessToken.updateMany({
          where: { reservationId: { in: ids } },
          data: { isActive: false },
        })
      }
    }

    return tx.room.update({
      where: { id: request.params.id },
      data: { status },
    })
  })
  return reply.send(updated)
}

module.exports = { handleCreate, handleGetOne, handleUpdate, handleUpdateStatus }
