const bcrypt = require('bcryptjs')
const crypto = require('crypto')
const { v4: uuidv4 } = require('uuid')
const dayjs = require('dayjs')
const { prisma } = require('../../config/database')
const env = require('../../config/env')
const { hashValue, generateOtp } = require('../../utils/crypto')
const { encryptField, decryptField, maskTail } = require('../../utils/fieldCrypto')
const { bankName } = require('../../utils/banks')
const { sendWhatsAppOtp } = require('../../utils/whatsapp')

// ── GUEST AUTH ────────────────────────────────────────────────

/**
 * Registra un nuevo huésped junto con sus datos de pago frecuente.
 * Envía OTP por WhatsApp para verificar el teléfono.
 */
async function registerGuest(data) {
  const {
    fullName,
    phone,
    cedula,
    paymentBank,
    paymentPhone,
    paymentCedula,
    password,
  } = data

  // Verificar si el teléfono ya existe
  const phoneHash = hashValue(phone)
  const existing = await prisma.guest.findUnique({ where: { phoneHash } })
  if (existing) {
    const error = new Error('Este número de teléfono ya está registrado')
    error.statusCode = 409
    throw error
  }

  // Verificar cédula
  if (cedula) {
    const existingCedula = await prisma.guest.findUnique({ where: { cedula } })
    if (existingCedula) {
      const error = new Error('Esta cédula ya está registrada')
      error.statusCode = 409
      throw error
    }
  }

  const passwordHash = await bcrypt.hash(password, env.BCRYPT_ROUNDS)
  const effectivePaymentCedula = paymentCedula || cedula
  const effectivePaymentPhone = paymentPhone || phone

  const guest = await prisma.guest.create({
    data: {
      fullName,
      phone,         // guardamos el teléfono en claro para enviar WhatsApp
      phoneHash,
      cedula,
      paymentBank,
      paymentCedula: encryptField(effectivePaymentCedula),
      paymentPhone: encryptField(effectivePaymentPhone),
      passwordHash,
      isVerified: false,
    },
    select: {
      id: true,
      fullName: true,
      phone: true,
      isVerified: true,
      createdAt: true,
    },
  })

  // Enviar OTP de verificación
  await createAndSendOtp(phone, guest.id, 'PHONE_VERIFICATION')

  return {
    message: 'Registro exitoso. Revisa tu WhatsApp para verificar tu número.',
    guestId: guest.id,
  }
}

/**
 * Actualiza los datos de pago frecuente del huésped.
 */
async function updateGuestPaymentProfile(guestId, { paymentCedula, paymentBank, paymentPhone }) {
  await prisma.guest.update({
    where: { id: guestId },
    data: {
      paymentBank,
      paymentCedula: encryptField(paymentCedula),
      paymentPhone: encryptField(paymentPhone),
    },
  })

  return {
    message: 'Datos de pago frecuente actualizados',
    paymentProfile: {
      bankCode: paymentBank,
      bankName: bankName(paymentBank),
      cedulaMasked: maskTail(paymentCedula, 4),
      phoneMasked: maskTail(paymentPhone, 4),
    },
  }
}

/**
 * Formatea el perfil de pago frecuente del huésped (enmascarado para respuestas API).
 */
function formatGuestPaymentProfile(guest) {
  if (!guest.paymentBank || !guest.paymentCedula || !guest.paymentPhone) {
    return null
  }
  const cedulaPlain = decryptField(guest.paymentCedula)
  const phonePlain = decryptField(guest.paymentPhone)
  return {
    bankCode: guest.paymentBank,
    bankName: bankName(guest.paymentBank),
    cedulaMasked: maskTail(cedulaPlain, 4),
    phoneMasked: maskTail(phonePlain, 4),
  }
}

/**
 * Verifica el OTP y activa la cuenta del huésped.
 */
async function verifyGuestOtp(phone, code, purpose) {
  const phoneHash = hashValue(phone)
  const codeHash = hashValue(code)

  // Buscar OTP válido
  const otp = await prisma.otpCode.findFirst({
    where: {
      phone,
      codeHash,
      purpose,
      isUsed: false,
      expiresAt: { gt: new Date() },
    },
  })

  if (!otp) {
    const error = new Error('Código OTP inválido o expirado')
    error.statusCode = 400
    throw error
  }

  // Marcar OTP como usado
  await prisma.otpCode.update({
    where: { id: otp.id },
    data: { isUsed: true },
  })

  if (purpose === 'PHONE_VERIFICATION') {
    // Activar cuenta
    await prisma.guest.update({
      where: { phoneHash },
      data: { isVerified: true },
    })
    return { message: 'Teléfono verificado exitosamente. Ya puedes iniciar sesión.' }
  }

  return { message: 'Código verificado correctamente.' }
}

