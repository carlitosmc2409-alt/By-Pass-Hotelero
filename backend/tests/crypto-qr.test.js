const { test, describe } = require('node:test')
const assert = require('node:assert/strict')
const path = require('path')

// Cargar variables de entorno de prueba antes de importar utilidades
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') })

const {
  generateQrToken,
  validateQrTokenSignature,
  hashQrToken,
  generateHotelBridgeToken,
  validateHotelBridgeToken,
  generateHotelIotToken,
  validateHotelIotToken,
  generateOtp,
  hashValue,
} = require('../src/utils/crypto')

describe('Módulo Criptográfico y Seguridad de Tokens StayPass', () => {
  const dummyReservationId = 'a0000000-0000-4000-8000-000000000001'
  const dummyHotelId = 'h1111111-1111-4111-8111-111111111111'

  test('generateQrToken emite token con 4 partes y hash SHA-256 no vacío', () => {
    const { rawToken, tokenHash } = generateQrToken(dummyReservationId)
    assert.ok(rawToken, 'rawToken debe estar definido')
    assert.ok(tokenHash, 'tokenHash debe estar definido')

    const parts = rawToken.split(':')
    assert.strictEqual(parts.length, 4, 'El rawToken debe componerse de 4 bloques (id, random, timestamp, signature)')
    assert.strictEqual(parts[0], dummyReservationId)
    assert.strictEqual(tokenHash.length, 64, 'El hash SHA-256 debe medir 64 caracteres hex')
  })

  test('validateQrTokenSignature aprueba tokens válidos y rechaza adulterados', () => {
    const { rawToken } = generateQrToken(dummyReservationId)
    assert.strictEqual(validateQrTokenSignature(rawToken), true, 'Firma legítima debe ser válida')

    // Modificar un solo carácter del cuerpo
    const tampered = rawToken.replace('a0000000', 'b0000000')
    assert.strictEqual(validateQrTokenSignature(tampered), false, 'Cuerpo alterado debe ser rechazado')

    // Modificar la firma
    const parts = rawToken.split(':')
    const badSig = parts.slice(0, 3).join(':') + ':0000000000000000000000000000000000000000000000000000000000000000'
    assert.strictEqual(validateQrTokenSignature(badSig), false, 'Firma adulterada debe ser rechazada')

    // Tokens malformados
    assert.strictEqual(validateQrTokenSignature('token-invalido'), false)
    assert.strictEqual(validateQrTokenSignature(null), false)
  })

  test('hashQrToken es determinista y genera el mismo hash para el mismo token', () => {
    const { rawToken, tokenHash } = generateQrToken(dummyReservationId)
    const computed = hashQrToken(rawToken)
    assert.strictEqual(computed, tokenHash)
  })

  test('generateHotelBridgeToken y validateHotelBridgeToken autentican el puente BDV', () => {
    const token = generateHotelBridgeToken(dummyHotelId)
    assert.strictEqual(validateHotelBridgeToken(dummyHotelId, token), true)
    assert.strictEqual(validateHotelBridgeToken('otro-hotel', token), false)
    assert.strictEqual(validateHotelBridgeToken(dummyHotelId, 'token-falso'), false)
  })

  test('generateHotelIotToken y validateHotelIotToken autentican las controladoras FAAC / ESP32', () => {
    const token = generateHotelIotToken(dummyHotelId)
    assert.strictEqual(validateHotelIotToken(dummyHotelId, token), true)
    assert.strictEqual(validateHotelIotToken('otro-hotel', token), false)
  })

  test('generateOtp genera longitud esperada y hashValue enmascara de forma segura', () => {
    const otp = generateOtp(6)
    assert.strictEqual(otp.length, 6)
    assert.match(otp, /^[0-9]{6}$/)

    const hash1 = hashValue(otp)
    const hash2 = hashValue(otp)
    assert.strictEqual(hash1, hash2)
    assert.strictEqual(hash1.length, 64)
  })
})
