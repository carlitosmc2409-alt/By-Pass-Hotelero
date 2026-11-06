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
  ]
  const missing = required.filter(key => !env[key])
  if (missing.length > 0) {
    throw new Error(`Variables de entorno faltantes: ${missing.join(', ')}`)
  }
}

validateEnv()

module.exports = env
