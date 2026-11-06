const ctrl = require('./auth.controller')

async function authRoutes(fastify) {
  // ── Huésped ──────────────────────────────────────────────
  // POST /api/v1/auth/guest/register
  fastify.post('/guest/register', ctrl.handleRegisterGuest)

  // POST /api/v1/auth/guest/verify-otp
  fastify.post('/guest/verify-otp', ctrl.handleVerifyOtp)

  // POST /api/v1/auth/guest/request-otp
  fastify.post('/guest/request-otp', ctrl.handleRequestOtp)

  // POST /api/v1/auth/guest/login
  fastify.post('/guest/login', ctrl.handleLoginGuest)

  // GET /api/v1/auth/guest/me  (requiere JWT)
  fastify.get('/guest/me', {
    preHandler: [fastify.authenticate, fastify.authorizeGuest],
  }, ctrl.handleGuestProfile)

  // ── Tokens ───────────────────────────────────────────────
  // POST /api/v1/auth/refresh
  fastify.post('/refresh', ctrl.handleRefreshToken)

  // POST /api/v1/auth/logout
  fastify.post('/logout', ctrl.handleLogout)

  // ── Propietario ──────────────────────────────────────────
  // POST /api/v1/auth/owner/register
  fastify.post('/owner/register', ctrl.handleRegisterOwner)

  // POST /api/v1/auth/owner/login
  fastify.post('/owner/login', ctrl.handleLoginOwner)

  // GET /api/v1/auth/owner/me  (requiere JWT)
  fastify.get('/owner/me', {
    preHandler: [fastify.authenticate, fastify.authorizeOwner],
  }, ctrl.handleOwnerProfile)
}

module.exports = authRoutes
