const authService = require('./auth.service')
const { BANKS } = require('../../utils/banks')
const {
  registerGuestSchema,
  updatePaymentProfileSchema,
  verifyOtpSchema,
  loginGuestSchema,
  refreshTokenSchema,
  requestOtpSchema,
  registerOwnerSchema,
  loginOwnerSchema,
  loginCleaningSchema,
  loginReceptionistSchema,
} = require('./auth.schema')

// ── GUEST ─────────────────────────────────────────────────────

async function handleRegisterGuest(request, reply) {
  const data = registerGuestSchema.parse(request.body)
  const result = await authService.registerGuest(data)
  return reply.status(201).send(result)
}

async function handleVerifyOtp(request, reply) {
  const { phone, code, purpose } = verifyOtpSchema.parse(request.body)
  const result = await authService.verifyGuestOtp(phone, code, purpose)
  return reply.send(result)
}

async function handleRequestOtp(request, reply) {
  const { phone, purpose } = requestOtpSchema.parse(request.body)
  const result = await authService.requestOtp(phone, purpose)
  return reply.send(result)
}

async function handleLoginGuest(request, reply) {
  const { phone, password } = loginGuestSchema.parse(request.body)
  const meta = {
    userAgent: request.headers['user-agent'],
    ip: request.ip,
  }
  const tokens = await authService.loginGuest(phone, password, request.server, meta)
  return reply.send(tokens)
}

async function handleRefreshToken(request, reply) {
  const { refreshToken } = refreshTokenSchema.parse(request.body)
  const result = await authService.refreshAccessToken(refreshToken, request.server)
  return reply.send(result)
}

async function handleLogout(request, reply) {
  const { refreshToken } = refreshTokenSchema.parse(request.body)
  await authService.revokeRefreshToken(refreshToken)
  return reply.send({ message: 'Sesión cerrada exitosamente' })
}

async function handleGuestProfile(request, reply) {
  const { prisma } = require('../../config/database')
  const guest = await prisma.guest.findUnique({
    where: { id: request.user.id },
    select: {
      id: true,
      fullName: true,
      phone: true,
      cedula: true,
      paymentBank: true,
      paymentCedula: true,
      paymentPhone: true,
      isVerified: true,
      createdAt: true,
    },
  })
  if (!guest) return reply.status(404).send({ message: 'Huésped no encontrado' })

  const { paymentBank, paymentCedula, paymentPhone, ...rest } = guest
  return reply.send({
    ...rest,
    paymentProfile: authService.formatGuestPaymentProfile(guest),
  })
}

async function handleUpdatePaymentProfile(request, reply) {
  const data = updatePaymentProfileSchema.parse(request.body)
  const result = await authService.updateGuestPaymentProfile(request.user.id, data)
  return reply.send(result)
}

async function handleListBanks(_request, reply) {
  const list = Object.entries(BANKS).map(([code, name]) => ({ code, name }))
  return reply.send(list)
}

// ── OWNER ─────────────────────────────────────────────────────

async function handleRegisterOwner(request, reply) {
  const data = registerOwnerSchema.parse(request.body)
  const result = await authService.registerOwner(data)
  return reply.status(201).send(result)
}

async function handleLoginOwner(request, reply) {
  const { email, password } = loginOwnerSchema.parse(request.body)
  const meta = {
    userAgent: request.headers['user-agent'],
    ip: request.ip,
  }
  const tokens = await authService.loginOwner(email, password, request.server, meta)
  return reply.send(tokens)
}

async function handleOwnerProfile(request, reply) {
  const { prisma } = require('../../config/database')
  const owner = await prisma.owner.findUnique({
    where: { id: request.user.id },
    select: {
      id: true,
      fullName: true,
      email: true,
      phone: true,
      cedula: true,
      isActive: true,
      createdAt: true,
    },
  })
  if (!owner) return reply.status(404).send({ message: 'Propietario no encontrado' })
  return reply.send(owner)
}

async function handleLoginCleaning(request, reply) {
  const data = loginCleaningSchema.parse(request.body)
  const result = await authService.loginCleaningStaff(data, request.server)
  return reply.send(result)
}

async function handleLoginReceptionist(request, reply) {
  const data = loginReceptionistSchema.parse(request.body)
  const result = await authService.loginReceptionist(data, request.server)
  return reply.send(result)
}

// ── RECUPERACIÓN DE CONTRASEÑA (EMAIL RESEND) ─────────────────

async function handleForgotPassword(request, reply) {
  const { email } = request.body || {}
  if (!email) {
    return reply.status(400).send({ message: 'El email es requerido' })
  }
  const result = await authService.requestPasswordReset(email)
  return reply.send(result)
}

async function handleResetPassword(request, reply) {
  const { email, code, newPassword } = request.body || {}
  if (!email || !code || !newPassword) {
    return reply.status(400).send({ message: 'email, code y newPassword son requeridos' })
  }
  if (newPassword.length < 8) {
    return reply.status(400).send({ message: 'La nueva contraseña debe tener al menos 8 caracteres' })
  }
  const result = await authService.resetPassword(email, code, newPassword)
  return reply.send(result)
}

module.exports = {
  handleRegisterGuest,
  handleVerifyOtp,
  handleRequestOtp,
  handleLoginGuest,
  handleRefreshToken,
  handleLogout,
  handleGuestProfile,
  handleUpdatePaymentProfile,
  handleListBanks,
  handleRegisterOwner,
  handleLoginOwner,
  handleOwnerProfile,
  handleLoginCleaning,
  handleLoginReceptionist,
  handleForgotPassword,
  handleResetPassword,
}
