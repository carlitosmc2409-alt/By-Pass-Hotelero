const cron = require('node-cron')
const { prisma } = require('../config/database')
const { emitRealtimeEvent } = require('./eventBus')
const dayjs = require('dayjs')

/**
 * Inicia todos los trabajos programados en segundo plano.
 */
function startCronJobs() {
  console.log('⏰ Iniciando jobs programados...')

  // Cada 1 minuto: liberar reservas impagas cuya ventana de 10 min venció
  cron.schedule('* * * * *', () => {
    expireUnpaidReservations().catch(err =>
      console.error('⚠️ [Cron] Error liberando reservas impagas:', err.message)
    )
  })

  // Cada 1 minuto: expirar reservas activas cuyo check-out ya pasó y poner habitación en CLEANING
  cron.schedule('* * * * *', () => {
    expireReservations().catch(err =>
      console.error('⚠️ [Cron] Error expirando estadías:', err.message)
    )
  })

  // Cada 1 minuto: liberar automáticamente habitaciones en CLEANING tras 30 min desocupadas
  cron.schedule('* * * * *', () => {
    autoReleaseCleaningRooms().catch(err =>
      console.error('⚠️ [Cron] Error en auto-liberación de limpieza:', err.message)
    )
  })

  // Cada hora: limpiar OTPs usados/expirados
  cron.schedule('0 * * * *', cleanExpiredOtps)

  // Cada hora: limpiar refresh tokens revocados/expirados
  cron.schedule('0 * * * *', cleanExpiredRefreshTokens)

  console.log('✅ Jobs programados activos')
}

/**
 * Cancela reservas en `PENDING_PAYMENT` cuyo pago sigue `PENDING` y superó `expiresAt`
 * (evita que reservas abandonadas bloqueen el inventario del hotel).
 */
async function expireUnpaidReservations() {
  const now = new Date()

  const expiredPayments = await prisma.payment.findMany({
    where: {
      status: 'PENDING',
      expiresAt: { lte: now },
      reservation: { status: 'PENDING_PAYMENT' },
    },
    select: { id: true, reservationId: true },
  })

  if (expiredPayments.length === 0) {
    return { expiredCount: 0 }
  }

  const paymentIds = expiredPayments.map(p => p.id)
  const reservationIds = expiredPayments.map(p => p.reservationId)

  await prisma.$transaction([
    prisma.payment.updateMany({
      where: { id: { in: paymentIds } },
      data: { status: 'FAILED' },
    }),
    prisma.reservation.updateMany({
      where: { id: { in: reservationIds } },
      data: { status: 'CANCELLED' },
    }),
  ])

  console.log(`⏰ [Cron] ${reservationIds.length} reservas impagas liberadas por vencimiento`)
  return { expiredCount: reservationIds.length }
}

/**
 * Marca como EXPIRED las reservas cuyo check-out ya pasó y siguen ACTIVE.
 * Desactiva sus AccessTokens, coloca la habitación en CLEANING ('Requiere Limpieza')
 * y emite el evento en tiempo real.
 */
