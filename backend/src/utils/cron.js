const cron = require('node-cron')
const { prisma } = require('../config/database')
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

  // Cada 5 minutos: expirar reservas activas cuyo check-out ya pasó y desactivar QRs
  cron.schedule('*/5 * * * *', () => {
    expireReservations().catch(err =>
      console.error('⚠️ [Cron] Error expirando estadías:', err.message)
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
 * También desactiva sus AccessTokens.
 */
async function expireReservations() {
  const now = new Date()

  // Buscar reservas activas con checkout pasado
  const expired = await prisma.reservation.findMany({
    where: {
      status: 'ACTIVE',
      checkOut: { lte: now },
    },
    select: { id: true },
  })

  if (expired.length === 0) return

  const ids = expired.map(r => r.id)

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
      where: { reservations: { some: { id: { in: ids } } } },
      data: { status: 'CLEANING' },
    }),
  ])

  console.log(`⏰ [Cron] ${ids.length} reservas expiradas procesadas`)
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

module.exports = { startCronJobs, expireUnpaidReservations, expireReservations }
