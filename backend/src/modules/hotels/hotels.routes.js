const ctrl = require('./hotels.controller')

async function hotelsRoutes(fastify) {
  // Propietario (registrar rutas estáticas antes de /:id)
  fastify.get('/my', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleListOwner)

  fastify.get('/:id/dashboard', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleOwnerDashboard)

  fastify.post('/', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleCreate)

  fastify.put('/:id', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleUpdate)

  // Públicas (app del huésped)
  fastify.get('/', ctrl.handleListPublic)
  fastify.get('/:id', ctrl.handleGetPublic)
}

module.exports = hotelsRoutes
