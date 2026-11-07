const { EventEmitter } = require('events')

const emitter = new EventEmitter()
emitter.setMaxListeners(500)

/**
 * Emite un evento en tiempo real asociado a un hotel y opcionalmente a un huésped/reserva.
 * Los suscriptores SSE reciben vistas filtradas según su rol (OWNER, CLEANING, GUEST, IOT_BRIDGE).
 */
function emitRealtimeEvent({
  hotelId,
  guestId = null,
  reservationId = null,
  type,
  payload = {},
  cleaningSafePayload = null,
}) {
  const timestamp = new Date().toISOString()
  emitter.emit('realtime', {
    hotelId,
    guestId,
    reservationId,
    type,
    payload,
    cleaningSafePayload,
    timestamp,
  })
}

function subscribeRealtime(listener) {
  emitter.on('realtime', listener)
  return () => emitter.off('realtime', listener)
}

module.exports = {
  emitRealtimeEvent,
  subscribeRealtime,
}
