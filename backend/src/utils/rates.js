const env = require('../config/env')

const CACHE_TTL_MS = 60 * 60 * 1000 // 1 hora
let cachedRate = null
let cachedAt = 0

let externalFetcher = async () => {
  const res = await fetch('https://ve.dolarapi.com/v1/dolares/oficial', {
    signal: AbortSignal.timeout(4000),
    headers: { Accept: 'application/json' },
  })
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} consultando tasa oficial`)
  }
  const data = await res.json()
  const val = Number(data?.promedio ?? data?.valor)
  if (!Number.isFinite(val) || val <= 0) {
    throw new Error('Respuesta de tasa oficial inválida')
  }
  return round2(val)
}

function setRateFetcher(customFn) {
  externalFetcher = customFn
  cachedRate = null
  cachedAt = 0
}

/**
 * Obtiene la tasa Bs/USD aplicable:
 * 1. En modo `simulated` (sin forceLive), retorna SIMULATED_BCV_RATE para determinismo en pruebas.
 * 2. En modo real (`bdv_notification` / `manual`), consulta la tasa oficial BCV con caché de 1h.
 * 3. Si la fuente externa falla, usa en orden: caché previa -> fallbackRate del hotel -> SIMULATED_BCV_RATE.
 */
async function getRate(options = {}) {
  const { fallbackRate = null, forceLive = false } = options

  if (!forceLive && env.PAYMENT_MODE === 'simulated' && env.SIMULATED_BCV_RATE > 0) {
    return round2(env.SIMULATED_BCV_RATE)
  }

  const now = Date.now()
  if (cachedRate && now - cachedAt < CACHE_TTL_MS) {
    return cachedRate
  }

  try {
    const live = await externalFetcher()
    if (live > 0) {
      cachedRate = round2(live)
      cachedAt = now
      return cachedRate
    }
  } catch (_) {
    // Continuar hacia la cadena de respaldo
  }

  if (Number(fallbackRate) > 0) {
    return round2(Number(fallbackRate))
  }

  if (cachedRate && cachedRate > 0) {
    return cachedRate
  }

  if (env.SIMULATED_BCV_RATE > 0) {
    return round2(env.SIMULATED_BCV_RATE)
  }

  const error = new Error('Tasa de cambio BCV no disponible temporalmente')
  error.statusCode = 503
  throw error
}

function round2(n) {
  return Math.round((Number(n) + Number.EPSILON) * 100) / 100
}

module.exports = { getRate, round2, setRateFetcher }