/**
 * Login de huésped con teléfono + contraseña.
 * Devuelve accessToken + refreshToken.
 */
async function loginGuest(phone, password, app, meta = {}) {
  const phoneHash = hashValue(phone)
  const guest = await prisma.guest.findUnique({ where: { phoneHash } })

  if (!guest) {
    const error = new Error('Teléfono o contraseña incorrectos')
    error.statusCode = 401
    throw error
  }

  if (!guest.isActive) {
    const error = new Error('Cuenta desactivada. Contacta soporte.')
    error.statusCode = 403
    throw error
  }

  if (!guest.isVerified) {
    const error = new Error('Debes verificar tu número de teléfono primero')
    error.statusCode = 403
    throw error
  }

  const validPassword = await bcrypt.compare(password, guest.passwordHash)
  if (!validPassword) {
    const error = new Error('Teléfono o contraseña incorrectos')
    error.statusCode = 401
    throw error
  }

  return generateTokenPair(app, {
    id: guest.id,
    role: 'GUEST',
    fullName: guest.fullName,
  }, { guestId: guest.id }, meta)
}

// ── OWNER AUTH ────────────────────────────────────────────────

/**
 * Registra un nuevo propietario de hotel.
 */
async function registerOwner(data) {
  const { fullName, email, phone, cedula, password } = data

  const existingEmail = await prisma.owner.findUnique({ where: { email } })
  if (existingEmail) {
    const error = new Error('Este email ya está registrado')
    error.statusCode = 409
    throw error
  }

  const existingPhone = await prisma.owner.findUnique({ where: { phone } })
  if (existingPhone) {
    const error = new Error('Este teléfono ya está registrado')
    error.statusCode = 409
    throw error
  }

  if (cedula) {
    const existingCedula = await prisma.owner.findUnique({ where: { cedula } })
    if (existingCedula) {
      const error = new Error('Esta cédula ya está registrada')
      error.statusCode = 409
      throw error
    }
  }

  const passwordHash = await bcrypt.hash(password, env.BCRYPT_ROUNDS)

  const owner = await prisma.owner.create({
    data: { fullName, email, phone, cedula, passwordHash },
    select: { id: true, fullName: true, email: true, createdAt: true },
  })

  return {
    message: 'Propietario registrado exitosamente.',
    ownerId: owner.id,
  }
}

/**
 * Login de propietario con email + contraseña.
 */
async function loginOwner(email, password, app, meta = {}) {
  const owner = await prisma.owner.findUnique({ where: { email } })

  if (!owner) {
    const error = new Error('Email o contraseña incorrectos')
    error.statusCode = 401
    throw error
  }

  if (!owner.isActive) {
    const error = new Error('Cuenta desactivada. Contacta soporte.')
    error.statusCode = 403
    throw error
  }

  const validPassword = await bcrypt.compare(password, owner.passwordHash)
  if (!validPassword) {
    const error = new Error('Email o contraseña incorrectos')
    error.statusCode = 401
    throw error
  }

  return generateTokenPair(app, {
    id: owner.id,
    role: 'OWNER',
    fullName: owner.fullName,
  }, { ownerId: owner.id }, meta)
}

/**
 * Login de personal operativo de limpieza/camareras (CLEANING) sin acceso financiero.
 */
async function loginCleaningStaff({ hotelCode, alias, pin }, app) {
  const { normalizeHotelSettings } = require('../../utils/hotelSettings')
  const cleanAlias = String(alias || '').trim().toLowerCase()
  const cleanCode = String(hotelCode || '').trim().toLowerCase()

  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(cleanCode)
  const hotels = await prisma.hotel.findMany({
    where: {
      status: 'ACTIVE',
      ...(cleanCode
        ? {
            OR: [
              ...(isUuid ? [{ id: cleanCode }] : []),
              { slug: cleanCode },
              { slug: { contains: cleanCode, mode: 'insensitive' } },
            ],
          }
        : {}),
    },
    select: { id: true, name: true, slug: true, settings: true },
  })

  for (const hotel of hotels) {
    const settings = normalizeHotelSettings(hotel.settings)
    const staff = settings.cleaningStaff.find(
      s => s.active !== false && String(s.alias || '').toLowerCase() === cleanAlias
    )
    if (staff && staff.pinHash) {
      const ok = await bcrypt.compare(String(pin), staff.pinHash)
      if (ok) {
        const accessToken = app.jwt.sign(
          {
            id: staff.id,
            role: 'CLEANING',
            hotelId: hotel.id,
            hotelName: hotel.name,
            fullName: staff.name,
            alias: staff.alias,
          },
          { expiresIn: '12h' }
        )
        return {
          accessToken,
          role: 'CLEANING',
          hotelId: hotel.id,
          hotelName: hotel.name,
          staffName: staff.name,
          alias: staff.alias,
        }
      }
    }
  }

  const error = new Error('Alias, código de hotel o PIN operativo incorrectos')
  error.statusCode = 401
  throw error
}

