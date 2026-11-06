const { prisma } = require('../../config/database')
const env = require('../../config/env')
const { decryptField } = require('../../utils/fieldCrypto')
const { round2 } = require('../../utils/rates')
const { extractBdvNotificationWithAI } = require('./bdvAiExtractor')

const EXTENSION_PREFIX = 'EXTENSION_OF:'

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

  // Separar cualquier segmento "Concepto:" o "Motivo:" escrito por el pagador
  let headerText = rawText
  let concept = null
  const conceptMatch = rawText.match(/\b(?:Concepto|Motivo)\s*[:.-]\s*(.+)$/i)
  if (conceptMatch) {
    concept = conceptMatch[1].trim()
    headerText = rawText.slice(0, conceptMatch.index).trim()
  }

  // Monto: "Bs. 1.500,00" o "Bs 1500.00" o "Bs.1500,50"
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

  // Referencia: "Ref: 00987654" o "Ref 987654" o "Referencia: 12345678"
  let reference = null
  const refMatch = headerText.match(/Ref(?:erencia)?[:.\s#-]*([0-9]{4,20})/i)
  if (refMatch) {
    reference = normalizeRef(refMatch[1])
  }

  // Teléfono venezolano: 0412/0414/0424/0416/0426/+58...
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
 * - Si es una reserva normal: activa la reserva y marca la habitación OCCUPIED.
 * - Si es una extensión (`EXTENSION_OF:<parentId>`): amplía `checkOut`, `durationHours`
 *   y `totalAmount` de la estadía madre, extiende el `validUntil` de su llave QR y
 *   cierra el registro auxiliar de extensión como COMPLETED.
 */
async function activateApprovedPaymentInTx(tx, { payment, reservation, confirmedBy, matchingEventId = null }) {
  await tx.payment.update({
    where: { id: payment.id },
    data: {
      status: 'APPROVED',
      confirmedAt: new Date(),
      confirmedBy,
    },
  })

  if (matchingEventId) {
    await tx.bankEvent.update({
      where: { id: matchingEventId },
      data: { matchedPaymentId: payment.id },
    })
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
        maxUses: { increment: 6 },
      },
    })
    await tx.reservation.update({
      where: { id: reservation.id },
      data: { status: 'COMPLETED' },
    })
    return {
      targetReservationId: parentId,
      isExtension: true,
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
    newCheckOut: reservation.checkOut,
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
    const targetId = payment.reservation.notes?.startsWith(EXTENSION_PREFIX)
      ? payment.reservation.notes.slice(EXTENSION_PREFIX.length)
      : payment.reservationId
    return {
      matched: true,
      status: 'APPROVED',
      alreadyApproved: true,
      reservationId: targetId,
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

  return {
    matched: true,
    status: 'APPROVED',
    bankEventId: matchingEvent.id,
    reservationId: activation.targetReservationId,
    isExtension: activation.isExtension,
    newCheckOut: activation.newCheckOut,
  }
}

/**
 * Registra un evento bancario entrante e intenta conciliarlo al instante:
 * 1) Por coincidencia de referencia si el huésped ya la reportó.
 * 2) En modo "Cero Clics" (sin que el huésped toque el teclado) si el monto en Bs
 *    coincide al céntimo exacto y el teléfono/cédula del push coincide con su perfil cifrado.
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

  // 1) Buscar si algún pago pendiente ya reportó esta referencia
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

  // 2) Conciliación "Cero Clics": el huésped aún no escribió la referencia, pero el push
  //    del banco trae monto exacto al céntimo + teléfono/cédula verificado de su perfil.
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
        await prisma.payment.update({
          where: { id: chosen.id },
          data: {
            gatewayRef: reference,
            reportedAt: new Date(),
            status: 'PENDING_REVIEW',
            metadata: { autoReportedByZeroClick: true, bankEventId: bankEvent.id },
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

  return { bankEvent, reconciliation, usedAiFallback }
}

module.exports = {
  normalizeRef,
  parseBdvNotificationText,
  activateApprovedPaymentInTx,
  reconcilePayment,
  recordBankEvent,
}
