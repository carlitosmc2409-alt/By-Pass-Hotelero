const { prisma } = require('../../config/database')
const env = require('../../config/env')
const { decryptField } = require('../../utils/fieldCrypto')
const { round2 } = require('../../utils/rates')
const { extractBdvNotificationWithAI } = require('./bdvAiExtractor')

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
 * Ejemplo: "PagomovilBDV recibido por Bs. 1.500,00 del 04129876543 Ref: 00987654"
 */
function parseBdvNotificationText(rawText) {
  if (!rawText || typeof rawText !== 'string') return {}

  // Separar cualquier segmento "Concepto:" o "Motivo:" escrito por el pagador
  // para que un texto malicioso en el concepto nunca contamine los regex de monto/referencia
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
    // Si tiene coma decimal estilo venezolano (1.500,00)
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

/**
 * Compara si la referencia reportada por el huésped coincide con la del banco.
 * Acepta coincidencia exacta o de los últimos 6 dígitos (muchos bancos muestran
 * solo los últimos 6 dígitos en la notificación push).
 */
function referencesMatch(guestRef, bankRef) {
  const a = normalizeRef(guestRef)
  const b = normalizeRef(bankRef)
  if (!a || !b) return false
  if (a === b) return true
  if (a.length >= 6 && b.length >= 6 && a.slice(-6) === b.slice(-6)) return true
  return false
}

/**
 * Verifica que los datos del emisor en el evento bancario coincidan con los
 * datos de pago frecuente registrados por el huésped (cuando el evento los incluye).
 */
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
 * Intenta conciliar un pago específico contra los eventos bancarios recibidos.
 * En modo `simulated`, si no existe un evento previo para esa referencia y no se
 * desactivó la auto-simulación, genera el evento simulado automáticamente.
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
    return { matched: true, status: 'APPROVED', alreadyApproved: true }
  }

  const hotelId = payment.reservation.room.hotelId
  const guest = payment.reservation.guest
  const ref = normalizeRef(payment.gatewayRef)

  if (!ref) {
    return { matched: false, reason: 'MISSING_REFERENCE' }
  }

  // Verificar expiración de la ventana de tasa bloqueada
  if (payment.expiresAt && new Date() > new Date(payment.expiresAt)) {
    return { matched: false, reason: 'PAYMENT_WINDOW_EXPIRED' }
  }

  // Buscar eventos no emparejados de este hotel
  let candidates = await prisma.bankEvent.findMany({
    where: {
      hotelId,
      matchedPaymentId: null,
    },
    orderBy: { receivedAt: 'desc' },
    take: 50,
  })

  let matchingEvent = candidates.find(ev => referencesMatch(ref, ev.reference))

  // En modo simulado, si no hay ningún evento previo para esta referencia y no se
  // pidió omitir la auto-creación, simulamos la recepción inmediata desde BDV.
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

  // Validar monto exacto en Bolívares
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

  // Validar identidad del emisor contra los datos de pago frecuente del huésped
  const payerCheck = verifyPayerMatchesGuest(matchingEvent, guest)
  if (!payerCheck.ok) {
    return {
      matched: false,
      reason: 'PAYER_MISMATCH',
      mismatchField: payerCheck.field,
    }
  }

  // Todo coincide → aprobar pago y activar reserva de forma atómica
  await prisma.$transaction([
    prisma.payment.update({
      where: { id: payment.id },
      data: {
        status: 'APPROVED',
        confirmedAt: new Date(),
        confirmedBy: `system:bank-event:${matchingEvent.id}`,
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
    prisma.bankEvent.update({
      where: { id: matchingEvent.id },
      data: { matchedPaymentId: payment.id },
    }),
  ])

  return {
    matched: true,
    status: 'APPROVED',
    bankEventId: matchingEvent.id,
    reservationId: payment.reservationId,
  }
}

/**
 * Registra un evento bancario entrante (desde el simulador o desde el agente
 * lector de notificaciones del Banco de Venezuela) e intenta conciliarlo
 * inmediatamente si el huésped ya había reportado la referencia.
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

  // Paso B: Si el texto crudo de la notificación cambió de formato y el Regex no
  // logró extraer la referencia o el monto, activamos el Agente IA (Gemini Structured Outputs)
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

  // Buscar si algún pago pendiente de revisión en ese hotel ya reportó esta referencia
  const pendingPayments = await prisma.payment.findMany({
    where: {
      status: { in: ['PENDING', 'PENDING_REVIEW'] },
      gatewayRef: { not: null },
      reservation: { room: { hotelId: input.hotelId } },
    },
    orderBy: { createdAt: 'desc' },
    take: 25,
  })

  const candidatePayment = pendingPayments.find(p => referencesMatch(p.gatewayRef, reference))
  let reconciliation = null
  if (candidatePayment) {
    reconciliation = await reconcilePayment(candidatePayment.id, { skipAutoSimulate: true })
  }

  return { bankEvent, reconciliation, usedAiFallback }
}

module.exports = {
  normalizeRef,
  parseBdvNotificationText,
  reconcilePayment,
  recordBankEvent,
}