// ── TOKENS ────────────────────────────────────────────────────

/**
 * Genera un par accessToken + refreshToken y guarda el refresh en BD.
 */
async function generateTokenPair(app, payload, dbRelation, meta = {}) {
  // Access token (corta duración)
  const accessToken = app.jwt.sign(payload)

  // Refresh token (larga duración, UUID aleatorio)
  const rawRefresh = uuidv4()
  const tokenHash = hashValue(rawRefresh)

  const expiresAt = dayjs().add(7, 'day').toDate()

  await prisma.refreshToken.create({
    data: {
      ...dbRelation,
      tokenHash,
      userAgent: meta.userAgent || null,
      ip: meta.ip || null,
      expiresAt,
    },
  })

  return { accessToken, refreshToken: rawRefresh }
}

/**
 * Renueva el access token usando el refresh token.
 */
async function refreshAccessToken(rawRefreshToken, app) {
  const tokenHash = hashValue(rawRefreshToken)

  const record = await prisma.refreshToken.findUnique({ where: { tokenHash } })

  if (!record || record.revokedAt || dayjs().isAfter(record.expiresAt)) {
    const error = new Error('Refresh token inválido o expirado')
    error.statusCode = 401
    throw error
  }

  // Determinar tipo de usuario
  let payload
  if (record.guestId) {
    const guest = await prisma.guest.findUnique({ where: { id: record.guestId } })
    payload = { id: guest.id, role: 'GUEST', fullName: guest.fullName }
  } else if (record.ownerId) {
    const owner = await prisma.owner.findUnique({ where: { id: record.ownerId } })
    payload = { id: owner.id, role: 'OWNER', fullName: owner.fullName }
  }

  const accessToken = app.jwt.sign(payload)
  return { accessToken }
}

/**
 * Revoca el refresh token (logout).
 */
async function revokeRefreshToken(rawRefreshToken) {
  const tokenHash = hashValue(rawRefreshToken)
  await prisma.refreshToken.updateMany({
    where: { tokenHash, revokedAt: null },
    data: { revokedAt: new Date() },
  })
}

// ── OTP ───────────────────────────────────────────────────────

async function createAndSendOtp(phone, guestId, purpose) {
  // Invalidar OTPs anteriores del mismo tipo
  await prisma.otpCode.updateMany({
    where: { phone, purpose, isUsed: false },
    data: { isUsed: true },
  })

  const code = generateOtp(env.OTP_LENGTH)
  const codeHash = hashValue(code)
  const expiresAt = dayjs().add(env.OTP_EXPIRES_MINUTES, 'minute').toDate()

  await prisma.otpCode.create({
    data: {
      guestId: guestId || null,
      phone,
      code,       // solo durante creación, no persiste en claro en DB
      codeHash,
      purpose,
      expiresAt,
    },
  })

  // Limpiar código en claro de BD inmediatamente
  // (el hash ya fue guardado, el código en claro solo se usa para enviar)
  await prisma.otpCode.updateMany({
    where: { phone, codeHash },
    data: { code: '' }, // limpiamos el código en claro
  })

  await sendWhatsAppOtp(phone, code, purpose)
}

async function requestOtp(phone, purpose) {
  const phoneHash = hashValue(phone)
  const guest = await prisma.guest.findUnique({ where: { phoneHash } })
  if (!guest) {
    const error = new Error('Número no registrado')
    error.statusCode = 404
    throw error
  }
  await createAndSendOtp(phone, guest.id, purpose)
  return { message: `Código OTP enviado a ${phone.slice(0, 6)}****` }
}

module.exports = {
  registerGuest,
  updateGuestPaymentProfile,
  formatGuestPaymentProfile,
  verifyGuestOtp,
  loginGuest,
  registerOwner,
  loginOwner,
  loginCleaningStaff,
  refreshAccessToken,
  revokeRefreshToken,
  requestOtp,
}
