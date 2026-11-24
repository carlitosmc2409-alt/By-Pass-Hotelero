const ctrl = require('./hotels.controller')

async function hotelsRoutes(fastify) {
  // Propietario (registrar rutas estáticas antes de /:id)
  fastify.get('/my', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleListOwner)

  fastify.get('/:id/dashboard', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleOwnerDashboard)

  fastify.get('/:id/cleaning-board', {
    preHandler: [fastify.authenticate, fastify.authorizeCleaningOrOwner],
  }, ctrl.handleCleaningBoard)

  fastify.get('/:id/reception-board', {
    preHandler: [fastify.authenticate, fastify.authorizeReceptionistOrOwner],
  }, ctrl.handleReceptionBoard)

  fastify.put('/:id/operations', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleUpdateOperations)

  fastify.post('/:id/staff', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleCreateStaff)

  fastify.delete('/:id/staff/:staffId', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleDeleteStaff)

  fastify.post('/', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleCreate)

  fastify.put('/:id', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleUpdate)

  // Públicas (app del huésped)
  fastify.get('/', ctrl.handleListPublic)
  fastify.get('/:id/menu', ctrl.handleGetMenu)
  fastify.get('/:id', ctrl.handleGetPublic)
}

module.exports = hotelsRoutes
