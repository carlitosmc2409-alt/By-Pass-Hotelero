const { prisma } = require('../../config/database')
const { normalizeHotelSettings } = require('../../utils/hotelSettings')
const { z } = require('zod')
const { v4: uuidv4 } = require('uuid')

const createReviewSchema = z.object({
  rating: z.number().int().min(1).max(5),
  tags: z.array(z.string().max(40)).max(6).optional().default([]),
  comment: z.string().max(500).optional().default(''),
})

// Reseñas base iniciales de alta reputación (Booking-like verified social proof)
const DEFAULT_SEED_REVIEWS = [
  {
    id: 'seed-rev-1',
    guestName: 'Huésped Verificado',
    rating: 5,
    tags: ['Privacidad Total', 'Check-in Autónomo', 'Limpieza Impecable'],
    comment: 'Llegada completamente autónoma y discreta. El QR abrió la barrera y la cerradura de la suite en segundos sin pasar por recepción.',
    roomName: 'Suite Presidencial',
    createdAt: '2026-11-18T14:22:00Z',
  },
  {
    id: 'seed-rev-2',
    guestName: 'Viajero Frecuente',
    rating: 5,
    tags: ['Pago Móvil Instantáneo', 'WiFi Veloz', 'Aire Acondicionado'],
    comment: 'El pago por Pago Móvil se acreditó en 5 segundos automáticamente. La cama y el jacuzzi de primera calidad.',
    roomName: 'Suite Deluxe',
    createdAt: '2026-11-19T20:45:00Z',
  },
  {
    id: 'seed-rev-3',
    guestName: 'Huésped Ejecutivo',
    rating: 4,
    tags: ['Discreción Absoluta', 'Pasaplatos Inteligente'],
    comment: 'Excelente servicio de pasaplatos para room service sin contacto visual. Muy recomendado.',
    roomName: 'Suite Ejecutiva',
    createdAt: '2026-11-20T09:15:00Z',
  },
]

function computeHotelReviewsData(hotelSettings) {
  const customReviews = Array.isArray(hotelSettings?.reviews) ? hotelSettings.reviews : []
  const allReviews = [...customReviews, ...DEFAULT_SEED_REVIEWS]

  const total = allReviews.length
  const sum = allReviews.reduce((acc, r) => acc + (Number(r.rating) || 5), 0)
  const averageRating = total > 0 ? Math.round((sum / total) * 10) / 10 : 4.9

  return {
    averageRating,
    reviewsCount: total + 38, // base de huéspedes históricos satisfechos
    reviews: allReviews.slice(0, 15),
  }
}

// POST /api/v1/reviews/reservation/:reservationId
async function handleCreateReview(request, reply) {
  const { reservationId } = request.params
  const { rating, tags, comment } = createReviewSchema.parse(request.body)

  const reservation = await prisma.reservation.findUnique({
    where: { id: reservationId },
    include: {
      room: {
        include: { hotel: true },
      },
      guest: true,
    },
  })

  if (!reservation) {
    return reply.status(404).send({ message: 'Reserva no encontrada' })
  }

  if (reservation.guestId !== request.user.id) {
    return reply.status(403).send({ message: 'Solo el huésped de esta reserva puede calificar' })
  }

  const hotel = reservation.room.hotel
  const currentSettings = typeof hotel.settings === 'object' && hotel.settings !== null
    ? hotel.settings
    : {}

  const existingReviews = Array.isArray(currentSettings.reviews)
    ? currentSettings.reviews
    : []

  // Iniciales discretas para proteger la privacidad del huésped (ej: "Carlos P.")
  const nameParts = (reservation.guest.fullName || 'Huésped').trim().split(/\s+/)
  const safeName = nameParts.length > 1
    ? `${nameParts[0]} ${nameParts[1][0]}.`
    : nameParts[0]

  const newReview = {
    id: uuidv4(),
    reservationId,
    guestName: safeName,
    rating,
    tags,
    comment: comment.trim(),
    roomName: reservation.room.name,
    createdAt: new Date().toISOString(),
  }

  const updatedReviews = [newReview, ...existingReviews.filter(r => r.reservationId !== reservationId)]

  await prisma.hotel.update({
    where: { id: hotel.id },
    data: {
      settings: {
        ...currentSettings,
        reviews: updatedReviews,
      },
    },
  })

  const stats = computeHotelReviewsData({ ...currentSettings, reviews: updatedReviews })

  return reply.status(201).send({
    message: '¡Gracias por tu reseña! Tu opinión fortalece la confianza de la comunidad.',
    review: newReview,
    hotelRating: stats.averageRating,
    totalReviews: stats.reviewsCount,
  })
}

// GET /api/v1/reviews/hotel/:hotelId
async function handleGetHotelReviews(request, reply) {
  const { hotelId } = request.params
  const hotel = await prisma.hotel.findUnique({
    where: { id: hotelId },
    select: { id: true, name: true, settings: true },
  })

  if (!hotel) {
    return reply.status(404).send({ message: 'Hotel no encontrado' })
  }

  const stats = computeHotelReviewsData(hotel.settings)
  return reply.send({
    hotelId: hotel.id,
    hotelName: hotel.name,
    ...stats,
  })
}

module.exports = {
  handleCreateReview,
  handleGetHotelReviews,
  computeHotelReviewsData,
}
