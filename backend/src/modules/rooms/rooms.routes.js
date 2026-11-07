const ctrl = require('./rooms.controller')

async function roomsRoutes(fastify) {
  fastify.get('/:id', ctrl.handleGetOne)

  fastify.post('/', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleCreate)

  fastify.put('/:id', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleUpdate)

  fastify.patch('/:id/status', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleUpdateStatus)

  fastify.patch('/:id/cleaning-status', {
    preHandler: [fastify.authenticate, fastify.authorizeCleaningOrOwner],
  }, ctrl.handleCleaningStatusUpdate)
}

module.exports = roomsRoutes
