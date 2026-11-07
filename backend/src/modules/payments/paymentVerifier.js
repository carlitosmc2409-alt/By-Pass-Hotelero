const { prisma } = require('../../config/database')
const env = require('../../config/env')
const { decryptField } = require('../../utils/fieldCrypto')
const { round2 } = require('../../utils/rates')
const { emitRealtimeEvent } = require('../../utils/eventBus')
const { extractBdvNotificationWithAI } = require('./bdvAiExtractor')

const EXTENSION_PREFIX = 'EXTENSION_OF:'
const ROOM_SERVICE_PREFIX = 'ROOM_SERVICE_OF:'

function parseRoomServiceNote(notes) {
  if (!notes || typeof notes !== 'string' || !notes.startsWith(ROOM_SERVICE_PREFIX)) {
    return null
  }
  const rest = notes.slice(ROOM_SERVICE_PREFIX.length)
  const sepIdx = rest.indexOf('|')
  if (sepIdx === -1) return { parentReservationId: rest, items: [], guestNote: '' }
  const parentReservationId = rest.slice(0, sepIdx)
  try {
    const parsed = JSON.parse(rest.slice(sepIdx + 1))
    return {
      parentReservationId,
      items: Array.isArray(parsed.items) ? parsed.items : [],
      guestNote: parsed.guestNote || '',
    }
  } catch (_) {
    return { parentReservationId, items: [], guestNote: '' }
  }
}

function normalizeRef(ref) {
  return String(ref || '').replace(/\D/g, '')
}

function normalizeDigits(val) {
  return String(val || '').replace(/\D/g, '')
}

function normalizeVePhone(raw) {
  if (!raw) return null
  const digits = String(raw).replace(/\D/g, '')
  if (digits.length === 11 && digits.startsWith('0')) {
    return '+58' + digits.slice(1)
  }
  if (digits.length === 12 && digits.startsWith('58')) {
    return '+' + digits
  }
  if (digits.length === 10) {
    return '+58' + digits
  }
  return null
}

/**
 * Extrae monto, referencia y teléfono emisor del texto de una notificación
 * de Pago Móvil del Banco de Venezuela (BDV).
 */
