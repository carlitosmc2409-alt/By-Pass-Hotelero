const {
  validateQrToken,
  generateReservationQr,
  invalidateQrToken,
  triggerFaacBarrierPulse,
} = require('../../utils/qr')
const { normalizeHotelSettings } = require('../../utils/hotelSettings')
const { emitRealtimeEvent } = require('../../utils/eventBus')
const { prisma } = require('../../config/database')
const dayjs = require('dayjs')
const { z } = require('zod')

const validateSchema = z.object({
  token: z.string().min(10),
  deviceId: z.string().optional(),
})

const checkoutSchema = z.object({
  reservationId: z.string().uuid(),
})

const guestFaacOpenSchema = z.object({
  reservationId: z.string().uuid(),
  direction: z.enum(['ENTRY', 'EXIT']).default('ENTRY'),
})

const ownerFaacPulseSchema = z.object({
  hotelId: z.string().uuid(),
  direction: z.enum(['ENTRY', 'EXIT']).default('ENTRY'),
  reason: z.string().max(120).optional(),
})

// POST /api/v1/access/validate
// Llamado por el tótem óptico de la barrera FAAC o la cerradura IoT al escanear el QR
async function handleValidateQr(request, reply) {
  const { token, deviceId } = validateSchema.parse(request.body)
  const result = await validateQrToken(token, deviceId)
  const statusCode = result.allowed ? 200 : 403
  return reply.status(statusCode).send(result)
}

// POST /api/v1/access/faac/open
// Apertura remota de barrera vehicular FAAC desde el teléfono del huésped con estadía activa
async function handleGuestOpenFaac(request, reply) {
  const { reservationId, direction } = guestFaacOpenSchema.parse(request.body)

  const reservation = await prisma.reservation.findUnique({
    where: { id: reservationId },
    include: {
      accessToken: true,
      room: { include: { hotel: true } },
    },
  })

  if (!reservation) {
    return reply.status(404).send({ message: 'Reserva no encontrada' })
  }
  if (reservation.guestId !== request.user.id) {
    return reply.status(403).send({ message: 'Acceso denegado a esta reserva' })
  }

  const settings = normalizeHotelSettings(reservation.room.hotel.settings)
  const faacConfig = settings.faac
  if (faacConfig.enabled === false) {
    return reply.status(400).send({ message: 'La apertura remota FAAC está deshabilitada en este hotel' })
  }

  const now = dayjs()
  const exitGraceMinutes = Number(faacConfig.exitGraceMinutes ?? 15)
  const canExitWithGrace =
    direction === 'EXIT' &&
    reservation.status === 'EXPIRED' &&
    now.isBefore(dayjs(reservation.checkOut).add(exitGraceMinutes, 'minute'))

  if (reservation.status !== 'ACTIVE' && !canExitWithGrace) {
    return reply.status(400).send({ message: 'Tu estadía no está activa para accionar la barrera FAAC' })
  }

  if (direction === 'ENTRY' && now.isAfter(dayjs(reservation.checkOut))) {
    return reply.status(403).send({ message: 'El horario de estadía ya venció' })
  }

  const deviceId = direction === 'EXIT' ? faacConfig.exitDeviceId : faacConfig.entryDeviceId

  if (reservation.accessToken) {
    await prisma.accessToken.update({
      where: { id: reservation.accessToken.id },
      data: { usedCount: { increment: 1 } },
    })
    await prisma.accessLog.create({
      data: {
        accessTokenId: reservation.accessToken.id,
        event: 'OPEN',
        deviceId,
        metadata: { accessZone: direction === 'EXIT' ? 'FAAC_EXIT' : 'FAAC_ENTRY', via: 'GUEST_APP' },
      },
    })
  }

  const faacPulse = triggerFaacBarrierPulse({
    hotelId: reservation.room.hotel.id,
    guestId: reservation.guestId,
    reservationId: reservation.id,
    roomName: reservation.room.name,
    direction,
    deviceId,
    faacConfig,
    triggeredBy: 'GUEST_APP',
  })

  return reply.send({
    allowed: true,
    direction,
    roomName: reservation.room.name,
    faacPulse,
    message:
      direction === 'EXIT'
        ? `Barrera FAAC de Salida activada (${faacPulse.pulseDurationMs} ms). Buen viaje.`
        : `Barrera FAAC de Entrada activada (${faacPulse.pulseDurationMs} ms). Avanza a Hab. ${reservation.room.name}.`,
  })
}

