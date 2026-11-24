const ctrl = require('./payments.controller')

async function paymentsRoutes(fastify) {
  // Huésped envía referencia → concilia automáticamente si coincide con notificación bancaria
  fastify.post('/:paymentId/submit-proof', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleSubmitProof)

  // Webhook para agente lector de notificaciones BDV (o simulador externo)
  fastify.post('/webhook/bdv-notification', ctrl.handleBdvNotificationWebhook)

  // Heartbeat y salud en vivo del puente Android BDV
  fastify.post('/webhook/bdv-bridge/heartbeat', ctrl.handleBdvBridgeHeartbeat)
  fastify.get('/bdv-bridge/status/:hotelId', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleGetBdvBridgeStatus)

  // Propietario o recepcionista confirma pago manualmente (contingencia)
  fastify.post('/:paymentId/confirm', {
    preHandler: [fastify.authenticate, fastify.authorizeReceptionistOrOwner],
  }, ctrl.handleConfirmPayment)

  // Propietario o recepcionista rechaza pago
  fastify.post('/:paymentId/reject', {
    preHandler: [fastify.authenticate, fastify.authorizeReceptionistOrOwner],
  }, ctrl.handleRejectPayment)

  // Propietario o recepcionista: pagos pendientes de un hotel
  fastify.get('/pending/:hotelId', {
    preHandler: [fastify.authenticate, fastify.authorizeReceptionistOrOwner],
  }, ctrl.handleListPending)
}

module.exports = paymentsRoutes
