const env = require('../config/env')

/**
 * Envía un código OTP por WhatsApp.
 * Soporta Twilio (sandbox y producción).
 *
 * En Venezuela, WhatsApp es más confiable que el SMS tradicional.
 * Movilnet/Digitel/Movistar tienen alta tasa de fallo en SMS.
 */
async function sendWhatsAppOtp(phone, code, purpose) {
  const messages = {
    PHONE_VERIFICATION: `🔐 *PMS Hotelero*\n\nTu código de verificación es: *${code}*\n\nVálido por ${env.OTP_EXPIRES_MINUTES} minutos.\n\n_No compartas este código con nadie._`,
    LOGIN: `🔐 *PMS Hotelero*\n\nCódigo de acceso: *${code}*\n\nVálido por ${env.OTP_EXPIRES_MINUTES} minutos.`,
    PASSWORD_RESET: `🔐 *PMS Hotelero*\n\nCódigo para restablecer contraseña: *${code}*\n\nVálido por ${env.OTP_EXPIRES_MINUTES} minutos.\n\n_Si no solicitaste esto, ignora este mensaje._`,
  }

  const message = messages[purpose] || `Tu código es: ${code}`

  if (env.isDev() && !env.TWILIO_ACCOUNT_SID) {
    // Modo desarrollo: solo imprimir en consola
    console.log(`\n📱 [WhatsApp OTP - DEV MODE]`)
    console.log(`   Para: ${phone}`)
    console.log(`   Código: ${code}`)
    console.log(`   Propósito: ${purpose}\n`)
    return { success: true, dev: true }
  }

  if (env.WHATSAPP_PROVIDER === 'twilio') {
    return sendViaTwilio(phone, message)
  }

  throw new Error(`Proveedor WhatsApp no soportado: ${env.WHATSAPP_PROVIDER}`)
}

async function sendViaTwilio(phone, message) {
  // Lazy-load del cliente Twilio para no romper si no está instalado en dev
  let twilio
  try {
    twilio = require('twilio')
  } catch {
    throw new Error('Paquete twilio no instalado. Ejecuta: npm install twilio')
  }

  const client = twilio(env.TWILIO_ACCOUNT_SID, env.TWILIO_AUTH_TOKEN)

  const result = await client.messages.create({
    from: env.TWILIO_WHATSAPP_FROM,
    to: `whatsapp:${phone}`,
    body: message,
  })

  return { success: true, sid: result.sid }
}

module.exports = { sendWhatsAppOtp }
