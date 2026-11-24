const { prisma } = require('../../config/database')
const env = require('../../config/env')
const { validateHotelBridgeToken } = require('../../utils/crypto')
const {
  normalizeRef,
  activateApprovedPaymentInTx,
  broadcastActivationEvents,
  reconcilePayment,
  recordBankEvent,
} = require('./paymentVerifier')
const { z } = require('zod')

const submitProofSchema = z.object({
  gatewayRef: z.string().min(4, 'Referencia de pago requerida'),
  notes: z.string().max(500).optional(),
  skipAutoSimulate: z.boolean().optional(),
})

const bdvNotificationSchema = z.object({
  hotelId: z.string().uuid(),
  rawText: z.string().optional(),
  amountVes: z.number().positive().optional(),
  reference: z.string().optional(),
  payerPhone: z.string().optional(),
  payerCedula: z.string().optional(),
  payerBank: z.string().optional(),
  concept: z.string().optional(),
  source: z.enum(['SIMULATED', 'BDV_NOTIFICATION']).optional(),
})

// POST /api/v1/payments/:paymentId/submit-proof
// Huésped envía referencia del pago (Pago Móvil) y el sistema intenta conciliarlo al instante
async function handleSubmitProof(request, reply) {
  const { gatewayRef: rawRef, notes, skipAutoSimulate } = submitProofSchema.parse(request.body)
  const gatewayRef = normalizeRef(rawRef)

  if (gatewayRef.length < 4) {
    return reply.status(422).send({
      statusCode: 422,
      error: 'Validation Error',
      message: 'La referencia debe contener al menos 4 dígitos numéricos',
    })
  }

  const payment = await prisma.payment.findUnique({
    where: { id: request.params.paymentId },
    include: { reservation: true },
  })

  if (!payment) return reply.status(404).send({ message: 'Pago no encontrado' })
  if (payment.reservation.guestId !== request.user.id) {
    return reply.status(403).send({ message: 'Acceso denegado' })
  }
  if (!['PENDING', 'PENDING_REVIEW'].includes(payment.status)) {
    return reply.status(400).send({ message: 'Este pago ya fue procesado' })
  }

  // Impedir reutilización de una referencia bancaria en otra reserva
  const duplicate = await prisma.payment.findFirst({
    where: {
      gateway: payment.gateway,
      gatewayRef,
      id: { not: payment.id },
    },
  })
  if (duplicate) {
    return reply.status(409).send({
      message: 'Esta referencia bancaria ya fue utilizada en otro pago',
    })
  }

  await prisma.$transaction([
    prisma.payment.update({
      where: { id: payment.id },
      data: {
        gatewayRef,
        reportedAt: new Date(),
        status: 'PENDING_REVIEW',
        metadata: { notes: notes || null, submittedAt: new Date() },
      },
    }),
    prisma.reservation.update({
      where: { id: payment.reservationId },
      data: { status: 'PAYMENT_PENDING_REVIEW' },
    }),
  ])

  // Si estamos en modo automático (simulated o bdv_notification), intentar conciliar al instante
  if (env.PAYMENT_MODE !== 'manual' && payment.gateway === 'PAGO_MOVIL') {
    const result = await reconcilePayment(payment.id, {
      skipAutoSimulate: Boolean(skipAutoSimulate),
    })

    if (result.matched) {
      return reply.send({
        status: 'APPROVED',
        autoVerified: true,
        isExtension: Boolean(result.isExtension),
        isRoomService: Boolean(result.isRoomService),
        reservationId: result.reservationId || payment.reservationId,
        orderReservationId: result.orderReservationId || null,
        bankEventId: result.bankEventId,
        message: result.isRoomService
          ? 'Consumo pagado automáticamente. En minutos estará en la esclusa privada de tu habitación.'
          : result.isExtension
            ? 'Extensión verificada automáticamente. El horario de tu llave QR ya fue ampliado.'
            : 'Pago verificado automáticamente. Tu reserva está activa y ya puedes obtener tu QR.',
      })
    }

    return reply.send({
      status: 'PENDING_REVIEW',
      autoVerified: false,
      reason: result.reason,
      expectedVes: result.expectedVes,
      receivedVes: result.receivedVes,
      message: 'Referencia registrada. Aún no coincide con una notificación bancaria válida.',
    })
  }

  return reply.send({
    status: 'PENDING_REVIEW',
    autoVerified: false,
    message: 'Referencia de pago enviada. El propietario confirmará en breve.',
  })
}

// POST /api/v1/payments/webhook/bdv-notification
// Recibe la notificación push capturada en el teléfono receptor (Banco de Venezuela)
// o inyectada por el simulador, y concilia automáticamente si el pago ya fue reportado.
async function handleBdvNotificationWebhook(request, reply) {
  const secret = request.headers['x-webhook-secret']
  const bridgeToken = request.headers['x-hotel-bridge-token']
  const rawHotelId = request.body && typeof request.body.hotelId === 'string'
    ? request.body.hotelId
    : null

  const secretValid = Boolean(secret && secret === env.PAGO_MOVIL_WEBHOOK_SECRET)
  const bridgeValid = Boolean(rawHotelId && bridgeToken && validateHotelBridgeToken(rawHotelId, bridgeToken))

  if (!secretValid && !bridgeValid) {
    return reply.status(401).send({
      statusCode: 401,
      error: 'Unauthorized',
      message: 'Credenciales de webhook o puente Android BDV inválidas',
    })
  }

  const data = bdvNotificationSchema.parse(request.body)
  const { bankEvent, reconciliation, usedAiFallback } = await recordBankEvent(data)

  return reply.status(201).send({
    bankEventId: bankEvent.id,
    amountVes: Number(bankEvent.amountVes),
    reference: bankEvent.reference,
    payerPhone: bankEvent.payerPhone,
    usedAiFallback,
    reconciliation,
  })
}

