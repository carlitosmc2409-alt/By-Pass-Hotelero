const ctrl = require('./reservations.controller')

async function reservationsRoutes(fastify) {
  // Huésped: crear reserva
  fastify.post('/', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleCreate)

  // Huésped: mis reservas
  fastify.get('/my', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleListGuest)

  // Huésped o propietario: detalle de reserva
  fastify.get('/:id', {
    preHandler: [fastify.authenticate],
  }, ctrl.handleGetOne)

  // Propietario: reservas de un hotel
  fastify.get('/hotel/:hotelId', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleListByHotel)
}

module.exports = reservationsRoutes
