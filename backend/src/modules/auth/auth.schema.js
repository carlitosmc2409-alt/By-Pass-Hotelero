const { z } = require('zod')

// Teléfono venezolano: +58 seguido de 10 dígitos (ej: +584121234567)
const venezuelaPhone = z
  .string()
  .regex(/^\+58[0-9]{10}$/, 'Teléfono venezolano inválido. Formato: +584121234567')

// Cédula venezolana: V-12345678 o E-12345678 (normalizada a "V-12345678")
const cedulaBase = z
  .string({ required_error: 'La cédula es obligatoria' })
  .regex(/^[VEve]-?\d{6,8}$/, 'Cédula inválida. Formato: V-12345678 o E-12345678')
  .transform(v => v.toUpperCase().replace('-', '').replace(/^([VE])(\d+)$/, '$1-$2'))

const cedulaOptional = cedulaBase.optional()
const cedulaRequired = cedulaBase

// ── Huésped ──────────────────────────────────────────────────

const registerGuestSchema = z.object({
  fullName: z.string().min(3, 'Nombre muy corto').max(100),
  phone: venezuelaPhone,
  cedula: cedulaOptional,
  password: z
    .string()
    .min(8, 'Contraseña mínima de 8 caracteres')
    .max(100)
    .regex(/[A-Z]/, 'Debe tener al menos una mayúscula')
    .regex(/[0-9]/, 'Debe tener al menos un número'),
})

const verifyOtpSchema = z.object({
  phone: venezuelaPhone,
  code: z.string().length(6, 'El código OTP debe tener 6 dígitos').regex(/^\d+$/),
  purpose: z.enum(['PHONE_VERIFICATION', 'LOGIN', 'PASSWORD_RESET']),
})

const loginGuestSchema = z.object({
  phone: venezuelaPhone,
  password: z.string().min(1, 'Contraseña requerida'),
})

const refreshTokenSchema = z.object({
  refreshToken: z.string().min(1),
})

const requestOtpSchema = z.object({
  phone: venezuelaPhone,
  purpose: z.enum(['PHONE_VERIFICATION', 'LOGIN', 'PASSWORD_RESET']),
})

// ── Propietario ───────────────────────────────────────────────

const registerOwnerSchema = z.object({
  fullName: z.string().min(3).max(100),
  email: z.string().email('Email inválido'),
  phone: venezuelaPhone,
  cedula: cedulaRequired,
  password: z
    .string()
    .min(10, 'Contraseña mínima de 10 caracteres para propietarios')
    .max(100)
    .regex(/[A-Z]/, 'Debe tener al menos una mayúscula')
    .regex(/[0-9]/, 'Debe tener al menos un número')
    .regex(/[^A-Za-z0-9]/, 'Debe tener al menos un carácter especial'),
})

const loginOwnerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
})

module.exports = {
  registerGuestSchema,
  verifyOtpSchema,
  loginGuestSchema,
  refreshTokenSchema,
  requestOtpSchema,
  registerOwnerSchema,
  loginOwnerSchema,
}
