const ctrl = require('./hotels.controller')

async function hotelsRoutes(fastify) {
  // Públicas (app del huésped)
  fastify.get('/', ctrl.handleListPublic)
  fastify.get('/:id', ctrl.handleGetPublic)

  // Propietario
  fastify.get('/my', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleListOwner)

  fastify.post('/', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleCreate)

  fastify.put('/:id', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleUpdate)
}

module.exports = hotelsRoutes
