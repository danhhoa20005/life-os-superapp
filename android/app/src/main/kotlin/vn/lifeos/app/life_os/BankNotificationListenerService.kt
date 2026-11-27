package vn.lifeos.app.life_os

import android.app.Notification
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray

/**
 * F10 / BG-01: Durable SQLite Append-Only Queue with Explicit ACK Lifecycle
 * (`received` -> `processing` -> `acknowledged`), AES-256-GCM Encrypted Payload Storage,
 * TTL Cleanup & Dead-Letter Cap (`MAX_ATTEMPTS = 5`).
 */
class LifeOsBankSignalQueueDb private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    private val appContext: Context = context.applicationContext

    companion object {
        private const val DB_NAME = "lifeos_bank_signal_queue.db"
        private const val DB_VERSION = 1
        private const val TABLE_QUEUE = "bank_signal_queue"
        private const val MAX_QUEUE_ROWS = 1000
        private const val MAX_ATTEMPTS = 5
        private const val STALE_PROCESSING_TIMEOUT_MS = 30_000L
        private const val RETENTION_TTL_MS = 7L * 24L * 3600_000L
        private const val QUEUE_AAD = "bank_queue"
        private val LOSV_MAGIC = byteArrayOf(
            'L'.code.toByte(),
            'O'.code.toByte(),
            'S'.code.toByte(),
            'V'.code.toByte()
        )

        @Volatile
        private var instance: LifeOsBankSignalQueueDb? = null

        fun getInstance(context: Context): LifeOsBankSignalQueueDb {
            return instance ?: synchronized(this) {
                instance ?: LifeOsBankSignalQueueDb(context).also { db ->
                    db.migrateLegacyPrefsIfNeeded(context.applicationContext)
                    instance = db
                }
            }
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_QUEUE (
                notification_key TEXT PRIMARY KEY,
                package_name TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                posted_at_ms INTEGER NOT NULL,
                state TEXT NOT NULL DEFAULT 'received',
                attempt_count INTEGER NOT NULL DEFAULT 0,
                last_attempt_ms INTEGER NOT NULL DEFAULT 0,
                created_at_ms INTEGER NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_bank_queue_state_time ON $TABLE_QUEUE(state, posted_at_ms ASC)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        onCreate(db)
    }

    private fun encryptField(plaintext: String): String {
        val cipherBytes = LifeOsSecureVault.encryptBytes(
            appContext,
            plaintext.toByteArray(Charsets.UTF_8),
            QUEUE_AAD
        )
        return Base64.encodeToString(cipherBytes, Base64.NO_WRAP)
    }

    private fun decryptField(stored: String): String {
        if (stored.isEmpty()) return ""
        val decoded = try {
            Base64.decode(stored, Base64.NO_WRAP)
        } catch (_: Exception) {
            // Safe fallback for legacy unencoded plaintext rows
            return stored
        }
        val hasLosvMagic = decoded.size >= LOSV_MAGIC.size &&
            decoded[0] == LOSV_MAGIC[0] &&
            decoded[1] == LOSV_MAGIC[1] &&
            decoded[2] == LOSV_MAGIC[2] &&
            decoded[3] == LOSV_MAGIC[3]
        if (!hasLosvMagic) {
            // Safe fallback for legacy plaintext rows stored prior to v3.27 encryption
            return stored
        }
        return try {
            val plainBytes = LifeOsSecureVault.decryptBytes(appContext, decoded, QUEUE_AAD)
            String(plainBytes, Charsets.UTF_8)
        } catch (_: Exception) {
            ""
        }
    }

    private fun migrateLegacyPrefsIfNeeded(context: Context) {
        try {
            val prefs = context.getSharedPreferences(
                BankNotificationListenerService.PREFS_NAME,
                Context.MODE_PRIVATE
            )
            val raw = prefs.getString(BankNotificationListenerService.KEY_QUEUED_JSON, null)
            if (raw.isNullOrBlank() || raw == "[]") return
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val title = BankNotificationListenerService.redactCardNumbers(obj.optString("title"))
                val body = BankNotificationListenerService.redactCardNumbers(obj.optString("body"))
                if (BankNotificationListenerService.containsOtpOrSecrets("$title $body")) continue
                if (BankNotificationListenerService.isMarketingPromo("$title $body")) continue
                enqueueReceived(
                    notificationKey = obj.optString("notificationKey").ifBlank { "legacy_$i" },
                    packageName = obj.optString("packageName"),
                    title = title,
                    body = body,
                    postedAtEpochMs = obj.optLong("postedAtEpochMs", System.currentTimeMillis())
                )
            }
            prefs.edit().remove(BankNotificationListenerService.KEY_QUEUED_JSON).apply()
        } catch (_: Exception) {
        }
    }

    @Synchronized
    fun enqueueReceived(
        notificationKey: String,
        packageName: String,
        title: String,
        body: String,
        postedAtEpochMs: Long
    ) {
        if (notificationKey.isBlank() || packageName.isBlank()) return
        val now = System.currentTimeMillis()
        try {
            val encryptedTitle = encryptField(title)
            val encryptedBody = encryptField(body)
            val db = writableDatabase
            val cv = ContentValues().apply {
                put("notification_key", notificationKey)
                put("package_name", packageName)
                put("title", encryptedTitle)
                put("body", encryptedBody)
                put("posted_at_ms", postedAtEpochMs)
                put("state", "received")
                put("attempt_count", 0)
                put("last_attempt_ms", 0L)
                put("created_at_ms", now)
            }
            db.insertWithOnConflict(TABLE_QUEUE, null, cv, SQLiteDatabase.CONFLICT_IGNORE)

            // Purge expired (> 7 days), dead-letter, or acknowledged rows and enforce bounded 1,000-row cap
            db.delete(
                TABLE_QUEUE,
                "state = 'acknowledged' OR created_at_ms < ? OR attempt_count >= ?",
                arrayOf((now - RETENTION_TTL_MS).toString(), MAX_ATTEMPTS.toString())
            )
            db.execSQL(
                """
                DELETE FROM $TABLE_QUEUE
                WHERE notification_key IN (
                    SELECT notification_key FROM $TABLE_QUEUE
                    ORDER BY created_at_ms DESC
                    LIMIT -1 OFFSET $MAX_QUEUE_ROWS
                )
                """.trimIndent()
            )
        } catch (_: Exception) {
        }
    }

    @Synchronized
    fun claimDrainableBatch(limit: Int = 200): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val now = System.currentTimeMillis()
        val staleCutoff = now - STALE_PROCESSING_TIMEOUT_MS
        val expiryCutoff = now - RETENTION_TTL_MS
        try {
            val db = writableDatabase
            db.beginTransaction()
            try {
                // Purge expired (> 7d) and dead-letter (>= MAX_ATTEMPTS) rows on every drain
                db.delete(
                    TABLE_QUEUE,
                    "state = 'acknowledged' OR created_at_ms < ? OR attempt_count >= ?",
                    arrayOf(expiryCutoff.toString(), MAX_ATTEMPTS.toString())
                )

                db.query(
                    TABLE_QUEUE,
                    arrayOf("notification_key", "package_name", "title", "body", "posted_at_ms", "attempt_count"),
                    "(state = 'received' OR (state = 'processing' AND last_attempt_ms < ?)) AND attempt_count < ?",
                    arrayOf(staleCutoff.toString(), MAX_ATTEMPTS.toString()),
                    null,
                    null,
                    "posted_at_ms ASC",
                    limit.toString()
                ).use { cursor ->
                    while (cursor.moveToNext()) {
                        val key = cursor.getString(0)
                        val pkg = cursor.getString(1)
                        val title = decryptField(cursor.getString(2))
                        val body = decryptField(cursor.getString(3))
                        val postedAt = cursor.getLong(4)
                        val attempts = cursor.getInt(5)

                        // Re-check OTP/secret after decryption in case rules tightened since enqueue
                        if ((title.isBlank() && body.isBlank()) ||
                            BankNotificationListenerService.containsOtpOrSecrets("$title $body")
                        ) {
                            db.delete(TABLE_QUEUE, "notification_key = ?", arrayOf(key))
                            continue
                        }

                        val upd = ContentValues().apply {
                            put("state", "processing")
                            put("attempt_count", attempts + 1)
                            put("last_attempt_ms", now)
                        }
                        db.update(TABLE_QUEUE, upd, "notification_key = ?", arrayOf(key))

                        out.add(
                            mapOf(
                                "packageName" to pkg,
                                "title" to title,
                                "body" to body,
                                "postedAtEpochMs" to postedAt,
                                "notificationKey" to key
                            )
                        )
                    }
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } catch (_: Exception) {
        }
        return out
    }

    @Synchronized
    fun acknowledgeKeys(keys: List<String>): Int {
        if (keys.isEmpty()) return 0
        var removed = 0
        try {
            val db = writableDatabase
            db.beginTransaction()
            try {
                for (key in keys) {
                    if (key.isNotBlank()) {
                        removed += db.delete(TABLE_QUEUE, "notification_key = ?", arrayOf(key))
                    }
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } catch (_: Exception) {
        }
        return removed
    }

    @Synchronized
    fun clearAll(): Int {
        return try {
            writableDatabase.delete(TABLE_QUEUE, null, null)
        } catch (_: Exception) {
            0
        }
    }
}

/**
 * Privacy-first Android NotificationListenerService for Life OS.
 * - Disabled by default (`enabled = false`).
 * - Only inspects notifications from explicitly allowlisted Vietnamese bank packages.
 * - Drops any notification containing OTP, PIN, CVV, CVC, 3DS, passcode, or verification codes
 *   and non-balance promotional spam on-device BEFORE persisting.
 * - Redacts 13–19 digit card PANs before enqueueing encrypted rows into `LifeOsBankSignalQueueDb`.
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

        private val OTP_PATTERNS = listOf(
            Regex(
                "\\b(otp|smart\\s*otp|digital\\s*otp|s-otp|m-otp|e-?otp|soft\\s*otp|3ds|cvv|cvc|passcode)\\b",
                RegexOption.IGNORE_CASE
            ),
            Regex(
                "\\bm[aã]\\s*(x[aá]c\\s*th[uự]c|x[aá]c\\s*nh[aậ]n|b[aả]o\\s*m[aậ]t|k[ií]ch\\s*ho[aạ]t|giao\\s*d[iị]ch|pin)\\b",
                RegexOption.IGNORE_CASE
            ),
            Regex(
                "\\b(verification|security|auth|authentication|activation|one[- ]?time)\\s*(code|pin|password|passcode)\\b",
                RegexOption.IGNORE_CASE
            ),
            Regex(
                "\\b(pin\\s*code|m[aậ]t\\s*kh[aẩ]u|kh[oô]ng\\s*chia\\s*s[eẻ]\\s*m[aã])\\b",
                RegexOption.IGNORE_CASE
            )
        )

        private val CARD_PAN_REGEX = Regex("\\b(?:\\d[ -]*?){12,18}\\d\\b")

        private val PROMO_MARKETING_REGEX = Regex(
            "(?<![\\p{L}\\p{N}])(khuy[eế]n\\s*m[aã]i|[uư]u\\s*[dđ][aã]i|vay\\s*nhanh|m[oở]\\s*th[eẻ]|gi[oơớờởỡợ]i\\s*thi[eệ]u\\s*b[aạ]n\\s*b[eè]|t[aặ]ng\\s+voucher|voucher|ho[aà]n\\s*ti[eề]n\\s*[dđ][eế]n|t[oố]i\\s*[dđ]a|c[oơ]\\s*h[oộ]i\\s*nh[aậ]n|tr[uú]ng\\s*th[uư][oở]ng|quay\\s*th[uư][oở]ng|gi[aả]m\\s*gi[aá]|flash\\s*sale)(?![\\p{L}\\p{N}])",
            RegexOption.IGNORE_CASE
        )

        private val BALANCE_CUE_REGEX = Regex(
            "(?:SD|S[oố]\\s*d[uư])\\s*[:=]?\\s*\\d",
            RegexOption.IGNORE_CASE
        )

        fun containsOtpOrSecrets(text: String): Boolean {
            if (text.isBlank()) return false
            return OTP_PATTERNS.any { it.containsMatchIn(text) }
        }

        fun redactCardNumbers(text: String): String {
            if (text.isEmpty()) return ""
            return CARD_PAN_REGEX.replace(text, "[REDACTED_CARD]")
        }

        fun isMarketingPromo(text: String): Boolean {
            if (text.isBlank()) return false
            return PROMO_MARKETING_REGEX.containsMatchIn(text) &&
                !BALANCE_CUE_REGEX.containsMatchIn(text)
        }

        private val BLOCKED_SMS_PACKAGES = setOf(
            "com.google.android.apps.messaging",
            "com.android.mms",
            "com.android.messaging",
            "com.samsung.android.messaging",
            "com.miui.mms",
            "com.coloros.mcs",
            "com.facebook.orca",
            "com.zing.zalo"
        )

        fun isBlockedSmsPackage(packageName: String?): Boolean {
            val clean = packageName?.trim()?.lowercase().orEmpty()
            if (clean.isEmpty()) return true
            if (BLOCKED_SMS_PACKAGES.contains(clean)) return true
            if (clean.endsWith(".mms") || clean.endsWith(".messaging")) return true
            return false
        }

        fun sanitizeAllowedPackages(packages: Iterable<String>): Set<String> {
            return packages
                .map { it.trim() }
                .filter { it.isNotEmpty() && !isBlockedSmsPackage(it) }
                .toSet()
        }

        fun clearListenerPreferences(context: Context) {
            try {
                context.applicationContext
                    .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(KEY_ENABLED, false)
                    .putBoolean(KEY_SOUNDBOX_ENABLED, false)
                    .putStringSet(KEY_PACKAGES, emptySet())
                    .remove(KEY_QUEUED_JSON)
                    .apply()
            } catch (_: Exception) {
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if ((sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return

        val pkg = sbn.packageName ?: return
        // Google Play SMS Policy compliance: strictly block SMS/Messaging apps BEFORE reading notification title or extras
        if (isBlockedSmsPackage(pkg)) return

        val allowed = prefs.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()
        if (!allowed.contains(pkg)) return

        val extras = sbn.notification?.extras ?: return
        val rawTitle = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val shortText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim().orEmpty()
        val baseBody = if (bigText.length >= shortText.length && bigText.isNotEmpty()) bigText else shortText
        val rawText = if (subText.isNotEmpty() && !baseBody.contains(subText)) "$baseBody $subText".trim() else baseBody
        if (rawTitle.isEmpty() && rawText.isEmpty()) return

        val combinedRaw = "$rawTitle $rawText"
        // Strict on-device OTP/secret block — never leaves the listener or enters local SQLite queue
        if (containsOtpOrSecrets(combinedRaw)) {
            return
        }
        // Drop obvious promotional / marketing notifications before storage
        if (isMarketingPromo(combinedRaw)) {
            return
        }

        val title = redactCardNumbers(rawTitle)
        val text = redactCardNumbers(rawText)

        // Optional Native Vietnamese "Loa Báo Tiền Về" (works even when app is closed!)
        if (prefs.getBoolean(KEY_SOUNDBOX_ENABLED, false)) {
            try {
                LifeOsSoundboxSpeaker.onBankNotificationCaptured(applicationContext, pkg, "$title $text")
            } catch (_: Exception) {
            }
        }

        val notifKey = "${sbn.key ?: pkg}_${sbn.postTime}_${(title + text).hashCode()}"

        // F10 / BG-01: Persist AES-256-GCM encrypted payload in durable SQLite queue FIRST
        LifeOsBankSignalQueueDb.getInstance(applicationContext).enqueueReceived(
            notificationKey = notifKey,
            packageName = pkg,
            title = title,
            body = text,
            postedAtEpochMs = sbn.postTime
        )

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
            LifeOsWidgetStore.onBackgroundBankSignalCaptured(applicationContext)
        }
    }
}
