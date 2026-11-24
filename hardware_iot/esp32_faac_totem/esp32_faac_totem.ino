/**
 * ============================================================================
 * StayPass QR · Firmware Oficial ESP32 para Tótem Barrera Vehicular FAAC y Puertas
 * ============================================================================
 * Hardware objetivo:
 *  - MCU: ESP32-WROOM-32 / ESP32-S3 (Alimentación 5V desde fuente DIN MeanWell)
 *  - Lector Óptico QR: Grow GM65 / GM67 / Waveshare 2D UART (3.3V TTL, 9600 bps)
 *      * GM65 TX -> ESP32 GPIO 16 (RX2)
 *      * GM65 RX -> ESP32 GPIO 17 (TX2)
 *      * GM65 VCC -> 5V | GND -> GND
 *  - Salida Relé Contacto Seco Optoacoplado (NO = Normalmente Abierto):
 *      * ESP32 GPIO 26 -> IN Relé Optoacoplado
 *      * Bornera Relé COM -> GND (J5 Central FAAC E615 / E024S / E680)
 *      * Bornera Relé NO  -> OPEN-A (J5 Central FAAC)
 *  - Entrada Fotocélula de Seguridad FAAC (Opcional / Diagnóstico):
 *      * ESP32 GPIO 33 (INPUT_PULLUP) <- Contacto auxiliar fotocélula SAFE
 *  - Semáforo LED / Buzzer Tótem:
 *      * GPIO 25 -> LED Verde (Pase)
 *      * GPIO 27 -> LED Rojo (Alto / Denegado)
 *      * GPIO 14 -> Buzzer Piezo activo 3.3V
 *
 * Librerías requeridas en Arduino IDE / PlatformIO:
 *  - ArduinoJson (v7+) por Benoit Blanchon
 *  - WiFi, HTTPClient, WebServer (incluidas en el core oficial ESP32 de Espressif)
 * ============================================================================
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <ArduinoJson.h>

// ── 1. CREDENCIALES GENERADAS DESDE EL PANEL DEL PROPIETARIO ────────────────
const char* WIFI_SSID       = "RED_MOTEL_IOT";
const char* WIFI_PASSWORD   = "CLAVE_WIFI_SEGURA";

// URL del backend StayPass (IP local del servidor o dominio HTTPS en la nube)
const char* API_BASE_URL    = "https://by-pass-hotelero.vercel.app/api/v1";

// Identificadores exclusivos del Hotel y de este Tótem (copiar desde Panel -> FAAC)
const char* HOTEL_ID        = "PEGAR_HOTEL_UUID_AQUI";
const char* IOT_TOKEN       = "PEGAR_IOT_HARDWARE_TOKEN_AQUI";
const char* DEVICE_ID       = "faac-entrada-1";   // "faac-entrada-1", "faac-salida-1" o "lock-101"
const char* DEVICE_ZONE     = "FAAC_ENTRY";       // "FAAC_ENTRY", "FAAC_EXIT" o "ROOM_DOOR"
const char* FIRMWARE_VER    = "ESP32-StayPass-FAAC-1.2.0";

// ── 2. MAPA DE PINES Y LÍMITES DE SEGURIDAD FÍSICA ──────────────────────────
constexpr int PIN_GM65_RX        = 16;
constexpr int PIN_GM65_TX        = 17;
constexpr int PIN_RELAY_OPEN_A   = 26; // Activo en HIGH (usar módulo relé High-Level Trigger)
constexpr int PIN_SAFE_PHOTOCELL = 33; // LOW = despejado, HIGH = obstáculo en fotocélula
constexpr int PIN_LED_GREEN      = 25;
constexpr int PIN_LED_RED        = 27;
constexpr int PIN_BUZZER         = 14;

constexpr unsigned long DEFAULT_PULSE_MS     = 1000;
constexpr unsigned long MAX_SAFETY_PULSE_MS  = 3000;  // Corte duro anti-enclavamiento
constexpr unsigned long RELAY_COOLDOWN_MS    = 2000;  // Período de enfriamiento mínimo entre pulsos
constexpr unsigned long SCAN_DEBOUNCE_MS     = 2800;  // Evita lecturas duplicadas del mismo QR
constexpr unsigned long HEARTBEAT_INTERVAL   = 15000; // Telemetría cada 15s

HardwareSerial ScannerSerial(2);
WebServer localServer(80);

// Estado no bloqueante del relé OPEN-A
bool relayClosed = false;
unsigned long relayOpenedAtMs = 0;
unsigned long relayTargetDurationMs = DEFAULT_PULSE_MS;
unsigned long lastPulseFinishedMs = 0;
unsigned long totalPulsesExecuted = 0;

// Antirrebote de lectura óptica UART
String uartBuffer = "";
String lastScannedToken = "";
unsigned long lastScanMs = 0;
unsigned long lastHeartbeatMs = 0;

// ── UTILIDADES DE SEÑALIZACIÓN ACÚSTICA Y LUMINOSA ──────────────────────────
void beepTone(int count, int durationMs) {
  for (int i = 0; i < count; i++) {
    digitalWrite(PIN_BUZZER, HIGH);
    delay(durationMs);
    digitalWrite(PIN_BUZZER, LOW);
    if (i + 1 < count) delay(70);
  }
}

void triggerDryContactPulse(unsigned long requestedMs) {
  // Evitar re-enclavamiento continuo o manipulación si el relé ya está activo o en cooldown
  if (relayClosed) return;
  if (millis() - lastPulseFinishedMs < RELAY_COOLDOWN_MS) return;

  unsigned long safeMs = requestedMs;
  if (safeMs < 200) safeMs = 200;
  if (safeMs > MAX_SAFETY_PULSE_MS) safeMs = MAX_SAFETY_PULSE_MS;

  digitalWrite(PIN_RELAY_OPEN_A, HIGH);
  digitalWrite(PIN_LED_GREEN, HIGH);
  digitalWrite(PIN_LED_RED, LOW);

  relayClosed = true;
  relayOpenedAtMs = millis();
  relayTargetDurationMs = safeMs;
  totalPulsesExecuted++;

  beepTone(2, 85);
}

void signalDenied() {
  digitalWrite(PIN_LED_GREEN, LOW);
  digitalWrite(PIN_LED_RED, HIGH);
  beepTone(1, 360);
}

// Comparación en tiempo constante para evitar ataques de timing en LAN
bool constantTimeEquals(const String& a, const char* b) {
  size_t lenB = strlen(b);
  if (a.length() != lenB) return false;
  uint8_t diff = 0;
  for (size_t i = 0; i < lenB; i++) {
    diff |= (uint8_t(a[i]) ^ uint8_t(b[i]));
  }
  return diff == 0;
}

// ── SERVIDOR HTTP LOCAL (/rpc/pulse) PARA APERTURA REMOTA DESDE AUTO/PANEL ──
void setupLocalWebhookServer() {
  localServer.on("/status", HTTP_GET, []() {
    JsonDocument doc;
    doc["ok"] = true;
    doc["deviceId"] = DEVICE_ID;
    doc["firmware"] = FIRMWARE_VER;
    doc["rssiDbm"] = WiFi.RSSI();
    doc["opticalReader"] = "GM65_UART_READY";
    doc["safePhotocell"] = digitalRead(PIN_SAFE_PHOTOCELL) == LOW ? "CLEAR" : "OBSTRUCTED";
    doc["relayState"] = relayClosed ? "CLOSED_PULSING" : "OPEN_NO";
    doc["pulseCount"] = totalPulsesExecuted;
    doc["uptimeSec"] = millis() / 1000;
    String out;
    serializeJson(doc, out);
    localServer.send(200, "application/json", out);
  });

  localServer.on("/rpc/pulse", HTTP_POST, []() {
    String rxToken = localServer.header("x-hotel-iot-token");
    if (!constantTimeEquals(rxToken, IOT_TOKEN)) {
      localServer.send(401, "application/json", "{\"ok\":false,\"message\":\"Unauthorized IoT token\"}");
      return;
    }

    JsonDocument body;
    deserializeJson(body, localServer.arg("plain"));
    bool dryRun = body["dryRun"] | false;
    unsigned long pulseMs = body["pulseDurationMs"] | DEFAULT_PULSE_MS;

    if (!dryRun) {
      triggerDryContactPulse(pulseMs);
    }

    JsonDocument res;
    res["ok"] = true;
    res["dryRun"] = dryRun;
    res["deviceId"] = DEVICE_ID;
    res["terminal"] = "J5:OPEN-A+GND";
    res["relayState"] = dryRun ? "DIAGNOSTIC_OK_NO_PULSE" : "PULSED_NO";
    res["pulseDurationMs"] = pulseMs;
    res["safePhotocell"] = digitalRead(PIN_SAFE_PHOTOCELL) == LOW ? "CLEAR" : "OBSTRUCTED";
    res["opticalReader"] = "GM65_UART_READY";
    res["rssiDbm"] = WiFi.RSSI();
    String out;
    serializeJson(res, out);
    localServer.send(200, "application/json", out);
  });

  const char* headerKeys[] = {"x-hotel-iot-token", "x-hotel-id"};
  localServer.collectHeaders(headerKeys, 2);
  localServer.begin();
}

// Estructura de cola offline para resiliencia ante caídas de internet
struct OfflineAccessEvent {
  char token[160];
  unsigned long timestampMs;
  bool granted;
};
constexpr int MAX_OFFLINE_EVENTS = 20;
OfflineAccessEvent offlineQueue[MAX_OFFLINE_EVENTS];
int offlineQueueCount = 0;

void enqueueOfflineAccess(const String& token, bool granted) {
  if (offlineQueueCount < MAX_OFFLINE_EVENTS) {
    strncpy(offlineQueue[offlineQueueCount].token, token.c_str(), sizeof(offlineQueue[offlineQueueCount].token) - 1);
    offlineQueue[offlineQueueCount].timestampMs = millis();
    offlineQueue[offlineQueueCount].granted = granted;
    offlineQueueCount++;
  }
}

void flushOfflineSync() {
  if (WiFi.status() != WL_CONNECTED || offlineQueueCount == 0) return;

  HTTPClient http;
  String url = String(API_BASE_URL) + "/access/iot/offline-sync";
  http.begin(url);
  http.setTimeout(3000);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("x-hotel-iot-token", IOT_TOKEN);

  JsonDocument doc;
  doc["hotelId"] = HOTEL_ID;
  doc["deviceId"] = DEVICE_ID;
  JsonArray arr = doc["events"].to<JsonArray>();

  for (int i = 0; i < offlineQueueCount; i++) {
    JsonObject ev = arr.add<JsonObject>();
    ev["token"] = offlineQueue[i].token;
    ev["timestamp"] = offlineQueue[i].timestampMs;
    ev["granted"] = offlineQueue[i].granted;
    ev["reason"] = "offline_local_validation";
  }

  String payload;
  serializeJson(doc, payload);
  int status = http.POST(payload);
  if (status >= 200 && status < 300) {
    offlineQueueCount = 0;
  }
  http.end();
}

// ── VALIDACIÓN OFFLINE SEGURA (FAIL-CLOSED) ──────────────────────────────────
// POR SEGURIDAD FÍSICA: Nunca abrir la barrera vehicular sin verificación criptográfica
// de firma HMAC, vigencia temporal y estado de reserva efectuada por el backend.
// Si no hay conectividad con el servidor, se deniega el acceso y se encola el intento
// para auditoría forense posterior.
bool validateOfflineFallback(const String& rawToken) {
  enqueueOfflineAccess(rawToken, false);
  return false;
}

// ── VALIDACIÓN DE QR ÓPTICO CONTRA POST /api/v1/access/validate ─────────────
void validateScannedQr(const String& rawToken) {
  if (WiFi.status() != WL_CONNECTED) {
    // Red caída: recurrir a validación criptográfica offline local
    if (!validateOfflineFallback(rawToken)) {
      signalDenied();
    }
    return;
  }

  HTTPClient http;
  String url = String(API_BASE_URL) + "/access/validate";
  http.begin(url);
  http.setTimeout(3500);
  http.addHeader("Content-Type", "application/json");

  JsonDocument reqDoc;
  reqDoc["token"] = rawToken;
  reqDoc["deviceId"] = DEVICE_ID;
  String payload;
  serializeJson(reqDoc, payload);

  int status = http.POST(payload);
  if (status == 200) {
    JsonDocument resDoc;
    if (!deserializeJson(resDoc, http.getString()) && (resDoc["allowed"] | false)) {
      unsigned long pulseMs = resDoc["faacPulse"]["pulseDurationMs"] | DEFAULT_PULSE_MS;
      triggerDryContactPulse(pulseMs);
    } else {
      signalDenied();
    }
  } else if (status <= 0 || status >= 500) {
    // Timeout o error de servidor: fallback local de contingencia
    if (!validateOfflineFallback(rawToken)) {
      signalDenied();
    }
  } else {
    signalDenied();
  }
  http.end();
}

// ── HEARTBEAT PERIÓDICO HACIA POST /api/v1/access/iot/heartbeat ─────────────
void sendHeartbeat() {
  if (WiFi.status() != WL_CONNECTED) return;

  // Sincronizar accesos almacenados en búfer offline
  if (offlineQueueCount > 0) {
    flushOfflineSync();
  }

  HTTPClient http;
  String url = String(API_BASE_URL) + "/access/iot/heartbeat";
  http.begin(url);
  http.setTimeout(2500);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("x-hotel-iot-token", IOT_TOKEN);

  JsonDocument doc;
  doc["hotelId"] = HOTEL_ID;
  doc["deviceId"] = DEVICE_ID;
  doc["zone"] = DEVICE_ZONE;
  doc["firmware"] = FIRMWARE_VER;
  doc["rssiDbm"] = WiFi.RSSI();
  doc["opticalReader"] = "GM65_UART_READY";
  doc["safePhotocell"] = digitalRead(PIN_SAFE_PHOTOCELL) == LOW ? "CLEAR" : "OBSTRUCTED";
  doc["relayState"] = relayClosed ? "CLOSED_PULSING" : "OPEN_NO";
  doc["uptimeSec"] = millis() / 1000;

  String body;
  serializeJson(doc, body);
  http.POST(body);
  http.end();
}

void connectWifiIfNeeded() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 8000) {
    delay(250);
  }
}

void setup() {
  // CRÍTICO: Fijar nivel LOW ANTES de configurar OUTPUT para evitar glitch al energizar
  digitalWrite(PIN_RELAY_OPEN_A, LOW);
  pinMode(PIN_RELAY_OPEN_A, OUTPUT);
  digitalWrite(PIN_RELAY_OPEN_A, LOW);

  pinMode(PIN_SAFE_PHOTOCELL, INPUT_PULLUP);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_RED, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  digitalWrite(PIN_LED_GREEN, LOW);
  digitalWrite(PIN_LED_RED, HIGH);
  digitalWrite(PIN_BUZZER, LOW);

  Serial.begin(115200);
  ScannerSerial.begin(9600, SERIAL_8N1, PIN_GM65_RX, PIN_GM65_TX);

  connectWifiIfNeeded();
  setupLocalWebhookServer();
  sendHeartbeat();
}

void loop() {
  // 1. Corte de seguridad no bloqueante del relé OPEN-A
  if (relayClosed && (millis() - relayOpenedAtMs >= relayTargetDurationMs)) {
    digitalWrite(PIN_RELAY_OPEN_A, LOW);
    digitalWrite(PIN_LED_GREEN, LOW);
    digitalWrite(PIN_LED_RED, HIGH);
    relayClosed = false;
    lastPulseFinishedMs = millis();
  }

  // 2. Atender pulsos remotos desde App del Huésped / Panel Propietario
  localServer.handleClient();

  // 3. Leer trama QR entrante desde el lector óptico GM65 (terminada en \r o \n)
  while (ScannerSerial.available()) {
    char c = (char)ScannerSerial.read();
    if (c == '\r' || c == '\n') {
      uartBuffer.trim();
      if (uartBuffer.length() >= 16) {
        unsigned long now = millis();
        if (uartBuffer != lastScannedToken || (now - lastScanMs) > SCAN_DEBOUNCE_MS) {
          lastScannedToken = uartBuffer;
          lastScanMs = now;
          validateScannedQr(uartBuffer);
        }
      }
      uartBuffer = "";
    } else if (uartBuffer.length() < 260) {
      uartBuffer += c;
    }
  }

  // 4. Reconexión WiFi y Heartbeat periódico
  if (millis() - lastHeartbeatMs >= HEARTBEAT_INTERVAL) {
    lastHeartbeatMs = millis();
    connectWifiIfNeeded();
    sendHeartbeat();
  }
}
