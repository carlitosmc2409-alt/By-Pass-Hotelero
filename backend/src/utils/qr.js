const QRCode = require('qrcode')
const { generateQrToken } = require('./crypto')
const dayjs = require('dayjs')
const { prisma } = require('../config/database')

/**
 * Emite (o rota) el token QR de una reserva confirmada.
 * Solo se guarda el hash del token, por lo que el token en claro solo existe
 * en esta respuesta. Cada llamada ROTA el token: el QR anterior deja de
 * funcionar y se devuelve uno nuevo (conserva usedCount y la ventana de tiempo).
 *
 * @param {string} reservationId
 * @param {Date} checkIn
 * @param {Date} checkOut
 * @returns {{ qrDataUrl: string, rawToken: string, validFrom: Date, validUntil: Date, accessTokenId: string }}
 */
async function generateReservationQr(reservationId, checkIn, checkOut) {
  const { rawToken, tokenHash } = generateQrToken(reservationId)

  const accessToken = await prisma.accessToken.upsert({
    where: { reservationId },
    create: {
      reservationId,
      tokenHash,
      validFrom: checkIn,
      validUntil: checkOut,
      isActive: true,
    },
    update: {
      tokenHash,
      validFrom: checkIn,
      validUntil: checkOut,
      isActive: true,
    },
  })

  // Generar imagen QR a partir del rawToken
  // El rawToken incluye la info de la reserva y la firma — nunca la cédula ni datos del huésped
  const qrDataUrl = await QRCode.toDataURL(rawToken, {
    errorCorrectionLevel: 'H',
    width: 400,
    margin: 2,
    color: {
      dark: '#1a1a2e',
      light: '#ffffff',
    },
  })

  return {
    qrDataUrl,
    rawToken,         // se envía al cliente; NO se guarda en BD
    validFrom: accessToken.validFrom,
    validUntil: accessToken.validUntil,
    accessTokenId: accessToken.id,
  }
}

/**
 * Valida un token QR escaneado por la cerradura.
 * Registra el evento y retorna si se debe abrir o no.
 *
 * @param {string} rawToken - Token recibido del QR
 * @param {string} deviceId - ID de la cerradura que escanea
 * @returns {{ allowed: boolean, message: string, reservationId?: string }}
 */
async function validateQrToken(rawToken, deviceId = null) {
  const { validateQrTokenSignature, hashQrToken } = require('./crypto')

  // 1. Verificar firma criptográfica
  const signatureValid = validateQrTokenSignature(rawToken)
  if (!signatureValid) {
    await logAccessEvent(null, 'DENIED', deviceId, { reason: 'invalid_signature' })
    return { allowed: false, message: 'Código QR inválido' }
  }

  // 2. Buscar en BD por hash
  const tokenHash = hashQrToken(rawToken)
  const accessToken = await prisma.accessToken.findUnique({
    where: { tokenHash },
    include: { reservation: { include: { room: true } } },
  })

  if (!accessToken) {
    return { allowed: false, message: 'Código QR no reconocido' }
  }

  const now = dayjs()

  // 3. Verificar si está activo
  if (!accessToken.isActive) {
    await logAccessEvent(accessToken.id, 'EXPIRED', deviceId, { reason: 'inactive' })
    return { allowed: false, message: 'Código QR desactivado' }
  }

  // 4. Verificar ventana de tiempo
  if (now.isBefore(dayjs(accessToken.validFrom))) {
    await logAccessEvent(accessToken.id, 'DENIED', deviceId, { reason: 'too_early' })
    return { allowed: false, message: 'La reserva aún no ha comenzado' }
  }

  if (now.isAfter(dayjs(accessToken.validUntil))) {
    // Marcar como inactivo
    await prisma.accessToken.update({
      where: { id: accessToken.id },
      data: { isActive: false },
    })
    await logAccessEvent(accessToken.id, 'EXPIRED', deviceId, { reason: 'time_expired' })
    return { allowed: false, message: 'El tiempo de estadía ha expirado' }
  }

  // 5. Verificar usos máximos
  if (accessToken.usedCount >= accessToken.maxUses) {
    await logAccessEvent(accessToken.id, 'DENIED', deviceId, { reason: 'max_uses_reached' })
    return { allowed: false, message: 'Número máximo de accesos alcanzado' }
  }

  // 6. ✅ Acceso permitido — incrementar contador
  await prisma.accessToken.update({
    where: { id: accessToken.id },
    data: { usedCount: { increment: 1 } },
  })

  await logAccessEvent(accessToken.id, 'OPEN', deviceId)

  return {
    allowed: true,
    message: 'Acceso permitido',
    reservationId: accessToken.reservationId,
    roomName: accessToken.reservation.room.name,
    validUntil: accessToken.validUntil,
  }
}

/**
 * Invalida un QR (checkout manual o expiración forzada).
 */
async function invalidateQrToken(reservationId) {
  await prisma.accessToken.updateMany({
    where: { reservationId, isActive: true },
    data: { isActive: false },
  })
}

async function logAccessEvent(accessTokenId, event, deviceId, metadata = {}) {
  if (!accessTokenId) return
  await prisma.accessLog.create({
    data: { accessTokenId, event, deviceId, metadata },
  })
}

module.exports = {
  generateReservationQr,
  validateQrToken,
  invalidateQrToken,
}
