const ctrl = require('./payments.controller')

async function paymentsRoutes(fastify) {
  // Huésped envía referencia → concilia automáticamente si coincide con notificación bancaria
  fastify.post('/:paymentId/submit-proof', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleSubmitProof)

  // Webhook para agente lector de notificaciones BDV (o simulador externo)
  fastify.post('/webhook/bdv-notification', ctrl.handleBdvNotificationWebhook)

  // Propietario confirma pago manualmente (respaldo)
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
