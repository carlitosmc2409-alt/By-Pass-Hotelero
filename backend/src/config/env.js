const path = require('path')
require('dotenv').config({ path: path.resolve(__dirname, '..', '..', '.env') })
require('dotenv').config()

const env = {
  NODE_ENV: process.env.NODE_ENV || 'development',
  PORT: parseInt(process.env.PORT) || 3000,
  HOST: process.env.HOST || '0.0.0.0',
  API_PREFIX: process.env.API_PREFIX || '/api/v1',

  DATABASE_URL: process.env.DATABASE_URL,

  JWT_SECRET: process.env.JWT_SECRET,
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET,
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || '15m',
  JWT_REFRESH_EXPIRES_IN: process.env.JWT_REFRESH_EXPIRES_IN || '7d',

  OTP_EXPIRES_MINUTES: parseInt(process.env.OTP_EXPIRES_MINUTES) || 10,
  OTP_LENGTH: parseInt(process.env.OTP_LENGTH) || 6,

  BCRYPT_ROUNDS: parseInt(process.env.BCRYPT_ROUNDS) || 12,

  QR_SECRET_KEY: process.env.QR_SECRET_KEY,

  // Cifrado de datos de pago del huésped (AES-256-GCM, 64 caracteres hex)
  DATA_ENCRYPTION_KEY: process.env.DATA_ENCRYPTION_KEY,

  // Verificación de pagos: manual | simulated | bdv_notification
  PAYMENT_MODE: process.env.PAYMENT_MODE || 'manual',
  PAYMENT_HOLD_MINUTES: parseInt(process.env.PAYMENT_HOLD_MINUTES) || 10,
  SIMULATED_BCV_RATE: parseFloat(process.env.SIMULATED_BCV_RATE) || 0,

  // Agente extractor IA (Gemini API) — fallback cuando cambia el formato de notificación BDV
  GEMINI_API_KEY: process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || '',
  GEMINI_MODEL: process.env.GEMINI_MODEL || 'gemini-3.8-flash',

  // WhatsApp
  WHATSAPP_PROVIDER: process.env.WHATSAPP_PROVIDER || 'twilio',
  TWILIO_ACCOUNT_SID: process.env.TWILIO_ACCOUNT_SID,
  TWILIO_AUTH_TOKEN: process.env.TWILIO_AUTH_TOKEN,
  TWILIO_WHATSAPP_FROM: process.env.TWILIO_WHATSAPP_FROM,

  // Pagos
  PAGO_MOVIL_WEBHOOK_SECRET: process.env.PAGO_MOVIL_WEBHOOK_SECRET,
  BINANCE_API_KEY: process.env.BINANCE_API_KEY,
  BINANCE_SECRET_KEY: process.env.BINANCE_SECRET_KEY,
  BINANCE_MERCHANT_ID: process.env.BINANCE_MERCHANT_ID,
  ZELLE_CONFIRMATION_TIMEOUT_MIN: parseInt(process.env.ZELLE_CONFIRMATION_TIMEOUT_MIN) || 30,

  // AWS
  AWS_ACCESS_KEY_ID: process.env.AWS_ACCESS_KEY_ID,
  AWS_SECRET_ACCESS_KEY: process.env.AWS_SECRET_ACCESS_KEY,
  AWS_REGION: process.env.AWS_REGION || 'us-east-1',
  AWS_S3_BUCKET: process.env.AWS_S3_BUCKET,

  // Resend Email Service
  RESEND_API_KEY: process.env.RESEND_API_KEY || '',
  EMAIL_FROM: process.env.EMAIL_FROM || 'StayPass <onboarding@resend.dev>',

  isProd: () => process.env.NODE_ENV === 'production',
  isDev: () => process.env.NODE_ENV === 'development',
}

// Validar variables críticas en producción
function validateEnv() {
  const required = [
    'DATABASE_URL',
    'JWT_SECRET',
    'JWT_REFRESH_SECRET',
    'QR_SECRET_KEY',
    'DATA_ENCRYPTION_KEY',
  ]
  const missing = required.filter(key => !env[key])
  if (missing.length > 0) {
    throw new Error(`Variables de entorno faltantes: ${missing.join(', ')}`)
  }
  if (!/^[0-9a-fA-F]{64}$/.test(env.DATA_ENCRYPTION_KEY)) {
    throw new Error('DATA_ENCRYPTION_KEY debe ser de 64 caracteres hexadecimales (32 bytes)')
  }
  if (!['manual', 'simulated', 'bdv_notification'].includes(env.PAYMENT_MODE)) {
    throw new Error('PAYMENT_MODE debe ser manual, simulated o bdv_notification')
  }
  if (env.PAYMENT_MODE === 'simulated' && env.isProd()) {
    throw new Error('PAYMENT_MODE=simulated no está permitido en producción')
  }
}

validateEnv()

module.exports = env
