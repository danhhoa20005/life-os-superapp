package vn.lifeos.app.life_os

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Privacy-first Android NotificationListenerService for Life OS.
 * - Disabled by default (`enabled = false`).
 * - Only inspects notifications from explicitly allowlisted Vietnamese bank packages.
 * - Drops any notification containing OTP, PIN, CVV, or verification codes on-device BEFORE emitting.
 * - When Life OS is closed (`eventSink == null`), queues redacted payloads locally in private
 *   SharedPreferences and refreshes Home Screen Widgets so zero bank movements are missed!
 */
class BankNotificationListenerService : NotificationListenerService() {

    companion object {
        const val PREFS_NAME = "lifeos_bank_listener_prefs"
        const val KEY_ENABLED = "consent_enabled"
        const val KEY_SOUNDBOX_ENABLED = "voice_soundbox_enabled"
        const val KEY_PACKAGES = "allowed_packages"
        const val KEY_QUEUED_JSON = "queued_notifications_json"

        @Volatile
        var eventSink: EventChannel.EventSink? = null

        private val OTP_REGEX = Regex(
            "\\b(otp|smart\\s*otp|m[aã]\\s*x[aá]c\\s*th[uự]c|m[aã]\\s*b[aả]o\\s*m[aậ]t|verification\\s*code|cvv|pin|m[aậ]t\\s*kh[aẩ]u)\\b",
            RegexOption.IGNORE_CASE
        )

        fun containsOtpOrSecrets(text: String): Boolean {
            return OTP_REGEX.containsMatchIn(text)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return

        val allowed = prefs.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()
        val pkg = sbn.packageName ?: return
        if (!allowed.contains(pkg)) return

        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val shortText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim().orEmpty()
        val baseBody = if (bigText.length >= shortText.length && bigText.isNotEmpty()) bigText else shortText
        val text = if (subText.isNotEmpty() && !baseBody.contains(subText)) "$baseBody $subText".trim() else baseBody
        if (title.isEmpty() && text.isEmpty()) return

        // Strict on-device OTP/secret block — never leaves the listener or enters local queue
        if (containsOtpOrSecrets("$title $text")) {
            return
        }

        // Optional Native Vietnamese "Loa Báo Tiền Về" (works even when app is closed!)
        if (prefs.getBoolean(KEY_SOUNDBOX_ENABLED, false)) {
            try {
                LifeOsSoundboxSpeaker.onBankNotificationCaptured(applicationContext, pkg, "$title $text")
            } catch (_: Exception) {
            }
        }

        val notifKey = sbn.key ?: "${pkg}_${sbn.postTime}"
        val sink = eventSink
        if (sink != null) {
            val payload = mapOf(
                "packageName" to pkg,
                "title" to title,
                "body" to text,
                "postedAtEpochMs" to sbn.postTime,
                "notificationKey" to notifKey
            )
            sink.success(payload)
        } else {
            // App is in background / killed -> persist safely in private queue for instant auto-ingest!
            try {
                val rawArr = prefs.getString(KEY_QUEUED_JSON, "[]") ?: "[]"
                val arr = JSONArray(rawArr)
                val item = JSONObject().apply {
                    put("packageName", pkg)
                    put("title", title)
                    put("body", text)
                    put("postedAtEpochMs", sbn.postTime)
                    put("notificationKey", notifKey)
                }
                val trimmed = JSONArray()
                val startIdx = (arr.length() - 59).coerceAtLeast(0)
                for (i in startIdx until arr.length()) {
                    trimmed.put(arr.get(i))
                }
                trimmed.put(item)
                prefs.edit().putString(KEY_QUEUED_JSON, trimmed.toString()).apply()
                LifeOsWidgetStore.onBackgroundBankSignalCaptured(applicationContext)
            } catch (_: Exception) {
            }
        }
    }
}
