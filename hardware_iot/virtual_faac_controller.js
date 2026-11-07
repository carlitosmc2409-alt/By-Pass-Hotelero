/**
 * ============================================================================
 * Emulador Virtual de Controladora Física ESP32 + Lector Óptico GM65 + FAAC
 * ============================================================================
 * Permite probar el 100% de la arquitectura física ANTES de comprar o cablear
 * la barrera FAAC y el lector óptico:
 *  - Escucha en http://localhost:3090/rpc/pulse (idéntico al ESP32 real en LAN)
 *  - Verifica firma constante `x-hotel-iot-token`
 *  - Simula cierre de bornera `J5: OPEN-A + GND` y fotocélula `SAFE`
 *  - Envía heartbeats periódicos a `POST /api/v1/access/iot/heartbeat`
 *  - Expone `POST /simulate-gm65-scan` para emular lectura UART2 del módulo GM65
 */
const http = require('http')
const path = require('path')
const crypto = require('crypto')

// Cargar entorno del backend sin imprimir ningún secreto
require(path.resolve(__dirname, '..', 'backend', 'node_modules', 'dotenv')).config({
  path: path.resolve(__dirname, '..', 'backend', '.env'),
})

const API_BASE = process.env.API_BASE_URL || 'http://localhost:3000/api/v1'
const PORT = Number(process.env.VIRTUAL_FAAC_PORT || 3090)
const startedAt = Date.now()

const controllerState = {
  hotelId: null,
  hotelName: null,
  gpio26RelayClosed: false,
  gpio33SafePhotocell: 'CLEAR', // 'CLEAR' | 'OBSTRUCTED'
  gm65UartStatus: 'GM65_UART_READY',
  pulseCount: 0,
  lastPulse: null,
  lastOpticalScan: null,
}

function computeHotelIotToken(hotelId) {
  const secret = process.env.QR_SECRET_KEY || ''
  return crypto
    .createHmac('sha256', secret)
    .update(`iot-faac:${String(hotelId)}`)
    .digest('hex')
}

function verifyIotToken(hotelId, received) {
  if (!hotelId || !received) return false
  const expected = Buffer.from(computeHotelIotToken(hotelId), 'hex')
  const rx = Buffer.from(String(received), 'hex')
  if (expected.length !== rx.length) return false
  return crypto.timingSafeEqual(expected, rx)
}

function pulseVirtualRelay(durationMs = 1000, meta = {}) {
  const safeMs = Math.min(Math.max(Number(durationMs) || 1000, 200), 3000)
  controllerState.gpio26RelayClosed = true
  controllerState.pulseCount += 1
  controllerState.lastPulse = {
    ...meta,
    pulseDurationMs: safeMs,
    at: new Date().toISOString(),
  }
  setTimeout(() => {
    controllerState.gpio26RelayClosed = false
  }, safeMs)
  return safeMs
}

async function discoverPrimaryHotel() {
  try {
    const res = await fetch(`${API_BASE}/hotels`, {
      signal: AbortSignal.timeout(2500),
    })
    if (!res.ok) return null
    const json = await res.json()
    const first = json.data && json.data[0]
    if (first && first.id) {
      controllerState.hotelId = first.id
      controllerState.hotelName = first.name
      return first.id
    }
  } catch (_) {}
  return controllerState.hotelId
}

