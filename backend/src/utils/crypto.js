const crypto = require('crypto')
const env = require('../config/env')

/**
 * Crea un hash SHA-256 de un valor usando la clave secreta de la app.
 * Se usa para guardar teléfonos, códigos OTP y refresh tokens de forma segura.
 */
function hashValue(value) {
  return crypto
    .createHmac('sha256', env.JWT_SECRET)
    .update(String(value))
    .digest('hex')
}

/**
 * Genera un código OTP numérico de N dígitos.
 */
function generateOtp(length = 6) {
  const max = Math.pow(10, length)
  const code = crypto.randomInt(0, max)
  return String(code).padStart(length, '0')
}

/**
 * Genera un token QR seguro (UUID v4 + timestamp + firma HMAC).
 * Retorna: { rawToken, tokenHash }
 * - rawToken: se envía a la app del huésped (nunca se guarda en BD)
 * - tokenHash: se guarda en BD para validación posterior
 */
function generateQrToken(reservationId) {
  const random = crypto.randomBytes(32).toString('hex')
  const timestamp = Date.now()
  const payload = `${reservationId}:${random}:${timestamp}`

  const signature = crypto
    .createHmac('sha256', env.QR_SECRET_KEY)
    .update(payload)
    .digest('hex')

  const rawToken = `${payload}:${signature}`
  const tokenHash = crypto
    .createHash('sha256')
    .update(rawToken)
    .digest('hex')

  return { rawToken, tokenHash }
}

/**
 * Valida la firma del token QR (autenticidad del token).
 * No verifica vigencia — eso lo hace la BD.
 */
function validateQrTokenSignature(rawToken) {
  if (typeof rawToken !== 'string') return false
  const parts = rawToken.split(':')
  if (parts.length !== 4) return false

  const [reservationId, random, timestamp, signature] = parts
  const payload = `${reservationId}:${random}:${timestamp}`

  const expectedSignature = crypto
    .createHmac('sha256', env.QR_SECRET_KEY)
    .update(payload)
    .digest('hex')

  const received = Buffer.from(signature, 'hex')
  const expected = Buffer.from(expectedSignature, 'hex')

  // timingSafeEqual lanza error si las longitudes difieren (firma malformada)
  if (received.length !== expected.length) return false

  return crypto.timingSafeEqual(received, expected)
}

/**
 * Obtiene el hash de un token QR raw (para buscar en BD).
 */
function hashQrToken(rawToken) {
  return crypto.createHash('sha256').update(rawToken).digest('hex')
}

module.exports = {
  hashValue,
  generateOtp,
  generateQrToken,
  validateQrTokenSignature,
  hashQrToken,
}
