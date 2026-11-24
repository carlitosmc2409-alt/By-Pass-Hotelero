const QRCode = require('qrcode')
const { generateQrToken, generateHotelIotToken } = require('./crypto')
const dayjs = require('dayjs')
const { prisma } = require('../config/database')
const { normalizeHotelSettings } = require('./hotelSettings')
const { emitRealtimeEvent } = require('./eventBus')
const { recordDevicePulse } = require('./iotRegistry')

/**
 * Envía una prueba diagnóstica (dryRun o pulso real) al relé IP / ESP32 configurado en `relayWebhookUrl`
 * firmada con `x-hotel-iot-token` y mide la latencia exacta en milisegundos.
 */
async function pingFaacRelayWebhook({
  hotelId,
  faacConfig,
  direction = 'ENTRY',
  dryRun = true,
}) {
  const webhookUrl = typeof faacConfig?.relayWebhookUrl === 'string'
    ? faacConfig.relayWebhookUrl.trim()
    : ''
  if (!/^https?:\/\//i.test(webhookUrl)) {
    return {
      configured: false,
      reachable: false,
      message: 'No hay una URL de Relé IP (relayWebhookUrl) configurada aún.',
    }
  }

  const deviceId =
    direction === 'EXIT' ? faacConfig?.exitDeviceId : faacConfig?.entryDeviceId
  const payload = {
    controller: 'FAAC',
    model: faacConfig?.model || 'FAAC 615 BPR / Placa E615',
    direction,
    deviceId: deviceId || 'faac-entrada-1',
    contact: faacConfig?.contactType || 'NO (OPEN-A + GND)',
    pulseDurationMs: Number(faacConfig?.pulseDurationMs || 1000),
    dryRun: Boolean(dryRun),
    triggeredBy: dryRun ? 'DIAGNOSTIC_PING' : 'OWNER_TEST_PULSE',
    triggeredAt: new Date().toISOString(),
  }

  const started = Date.now()
  try {
    const res = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-hotel-id': String(hotelId),
        'x-hotel-iot-token': generateHotelIotToken(hotelId),
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(3000),
    })
    const latencyMs = Date.now() - started
    let relayBody = null
    try {
      relayBody = await res.json()
    } catch (_) {}

    if (!dryRun && res.ok) {
      recordDevicePulse({ hotelId, deviceId: payload.deviceId, latencyMs })
    }

    return {
      configured: true,
      reachable: res.ok,
      statusCode: res.status,
      latencyMs,
      webhookUrl,
      dryRun: Boolean(dryRun),
      relayBody,
      message: res.ok
        ? (dryRun
            ? `Controladora FAAC en línea (${latencyMs} ms) · Bornera OPEN-A lista (sin abrir barrera)`
            : `Pulso real ejecutado en controladora FAAC (${latencyMs} ms)`)
        : `El relé respondió con código HTTP ${res.status}`,
    }
  } catch (err) {
    return {
      configured: true,
      reachable: false,
      latencyMs: Date.now() - started,
      webhookUrl,
      dryRun: Boolean(dryRun),
      message: `Controladora IP no accesible en ${webhookUrl}: ${err.message}`,
    }
  }
}

/**
 * Dispara el pulso de contacto seco hacia el controlador de Barrera Vehicular FAAC
 * (ej. placas FAAC E615 / E620 / E680 en bornera OPEN-A + GND) vía relé IP firmado
 * y transmite el evento en tiempo real por SSE al Panel, App y Terminal IoT.
 */
function triggerFaacBarrierPulse({
  hotelId,
  guestId = null,
  reservationId = null,
  roomName = null,
  direction = 'ENTRY', // 'ENTRY' | 'EXIT'
  deviceId,
  faacConfig,
  triggeredBy = 'QR_SCANNER',
}) {
  const pulse = {
    controller: 'FAAC',
    model: faacConfig?.model || 'FAAC 615 BPR / Placa E615',
    direction,
    deviceId: deviceId || (direction === 'EXIT' ? faacConfig?.exitDeviceId : faacConfig?.entryDeviceId) || 'faac-entrada-1',
    contact: faacConfig?.contactType || 'NO (OPEN-A + GND)',
    pulseDurationMs: Number(faacConfig?.pulseDurationMs || 1000),
    roomName,
    triggeredBy,
    triggeredAt: new Date().toISOString(),
  }

  recordDevicePulse({ hotelId, deviceId: pulse.deviceId })

  const webhookUrl = typeof faacConfig?.relayWebhookUrl === 'string'
    ? faacConfig.relayWebhookUrl.trim()
    : ''
  if (/^https?:\/\//i.test(webhookUrl)) {
    const t0 = Date.now()
    fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-hotel-id': String(hotelId),
        'x-hotel-iot-token': generateHotelIotToken(hotelId),
      },
      body: JSON.stringify(pulse),
      signal: AbortSignal.timeout(2500),
    })
      .then(async res => {
        if (res.ok) {
          const latencyMs = Date.now() - t0
          recordDevicePulse({ hotelId, deviceId: pulse.deviceId, latencyMs })
          emitRealtimeEvent({
            hotelId,
            type: 'FAAC_RELAY_ACK',
            payload: {
              deviceId: pulse.deviceId,
              direction,
              latencyMs,
              acknowledgedAt: new Date().toISOString(),
            },
          })
        }
      })
      .catch(() => {})
  }

  emitRealtimeEvent({
    hotelId,
    guestId,
    reservationId,
    type: 'FAAC_BARRIER_PULSE',
    payload: pulse,
    cleaningSafePayload: {
      controller: 'FAAC',
      direction,
      deviceId: pulse.deviceId,
      roomName,
      triggeredAt: pulse.triggeredAt,
    },
  })

  return pulse
}

