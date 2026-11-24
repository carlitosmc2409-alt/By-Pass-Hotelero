const { handleCreateReview, handleGetHotelReviews } = require('./reviews.controller')

async function reviewsRoutes(fastify) {
  // Calificación pública del hotel y listado de reseñas verificadas
  fastify.get('/hotel/:hotelId', handleGetHotelReviews)

  // Enviar reseña (requiere autenticación del huésped)
  fastify.post('/reservation/:reservationId', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
    handler: handleCreateReview,
  })
}

module.exports = reviewsRoutes