// POST /api/v1/payments/:paymentId/confirm  — PROPIETARIO confirma el pago manualmente (respaldo / contingencia BDV)
async function handleConfirmPayment(request, reply) {
  const body = request.body || {}
  const gatewayRef = body.gatewayRef ? normalizeRef(body.gatewayRef) : null
  const gateway = body.gateway || null
  const notes = body.notes || 'Confirmado manualmente por el administrador'
  const reason = body.reason || null

  const payment = await prisma.payment.findUnique({
    where: { id: request.params.paymentId },
    include: {
      reservation: { include: { room: { include: { hotel: true } } } },
    },
  })

  if (!payment) return reply.status(404).send({ message: 'Pago no encontrado' })

  if (payment.reservation.room.hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin permiso para confirmar este pago' })
  }

  if (!['PENDING', 'PENDING_REVIEW'].includes(payment.status)) {
    return reply.status(400).send({ message: 'El pago ya fue procesado' })
  }

  if (gatewayRef && gatewayRef !== payment.gatewayRef) {
    const duplicate = await prisma.payment.findFirst({
      where: {
        gateway: gateway || payment.gateway,
        gatewayRef,
        id: { not: payment.id },
      },
    })
    if (duplicate) {
      return reply.status(409).send({
        message: 'Esta referencia bancaria ya fue utilizada en otro pago',
      })
    }
  }

  const activation = await prisma.$transaction(async (tx) =>
    activateApprovedPaymentInTx(tx, {
      payment,
      reservation: payment.reservation,
      confirmedBy: `manual:owner:${request.user.id}`,
      manualData: { gatewayRef, gateway, notes, reason },
    })
  )

  broadcastActivationEvents({
    hotelId: payment.reservation.room.hotelId,
    guestId: payment.reservation.guestId,
    roomId: payment.reservation.roomId,
    roomName: payment.reservation.room.name,
    paymentId: payment.id,
    activation,
  })

  return reply.send({
    message: activation.isRoomService
      ? 'Pago de consumo confirmado manualmente. Orden enviada a entrega en pasaplatos.'
      : activation.isExtension
        ? 'Extensión confirmada manualmente. El horario del QR del huésped fue ampliado.'
        : 'Pago confirmado manualmente. La reserva está activa y el huésped ya puede obtener su QR.',
    reservationId: activation.targetReservationId,
    orderReservationId: activation.orderReservationId || null,
    isExtension: activation.isExtension,
    isRoomService: Boolean(activation.isRoomService),
    gateway: gateway || payment.gateway,
    gatewayRef: gatewayRef || payment.gatewayRef,
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
        select: {
          id: true,
          checkIn: true,
          checkOut: true,
          durationHours: true,
          room: { select: { name: true } },
        },
      },
    },
    orderBy: { createdAt: 'asc' },
  })

  return reply.send(payments)
}

// Registro en memoria de la salud del puente Android de cada hotel
const bdvBridgeStatusByHotel = new Map()

// POST /api/v1/payments/webhook/bdv-bridge/heartbeat
async function handleBdvBridgeHeartbeat(request, reply) {
  const token = request.headers['x-hotel-bridge-token']
  const body = request.body || {}
  const hotelId = String(body.hotelId || '')

  if (!hotelId || !token) {
    return reply.status(401).send({ message: 'Credenciales incompletas' })
  }

  const isValid = validateHotelBridgeToken(hotelId, token)
  if (!isValid) {
    return reply.status(401).send({ message: 'Token de puente BDV no válido' })
  }

  const now = Date.now()
  const statusInfo = {
    hotelId,
    online: true,
    lastHeartbeatMs: now,
    lastHeartbeatAt: new Date().toISOString(),
    pendingQueueCount: Number(body.pendingQueueCount || 0),
    forwardedCount: Number(body.forwardedCount || 0),
    version: body.version || '2.0',
    ip: request.ip,
  }
  bdvBridgeStatusByHotel.set(hotelId, statusInfo)

  return reply.send({ status: 'ok', acknowledgedAt: statusInfo.lastHeartbeatAt })
}

// GET /api/v1/payments/bdv-bridge/status/:hotelId
async function handleGetBdvBridgeStatus(request, reply) {
  const { hotelId } = request.params
  const hotel = await prisma.hotel.findUnique({ where: { id: hotelId }, select: { ownerId: true } })

  if (!hotel || hotel.ownerId !== request.user.id) {
    return reply.status(403).send({ message: 'Sin acceso' })
  }

  const record = bdvBridgeStatusByHotel.get(hotelId)
  const isOnline = record && (Date.now() - record.lastHeartbeatMs < 120000)

  return reply.send({
    hotelId,
    online: Boolean(isOnline),
    lastHeartbeatAt: record?.lastHeartbeatAt || null,
    pendingQueueCount: record?.pendingQueueCount || 0,
    forwardedCount: record?.forwardedCount || 0,
    version: record?.version || null,
    latencySec: record ? Math.round((Date.now() - record.lastHeartbeatMs) / 1000) : null,
  })
}

module.exports = {
  handleSubmitProof,
  handleBdvNotificationWebhook,
  handleBdvBridgeHeartbeat,
  handleGetBdvBridgeStatus,
  handleConfirmPayment,
  handleRejectPayment,
  handleListPending,
}