function parseBdvNotificationText(rawText) {
  if (!rawText || typeof rawText !== 'string') return {}

  let headerText = rawText
  let concept = null
  const conceptMatch = rawText.match(/\b(?:Concepto|Motivo)\s*[:.-]\s*(.+)$/i)
  if (conceptMatch) {
    concept = conceptMatch[1].trim()
    headerText = rawText.slice(0, conceptMatch.index).trim()
  }

  let amountVes = null
  const amountMatch = headerText.match(/Bs\.?\s*([0-9.,]+)/i)
  if (amountMatch) {
    const rawNum = amountMatch[1].trim()
    const normalized = rawNum.includes(',')
      ? rawNum.replace(/\./g, '').replace(',', '.')
      : rawNum.replace(/,/g, '')
    const parsed = parseFloat(normalized)
    if (!Number.isNaN(parsed)) amountVes = round2(parsed)
  }

  let reference = null
  const refMatch = headerText.match(/Ref(?:erencia)?[:.\s#-]*([0-9]{4,20})/i)
  if (refMatch) {
    reference = normalizeRef(refMatch[1])
  }

  let payerPhone = null
  const phoneMatch = headerText.match(/(?:\+?58|0)?\s*(4(?:12|14|24|16|26))[\s-]*([0-9]{7})/)
  if (phoneMatch) {
    payerPhone = `+58${phoneMatch[1]}${phoneMatch[2]}`
  }

  return { amountVes, reference, payerPhone, concept }
}

function referencesMatch(guestRef, bankRef) {
  const a = normalizeRef(guestRef)
  const b = normalizeRef(bankRef)
  if (!a || !b) return false
  if (a === b) return true
  if (a.length >= 6 && b.length >= 6 && a.slice(-6) === b.slice(-6)) return true
  return false
}

function verifyPayerMatchesGuest(bankEvent, guest) {
  if (bankEvent.payerPhone && guest.paymentPhone) {
    const guestPhone = decryptField(guest.paymentPhone)
    if (normalizeVePhone(bankEvent.payerPhone) !== normalizeVePhone(guestPhone)) {
      return { ok: false, field: 'payerPhone' }
    }
  }
  if (bankEvent.payerCedula && guest.paymentCedula) {
    const guestCedula = decryptField(guest.paymentCedula)
    if (normalizeDigits(bankEvent.payerCedula) !== normalizeDigits(guestCedula)) {
      return { ok: false, field: 'payerCedula' }
    }
  }
  if (bankEvent.payerBank && guest.paymentBank) {
    if (String(bankEvent.payerBank) !== String(guest.paymentBank)) {
      return { ok: false, field: 'payerBank' }
    }
  }
  return { ok: true }
}

/**
 * Ejecuta dentro de una transacción Prisma los efectos de un pago aprobado:
 * - Reserva normal: activa la reserva y marca la habitación OCCUPIED.
 * - Extensión (`EXTENSION_OF:<parentId>`): amplía `checkOut`, `durationHours`, `totalAmount` y vigencia QR.
 * - Room Service (`ROOM_SERVICE_OF:<parentId>|<json>`): habilita orden de entrega en esclusa/pasaplatos.
 */
async function activateApprovedPaymentInTx(tx, { payment, reservation, confirmedBy, matchingEventId = null }) {
  const prevMeta = (payment.metadata && typeof payment.metadata === 'object')
    ? payment.metadata
    : {}
  const roomServiceInfo = parseRoomServiceNote(reservation.notes)

  await tx.payment.update({
    where: { id: payment.id },
    data: {
      status: 'APPROVED',
      confirmedAt: new Date(),
      confirmedBy,
      ...(roomServiceInfo
        ? {
            metadata: {
              ...prevMeta,
              isRoomService: true,
              parentReservationId: roomServiceInfo.parentReservationId,
              items: roomServiceInfo.items,
              guestNote: roomServiceInfo.guestNote,
              deliveryStatus: 'PENDING_DELIVERY',
            },
          }
        : {}),
    },
  })

  if (matchingEventId) {
    await tx.bankEvent.update({
      where: { id: matchingEventId },
      data: { matchedPaymentId: payment.id },
    })
  }

  if (roomServiceInfo) {
    await tx.reservation.update({
      where: { id: reservation.id },
      data: { status: 'COMPLETED' },
    })
    return {
      targetReservationId: roomServiceInfo.parentReservationId,
      orderReservationId: reservation.id,
      isExtension: false,
      isRoomService: true,
      items: roomServiceInfo.items,
      guestNote: roomServiceInfo.guestNote,
      newCheckOut: reservation.checkOut,
    }
  }

  const isExtension = Boolean(reservation.notes && reservation.notes.startsWith(EXTENSION_PREFIX))
  if (isExtension) {
    const parentId = reservation.notes.slice(EXTENSION_PREFIX.length)
    await tx.reservation.update({
      where: { id: parentId },
      data: {
        checkOut: reservation.checkOut,
        durationHours: { increment: reservation.durationHours },
        totalAmount: { increment: reservation.totalAmount },
      },
    })
    await tx.accessToken.updateMany({
      where: { reservationId: parentId },
      data: {
        validUntil: reservation.checkOut,
        isActive: true,
        maxUses: { increment: 10 },
      },
    })
    await tx.reservation.update({
      where: { id: reservation.id },
      data: { status: 'COMPLETED' },
    })
    return {
      targetReservationId: parentId,
      isExtension: true,
      isRoomService: false,
      newCheckOut: reservation.checkOut,
    }
  }

  await tx.reservation.update({
    where: { id: reservation.id },
    data: { status: 'ACTIVE' },
  })
  await tx.room.update({
    where: { id: reservation.roomId },
    data: { status: 'OCCUPIED' },
  })

  return {
    targetReservationId: reservation.id,
    isExtension: false,
    isRoomService: false,
    newCheckOut: reservation.checkOut,
  }
}

function broadcastActivationEvents({ hotelId, guestId, roomId, roomName, paymentId, activation }) {
  emitRealtimeEvent({
    hotelId,
    guestId,
    reservationId: activation.targetReservationId,
    type: 'PAYMENT_APPROVED',
    payload: {
      paymentId,
      reservationId: activation.targetReservationId,
      orderReservationId: activation.orderReservationId || null,
      roomName,
      isExtension: Boolean(activation.isExtension),
      isRoomService: Boolean(activation.isRoomService),
      newCheckOut: activation.newCheckOut,
    },
  })

  if (activation.isRoomService) {
    const orderPayload = {
      orderId: activation.orderReservationId,
      roomName,
      items: activation.items || [],
      guestNote: activation.guestNote || '',
      deliveryStatus: 'PENDING_DELIVERY',
    }
    emitRealtimeEvent({
      hotelId,
      guestId,
      reservationId: activation.targetReservationId,
      type: 'ROOM_SERVICE_ORDER',
      payload: orderPayload,
      cleaningSafePayload: orderPayload,
    })
  } else if (!activation.isExtension) {
    emitRealtimeEvent({
      hotelId,
      type: 'ROOM_STATUS_CHANGED',
      payload: { roomId, roomName, status: 'OCCUPIED' },
      cleaningSafePayload: { roomId, roomName, status: 'OCCUPIED' },
    })
  }
}

/**
 * Intenta conciliar un pago específico contra los eventos bancarios recibidos.
 */
async function reconcilePayment(paymentId, options = {}) {
  const payment = await prisma.payment.findUnique({
    where: { id: paymentId },
    include: {
      reservation: {
        include: {
          guest: true,
          room: { include: { hotel: true } },
        },
      },
    },
  })

  if (!payment) {
    const err = new Error('Pago no encontrado')
    err.statusCode = 404
    throw err
  }

  if (payment.status === 'APPROVED') {
    const rs = parseRoomServiceNote(payment.reservation.notes)
    const targetId = payment.reservation.notes?.startsWith(EXTENSION_PREFIX)
      ? payment.reservation.notes.slice(EXTENSION_PREFIX.length)
      : rs
        ? rs.parentReservationId
        : payment.reservationId
    return {
      matched: true,
      status: 'APPROVED',
      alreadyApproved: true,
      reservationId: targetId,
      isRoomService: Boolean(rs),
    }
  }

  const hotelId = payment.reservation.room.hotelId
  const guest = payment.reservation.guest
  const ref = normalizeRef(payment.gatewayRef)

  if (!ref) {
    return { matched: false, reason: 'MISSING_REFERENCE' }
  }

  if (payment.expiresAt && new Date() > new Date(payment.expiresAt)) {
    return { matched: false, reason: 'PAYMENT_WINDOW_EXPIRED' }
  }

  const candidates = await prisma.bankEvent.findMany({
    where: {
      hotelId,
      matchedPaymentId: null,
    },
    orderBy: { receivedAt: 'desc' },
    take: 50,
  })

  let matchingEvent = candidates.find(ev => referencesMatch(ref, ev.reference))

  if (!matchingEvent && env.PAYMENT_MODE === 'simulated' && !options.skipAutoSimulate) {
    const guestPhone = guest.paymentPhone ? decryptField(guest.paymentPhone) : guest.phone
    const guestCedula = guest.paymentCedula ? decryptField(guest.paymentCedula) : guest.cedula
    matchingEvent = await prisma.bankEvent.create({
      data: {
        hotelId,
        source: 'SIMULATED',
        amountVes: payment.amountVes || payment.amount,
        reference: ref,
        payerPhone: guestPhone || null,
        payerCedula: guestCedula ? normalizeDigits(guestCedula) : null,
        payerBank: guest.paymentBank || '0102',
        rawText: `[SIMULATED BDV] PagomovilBDV recibido por Bs. ${payment.amountVes || payment.amount} del ${guestPhone} Ref: ${ref}`,
      },
    })
  }

  if (!matchingEvent) {
    return { matched: false, reason: 'BANK_EVENT_NOT_FOUND' }
  }

  const expectedVes = round2(Number(payment.amountVes || payment.amount))
  const receivedVes = round2(Number(matchingEvent.amountVes))
  if (expectedVes !== receivedVes) {
    return {
      matched: false,
      reason: 'AMOUNT_MISMATCH',
      expectedVes,
      receivedVes,
    }
  }

  const payerCheck = verifyPayerMatchesGuest(matchingEvent, guest)
  if (!payerCheck.ok) {
    return {
      matched: false,
      reason: 'PAYER_MISMATCH',
      mismatchField: payerCheck.field,
    }
  }

  const activation = await prisma.$transaction(async (tx) =>
    activateApprovedPaymentInTx(tx, {
      payment,
      reservation: payment.reservation,
      confirmedBy: `system:bank-event:${matchingEvent.id}`,
      matchingEventId: matchingEvent.id,
    })
  )

  broadcastActivationEvents({
    hotelId,
    guestId: payment.reservation.guestId,
    roomId: payment.reservation.roomId,
    roomName: payment.reservation.room.name,
    paymentId: payment.id,
    activation,
  })

  return {
    matched: true,
    status: 'APPROVED',
    bankEventId: matchingEvent.id,
    reservationId: activation.targetReservationId,
    orderReservationId: activation.orderReservationId || null,
    isExtension: activation.isExtension,
    isRoomService: activation.isRoomService,
    newCheckOut: activation.newCheckOut,
  }
}

/**
 * Registra un evento bancario entrante e intenta conciliarlo al instante (con referencia o Zero-Click).
 */
async function recordBankEvent(input) {
  const parsed = input.rawText ? parseBdvNotificationText(input.rawText) : {}
  let reference = normalizeRef(input.reference || parsed.reference)
  let amountVes = input.amountVes !== undefined ? round2(input.amountVes) : parsed.amountVes
  let payerPhone = normalizeVePhone(input.payerPhone || parsed.payerPhone)
  const payerCedula = input.payerCedula ? normalizeDigits(input.payerCedula) : null
  let payerBank = input.payerBank || null
  let concept = input.concept || parsed.concept || null
  let usedAiFallback = false

  if (input.rawText && (!reference || reference.length < 4 || !amountVes || amountVes <= 0)) {
    const aiExtracted = await extractBdvNotificationWithAI(input.rawText)
    if (aiExtracted.usedAiFallback) {
      usedAiFallback = true
      if (!input.reference && aiExtracted.reference) {
        reference = normalizeRef(aiExtracted.reference)
      }
      if (input.amountVes === undefined && aiExtracted.amountVes) {
        amountVes = aiExtracted.amountVes
      }
      if (!input.payerPhone && aiExtracted.payerPhone) {
        payerPhone = normalizeVePhone(aiExtracted.payerPhone)
      }
      if (!input.payerBank && aiExtracted.payerBank) {
        payerBank = aiExtracted.payerBank
      }
      if (!input.concept && aiExtracted.concept) {
        concept = aiExtracted.concept
      }
    }
  }

  if (!reference || reference.length < 4) {
    const err = new Error('No se pudo extraer una referencia válida de la notificación bancaria')
    err.statusCode = 422
    throw err
  }
  if (!amountVes || amountVes <= 0) {
    const err = new Error('No se pudo extraer un monto válido en Bs de la notificación bancaria')
    err.statusCode = 422
    throw err
  }

  const bankEvent = await prisma.bankEvent.create({
    data: {
      hotelId: input.hotelId,
      source: input.source || 'BDV_NOTIFICATION',
      amountVes,
      reference,
      payerPhone,
      payerCedula,
      payerBank,
      concept,
      rawText: input.rawText || null,
    },
  })

  const pendingWithRef = await prisma.payment.findMany({
    where: {
      status: { in: ['PENDING', 'PENDING_REVIEW'] },
      gatewayRef: { not: null },
      reservation: { room: { hotelId: input.hotelId } },
    },
    orderBy: { createdAt: 'desc' },
    take: 25,
  })

  let candidatePayment = pendingWithRef.find(p => referencesMatch(p.gatewayRef, reference))
  let zeroClick = false

  if (!candidatePayment && (payerPhone || payerCedula)) {
    const refAlreadyUsed = await prisma.payment.findFirst({
      where: {
        gateway: 'PAGO_MOVIL',
        gatewayRef: reference,
      },
      select: { id: true },
    })

    if (!refAlreadyUsed) {
      const openUnreported = await prisma.payment.findMany({
        where: {
          status: 'PENDING',
          gatewayRef: null,
          OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
          reservation: { room: { hotelId: input.hotelId } },
        },
        include: {
          reservation: { include: { guest: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: 25,
      })

      const exactMatches = openUnreported.filter(p => {
        const expectedVes = round2(Number(p.amountVes || p.amount))
        if (expectedVes !== round2(Number(amountVes))) return false
        const guest = p.reservation.guest
        const hasVerifiedIdentity =
          Boolean(payerPhone && guest.paymentPhone) ||
          Boolean(payerCedula && guest.paymentCedula)
        if (!hasVerifiedIdentity) return false
        return verifyPayerMatchesGuest(bankEvent, guest).ok
      })

      if (exactMatches.length === 1) {
        const chosen = exactMatches[0]
        const prevMeta = (chosen.metadata && typeof chosen.metadata === 'object')
          ? chosen.metadata
          : {}
        await prisma.payment.update({
          where: { id: chosen.id },
          data: {
            gatewayRef: reference,
            reportedAt: new Date(),
            status: 'PENDING_REVIEW',
            metadata: { ...prevMeta, autoReportedByZeroClick: true, bankEventId: bankEvent.id },
          },
        })
        candidatePayment = chosen
        zeroClick = true
      }
    }
  }

  let reconciliation = null
  if (candidatePayment) {
    reconciliation = await reconcilePayment(candidatePayment.id, { skipAutoSimulate: true })
    if (reconciliation && zeroClick) {
      reconciliation.zeroClick = true
    }
  }

  emitRealtimeEvent({
    hotelId: input.hotelId,
    type: 'BANK_EVENT_RECEIVED',
    payload: {
      bankEventId: bankEvent.id,
      amountVes: Number(bankEvent.amountVes),
      reference: bankEvent.reference,
      matched: Boolean(reconciliation?.matched),
      zeroClick,
    },
  })

  return { bankEvent, reconciliation, usedAiFallback }
}

module.exports = {
  normalizeRef,
  parseBdvNotificationText,
  activateApprovedPaymentInTx,
  broadcastActivationEvents,
  reconcilePayment,
  recordBankEvent,
}
