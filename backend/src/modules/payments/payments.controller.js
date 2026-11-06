const { prisma } = require('../../config/database')
const { z } = require('zod')

/**
 * PAGOS EN VENEZUELA
 *
 * Estrategia para el piloto:
 * 1. Pago Móvil: el huésped hace la transferencia y envía el número de referencia.
 *    El propietario confirma manualmente (o por webhook si el banco lo soporta).
 * 2. Zelle: el huésped transfiere y sube comprobante. Propietario confirma.
 * 3. Binance Pay: integración directa (fase posterior).
 *
 * Flujo:
 *   Huésped → POST /payments/:id/submit-proof → sube referencia/comprobante
 *   Propietario → POST /payments/:id/confirm → confirma pago
 *   Sistema → genera QR automáticamente al confirmar
 */

const submitProofSchema = z.object({
  gatewayRef: z.string().min(4, 'Referencia de pago requerida'),
  notes: z.string().max(500).optional(),
})

// POST /api/v1/payments/:paymentId/submit-proof
// Huésped envía referencia del pago (Pago Móvil / Zelle)
async function handleSubmitProof(request, reply) {
  const { gatewayRef, notes } = submitProofSchema.parse(request.body)

  const payment = await prisma.payment.findUnique({
    where: { id: request.params.paymentId },
    include: { reservation: true },
  })

  if (!payment) return reply.status(404).send({ message: 'Pago no encontrado' })
  if (payment.reservation.guestId !== request.user.id) {
    return reply.status(403).send({ message: 'Acceso denegado' })
  }
  if (payment.status !== 'PENDING') {
    return reply.status(400).send({ message: 'Este pago ya fue procesado' })
  }

  await prisma.$transaction([
    prisma.payment.update({
      where: { id: payment.id },
      data: {
        gatewayRef,
        status: 'PENDING_REVIEW',
        metadata: { notes: notes || null, submittedAt: new Date() },
      },
    }),
    prisma.reservation.update({
      where: { id: payment.reservationId },
      data: { status: 'PAYMENT_PENDING_REVIEW' },
    }),
  ])

  return reply.send({
    message: 'Referencia de pago enviada. El propietario confirmará en breve.',
  })
}

// POST /api/v1/payments/:paymentId/confirm  — PROPIETARIO confirma el pago
async function handleConfirmPayment(request, reply) {
  const payment = await prisma.payment.findUnique({
    where: { id: request.params.paymentId },
    include: {
      reservation: { include: { room: { include: { hotel: true } } } },
    },
  })

  if (!payment) return reply.status(404).send({ message: 'Pago no encontrado' })

  // Solo el propietario del hotel puede confirmar
  if (payment.reservation.room.hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin permiso para confirmar este pago' })
  }

  if (!['PENDING', 'PENDING_REVIEW'].includes(payment.status)) {
    return reply.status(400).send({ message: 'El pago ya fue procesado' })
  }

  // Confirmar pago y activar reserva en transacción
  const [, updatedReservation] = await prisma.$transaction([
    prisma.payment.update({
      where: { id: payment.id },
      data: {
        status: 'APPROVED',
        confirmedAt: new Date(),
        confirmedBy: request.user.id,
      },
    }),
    prisma.reservation.update({
      where: { id: payment.reservationId },
      data: { status: 'ACTIVE' },
    }),
    prisma.room.update({
      where: { id: payment.reservation.roomId },
      data: { status: 'OCCUPIED' },
    }),
  ])

  // El QR lo emite el huésped al consultarlo (GET /access/qr/:reservationId)
  return reply.send({
    message: 'Pago confirmado. La reserva está activa y el huésped ya puede obtener su QR.',
    reservationId: updatedReservation.id,
    // En producción: notificar al huésped por WhatsApp que su reserva está activa
  })
}

// POST /api/v1/payments/:paymentId/reject  — PROPIETARIO rechaza el pago
async function handleRejectPayment(request, reply) {
  const payment = await prisma.payment.findUnique({
    where: { id: request.params.paymentId },
    include: { reservation: { include: { room: { include: { hotel: true } } } } },
  })

  if (!payment) return reply.status(404).send({ message: 'Pago no encontrado' })
  if (payment.reservation.room.hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin permiso' })
  }

  await prisma.$transaction([
    prisma.payment.update({
      where: { id: payment.id },
      data: { status: 'FAILED' },
    }),
    prisma.reservation.update({
      where: { id: payment.reservationId },
      data: { status: 'CANCELLED' },
    }),
  ])

  return reply.send({ message: 'Pago rechazado y reserva cancelada.' })
}

// GET /api/v1/payments/pending/:hotelId  — pagos pendientes de un hotel
async function handleListPending(request, reply) {
  const { hotelId } = request.params
  const hotel = await prisma.hotel.findUnique({ where: { id: hotelId } })

  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso' })
  }

  const payments = await prisma.payment.findMany({
    where: {
      status: { in: ['PENDING', 'PENDING_REVIEW'] },
      reservation: { room: { hotelId } },
    },
    include: {
      reservation: {
        include: {
          room: { select: { name: true } },
          guest: { select: { fullName: true, phone: true } },
        },
      },
    },
    orderBy: { createdAt: 'asc' },
  })

  return reply.send(payments)
}

module.exports = {
  handleSubmitProof,
  handleConfirmPayment,
  handleRejectPayment,
  handleListPending,
}