async function expireReservations() {
  const now = new Date()

  // Buscar reservas activas con checkout pasado
  const expired = await prisma.reservation.findMany({
    where: {
      status: 'ACTIVE',
      checkOut: { lte: now },
    },
    include: {
      room: { select: { id: true, name: true, hotelId: true } },
    },
  })

  if (expired.length === 0) return { expiredCount: 0 }

  const ids = expired.map(r => r.id)
  const roomIds = [...new Set(expired.map(r => r.roomId))]

  await prisma.$transaction([
    // Marcar reservas como expiradas
    prisma.reservation.updateMany({
      where: { id: { in: ids } },
      data: { status: 'EXPIRED' },
    }),
    // Desactivar QRs de esas reservas
    prisma.accessToken.updateMany({
      where: { reservationId: { in: ids }, isActive: true },
      data: { isActive: false },
    }),
    // Marcar habitaciones en limpieza tras vencer estadía
    prisma.room.updateMany({
      where: { id: { in: roomIds } },
      data: { status: 'CLEANING' },
    }),
  ])

  // Emitir evento en tiempo real para alertar al panel del propietario y tablero de limpieza
  for (const res of expired) {
    emitRealtimeEvent({
      hotelId: res.room.hotelId,
      guestId: res.guestId,
      reservationId: res.id,
      type: 'ROOM_STATUS_CHANGED',
      payload: {
        roomId: res.room.id,
        roomName: res.room.name,
        status: 'CLEANING',
        reason: 'RESERVATION_EXPIRED',
      },
      cleaningSafePayload: {
        roomId: res.room.id,
        roomName: res.room.name,
        status: 'CLEANING',
        reason: 'RESERVATION_EXPIRED',
      },
    })
  }

  console.log(`⏰ [Cron] ${ids.length} estadías vencidas procesadas → Habitaciones en 'Requiere Limpieza'`)
  return { expiredCount: ids.length }
}

/**
 * Pasa automáticamente a AVAILABLE ('Lista') las habitaciones que llevan
 * 30 minutos o más en estado CLEANING sin que la trabajadora las haya marcado manualmente.
 */
async function autoReleaseCleaningRooms() {
  const threshold = dayjs().subtract(30, 'minute').toDate()

  const roomsToRelease = await prisma.room.findMany({
    where: {
      status: 'CLEANING',
      updatedAt: { lte: threshold },
    },
    select: { id: true, name: true, hotelId: true },
  })

  if (roomsToRelease.length === 0) {
    return { releasedCount: 0 }
  }

  const roomIds = roomsToRelease.map(r => r.id)

  await prisma.room.updateMany({
    where: { id: { in: roomIds } },
    data: { status: 'AVAILABLE' },
  })

  // Emitir evento SSE para reflejar disponibilidad inmediata en app huésped y panel
  for (const r of roomsToRelease) {
    emitRealtimeEvent({
      hotelId: r.hotelId,
      type: 'ROOM_STATUS_CHANGED',
      payload: {
        roomId: r.id,
        roomName: r.name,
        status: 'AVAILABLE',
        reason: 'AUTO_CLEANING_TIMEOUT_30MIN',
      },
      cleaningSafePayload: {
        roomId: r.id,
        roomName: r.name,
        status: 'AVAILABLE',
        reason: 'AUTO_CLEANING_TIMEOUT_30MIN',
      },
    })
    console.log(`🧹 [Cron] Habitación ${r.name} colocada automáticamente como 'Lista' (AVAILABLE) tras 30 min desocupada.`)
  }

  return { releasedCount: roomsToRelease.length }
}

/**
 * Elimina OTPs expirados o ya usados (más de 24h).
 */
async function cleanExpiredOtps() {
  const cutoff = dayjs().subtract(24, 'hour').toDate()
  const result = await prisma.otpCode.deleteMany({
    where: {
      OR: [
        { isUsed: true, createdAt: { lte: cutoff } },
        { expiresAt: { lte: cutoff } },
      ],
    },
  })
  if (result.count > 0) {
    console.log(`🧹 [Cron] ${result.count} OTPs eliminados`)
  }
}

/**
 * Elimina refresh tokens revocados o expirados (más de 30 días).
 */
async function cleanExpiredRefreshTokens() {
  const cutoff = dayjs().subtract(30, 'day').toDate()
  const result = await prisma.refreshToken.deleteMany({
    where: {
      OR: [
        { revokedAt: { not: null, lte: cutoff } },
        { expiresAt: { lte: new Date() } },
      ],
    },
  })
  if (result.count > 0) {
    console.log(`🧹 [Cron] ${result.count} refresh tokens eliminados`)
  }
}

module.exports = {
  startCronJobs,
  expireUnpaidReservations,
  expireReservations,
  autoReleaseCleaningRooms,
}
