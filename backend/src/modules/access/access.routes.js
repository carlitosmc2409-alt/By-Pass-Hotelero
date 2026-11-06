const ctrl = require('./access.controller')

async function accessRoutes(fastify) {
  // POST /api/v1/access/validate  — para cerraduras IoT (sin auth JWT, con deviceId)
  fastify.post('/validate', ctrl.handleValidateQr)

  // POST /api/v1/access/checkout  — huésped hace check-out desde la app
  fastify.post('/checkout', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleCheckout)

  // GET /api/v1/access/qr/:reservationId  — obtener/generar QR
  fastify.get('/qr/:reservationId', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleGetQr)
}

module.exports = accessRoutes
