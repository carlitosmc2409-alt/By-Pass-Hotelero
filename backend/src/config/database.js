const { PrismaClient } = require('@prisma/client')
const env = require('./env')

const prisma = new PrismaClient({
  log: env.isDev() ? ['query', 'info', 'warn', 'error'] : ['error'],
})

// Verificar conexión al iniciar
async function connectDB() {
  try {
    await prisma.$connect()
    console.log('✅ Base de datos conectada')
  } catch (error) {
    console.error('❌ Error conectando a la base de datos:', error.message)
    process.exit(1)
  }
}

async function disconnectDB() {
  await prisma.$disconnect()
  console.log('🔌 Base de datos desconectada')
}

module.exports = { prisma, connectDB, disconnectDB }
