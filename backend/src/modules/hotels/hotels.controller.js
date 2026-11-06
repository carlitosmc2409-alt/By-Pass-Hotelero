const { prisma } = require('../../config/database')
const { z } = require('zod')

const createHotelSchema = z.object({
  name: z.string().min(2).max(100),
  address: z.string().min(5),
  city: z.string().min(2),
  phone: z.string().optional(),
  description: z.string().optional(),
  latitude: z.number().optional(),
  longitude: z.number().optional(),
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

module.exports = { handleCreate, handleListPublic, handleGetPublic, handleListOwner, handleUpdate }
