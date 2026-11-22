package vn.lifeos.app.life_os

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel

/**
 * Privacy-first Android NotificationListenerService for Life OS.
 * - Disabled by default (`enabled = false`).
 * - Only inspects notifications from explicitly allowlisted Vietnamese bank packages.
 * - Drops any notification containing OTP, PIN, CVV, or verification codes on-device BEFORE emitting.
 * - Never logs raw notification text.
 */
class BankNotificationListenerService : NotificationListenerService() {

    companion object {
        const val PREFS_NAME = "lifeos_bank_listener_prefs"
        const val KEY_ENABLED = "consent_enabled"
        const val KEY_PACKAGES = "allowed_packages"

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
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return

        // Strict on-device OTP/secret block — never leaves the listener
        if (containsOtpOrSecrets("$title $text")) {
            return
        }

        val sink = eventSink ?: return
        val payload = mapOf(
            "packageName" to pkg,
            "title" to title,
            "body" to text,
            "postedAtEpochMs" to sbn.postTime,
            "notificationKey" to (sbn.key ?: "${pkg}_${sbn.postTime}")
        )
        sink.success(payload)
    }
}
