/**
 * Registro en memoria de telemetría y salud de controladoras físicas/virtuales IoT
 * (Tótems ESP32 + Lector Óptico GM65 + Relés de Barreras FAAC y Cerraduras).
 */
const devicesByHotel = new Map()
const ONLINE_TTL_MS = 45000

function getHotelMap(hotelId) {
  const key = String(hotelId)
  if (!devicesByHotel.has(key)) {
    devicesByHotel.set(key, new Map())
  }
  return devicesByHotel.get(key)
}

function recordDeviceHeartbeat({
  hotelId,
  deviceId,
  zone = 'FAAC_ENTRY',
  firmware = 'ESP32-StayPass-1.0',
  rssiDbm = -48,
  opticalReader = 'GM65_READY',
  safePhotocell = 'CLEAR',
  relayState = 'OPEN_NO',
  uptimeSec = 0,
  ip = null,
  emulated = false,
}) {
  const map = getHotelMap(hotelId)
  const prev = map.get(deviceId) || {}
  const nowIso = new Date().toISOString()

  const updated = {
    hotelId,
    deviceId,
    zone,
    firmware,
    rssiDbm: Number(rssiDbm ?? -50),
    opticalReader,
    safePhotocell,
    relayState,
    uptimeSec: Number(uptimeSec ?? 0),
    ip: ip || prev.ip || null,
    emulated: Boolean(emulated),
    pulseCount: Number(prev.pulseCount || 0),
    lastPulseAt: prev.lastPulseAt || null,
    lastLatencyMs: prev.lastLatencyMs ?? null,
    lastSeenAt: nowIso,
    lastSeenMs: Date.now(),
  }

  map.set(deviceId, updated)
  return formatDevice(updated)
}

function recordDevicePulse({ hotelId, deviceId, latencyMs = null }) {
  if (!hotelId || !deviceId) return
  const map = getHotelMap(hotelId)
  const prev = map.get(deviceId)
  const nowIso = new Date().toISOString()
  if (prev) {
    prev.pulseCount = Number(prev.pulseCount || 0) + 1
    prev.lastPulseAt = nowIso
    if (latencyMs !== null) prev.lastLatencyMs = latencyMs
    prev.lastSeenMs = Date.now()
    prev.lastSeenAt = nowIso
  } else {
    map.set(deviceId, {
      hotelId,
      deviceId,
      zone: deviceId.includes('salida') ? 'FAAC_EXIT' : 'FAAC_ENTRY',
      firmware: 'Webhook-IP-Relay',
      rssiDbm: -45,
      opticalReader: 'EXTERNAL_TOTEM',
      safePhotocell: 'CLEAR',
      relayState: 'OPEN_NO',
      uptimeSec: 0,
      ip: null,
      emulated: false,
      pulseCount: 1,
      lastPulseAt: nowIso,
      lastLatencyMs: latencyMs,
      lastSeenAt: nowIso,
      lastSeenMs: Date.now(),
    })
  }
}

function formatDevice(d) {
  const ageMs = Date.now() - Number(d.lastSeenMs || 0)
  const { lastSeenMs, ...rest } = d
  return {
    ...rest,
    online: ageMs <= ONLINE_TTL_MS,
    secondsSinceHeartbeat: Math.max(0, Math.round(ageMs / 1000)),
  }
}

function listHotelDevices(hotelId) {
  const map = devicesByHotel.get(String(hotelId))
  if (!map) return []
  return Array.from(map.values())
    .map(formatDevice)
    .sort((a, b) => String(a.deviceId).localeCompare(String(b.deviceId)))
}

module.exports = {
  recordDeviceHeartbeat,
  recordDevicePulse,
  listHotelDevices,
}
