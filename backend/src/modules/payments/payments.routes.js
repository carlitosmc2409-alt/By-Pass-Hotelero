const ctrl = require('./payments.controller')

async function paymentsRoutes(fastify) {
  // Huésped envía comprobante
  fastify.post('/:paymentId/submit-proof', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleSubmitProof)

  // Propietario confirma pago → genera QR automáticamente
  fastify.post('/:paymentId/confirm', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleConfirmPayment)

  // Propietario rechaza pago
  fastify.post('/:paymentId/reject', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleRejectPayment)

  // Propietario: pagos pendientes de un hotel
  fastify.get('/pending/:hotelId', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleListPending)
}

module.exports = paymentsRoutes
