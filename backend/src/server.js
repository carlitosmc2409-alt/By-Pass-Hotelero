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
    // En Windows, escuchar en '::' habilita dual-stack (::1 + 127.0.0.1 + LAN) evitando demoras en localhost
    const listenHost = env.HOST === '0.0.0.0' ? '::' : env.HOST
    try {
      await app.listen({ port: env.PORT, host: listenHost })
    } catch {
      await app.listen({ port: env.PORT, host: env.HOST })
    }
    console.log(`🚀 Servidor corriendo en http://localhost:${env.PORT}`)
    console.log(`📖 API disponible en http://localhost:${env.PORT}${env.API_PREFIX}`)
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
