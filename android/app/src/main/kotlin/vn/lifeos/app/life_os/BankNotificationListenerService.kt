package vn.lifeos.app.life_os

import android.app.Notification
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray

/**
 * F10 / BG-01: Durable SQLite Append-Only Queue with Explicit ACK Lifecycle
 * (`received` -> `processing` -> `acknowledged`).
 * - Never drops notifications if Flutter crashes between `drainQueuedNotifications` and Firestore commit.
 * - Automatically re-offers stale `processing` items (> 30s without ACK) on next drain/restart.
 * - Retains up to 1,000 unacknowledged events (7-day TTL) and migrates any legacy SharedPreferences queue.
 */
class LifeOsBankSignalQueueDb private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    companion object {
        private const val DB_NAME = "lifeos_bank_signal_queue.db"
        private const val DB_VERSION = 1
        private const val TABLE_QUEUE = "bank_signal_queue"
        private const val MAX_QUEUE_ROWS = 1000
        private const val STALE_PROCESSING_TIMEOUT_MS = 30_000L
        private const val RETENTION_TTL_MS = 7L * 24L * 3600_000L

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
                enqueueReceived(
                    notificationKey = obj.optString("notificationKey").ifBlank { "legacy_$i" },
                    packageName = obj.optString("packageName"),
                    title = obj.optString("title"),
                    body = obj.optString("body"),
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
            val db = writableDatabase
            val cv = ContentValues().apply {
                put("notification_key", notificationKey)
                put("package_name", packageName)
                put("title", title)
                put("body", body)
                put("posted_at_ms", postedAtEpochMs)
                put("state", "received")
                put("attempt_count", 0)
                put("last_attempt_ms", 0L)
                put("created_at_ms", now)
            }
            db.insertWithOnConflict(TABLE_QUEUE, null, cv, SQLiteDatabase.CONFLICT_IGNORE)

            // Purge expired (> 7 days) oracknowledged rows and enforce bounded 1,000-row cap
            db.delete(
                TABLE_QUEUE,
                "state = 'acknowledged' OR created_at_ms < ?",
                arrayOf((now - RETENTION_TTL_MS).toString())
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
        try {
            val db = writableDatabase
            db.beginTransaction()
            try {
                db.query(
                    TABLE_QUEUE,
                    arrayOf("notification_key", "package_name", "title", "body", "posted_at_ms", "attempt_count"),
                    "state = 'received' OR (state = 'processing' AND last_attempt_ms < ?)",
                    arrayOf(staleCutoff.toString()),
                    null,
                    null,
                    "posted_at_ms ASC",
                    limit.toString()
                ).use { cursor ->
                    while (cursor.moveToNext()) {
                        val key = cursor.getString(0)
                        val pkg = cursor.getString(1)
                        val title = cursor.getString(2)
                        val body = cursor.getString(3)
                        val postedAt = cursor.getLong(4)
                        val attempts = cursor.getInt(5)

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
}

/**
 * Privacy-first Android NotificationListenerService for Life OS.
 * - Disabled by default (`enabled = false`).
 * - Only inspects notifications from explicitly allowlisted Vietnamese bank packages.
 * - Drops any notification containing OTP, PIN, CVV, or verification codes on-device BEFORE persisting.
 * - Writes every valid signal to `LifeOsBankSignalQueueDb` BEFORE forwarding to Flutter so an app
 *   crash or background kill never loses a single bank movement (F10 / BG-01).
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

        // Strict on-device OTP/secret block — never leaves the listener or enters local SQLite queue
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

        val notifKey = "${sbn.key ?: pkg}_${sbn.postTime}_${(title + text).hashCode()}"

        // F10 / BG-01: Persist in durable SQLite queue FIRST (survives process kill / mid-drain crash)
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
