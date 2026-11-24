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

  // Huésped: extender estadía activa (+1h .. +24h)
  fastify.post('/:id/extend', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleExtend)

  // Huésped: crear pedido anónimo Room Service (entrega por esclusa/pasaplatos)
  fastify.post('/:id/room-service', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleCreateRoomServiceOrder)

  // Huésped o propietario: consultar pedidos Room Service de una estadía
  fastify.get('/:id/orders', {
    preHandler: [fastify.authenticate],
  }, ctrl.handleListRoomServiceOrders)

  // Personal de limpieza, recepcionista o propietario: marcar pedido Room Service entregado en pasaplatos
  fastify.patch('/:orderId/deliver-order', {
    preHandler: [fastify.authenticate, fastify.authorizeStaffOrOwner],
  }, ctrl.handleDeliverRoomServiceOrder)

  // Huésped o personal: detalle de reserva
  fastify.get('/:id', {
    preHandler: [fastify.authenticate],
  }, ctrl.handleGetOne)

  // Propietario o recepcionista: reservas de un hotel
  fastify.get('/hotel/:hotelId', {
    preHandler: [fastify.authenticate, fastify.authorizeReceptionistOrOwner],
  }, ctrl.handleListByHotel)
}

module.exports = reservationsRoutes
