package com.example.pms_owner_panel

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class BdvNotificationListenerService : NotificationListenerService() {

    companion object {
        const val PREFS_NAME = "staypass_bdv_bridge"
        private const val QUEUE_KEY = "pending_queue_json"
        private const val MAX_QUEUE_SIZE = 100
        private const val TAG = "StayPassBdvBridge"

        private val BDV_PACKAGES = setOf(
            "ve.com.bdv.bdvdigital",
            "com.banvenez.solucionesmoviles",
            "com.bdv.app"
        )

        private val recentHashes = LinkedHashSet<String>()
        private val queueLock = Any()

        fun getPendingQueueCount(context: Context): Int {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(QUEUE_KEY, "[]") ?: "[]"
            return runCatching { JSONArray(raw).length() }.getOrDefault(0)
        }

        fun flushPendingQueue(context: Context) {
            synchronized(queueLock) {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val apiBaseUrl = prefs.getString("apiBaseUrl", null)?.trim()?.trimEnd('/') ?: ""
                val hotelId = prefs.getString("hotelId", null)?.trim() ?: ""
                val bridgeToken = prefs.getString("bridgeToken", null)?.trim() ?: ""

                if (apiBaseUrl.isEmpty() || hotelId.isEmpty() || bridgeToken.isEmpty()) return

                val rawQueue = prefs.getString(QUEUE_KEY, "[]") ?: "[]"
                val currentArray = runCatching { JSONArray(rawQueue) }.getOrNull() ?: return
                if (currentArray.length() == 0) return

                val remaining = JSONArray()
                for (i in 0 until currentArray.length()) {
                    val item = currentArray.optJSONObject(i) ?: continue
                    val text = item.optString("rawText", "")
                    if (text.isEmpty()) continue

                    val delivered = sendHttpEvent(
                        context = context,
                        apiBaseUrl = apiBaseUrl,
                        hotelId = hotelId,
                        bridgeToken = bridgeToken,
                        rawText = text
                    )
                    if (!delivered) {
                        // Si la red sigue caída, conservar este y el resto en orden FIFO
                        for (j in i until currentArray.length()) {
                            currentArray.optJSONObject(j)?.let { remaining.put(it) }
                        }
                        break
                    }
                }

                prefs.edit().putString(QUEUE_KEY, remaining.toString()).apply()
            }
        }

        private fun enqueueFailedEvent(context: Context, rawText: String) {
            synchronized(queueLock) {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val rawQueue = prefs.getString(QUEUE_KEY, "[]") ?: "[]"
                val arr = runCatching { JSONArray(rawQueue) }.getOrDefault(JSONArray())

                // Evitar duplicar el mismo texto en la cola offline
                for (i in 0 until arr.length()) {
                    if (arr.optJSONObject(i)?.optString("rawText") == rawText) {
                        return
                    }
                }

                val trimmed = JSONArray()
                val startIdx = if (arr.length() >= MAX_QUEUE_SIZE) arr.length() - MAX_QUEUE_SIZE + 1 else 0
                for (i in startIdx until arr.length()) {
                    arr.optJSONObject(i)?.let { trimmed.put(it) }
                }

                trimmed.put(
                    JSONObject().apply {
                        put("rawText", rawText)
                        put("queuedAt", System.currentTimeMillis())
                    }
                )
                prefs.edit().putString(QUEUE_KEY, trimmed.toString()).apply()
            }
        }

        /**
         * Envía un heartbeat periódico al backend para notificar que el teléfono
         * del propietario sigue activo y reportando pagos.
         */
        fun sendHeartbeat(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val apiBaseUrl = prefs.getString("apiBaseUrl", null)?.trim()?.trimEnd('/') ?: ""
            val hotelId = prefs.getString("hotelId", null)?.trim() ?: ""
            val bridgeToken = prefs.getString("bridgeToken", null)?.trim() ?: ""
            val enabled = prefs.getBoolean("enabled", false)

            if (apiBaseUrl.isEmpty() || hotelId.isEmpty() || bridgeToken.isEmpty() || !enabled) return

            var conn: HttpURLConnection? = null
            try {
                val endpoint = URL("$apiBaseUrl/payments/webhook/bdv-bridge/heartbeat")
                conn = (endpoint.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 5000
                    readTimeout = 8000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    setRequestProperty("x-hotel-bridge-token", bridgeToken)
                }

                val payload = JSONObject().apply {
                    put("hotelId", hotelId)
                    put("pendingQueueCount", getPendingQueueCount(context))
                    put("forwardedCount", prefs.getInt("forwardedCount", 0))
                    put("version", "StayPass-BDV-Bridge-2.0")
                }

                OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                    writer.write(payload.toString())
                    writer.flush()
                }
                val code = conn.responseCode
                if (code in 200..299) {
                    val nowStamp = SimpleDateFormat("dd/MM HH:mm:ss", Locale.getDefault()).format(Date())
                    prefs.edit().putString("lastHeartbeatAt", nowStamp).apply()
                }
            } catch (_: Exception) {
            } finally {
                conn?.disconnect()
            }
        }

        /**
         * Envía el evento al backend. Retorna `true` si el servidor respondió definitivamente
         * (2xx o 4xx no recuperable), o `false` si hubo caída de red / timeout / HTTP 5xx
         * para que se reintente desde la cola offline.
         */
        fun sendHttpEvent(
            context: Context,
            apiBaseUrl: String,
            hotelId: String,
            bridgeToken: String,
            rawText: String
        ): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val nowStamp = SimpleDateFormat("dd/MM HH:mm:ss", Locale.getDefault()).format(Date())

            var conn: HttpURLConnection? = null
            return try {
                val endpoint = URL("$apiBaseUrl/payments/webhook/bdv-notification")
                conn = (endpoint.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 8000
                    readTimeout = 12000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    setRequestProperty("x-hotel-bridge-token", bridgeToken)
                }

                val payload = JSONObject().apply {
                    put("hotelId", hotelId)
                    put("rawText", rawText)
                    put("source", "BDV_NOTIFICATION")
                }

                OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                    writer.write(payload.toString())
                    writer.flush()
                }

                val status = conn.responseCode
                val stream = if (status in 200..299) conn.inputStream else conn.errorStream
                val responseBody = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""

                if (status in 200..299) {
                    val json = runCatching { JSONObject(responseBody) }.getOrNull()
                    val ref = json?.optString("reference", "") ?: ""
                    val amount = json?.optDouble("amountVes", 0.0) ?: 0.0
                    val matched = json?.optJSONObject("reconciliation")?.optBoolean("matched", false) ?: false
                    val zeroClick = json?.optJSONObject("reconciliation")?.optBoolean("zeroClick", false) ?: false
                    val summary = when {
                        matched && zeroClick -> "Cero-Clics Bs. $amount (Ref $ref)"
                        matched -> "Conciliado Bs. $amount (Ref $ref)"
                        else -> "Registrado Bs. $amount (Ref $ref)"
                    }

                    val newCount = prefs.getInt("forwardedCount", 0) + 1
                    prefs.edit()
                        .putInt("forwardedCount", newCount)
                        .putString("lastEventSummary", summary)
                        .putString("lastForwardedAt", nowStamp)
                        .putString("lastError", "")
                        .apply()
                    true
                } else if (status in listOf(401, 403, 404) || status >= 500 || status == 429) {
                    // Errores de credenciales, red o caída de servidor: CONSERVAR en cola para no perder pagos reales
                    Log.w(TAG, "Error recuperable HTTP $status, conservando en cola offline")
                    prefs.edit()
                        .putString("lastError", "Error HTTP $status · Conservado en cola offline para reintento ($nowStamp)")
                        .apply()
                    false
                } else if (status in listOf(400, 422)) {
                    // Payload con formato no bancario o datos descartables
                    Log.w(TAG, "Webhook devolvio HTTP $status (descartable): $responseBody")
                    prefs.edit()
                        .putString("lastError", "Descartado por formato no procesable HTTP $status ($nowStamp)")
                        .apply()
                    true
                } else {
                    Log.w(TAG, "Webhook devolvio HTTP $status: $responseBody")
                    prefs.edit()
                        .putString("lastError", "HTTP $status al enviar push BDV ($nowStamp)")
                        .apply()
                    false
                }
            } catch (e: Exception) {
                Log.e(TAG, "Sin red al enviar push BDV, encolando offline", e)
                prefs.edit()
                    .putString("lastError", "Sin conexión (${e.javaClass.simpleName}) · Guardado en cola offline ($nowStamp)")
                    .apply()
                false
            } finally {
                conn?.disconnect()
            }
        }
    }

    private val scheduler = Executors.newSingleThreadScheduledExecutor()

    override fun onCreate() {
        super.onCreate()
        showOngoingBridgeNotification()

        // Reintento automático cada 20 segundos si existen notificaciones en cola offline
        scheduler.scheduleWithFixedDelay(
            {
                runCatching {
                    if (getPendingQueueCount(applicationContext) > 0) {
                        flushPendingQueue(applicationContext)
                    }
                }
            },
            15,
            20,
            TimeUnit.SECONDS
        )

        // Heartbeat periódico cada 45 segundos para mantener canal caliente y telemetría de vida
        scheduler.scheduleWithFixedDelay(
            {
                runCatching {
                    sendHeartbeat(applicationContext)
                }
            },
            5,
            45,
            TimeUnit.SECONDS
        )
    }

    private fun showOngoingBridgeNotification() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channelId = "staypass_bdv_bridge"
            val channel = android.app.NotificationChannel(
                channelId,
                "StayPass · Puente Pago Móvil BDV",
                android.app.NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitorea pagos de Banco de Venezuela en segundo plano para auto-check-in"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        scheduler.shutdownNow()
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val notification = sbn.notification ?: return
        val flags = notification.flags
        if ((flags and Notification.FLAG_ONGOING_EVENT) != 0) return
        if ((flags and Notification.FLAG_GROUP_SUMMARY) != 0) return

        val pkg = sbn.packageName ?: ""
        if (pkg == applicationContext.packageName) return

        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("enabled", false)
        if (!enabled) return

        val hotelId = prefs.getString("hotelId", null)?.trim() ?: ""
        val bridgeToken = prefs.getString("bridgeToken", null)?.trim() ?: ""
        val apiBaseUrl = prefs.getString("apiBaseUrl", null)?.trim()?.trimEnd('/') ?: ""
        val allowTestSources = prefs.getBoolean("allowTestSources", false)

        if (hotelId.isEmpty() || bridgeToken.isEmpty() || apiBaseUrl.isEmpty()) {
            return
        }

        val extras = notification.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
        val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim() ?: ""

        val bodyText = if (bigText.length > text.length) bigText else text
        val combinedText = listOf(title, bodyText)
            .filter { it.isNotEmpty() }
            .joinToString(" - ")
            .trim()

        if (combinedText.length < 12) return

        val isOfficialBdvPackage = BDV_PACKAGES.contains(pkg)
        if (!isOfficialBdvPackage && !allowTestSources) {
            return
        }

        if (!looksLikeBdvPaymentNotification(combinedText, isOfficialBdvPackage)) {
            return
        }

        val dedupKey = sha256("$pkg|${sbn.postTime}|$combinedText")
        synchronized(recentHashes) {
            if (recentHashes.contains(dedupKey)) return
            recentHashes.add(dedupKey)
            if (recentHashes.size > 60) {
                val first = recentHashes.iterator().next()
                recentHashes.remove(first)
            }
        }

        scheduler.execute {
            flushPendingQueue(applicationContext)
            val ok = sendHttpEvent(
                context = applicationContext,
                apiBaseUrl = apiBaseUrl,
                hotelId = hotelId,
                bridgeToken = bridgeToken,
                rawText = combinedText
            )
            if (!ok) {
                enqueueFailedEvent(applicationContext, combinedText)
            }
        }
    }

    private fun looksLikeBdvPaymentNotification(text: String, isOfficialPkg: Boolean): Boolean {
        val lower = text.lowercase(Locale.ROOT)
        val hasAmountCue = lower.contains("bs") ||
            lower.contains("bolivar") ||
            lower.contains("bolívar") ||
            lower.contains("pagomovil") ||
            lower.contains("pago movil") ||
            lower.contains("pago móvil") ||
            lower.contains("abono")

        if (isOfficialPkg) {
            return hasAmountCue
        }

        val hasBdvBrand = lower.contains("pagomovilbdv") ||
            lower.contains("bdv") ||
            lower.contains("banco de venezuela")
        val hasRefCue = lower.contains("ref") ||
            lower.contains("comprobante") ||
            lower.contains("operacion") ||
            lower.contains("operación")

        return hasBdvBrand && hasAmountCue && hasRefCue
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val bytes = digest.digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