// POST /api/v1/access/faac/owner-pulse
// Apertura manual de cortesía/emergencia de barrera FAAC desde el Panel del Propietario
async function handleOwnerPulseFaac(request, reply) {
  const { hotelId, direction, reason } = ownerFaacPulseSchema.parse(request.body)

  const hotel = await prisma.hotel.findUnique({ where: { id: hotelId } })
  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso a este hotel' })
  }

  const settings = normalizeHotelSettings(hotel.settings)
  const faacConfig = settings.faac
  const deviceId = direction === 'EXIT' ? faacConfig.exitDeviceId : faacConfig.entryDeviceId

  const faacPulse = triggerFaacBarrierPulse({
    hotelId: hotel.id,
    direction,
    deviceId,
    faacConfig,
    roomName: reason || 'Apertura Manual Panel',
    triggeredBy: 'OWNER_PANEL',
  })

  return reply.send({
    allowed: true,
    faacPulse,
    message: `Pulso FAAC (${direction === 'EXIT' ? 'Salida' : 'Entrada'}) enviado por ${faacPulse.pulseDurationMs} ms.`,
  })
}

// POST /api/v1/access/checkout
// Check-out manual desde la app del huésped
async function handleCheckout(request, reply) {
  const { reservationId } = checkoutSchema.parse(request.body)

  const reservation = await prisma.reservation.findUnique({
    where: { id: reservationId },
    include: { room: true },
  })

  if (!reservation) {
    return reply.status(404).send({ message: 'Reserva no encontrada' })
  }

  if (reservation.guestId !== request.user.id) {
    return reply.status(403).send({ message: 'No tienes permiso para hacer check-out de esta reserva' })
  }

  if (reservation.status !== 'ACTIVE') {
    return reply.status(400).send({ message: 'La reserva no está activa' })
  }

  await prisma.$transaction([
    prisma.reservation.update({
      where: { id: reservationId },
      data: { status: 'COMPLETED', checkOut: new Date() },
    }),
    prisma.room.update({
      where: { id: reservation.roomId },
      data: { status: 'CLEANING' },
    }),
  ])

  await invalidateQrToken(reservationId)

  emitRealtimeEvent({
    hotelId: reservation.room.hotelId,
    guestId: reservation.guestId,
    reservationId,
    type: 'ROOM_STATUS_CHANGED',
    payload: {
      roomId: reservation.roomId,
      roomName: reservation.room.name,
      status: 'CLEANING',
      reason: 'GUEST_CHECKOUT',
    },
    cleaningSafePayload: {
      roomId: reservation.roomId,
      roomName: reservation.room.name,
      status: 'CLEANING',
      reason: 'GUEST_CHECKOUT',
    },
  })

  return reply.send({ message: 'Check-out realizado exitosamente' })
}

// GET /api/v1/access/qr/:reservationId
// Obtener el QR de una reserva activa (huésped autenticado)
async function handleGetQr(request, reply) {
  const { reservationId } = request.params

  const reservation = await prisma.reservation.findUnique({
    where: { id: reservationId },
    include: { room: { include: { hotel: true } } },
  })

  if (!reservation) {
    return reply.status(404).send({ message: 'Reserva no encontrada' })
  }

  if (reservation.guestId !== request.user.id) {
    return reply.status(403).send({ message: 'Acceso denegado' })
  }

  if (reservation.status !== 'ACTIVE') {
    return reply.status(400).send({ message: 'La reserva no está activa o el pago no ha sido confirmado' })
  }

  const qrData = await generateReservationQr(
    reservationId,
    reservation.checkIn,
    reservation.checkOut
  )

  const settings = normalizeHotelSettings(reservation.room.hotel.settings)

  return reply.send({
    qrDataUrl: qrData.qrDataUrl,
    rawToken: qrData.rawToken,
    validFrom: qrData.validFrom,
    validUntil: qrData.validUntil,
    hotelId: reservation.room.hotel.id,
    hotelName: reservation.room.hotel.name,
    roomName: reservation.room.name,
    faac: {
      enabled: settings.faac.enabled !== false,
      model: settings.faac.model,
      entryDeviceId: settings.faac.entryDeviceId,
      exitDeviceId: settings.faac.exitDeviceId,
      exitGraceMinutes: settings.faac.exitGraceMinutes,
    },
  })
}

module.exports = {
  handleValidateQr,
  handleGuestOpenFaac,
  handleOwnerPulseFaac,
  handleCheckout,
  handleGetQr,
}
