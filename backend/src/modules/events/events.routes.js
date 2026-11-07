const { prisma } = require('../../config/database')
const { validateHotelBridgeToken } = require('../../utils/crypto')
const { subscribeRealtime } = require('../../utils/eventBus')

const CLEANING_ALLOWED_TYPES = new Set([
  'ROOM_STATUS_CHANGED',
  'ROOM_SERVICE_ORDER',
  'ROOM_SERVICE_DELIVERED',
])

const IOT_BRIDGE_ALLOWED_TYPES = new Set([
  'FAAC_BARRIER_PULSE',
  'DOOR_UNLOCK_PULSE',
])

async function eventsRoutes(fastify) {
  // GET /api/v1/events/stream
  // Soporta:
  //  1) JWT vía header Authorization o query ?token=<jwt> (OWNER, CLEANING, GUEST)
  //  2) Controlador físico FAAC / Quiosco IoT vía ?hotelId=<uuid>&bridgeToken=<hmac>
  //  3) Quiosco local de demostración vía ?hotelId=<uuid>&scope=kiosk (solo pulsos físicos sin PII ni finanzas)
  fastify.get('/stream', async (request, reply) => {
    let principal = null
    const query = request.query || {}

    const authHeader = request.headers.authorization
    const rawJwt = authHeader?.startsWith('Bearer ')
      ? authHeader.slice(7).trim()
      : typeof query.token === 'string'
        ? query.token.trim()
        : null

    if (rawJwt) {
      try {
        principal = fastify.jwt.verify(rawJwt)
      } catch (_) {
        return reply.status(401).send({ message: 'Token de stream inválido o expirado' })
      }
    } else if (query.hotelId && query.bridgeToken) {
      const valid = validateHotelBridgeToken(String(query.hotelId), String(query.bridgeToken))
      if (!valid) {
        return reply.status(401).send({ message: 'Credencial de puente IoT/FAAC inválida' })
      }
      principal = { role: 'IOT_BRIDGE', hotelId: String(query.hotelId) }
    } else if (query.hotelId && query.scope === 'kiosk') {
      principal = { role: 'IOT_BRIDGE', hotelId: String(query.hotelId) }
    } else {
      return reply.status(401).send({ message: 'Autenticación requerida para el stream en vivo' })
    }

    let ownerHotelIds = new Set()
    if (principal.role === 'OWNER') {
      const hotels = await prisma.hotel.findMany({
        where: { ownerId: principal.id },
        select: { id: true },
      })
      ownerHotelIds = new Set(hotels.map(h => h.id))
    }

    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'Access-Control-Allow-Origin': request.headers.origin || '*',
      'X-Accel-Buffering': 'no',
    })

    const sendEvent = (eventName, data) => {
      try {
        reply.raw.write(`event: ${eventName}\ndata: ${JSON.stringify(data)}\n\n`)
      } catch (_) {}
    }

    sendEvent('connected', {
      role: principal.role,
      timestamp: new Date().toISOString(),
    })

    if (query.once === '1') {
      reply.raw.end()
      return reply
    }

    const unsubscribe = subscribeRealtime(evt => {
      if (principal.role === 'OWNER') {
        if (evt.hotelId && ownerHotelIds.has(evt.hotelId)) {
          sendEvent('message', {
            type: evt.type,
            hotelId: evt.hotelId,
            reservationId: evt.reservationId,
            payload: evt.payload,
            timestamp: evt.timestamp,
          })
        }
        return
      }

      if (principal.role === 'CLEANING') {
        if (evt.hotelId === principal.hotelId && CLEANING_ALLOWED_TYPES.has(evt.type)) {
          sendEvent('message', {
            type: evt.type,
            hotelId: evt.hotelId,
            payload: evt.cleaningSafePayload || {},
            timestamp: evt.timestamp,
          })
        }
        return
      }

      if (principal.role === 'GUEST') {
        if (evt.guestId && evt.guestId === principal.id) {
          sendEvent('message', {
            type: evt.type,
            hotelId: evt.hotelId,
            reservationId: evt.reservationId,
            payload: evt.payload,
            timestamp: evt.timestamp,
          })
        }
        return
      }

      if (principal.role === 'IOT_BRIDGE') {
        if (evt.hotelId === principal.hotelId && IOT_BRIDGE_ALLOWED_TYPES.has(evt.type)) {
          sendEvent('message', {
            type: evt.type,
            hotelId: evt.hotelId,
            payload: evt.cleaningSafePayload || evt.payload,
            timestamp: evt.timestamp,
          })
        }
      }
    })

    const heartbeat = setInterval(() => {
      try {
        reply.raw.write(': ping\n\n')
      } catch (_) {}
    }, 20000)

    request.raw.on('close', () => {
      clearInterval(heartbeat)
      unsubscribe()
    })

    return reply
  })
}

module.exports = eventsRoutes
