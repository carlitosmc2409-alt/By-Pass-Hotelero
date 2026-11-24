const { Resend } = require('resend')
const env = require('../config/env')

let resendClient = null
if (env.RESEND_API_KEY) {
  resendClient = new Resend(env.RESEND_API_KEY)
}

/**
 * Enviar correo de bienvenida al registrarse un nuevo usuario (propietario o huésped)
 */
async function sendWelcomeEmail({ to, name, role = 'Huésped' }) {
  if (!resendClient) {
    console.warn(`[EmailService] RESEND_API_KEY no configurada. Simulando bienvenida para: ${to}`)
    return { success: false, simulated: true }
  }

  const html = `
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; margin: 0; padding: 20px; color: #f8fafc; }
      .container { max-width: 560px; margin: 0 auto; background: #1e293b; border-radius: 12px; border: 1px solid #334155; padding: 32px; }
      .header { border-bottom: 1px solid #334155; padding-bottom: 20px; margin-bottom: 24px; }
      .brand { font-size: 22px; font-weight: bold; color: #38bdf8; letter-spacing: -0.5px; }
      h2 { color: #ffffff; margin-top: 0; }
      p { color: #94a3b8; line-height: 1.6; font-size: 15px; }
      .badge { display: inline-block; background: rgba(56, 189, 248, 0.15); color: #38bdf8; padding: 4px 12px; border-radius: 9999px; font-size: 13px; font-weight: 600; margin-bottom: 12px; }
      .footer { margin-top: 32px; padding-top: 16px; border-top: 1px solid #334155; font-size: 12px; color: #64748b; text-align: center; }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="header">
        <div class="brand">StayPass</div>
      </div>
      <div class="badge">Cuenta Creada</div>
      <h2>¡Bienvenido, ${name}!</h2>
      <p>Tu cuenta como <strong>${role}</strong> ha sido configurada exitosamente en StayPass, el sistema de acceso inteligente y gestión hotelera sin fricción.</p>
      <p>Ahora puedes acceder a la plataforma, gestionar tus reservas y generar tu llave de acceso digital por código QR.</p>
      <p>Si tienes alguna duda o necesitas asistencia, estamos para ayudarte.</p>
      <div class="footer">
        © ${new Date().getFullYear()} StayPass · Tu habitación sin esperas ni preguntas. Todos los derechos reservados.
      </div>
    </div>
  </body>
  </html>
  `

  try {
    const data = await resendClient.emails.send({
      from: env.EMAIL_FROM,
      to,
      subject: `¡Bienvenido a StayPass, ${name}!`,
      html,
    })
    return { success: true, data }
  } catch (error) {
    console.error('[EmailService] Error enviando correo de bienvenida:', error.message)
    return { success: false, error: error.message }
  }
}

/**
 * Enviar correo de recuperación de contraseña con enlace y código seguro
 */
async function sendPasswordResetEmail({ to, name, resetUrl, code }) {
  if (!resendClient) {
    console.warn(`[EmailService] RESEND_API_KEY no configurada. Simulando recuperación para: ${to} (Código: ${code})`)
    return { success: false, simulated: true }
  }

  const html = `
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; margin: 0; padding: 20px; color: #f8fafc; }
      .container { max-width: 560px; margin: 0 auto; background: #1e293b; border-radius: 12px; border: 1px solid #334155; padding: 32px; }
      .header { border-bottom: 1px solid #334155; padding-bottom: 20px; margin-bottom: 24px; }
      .brand { font-size: 22px; font-weight: bold; color: #38bdf8; letter-spacing: -0.5px; }
      h2 { color: #ffffff; margin-top: 0; }
      p { color: #94a3b8; line-height: 1.6; font-size: 15px; }
      .code-box { background: #0f172a; border: 1px dashed #38bdf8; border-radius: 8px; padding: 18px; text-align: center; margin: 24px 0; }
      .code { font-size: 28px; font-weight: bold; letter-spacing: 6px; color: #38bdf8; font-family: monospace; }
      .btn { display: inline-block; background: #0284c7; color: #ffffff; padding: 12px 24px; border-radius: 8px; font-weight: 600; text-decoration: none; margin-top: 10px; }
      .warning { font-size: 13px; color: #f59e0b; margin-top: 20px; }
      .footer { margin-top: 32px; padding-top: 16px; border-top: 1px solid #334155; font-size: 12px; color: #64748b; text-align: center; }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="header">
        <div class="brand">StayPass</div>
      </div>
      <h2>Recuperación de Contraseña</h2>
      <p>Hola, ${name}. Hemos recibido una solicitud para restablecer la contraseña de tu cuenta StayPass.</p>
      
      <div class="code-box">
        <div style="font-size: 13px; color: #94a3b8; margin-bottom: 8px;">Tu código de seguridad:</div>
        <div class="code">${code}</div>
      </div>

      ${resetUrl ? `<div style="text-align: center; margin-bottom: 20px;"><a href="${resetUrl}" class="btn">Restablecer mi Contraseña</a></div>` : ''}

      <p class="warning">⚠️ Este código expirará en 15 minutos. Si no solicitaste este cambio, puedes ignorar este correo de forma segura.</p>
      <div class="footer">
        © ${new Date().getFullYear()} StayPass · Tu habitación sin esperas ni preguntas. Todos los derechos reservados.
      </div>
    </div>
  </body>
  </html>
  `

  try {
    const data = await resendClient.emails.send({
      from: env.EMAIL_FROM,
      to,
      subject: `Código de recuperación de contraseña: ${code}`,
      html,
    })
    return { success: true, data }
  } catch (error) {
    console.error('[EmailService] Error enviando correo de recuperación:', error.message)
    return { success: false, error: error.message }
  }
}

module.exports = {
  sendWelcomeEmail,
  sendPasswordResetEmail,
}
