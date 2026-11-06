const { buildApp } = require('./config/app')
const { connectDB, disconnectDB } = require('./config/database')
const env = require('./config/env')
const { startCronJobs } = require('./utils/cron')

async function start() {
  const app = await buildApp()

  await connectDB()

  // Jobs de fondo (expirar reservas, limpiar OTPs, etc.)
  startCronJobs()

  try {
    await app.listen({ port: env.PORT, host: env.HOST })
    console.log(`🚀 Servidor corriendo en http://${env.HOST}:${env.PORT}`)
    console.log(`📖 API disponible en http://${env.HOST}:${env.PORT}${env.API_PREFIX}`)
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }

  // Graceful shutdown
  const signals = ['SIGINT', 'SIGTERM']
  signals.forEach(signal => {
    process.on(signal, async () => {
      console.log(`\n⚠️  Señal ${signal} recibida. Cerrando servidor...`)
      await app.close()
      await disconnectDB()
      process.exit(0)
    })
  })
}

start()
