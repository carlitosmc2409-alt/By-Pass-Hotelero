const { validateQrToken, generateReservationQr, invalidateQrToken } = require('../../utils/qr')
const { prisma } = require('../../config/database')
const { z } = require('zod')

const validateSchema = z.object({
  token: z.string().min(10),
  deviceId: z.string().optional(),
})

const checkoutSchema = z.object({
  reservationId: z.string().uuid(),
})

// POST /api/v1/access/validate
// Llamado por la cerradura IoT al escanear el QR
async function handleValidateQr(request, reply) {
  const { token, deviceId } = validateSchema.parse(request.body)
  const result = await validateQrToken(token, deviceId)
  const statusCode = result.allowed ? 200 : 403
  return reply.status(statusCode).send(result)
}

// POST /api/v1/access/checkout
// Check-out manual desde la app del huésped
async function handleCheckout(request, reply) {
  const { reservationId } = checkoutSchema.parse(request.body)

  // Verificar que la reserva pertenece al huésped autenticado
  const reservation = await prisma.reservation.findUnique({
    where: { id: reservationId },
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

  // Cada solicitud emite un token nuevo e invalida el anterior
  const qrData = await generateReservationQr(
    reservationId,
    reservation.checkIn,
    reservation.checkOut
  )

  return reply.send({
    qrDataUrl: qrData.qrDataUrl,
    rawToken: qrData.rawToken,
    validFrom: qrData.validFrom,
    validUntil: qrData.validUntil,
    hotelName: reservation.room.hotel.name,
    roomName: reservation.room.name,
  })
}

module.exports = { handleValidateQr, handleCheckout, handleGetQr }
