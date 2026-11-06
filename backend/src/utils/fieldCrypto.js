const crypto = require('crypto')
const env = require('../config/env')

const VERSION = 'v1'

function key() {
  return Buffer.from(env.DATA_ENCRYPTION_KEY, 'hex')
}

/**
 * Cifra un texto con AES-256-GCM. Formato: v1:iv:tag:ciphertext (hex).
 */
function encryptField(plain) {
  if (plain === null || plain === undefined || plain === '') return null
  const iv = crypto.randomBytes(12)
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv)
  const ct = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()])
  const tag = cipher.getAuthTag()
  return [VERSION, iv.toString('hex'), tag.toString('hex'), ct.toString('hex')].join(':')
}

function decryptField(payload) {
  if (!payload) return null
  const [version, iv, tag, ct] = payload.split(':')
  if (version !== VERSION || !iv || !tag || !ct) {
    throw new Error('Formato de campo cifrado inválido')
  }
  const decipher = crypto.createDecipheriv('aes-256-gcm', key(), Buffer.from(iv, 'hex'))
  decipher.setAuthTag(Buffer.from(tag, 'hex'))
  return Buffer.concat([
    decipher.update(Buffer.from(ct, 'hex')),
    decipher.final(),
  ]).toString('utf8')
}

/** Devuelve solo los últimos N caracteres, para mostrar datos sin exponerlos. */
function maskTail(value, visible = 4) {
  if (!value) return null
  const s = String(value)
  return '*'.repeat(Math.max(0, s.length - visible)) + s.slice(-visible)
}

module.exports = { encryptField, decryptField, maskTail }