async function emitHeartbeats() {
  const hotelId = controllerState.hotelId || (await discoverPrimaryHotel())
  if (!hotelId) return

  const token = computeHotelIotToken(hotelId)
  const uptimeSec = Math.floor((Date.now() - startedAt) / 1000)
  const virtualNodes = [
    {
      deviceId: 'faac-entrada-1',
      zone: 'FAAC_ENTRY',
      firmware: 'ESP32-StayPass-FAAC-1.2.0 (Emulador)',
      rssiDbm: -44,
      opticalReader: controllerState.gm65UartStatus,
      safePhotocell: controllerState.gpio33SafePhotocell,
      relayState: controllerState.gpio26RelayClosed ? 'CLOSED_PULSING' : 'OPEN_NO',
    },
    {
      deviceId: 'faac-salida-1',
      zone: 'FAAC_EXIT',
      firmware: 'ESP32-StayPass-FAAC-1.2.0 (Emulador)',
      rssiDbm: -48,
      opticalReader: controllerState.gm65UartStatus,
      safePhotocell: controllerState.gpio33SafePhotocell,
      relayState: 'OPEN_NO',
    },
    {
      deviceId: 'lock-101',
      zone: 'ROOM_DOOR',
      firmware: 'ESP32-StayPass-Lock-1.2.0 (Emulador)',
      rssiDbm: -51,
      opticalReader: 'GM65_UART_READY',
      safePhotocell: 'N/A',
      relayState: 'OPEN_NO',
    },
  ]

  for (const node of virtualNodes) {
    try {
      await fetch(`${API_BASE}/access/iot/heartbeat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-hotel-iot-token': token,
        },
        body: JSON.stringify({
          hotelId,
          ...node,
          uptimeSec,
          emulated: true,
        }),
        signal: AbortSignal.timeout(2500),
      })
    } catch (_) {}
  }
}

function readJsonBody(req) {
  return new Promise((resolve) => {
    let raw = ''
    req.on('data', (chunk) => {
      if (raw.length < 32768) raw += chunk
    })
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {})
      } catch (_) {
        resolve({})
      }
    })
  })
}

function sendJson(res, status, obj) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, x-hotel-iot-token, x-hotel-id',
  })
  res.end(JSON.stringify(obj))
}

function startVirtualFaacController(port = PORT) {
  const server = http.createServer(async (req, res) => {
    if (req.method === 'OPTIONS') {
      return sendJson(res, 200, { ok: true })
    }

    const url = (req.url || '/').split('?')[0]

    if (req.method === 'GET' && url === '/status') {
      return sendJson(res, 200, {
        ok: true,
        emulated: true,
        firmware: 'ESP32-StayPass-FAAC-1.2.0 (Emulador)',
        hotelId: controllerState.hotelId,
        hotelName: controllerState.hotelName,
        pins: {
          GPIO16_UART2_RX: controllerState.gm65UartStatus,
          GPIO26_RELAY_OPEN_A: controllerState.gpio26RelayClosed
            ? 'HIGH (BORNERA OPEN-A CERRADA)'
            : 'LOW (BORNERA OPEN-A ABIERTA NO)',
          GPIO33_SAFE_PHOTOCELL: controllerState.gpio33SafePhotocell,
        },
        pulseCount: controllerState.pulseCount,
        lastPulse: controllerState.lastPulse,
        lastOpticalScan: controllerState.lastOpticalScan,
        uptimeSec: Math.floor((Date.now() - startedAt) / 1000),
      })
    }

    if (req.method === 'POST' && url === '/rpc/pulse') {
      const body = await readJsonBody(req)
      const hotelId = req.headers['x-hotel-id'] || controllerState.hotelId
      const rxToken = req.headers['x-hotel-iot-token'] || ''

      if (!verifyIotToken(hotelId, rxToken)) {
        return sendJson(res, 401, {
          ok: false,
          message: 'Firma x-hotel-iot-token rechazada por el ESP32 virtual',
        })
      }

      const dryRun = Boolean(body.dryRun)
      let pulsedMs = Number(body.pulseDurationMs || 1000)
      if (!dryRun) {
        pulsedMs = pulseVirtualRelay(pulsedMs, {
          deviceId: body.deviceId || 'faac-entrada-1',
          direction: body.direction || 'ENTRY',
          triggeredBy: body.triggeredBy || 'WEBHOOK',
        })
      }

      return sendJson(res, 200, {
        ok: true,
        emulated: true,
        dryRun,
        deviceId: body.deviceId || 'faac-entrada-1',
        terminal: 'J5:OPEN-A+GND',
        relayState: dryRun ? 'DIAGNOSTIC_OK_NO_PULSE' : 'PULSED_NO',
        pulseDurationMs: pulsedMs,
        safePhotocell: controllerState.gpio33SafePhotocell,
        opticalReader: controllerState.gm65UartStatus,
        rssiDbm: -44,
        pulseCount: controllerState.pulseCount,
      })
    }

    // Simula que el lector óptico GM65 entrega por UART2 una trama QR al ESP32
    if (req.method === 'POST' && url === '/simulate-gm65-scan') {
      const body = await readJsonBody(req)
      const rawToken = String(body.token || '').trim()
      const deviceId = String(body.deviceId || 'faac-entrada-1').trim()

      if (rawToken.length < 10) {
        return sendJson(res, 400, {
          ok: false,
          message: 'Trama UART GM65 vacía o demasiado corta',
        })
      }

      try {
        const t0 = Date.now()
        const apiRes = await fetch(`${API_BASE}/access/validate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token: rawToken, deviceId }),
          signal: AbortSignal.timeout(3500),
        })
        const apiData = await apiRes.json()
        const rttMs = Date.now() - t0

        if (apiRes.ok && apiData.allowed) {
          const ms = (apiData.faacPulse && apiData.faacPulse.pulseDurationMs) || 1000
          pulseVirtualRelay(ms, {
            deviceId,
            direction: deviceId.includes('salida') ? 'EXIT' : 'ENTRY',
            triggeredBy: 'GM65_UART2_OPTICAL',
          })
        }

        controllerState.lastOpticalScan = {
          deviceId,
          allowed: Boolean(apiData.allowed),
          rttMs,
          at: new Date().toISOString(),
        }

        return sendJson(res, apiRes.status, {
          ...apiData,
          esp32Telemetry: {
            uartPort: 'UART2 (GPIO16 RX <- GM65)',
            backendRttMs: rttMs,
            gpio26RelayTriggered: Boolean(apiData.allowed),
            safePhotocell: controllerState.gpio33SafePhotocell,
          },
        })
      } catch (err) {
        return sendJson(res, 502, {
          ok: false,
          allowed: false,
          message: `ESP32 no pudo contactar API: ${err.message}`,
        })
      }
    }

    return sendJson(res, 404, { ok: false, message: 'Ruta no encontrada en ESP32 virtual' })
  })

  server.listen(port, '0.0.0.0', () => {
    console.log(
      `✅ Controladora Virtual ESP32 + Lector GM65 + FAAC activa en http://localhost:${port}`
    )
    setTimeout(emitHeartbeats, 1200)
    setInterval(emitHeartbeats, 12000)
  })

  return server
}

if (require.main === module) {
  startVirtualFaacController(PORT)
}

module.exports = { startVirtualFaacController }
