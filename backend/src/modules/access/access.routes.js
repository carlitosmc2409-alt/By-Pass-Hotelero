const ctrl = require('./access.controller')

async function accessRoutes(fastify) {
  // POST /api/v1/access/validate  — para tótems QR de barreras FAAC y cerraduras IoT
  fastify.post('/validate', ctrl.handleValidateQr)

  // POST /api/v1/access/faac/open  — huésped acciona barrera FAAC de entrada/salida desde la app
  fastify.post('/faac/open', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleGuestOpenFaac)

  // POST /api/v1/access/faac/owner-pulse  — propietario o recepcionista envía pulso manual FAAC
  fastify.post('/faac/owner-pulse', {
    preHandler: [fastify.authenticate, fastify.authorizeReceptionistOrOwner],
  }, ctrl.handleOwnerPulseFaac)

  // POST /api/v1/access/checkout  — huésped o personal hace check-out
  fastify.post('/checkout', {
    preHandler: [fastify.authenticate],
  }, ctrl.handleCheckout)

  // GET /api/v1/access/qr/:reservationId  — obtener/generar QR rotativo (huésped o recepción en asistencia)
  fastify.get('/qr/:reservationId', {
    preHandler: [fastify.authenticate],
  }, ctrl.handleGetQr)

  // POST /api/v1/access/iot/heartbeat  — telemetría de tótems ESP32 / GM65 / relés FAAC
  fastify.post('/iot/heartbeat', ctrl.handleIotHeartbeat)

  // POST /api/v1/access/iot/offline-sync — sincronización diferida de accesos concedidos offline
  fastify.post('/iot/offline-sync', ctrl.handleIotOfflineSync)

  // GET /api/v1/access/iot/devices/:hotelId  — estado en vivo de controladoras IoT
  fastify.get('/iot/devices/:hotelId', {
    preHandler: [fastify.authenticate, fastify.authorizeReceptionistOrOwner],
  }, ctrl.handleListIotDevices)

  // POST /api/v1/access/iot/test-relay  — diagnóstico / apertura de relé cerradura o barrera
  fastify.post('/iot/test-relay', {
    preHandler: [fastify.authenticate, fastify.authorizeReceptionistOrOwner],
  }, ctrl.handleTestFaacRelay)
}

module.exports = accessRoutes