/**
 * Emite (o rota) el token QR de una reserva confirmada.
 * Margen amplio (quiet zone = 3) y corrección 'H' optimizados para lectores ópticos
 * exteriores en pedestales de barreras vehiculares FAAC y cerraduras de habitación.
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
      maxUses: 30,
      isActive: true,
    },
    update: {
      tokenHash,
      validFrom: checkIn,
      validUntil: checkOut,
      isActive: true,
    },
  })

  const qrDataUrl = await QRCode.toDataURL(rawToken, {
    errorCorrectionLevel: 'H',
    width: 480,
    margin: 3,
    color: {
      dark: '#09090e',
      light: '#ffffff',
    },
  })

  return {
    qrDataUrl,
    rawToken,
    validFrom: accessToken.validFrom,
    validUntil: accessToken.validUntil,
    accessTokenId: accessToken.id,
  }
}

/**
 * Valida un token QR escaneado por barrera vehicular FAAC, garaje o cerradura de puerta.
 */
async function validateQrToken(rawToken, deviceId = null) {
  const { validateQrTokenSignature, hashQrToken } = require('./crypto')

  // 1. Verificar firma criptográfica HMAC-SHA256
  const signatureValid = validateQrTokenSignature(rawToken)
  if (!signatureValid) {
    await logAccessEvent(null, 'DENIED', deviceId, { reason: 'invalid_signature' })
    return { allowed: false, message: 'Código QR inválido' }
  }

  // 2. Buscar en BD por hash
  const tokenHash = hashQrToken(rawToken)
  const accessToken = await prisma.accessToken.findUnique({
    where: { tokenHash },
    include: {
      reservation: {
        include: {
          room: {
            include: {
              hotel: { select: { id: true, name: true, settings: true } },
            },
          },
        },
      },
    },
  })

  if (!accessToken) {
    return { allowed: false, message: 'Código QR no reconocido' }
  }

  const now = dayjs()
  const room = accessToken.reservation.room
  const settings = normalizeHotelSettings(room.hotel?.settings)
  const faacConfig = settings.faac

  const normalizedDevice = typeof deviceId === 'string' ? deviceId.trim().toLowerCase() : ''
  const isFaacExit =
    normalizedDevice.startsWith('faac-salida') ||
    normalizedDevice.startsWith('faac-exit') ||
    normalizedDevice.startsWith('barrera-salida')
  const isFaacEntry =
    (normalizedDevice.startsWith('faac') && !isFaacExit) ||
    normalizedDevice.startsWith('barrera-faac')
  const isGarageGate =
    normalizedDevice.startsWith('garaje') ||
    (normalizedDevice.startsWith('barrera') && !isFaacEntry && !isFaacExit) ||
    normalizedDevice.startsWith('gate')
  const isSharedGate =
    !normalizedDevice ||
    isFaacEntry ||
    isFaacExit ||
    isGarageGate ||
    normalizedDevice.startsWith('lock-demo')

  const exitGraceMinutes = Number(faacConfig?.exitGraceMinutes ?? 15)
  const withinExitGrace =
    isFaacExit &&
    accessToken.reservation.status !== 'COMPLETED' &&
    accessToken.reservation.status !== 'CANCELLED' &&
    now.isBefore(dayjs(accessToken.validUntil).add(exitGraceMinutes, 'minute'))

  // 3. Verificar si está activo (permitiendo gracia de salida en barrera FAAC de salida)
  if (!accessToken.isActive && !withinExitGrace) {
    await logAccessEvent(accessToken.id, 'EXPIRED', deviceId, { reason: 'inactive' })
    return { allowed: false, message: 'Código QR desactivado' }
  }

  // 4. Verificar ventana de tiempo
  if (now.isBefore(dayjs(accessToken.validFrom))) {
    await logAccessEvent(accessToken.id, 'DENIED', deviceId, { reason: 'too_early' })
    return { allowed: false, message: 'La reserva aún no ha comenzado' }
  }

  const isPastValidUntil = now.isAfter(dayjs(accessToken.validUntil))
  if (isPastValidUntil && !withinExitGrace) {
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

  // 5.5 Verificar correspondencia de cerradura específica de habitación vs barrera vehicular
  if (!isSharedGate) {
    const slugRoomLock = 'lock-' + String(room.name).trim().toLowerCase().replace(/\s+/g, '-')
    const configuredLock = room.lockDeviceId ? String(room.lockDeviceId).trim().toLowerCase() : null
    const matchesRoom =
      normalizedDevice === slugRoomLock ||
      normalizedDevice === String(room.id).toLowerCase() ||
      (configuredLock && normalizedDevice === configuredLock)

    if (!matchesRoom) {
      await logAccessEvent(accessToken.id, 'DENIED', deviceId, {
        reason: 'wrong_room_lock',
        expectedRoom: room.name,
      })
      return {
        allowed: false,
        message: `Puerta incorrecta: este QR pertenece a la habitación ${room.name}`,
        expectedRoom: room.name,
      }
    }
  }

  // 6. Acceso permitido — incrementar contador
  const updatedToken = await prisma.accessToken.update({
    where: { id: accessToken.id },
    data: { usedCount: { increment: 1 } },
  })

  let accessZone = 'ROOM_DOOR'
  if (isFaacEntry) accessZone = 'FAAC_ENTRY'
  else if (isFaacExit) accessZone = 'FAAC_EXIT'
  else if (isGarageGate) accessZone = 'GARAGE_GATE'

  await logAccessEvent(accessToken.id, 'OPEN', deviceId, {
    accessZone,
    usedExitGrace: Boolean(isPastValidUntil && withinExitGrace),
  })

  let faacPulse = null
  if (isFaacEntry || isFaacExit) {
    faacPulse = triggerFaacBarrierPulse({
      hotelId: room.hotel.id,
      guestId: accessToken.reservation.guestId,
      reservationId: accessToken.reservationId,
      roomName: room.name,
      direction: isFaacExit ? 'EXIT' : 'ENTRY',
      deviceId: deviceId || (isFaacExit ? faacConfig.exitDeviceId : faacConfig.entryDeviceId),
      faacConfig,
      triggeredBy: 'QR_TOTEM',
    })

    // Al escanear la salida en el tótem FAAC, el cliente abandona el establecimiento:
    // Se completa la estadía, se desactiva el QR y la habitación pasa a 'Requiere Limpieza' (CLEANING)
    if (isFaacExit) {
      await prisma.$transaction([
        prisma.reservation.update({
          where: { id: accessToken.reservationId },
          data: { status: 'COMPLETED', checkOut: new Date() },
        }),
        prisma.accessToken.update({
          where: { id: accessToken.id },
          data: { isActive: false },
        }),
        prisma.room.update({
          where: { id: room.id },
          data: { status: 'CLEANING' },
        }),
      ])

      emitRealtimeEvent({
        hotelId: room.hotel.id,
        guestId: accessToken.reservation.guestId,
        reservationId: accessToken.reservationId,
        type: 'ROOM_STATUS_CHANGED',
        payload: {
          roomId: room.id,
          roomName: room.name,
          status: 'CLEANING',
          reason: 'FAAC_EXIT_TOTEM_SCAN',
        },
        cleaningSafePayload: {
          roomId: room.id,
          roomName: room.name,
          status: 'CLEANING',
          reason: 'FAAC_EXIT_TOTEM_SCAN',
        },
      })
    }
  } else {
    emitRealtimeEvent({
      hotelId: room.hotel.id,
      guestId: accessToken.reservation.guestId,
      reservationId: accessToken.reservationId,
      type: 'DOOR_UNLOCK_PULSE',
      payload: {
        accessZone,
        deviceId: deviceId || null,
        roomName: room.name,
        triggeredAt: new Date().toISOString(),
      },
    })
  }

  let message = `Cerradura desbloqueada · Habitación ${room.name}`
  if (isFaacEntry) {
    message = `Barrera FAAC de Entrada abierta · Avanza a Habitación ${room.name}`
  } else if (isFaacExit) {
    message = isPastValidUntil
      ? `Barrera FAAC de Salida abierta (ventana de cortesía) · Buen viaje`
      : `Barrera FAAC de Salida abierta · Habitación ${room.name}`
  } else if (isGarageGate) {
    message = `Barrera abierta · Dirígete a Habitación ${room.name}`
  }

  return {
    allowed: true,
    message,
    reservationId: accessToken.reservationId,
    hotelName: room.hotel?.name || '',
    roomName: room.name,
    deviceId: deviceId || null,
    accessZone,
    isBarrier: isFaacEntry || isFaacExit || isGarageGate,
    usedExitGrace: Boolean(isPastValidUntil && withinExitGrace),
    faacPulse,
    usedCount: updatedToken.usedCount,
    maxUses: updatedToken.maxUses,
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
  triggerFaacBarrierPulse,
  pingFaacRelayWebhook,
}
