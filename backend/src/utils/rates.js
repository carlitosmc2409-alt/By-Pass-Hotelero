const env = require('../config/env')

/**
 * Tasa Bs/USD. Por ahora solo existe la tasa simulada de pruebas.
 * Cuando se conecte la fuente oficial (BCV), reemplazar el cuerpo de getRate().
 */
async function getRate() {
  if (env.PAYMENT_MODE === 'simulated' && env.SIMULATED_BCV_RATE > 0) {
    return env.SIMULATED_BCV_RATE
  }
  const error = new Error('Tasa de cambio no disponible')
  error.statusCode = 503
  throw error
}

function round2(n) {
  return Math.round((Number(n) + Number.EPSILON) * 100) / 100
}

module.exports = { getRate, round2 }
