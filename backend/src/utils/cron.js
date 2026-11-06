const cron = require('node-cron')
const { prisma } = require('../config/database')
const dayjs = require('dayjs')

/**
 * Inicia todos los trabajos programados en segundo plano.
 */
function startCronJobs() {
  console.log('⏰ Iniciando jobs programados...')

  // Cada 5 minutos: expirar reservas y QRs vencidos
  cron.schedule('*/5 * * * *', expireReservations)

  // Cada hora: limpiar OTPs usados/expirados
  cron.schedule('0 * * * *', cleanExpiredOtps)

  // Cada hora: limpiar refresh tokens revocados/expirados
  cron.schedule('0 * * * *', cleanExpiredRefreshTokens)

  console.log('✅ Jobs programados activos')
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
    // Marcar habitaciones como disponibles (limpieza)
    // (En producción podría marcar como CLEANING primero)
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

module.exports = { startCronJobs }
