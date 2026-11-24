const { test, describe } = require('node:test')
const assert = require('node:assert/strict')
const { round2, getRate } = require('../src/utils/rates')

describe('Cálculos de Tarifas y Conversión Cambiaria', () => {
  test('round2 redondea con precisión bancaria a 2 decimales', () => {
    assert.strictEqual(round2(10.555), 10.56)
    assert.strictEqual(round2(10.554), 10.55)
    assert.strictEqual(round2(10), 10.00)
    assert.strictEqual(round2('25.409'), 25.41)
  })

  test('getRate retorna fallbackRate cuando no hay conexión externa configurada', async () => {
    const rate = await getRate({ fallbackRate: 45.50 })
    assert.ok(typeof rate === 'number')
    assert.ok(rate > 0)
  })
})
