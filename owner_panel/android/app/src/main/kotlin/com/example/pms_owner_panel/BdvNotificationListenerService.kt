package com.example.pms_owner_panel

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class BdvNotificationListenerService : NotificationListenerService() {

    companion object {
        const val PREFS_NAME = "staypass_bdv_bridge"
        private const val TAG = "StayPassBdvBridge"

        private val BDV_PACKAGES = setOf(
            "ve.com.bdv.bdvdigital",
            "com.banvenez.solucionesmoviles",
            "com.bdv.app"
        )

        private val recentHashes = LinkedHashSet<String>()
    }

    private val executor = Executors.newSingleThreadExecutor()

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
        val allowTestSources = prefs.getBoolean("allowTestSources", true)

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

        executor.execute {
            forwardToBackend(
                apiBaseUrl = apiBaseUrl,
                hotelId = hotelId,
                bridgeToken = bridgeToken,
                rawText = combinedText
            )
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

    private fun forwardToBackend(
        apiBaseUrl: String,
        hotelId: String,
        bridgeToken: String,
        rawText: String
    ) {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val nowStamp = SimpleDateFormat("dd/MM HH:mm:ss", Locale.getDefault()).format(Date())

        var conn: HttpURLConnection? = null
        try {
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
                val summary = if (matched) {
                    "Conciliado Bs. $amount (Ref $ref)"
                } else {
                    "Registrado Bs. $amount (Ref $ref)"
                }

                val newCount = prefs.getInt("forwardedCount", 0) + 1
                prefs.edit()
                    .putInt("forwardedCount", newCount)
                    .putString("lastEventSummary", summary)
                    .putString("lastForwardedAt", nowStamp)
                    .putString("lastError", "")
                    .apply()
            } else {
                Log.w(TAG, "Webhook devolvio HTTP $status: $responseBody")
                prefs.edit()
                    .putString("lastError", "HTTP $status al enviar push BDV ($nowStamp)")
                    .apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reenviando notificacion BDV", e)
            prefs.edit()
                .putString("lastError", "${e.javaClass.simpleName}: ${e.message} ($nowStamp)")
                .apply()
        } finally {
            conn?.disconnect()
        }
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val bytes = digest.digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
