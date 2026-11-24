const Fastify = require('fastify')
const cors = require('@fastify/cors')
const helmet = require('@fastify/helmet')
const rateLimit = require('@fastify/rate-limit')
const env = require('./env')

async function buildApp() {
  const app = Fastify({
    bodyLimit: 12 * 1024 * 1024, // 12 MB para permitir subida de fotografías en Base64 / URL
    logger: {
      level: env.isDev() ? 'info' : 'warn',
      transport: env.isDev()
        ? { target: 'pino-pretty', options: { colorize: true } }
        : undefined,
    },
    trustProxy: true,
  })

  // ── Plugins de seguridad ──────────────────────────────────
  await app.register(helmet, {
    contentSecurityPolicy: false, // API REST, no sirve HTML
  })

  await app.register(cors, {
    origin: env.isProd()
      ? ['https://tudominio.com'] // reemplazar en producción
      : true,
    credentials: true,
    methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE', 'OPTIONS'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'x-hotel-bridge-token',
      'x-webhook-secret',
    ],
  })

  await app.register(rateLimit, {
    global: true,
    max: env.isProd() ? 120 : 1000,
    timeWindow: '1 minute',
    errorResponseBuilder: () => ({
      statusCode: 429,
      error: 'Too Many Requests',
      message: 'Has superado el límite de peticiones. Intenta en un momento.',
    }),
  })

  // ── JWT ───────────────────────────────────────────────────
  await app.register(require('@fastify/jwt'), {
    secret: env.JWT_SECRET,
    sign: { expiresIn: env.JWT_EXPIRES_IN },
  })

  // ── Decorators globales ───────────────────────────────────
  // Verifica JWT y adjunta payload al request
  app.decorate('authenticate', async function (request, reply) {
    try {
      await request.jwtVerify()
    } catch (err) {
      reply.status(401).send({
        statusCode: 401,
        error: 'Unauthorized',
        message: 'Token inválido o expirado',
      })
    }
  })

  // Verifica que el usuario autenticado sea propietario
  app.decorate('authorizeOwner', async function (request, reply) {
    if (request.user?.role !== 'OWNER') {
      reply.status(403).send({
        statusCode: 403,
        error: 'Forbidden',
        message: 'Acceso solo para propietarios',
      })
    }
  })

  // Verifica que el usuario sea personal operativo (CLEANING) o propietario (OWNER)
  app.decorate('authorizeCleaningOrOwner', async function (request, reply) {
    if (request.user?.role !== 'OWNER' && request.user?.role !== 'CLEANING') {
      reply.status(403).send({
        statusCode: 403,
        error: 'Forbidden',
        message: 'Acceso solo para personal operativo o propietario',
      })
    }
  })

  // Verifica que el usuario sea recepcionista (RECEPTIONIST) o propietario (OWNER)
  app.decorate('authorizeReceptionistOrOwner', async function (request, reply) {
    if (request.user?.role !== 'OWNER' && request.user?.role !== 'RECEPTIONIST') {
      reply.status(403).send({
        statusCode: 403,
        error: 'Forbidden',
        message: 'Acceso solo para recepción o propietario',
      })
    }
  })

  // Verifica que el usuario sea cualquier personal (OWNER, RECEPTIONIST, CLEANING)
  app.decorate('authorizeStaffOrOwner', async function (request, reply) {
    if (!['OWNER', 'RECEPTIONIST', 'CLEANING'].includes(request.user?.role)) {
      reply.status(403).send({
        statusCode: 403,
        error: 'Forbidden',
        message: 'Acceso restringido a personal autorizado del hotel',
      })
    }
  })

  // Verifica que el usuario autenticado sea huésped
  app.decorate('authorizeGuest', async function (request, reply) {
    if (request.user?.role !== 'GUEST') {
      reply.status(403).send({
        statusCode: 403,
        error: 'Forbidden',
        message: 'Acceso solo para huéspedes',
      })
    }
  })

  // ── Health check ──────────────────────────────────────────
  app.get('/health', async () => ({
    status: 'ok',
    timestamp: new Date().toISOString(),
    env: env.NODE_ENV,
  }))

  // ── Rutas ─────────────────────────────────────────────────
  const prefix = env.API_PREFIX

  app.register(require('../modules/auth/auth.routes'), { prefix: `${prefix}/auth` })
  app.register(require('../modules/hotels/hotels.routes'), { prefix: `${prefix}/hotels` })
  app.register(require('../modules/rooms/rooms.routes'), { prefix: `${prefix}/rooms` })
  app.register(require('../modules/reservations/reservations.routes'), { prefix: `${prefix}/reservations` })
  app.register(require('../modules/payments/payments.routes'), { prefix: `${prefix}/payments` })
  app.register(require('../modules/access/access.routes'), { prefix: `${prefix}/access` })
  app.register(require('../modules/events/events.routes'), { prefix: `${prefix}/events` })
  app.register(require('../modules/integrations/integrations.routes'), { prefix: `${prefix}/integrations` })
  app.register(require('../modules/reviews/reviews.routes'), { prefix: `${prefix}/reviews` })

  // ── Error handler global ──────────────────────────────────
  app.setErrorHandler((error, request, reply) => {
    const statusCode = error.statusCode || 500

    if (statusCode >= 500) {
      app.log.error(error)
    }

    // Errores de validación Zod
    if (error.name === 'ZodError') {
      return reply.status(422).send({
        statusCode: 422,
        error: 'Validation Error',
        message: 'Datos inválidos',
        details: error.errors,
      })
    }

    reply.status(statusCode).send({
      statusCode,
      error: error.name || 'Internal Server Error',
      message: env.isProd() && statusCode >= 500
        ? 'Error interno del servidor'
        : error.message,
    })
  })

  // ── 404 ───────────────────────────────────────────────────
  app.setNotFoundHandler((request, reply) => {
    reply.status(404).send({
      statusCode: 404,
      error: 'Not Found',
      message: `Ruta ${request.method} ${request.url} no encontrada`,
    })
  })

  return app
}

module.exports = { buildApp }
