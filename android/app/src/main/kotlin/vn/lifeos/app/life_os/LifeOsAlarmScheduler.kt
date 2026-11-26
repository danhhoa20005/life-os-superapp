package vn.lifeos.app.life_os

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Continuous Alarm Audio & Vibration controller using `AudioAttributes.USAGE_ALARM`
 * (plays on the dedicated OS Alarm stream even if phone ringer is silent, with a 45s safety auto-stop).
 */
object LifeOsAlarmRinger {
    private var mediaPlayer: MediaPlayer? = null
    private var activeVibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var autoStopRunnable: Runnable? = null

    @Synchronized
    fun startRinging(context: Context) {
        stopRinging(context)
        val appCtx = context.applicationContext

        // 1. Acquire temporary CPU WakeLock (max 50s) so alarm rings reliably from deep sleep
        try {
            val pm = appCtx.getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = pm?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "LifeOS:AlarmRingerWakeLock"
            )?.apply {
                setReferenceCounted(false)
                acquire(50_000L)
            }
        } catch (_: Exception) {
        }

        // 2. Start looping system Alarm Ringtone on USAGE_ALARM stream
        try {
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            if (alarmUri != null) {
                val mp = MediaPlayer()
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                mp.setDataSource(appCtx, alarmUri)
                mp.isLooping = true
                mp.prepare()
                mp.start()
                mediaPlayer = mp
            }
        } catch (_: Exception) {
        }

        // 3. Start rhythmic alarm vibration waveform
        try {
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = appCtx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                appCtx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            if (vib != null && vib.hasVibrator()) {
                val pattern = longArrayOf(0L, 500L, 400L, 500L, 700L)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val attrs = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .build()
                    @Suppress("DEPRECATION")
                    vib.vibrate(VibrationEffect.createWaveform(pattern, 0), attrs)
                } else {
                    @Suppress("DEPRECATION")
                    vib.vibrate(pattern, 0)
                }
                activeVibrator = vib
            }
        } catch (_: Exception) {
        }

        // 4. Safety 45-second auto-cutoff so an unattended alarm never drains battery indefinitely
        val cutoff = Runnable { stopRinging(appCtx) }
        autoStopRunnable = cutoff
        mainHandler.postDelayed(cutoff, 45_000L)
    }

    @Synchronized
    fun stopRinging(context: Context? = null, notificationEventId: String? = null) {
        autoStopRunnable?.let { mainHandler.removeCallbacks(it) }
        autoStopRunnable = null

        try {
            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Exception) {
        } finally {
            mediaPlayer = null
        }

        try {
            activeVibrator?.cancel()
        } catch (_: Exception) {
        } finally {
            activeVibrator = null
        }

        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }

        if (context != null && !notificationEventId.isNullOrBlank()) {
            try {
                val nm = context.applicationContext
                    .getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                nm?.cancel(LifeOsAlarmScheduler.notificationIdFor(notificationEventId))
                nm?.cancel(notificationEventId.hashCode())
            } catch (_: Exception) {
            }
        }
    }
}

/**
 * Real Android OS Alarm & Background Notification Engine:
 * - Full-Screen Alarms (`AlarmManager.setAlarmClock` + `CHANNEL_ID`)
 * - Outside-the-Screen Heads-Up & Lock-Screen Reminders (`setExactAndAllowWhileIdle` + `HEALTH_CHANNEL_ID`)
 * - Autonomous Multi-Day Hydration Daemon (works even when app is swiped away or phone reboots)
 * - Direct Lock-Screen Action Buttons (`+Uống nước`, `Hoãn 15 phút`) queued safely offline
 */
object LifeOsAlarmScheduler {
    const val PREFS_NAME = "lifeos_scheduled_alarms_v1"
    const val PREFS_HYDRATION_DAEMON = "lifeos_hydration_daemon_v1"
    const val PREFS_BG_ACTIONS = "lifeos_bg_health_actions_v1"
    private const val KEY_BG_QUEUE = "queued_actions_json"

    const val CHANNEL_ID = "lifeos_calendar_alarms_v2"
    const val HEALTH_CHANNEL_ID = "lifeos_daily_reminders_v2"
    const val WATER_NOTIFICATION_ID = 770101
    private const val DAEMON_WATER_NEXT_ID = "water_daemon_next"

    const val ACTION_ALARM_FIRED = "vn.lifeos.app.ACTION_CALENDAR_ALARM_FIRED"
    const val ACTION_ALARM_DISMISS = "vn.lifeos.app.ACTION_CALENDAR_ALARM_DISMISS"
    const val ACTION_ALARM_SNOOZE = "vn.lifeos.app.ACTION_CALENDAR_ALARM_SNOOZE"
    const val ACTION_REMINDER_SNOOZE_15M = "vn.lifeos.app.ACTION_REMINDER_SNOOZE_15M"
    const val ACTION_WATER_QUICK_LOG = "vn.lifeos.app.ACTION_WATER_QUICK_LOG"
    const val ACTION_OPEN_RINGING_UI = "vn.lifeos.app.ALARM_RINGING"

    @Volatile
    var onBackgroundHealthActionPing: (() -> Unit)? = null

    fun notificationIdFor(eventId: String): Int {
        return if (eventId.startsWith("water_")) WATER_NOTIFICATION_ID else eventId.hashCode()
    }

    fun todayDayKey(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    }

    fun acquireBriefWakeLock(context: Context, timeoutMs: Long = 4_000L) {
        try {
            val pm = context.applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
            pm?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "LifeOS:BackgroundReminderWakeLock"
            )?.apply {
                setReferenceCounted(false)
                acquire(timeoutMs)
            }
        } catch (_: Exception) {
        }
    }

    fun isPostNotificationsGranted(context: Context): Boolean {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        val systemEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            nm?.areNotificationsEnabled() != false
        } else {
            true
        }
        if (!systemEnabled) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun isBatteryOptimizationIgnored(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && pm != null) {
            pm.isIgnoringBatteryOptimizations(context.packageName)
        } else {
            true
        }
    }

    fun requestIgnoreBatteryOptimizations(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            } catch (_: Exception) {
                try {
                    val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(fallback)
                } catch (_: Exception) {
                }
            }
        }
    }

    fun openAppNotificationSettings(context: Context) {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            }
            context.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    fun canScheduleExact(context: Context): Boolean {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.canScheduleExactAlarms()
        } else {
            true
        }
    }

    fun openExactAlarmSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }

    fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val alarmChannel = NotificationChannel(
                    CHANNEL_ID,
                    "Báo thức & Chuông hẹn LifeOS",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Đổ chuông báo thức và nhắc lịch hẹn đúng giờ trên thiết bị"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 300, 500)
                    setSound(alarmSound, attrs)
                    setBypassDnd(true)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                }
                nm.createNotificationChannel(alarmChannel)
            }

            if (nm.getNotificationChannel(HEALTH_CHANNEL_ID) == null) {
                val notifSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val notifAttrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val healthChannel = NotificationChannel(
                    HEALTH_CHANNEL_ID,
                    "Nhắc Sinh hoạt & Lịch trình",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Thông báo nổi ngoài màn hình nhắc uống nước và sinh hoạt định kỳ"
                    enableLights(true)
                    lightColor = Color.parseColor("#0284C7")
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 260, 150, 260)
                    if (notifSound != null) {
                        setSound(notifSound, notifAttrs)
                    }
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                nm.createNotificationChannel(healthChannel)
            }
        }
    }

    /**
     * Persists hydration schedule & current intake natively so Android can keep firing & rolling over
     * across multiple days even when the Flutter app is never opened!
     */
    fun syncHydrationDaemonConfig(
        context: Context,
        enabled: Boolean,
        intervalMinutes: Int,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        targetWaterMl: Int,
        waterMl: Int,
        preferredCupMl: Int,
        dayKey: String
    ) {
        val appCtx = context.applicationContext
        appCtx.getSharedPreferences(PREFS_HYDRATION_DAEMON, Context.MODE_PRIVATE)
            .edit()
            .putBoolean("enabled", enabled)
            .putInt("intervalMinutes", intervalMinutes.coerceIn(30, 360))
            .putInt("startHour", startHour.coerceIn(4, 14))
            .putInt("startMinute", startMinute.coerceIn(0, 59))
            .putInt("endHour", endHour.coerceIn(6, 23))
            .putInt("endMinute", endMinute.coerceIn(0, 59))
            .putInt("targetWaterMl", targetWaterMl.coerceIn(500, 10000))
            .putInt("waterMl", waterMl.coerceIn(0, 10000))
            .putInt("preferredCupMl", preferredCupMl.coerceIn(100, 600))
            .putString("dayKey", dayKey.ifBlank { todayDayKey() })
            .apply()

        if (!enabled) {
            cancelAlarm(appCtx, DAEMON_WATER_NEXT_ID)
            val nm = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancel(WATER_NOTIFICATION_ID)
        } else {
            ensureNextDaemonWaterAlarmScheduled(appCtx)
        }
    }

    /**
     * Ensures at least one future waking-hour water alarm is scheduled natively (crucial after midnight
     * rollover or reboot when the Flutter engine hasn't run).
     */
    fun ensureNextDaemonWaterAlarmScheduled(context: Context) {
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_HYDRATION_DAEMON, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", false)) return

        // If any explicit water_rem_* slot is already scheduled in the future, no duplicate daemon slot needed yet
        val now = System.currentTimeMillis()
        val alarmPrefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        for ((key, rawVal) in alarmPrefs.all) {
            if (key.startsWith("water_rem_")) {
                val str = rawVal as? String ?: continue
                val triggerMs = try {
                    JSONObject(str).optLong("triggerAtEpochMs", 0L)
                } catch (_: Exception) {
                    0L
                }
                if (triggerMs > now + 5_000L) {
                    return
                }
            }
        }

        val today = todayDayKey()
        var waterMl = prefs.getInt("waterMl", 0)
        val savedDay = prefs.getString("dayKey", today) ?: today
        if (savedDay != today) {
            waterMl = 0
            prefs.edit().putString("dayKey", today).putInt("waterMl", 0).apply()
        }

        val targetMl = prefs.getInt("targetWaterMl", 2000)
        val cupMl = prefs.getInt("preferredCupMl", 250)
        val intervalMins = prefs.getInt("intervalMinutes", 90).coerceIn(30, 360)
        val startH = prefs.getInt("startHour", 7).coerceIn(4, 14)
        val startM = prefs.getInt("startMinute", 0).coerceIn(0, 59)
        val endH = prefs.getInt("endHour", 21).coerceIn((startH + 2).coerceAtMost(23), 23)
        val endM = prefs.getInt("endMinute", 0).coerceIn(0, 59)

        val nextTriggerMs = computeNextHydrationSlotEpochMs(
            nowMs = now,
            isGoalReached = waterMl >= targetMl,
            intervalMins = intervalMins,
            startH = startH,
            startM = startM,
            endH = endH,
            endM = endM
        )
        val remaining = (targetMl - waterMl).coerceAtLeast(0)
        val sub = if (waterMl >= targetMl) {
            "Khởi đầu ngày mới khỏe khoắn với 1 cốc nước ấm ~${cupMl} ml nhé!"
        } else {
            "Uống thêm ~${cupMl} ml · Còn thiếu ${remaining} ml để đạt chuẩn ${targetMl} ml."
        }
        scheduleAlarm(
            context = appCtx,
            eventId = DAEMON_WATER_NEXT_ID,
            title = "Đến giờ uống nước (${if (waterMl >= targetMl) 0 else waterMl}/${targetMl} ml)",
            subtitle = sub,
            triggerAtEpochMs = nextTriggerMs,
            minutesBefore = 0,
            fullScreen = false,
            cupMl = cupMl
        )
    }

    private fun computeNextHydrationSlotEpochMs(
        nowMs: Long,
        isGoalReached: Boolean,
        intervalMins: Int,
        startH: Int,
        startM: Int,
        endH: Int,
        endM: Int
    ): Long {
        val tomorrowStart = Calendar.getInstance().apply {
            timeInMillis = nowMs
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, startH)
            set(Calendar.MINUTE, startM)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        if (isGoalReached) return tomorrowStart

        val cursor = Calendar.getInstance().apply {
            timeInMillis = nowMs
            set(Calendar.HOUR_OF_DAY, startH)
            set(Calendar.MINUTE, startM)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val endToday = Calendar.getInstance().apply {
            timeInMillis = nowMs
            set(Calendar.HOUR_OF_DAY, endH)
            set(Calendar.MINUTE, if (endM > 0) endM else 30)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        while (cursor.timeInMillis <= endToday) {
            if (cursor.timeInMillis > nowMs + 15_000L) {
                return cursor.timeInMillis
            }
            cursor.add(Calendar.MINUTE, intervalMins)
        }
        return tomorrowStart
    }

    fun enqueueBackgroundHealthAction(context: Context, item: JSONObject) {
        val appCtx = context.applicationContext
        try {
            val prefs = appCtx.getSharedPreferences(PREFS_BG_ACTIONS, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_BG_QUEUE, "[]") ?: "[]"
            val arr = JSONArray(raw)
            val trimmed = JSONArray()
            val startIdx = (arr.length() - 49).coerceAtLeast(0)
            for (i in startIdx until arr.length()) {
                trimmed.put(arr.get(i))
            }
            trimmed.put(item)
            prefs.edit().putString(KEY_BG_QUEUE, trimmed.toString()).apply()
        } catch (_: Exception) {
        }
        try {
            Handler(Looper.getMainLooper()).post {
                onBackgroundHealthActionPing?.invoke()
            }
        } catch (_: Exception) {
        }
    }

    fun drainQueuedBackgroundHealthActions(context: Context): List<Map<String, Any>> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_BG_ACTIONS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_BG_QUEUE, "[]") ?: "[]"
        if (raw == "[]" || raw.isBlank()) return emptyList()
        prefs.edit().putString(KEY_BG_QUEUE, "[]").apply()
        val out = mutableListOf<Map<String, Any>>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                out.add(
                    mapOf(
                        "type" to obj.optString("type", ""),
                        "ml" to obj.optInt("ml", 0),
                        "medId" to obj.optString("medId", ""),
                        "loggedAtEpochMs" to obj.optLong("loggedAtEpochMs", System.currentTimeMillis())
                    )
                )
            }
        } catch (_: Exception) {
        }
        return out
    }

    /**
     * Posts a standard outside-the-app Heads-Up + Lock-Screen Notification immediately
     * (used both by background BroadcastReceiver wakeup AND by 1-tap user test button).
     */
    fun showStandardReminderNotification(
        context: Context,
        eventId: String,
        title: String,
        subtitle: String,
        fullScreen: Boolean,
        cupMl: Int = 250
    ) {
        val appCtx = context.applicationContext
        ensureNotificationChannel(appCtx)

        val launchIntent = Intent(appCtx, MainActivity::class.java).apply {
            this.action = ACTION_OPEN_RINGING_UI
            putExtra("eventId", eventId)
            putExtra("title", title)
            putExtra("subtitle", subtitle)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }
        val launchPi = PendingIntent.getActivity(
            appCtx,
            eventId.hashCode(),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val nm = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val isWater = eventId.startsWith("water_")

        if (isWater) {
            val resolvedCup = if (cupMl > 0) {
                cupMl
            } else {
                appCtx.getSharedPreferences(PREFS_HYDRATION_DAEMON, Context.MODE_PRIVATE)
                    .getInt("preferredCupMl", 250)
            }

            // Refresh water title/subtitle dynamically from native daemon progress if available
            var resolvedTitle = title
            var resolvedSubtitle = subtitle
            val hPrefs = appCtx.getSharedPreferences(PREFS_HYDRATION_DAEMON, Context.MODE_PRIVATE)
            if (hPrefs.contains("targetWaterMl")) {
                val today = todayDayKey()
                var wMl = hPrefs.getInt("waterMl", 0)
                if (hPrefs.getString("dayKey", today) != today) {
                    wMl = 0
                    hPrefs.edit().putString("dayKey", today).putInt("waterMl", 0).apply()
                }
                val tMl = hPrefs.getInt("targetWaterMl", 2000)
                val remMl = (tMl - wMl).coerceAtLeast(0)
                resolvedTitle = "Đến giờ uống nước ($wMl/$tMl ml)"
                resolvedSubtitle = if (remMl > 0) {
                    "Bấm Đã uống +${resolvedCup}ml ngay trên thông báo này · Còn thiếu $remMl ml hôm nay."
                } else {
                    "Bạn đã hoàn thành mục tiêu $tMl ml nước hôm nay!"
                }
            }

            val snooze15Pi = buildBroadcastPendingIntent(
                context = appCtx,
                action = ACTION_REMINDER_SNOOZE_15M,
                eventId = eventId,
                title = resolvedTitle,
                subtitle = resolvedSubtitle,
                fullScreen = false,
                cupMl = resolvedCup,
                flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(appCtx, HEALTH_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_widget_leaf)
                .setColor(Color.parseColor("#0284C7"))
                .setContentTitle(resolvedTitle)
                .setContentText(resolvedSubtitle)
                .setStyle(NotificationCompat.BigTextStyle().bigText(resolvedSubtitle))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .setContentIntent(launchPi)

            val drinkPi = buildBroadcastPendingIntent(
                context = appCtx,
                action = ACTION_WATER_QUICK_LOG,
                eventId = eventId,
                title = resolvedTitle,
                subtitle = resolvedSubtitle,
                fullScreen = false,
                cupMl = resolvedCup,
                flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, "✓ Đã uống +${resolvedCup}ml", drinkPi)
            builder.addAction(0, "Hoãn 15 phút", snooze15Pi)

            nm.notify(notificationIdFor(eventId), builder.build())
            return
        }

        // Full-Screen Calendar / Personal Alarm notification
        val snoozePi = buildBroadcastPendingIntent(
            context = appCtx,
            action = ACTION_ALARM_SNOOZE,
            eventId = eventId,
            title = title,
            subtitle = subtitle,
            fullScreen = true,
            flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val dismissPi = buildBroadcastPendingIntent(
            context = appCtx,
            action = ACTION_ALARM_DISMISS,
            eventId = eventId,
            title = title,
            subtitle = subtitle,
            fullScreen = false,
            flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(appCtx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_widget_leaf)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setStyle(NotificationCompat.BigTextStyle().bigText(subtitle))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(fullScreen)
            .setAutoCancel(!fullScreen)
            .setContentIntent(launchPi)
            .addAction(0, "Hoãn 5 phút", snoozePi)
            .addAction(0, "Tắt báo thức", dismissPi)

        if (fullScreen) {
            builder.setFullScreenIntent(launchPi, true)
        }

        nm.notify(notificationIdFor(eventId), builder.build())
    }

    fun scheduleAlarm(
        context: Context,
        eventId: String,
        title: String,
        subtitle: String,
        triggerAtEpochMs: Long,
        minutesBefore: Int,
        fullScreen: Boolean,
        cupMl: Int = 250
    ): Map<String, Any> {
        val appCtx = context.applicationContext
        ensureNotificationChannel(appCtx)
        val am = appCtx.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val safeTriggerMs = if (triggerAtEpochMs < System.currentTimeMillis() + 2000L) {
            System.currentTimeMillis() + 3000L
        } else {
            triggerAtEpochMs
        }

        val pi = buildBroadcastPendingIntent(
            appCtx,
            action = ACTION_ALARM_FIRED,
            eventId = eventId,
            title = title,
            subtitle = subtitle,
            fullScreen = fullScreen,
            cupMl = cupMl,
            flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )!!

        val showIntent = Intent(appCtx, MainActivity::class.java).apply {
            action = ACTION_OPEN_RINGING_UI
            putExtra("eventId", eventId)
            putExtra("title", title)
            putExtra("subtitle", subtitle)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val showPi = PendingIntent.getActivity(
            appCtx,
            eventId.hashCode(),
            showIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        var exactUsed = false
        try {
            if (canScheduleExact(appCtx)) {
                if (fullScreen) {
                    // Gold-standard Android Clock API: wakes Doze to exact millisecond & shows status-bar alarm icon
                    val clockInfo = AlarmManager.AlarmClockInfo(safeTriggerMs, showPi)
                    am.setAlarmClock(clockInfo, pi)
                } else {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, safeTriggerMs, pi)
                }
                exactUsed = true
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, safeTriggerMs, pi)
            }
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, safeTriggerMs, pi)
        }

        val meta = JSONObject().apply {
            put("eventId", eventId)
            put("title", title)
            put("subtitle", subtitle)
            put("triggerAtEpochMs", safeTriggerMs)
            put("minutesBefore", minutesBefore)
            put("fullScreen", fullScreen)
            put("cupMl", cupMl)
            put("exactScheduled", exactUsed)
        }
        appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(eventId, meta.toString())
            .apply()

        return mapOf(
            "eventId" to eventId,
            "title" to title,
            "subtitle" to subtitle,
            "triggerAtEpochMs" to safeTriggerMs,
            "minutesBefore" to minutesBefore,
            "fullScreen" to fullScreen,
            "exactScheduled" to exactUsed
        )
    }

    fun cancelAlarm(context: Context, eventId: String) {
        val appCtx = context.applicationContext
        LifeOsAlarmRinger.stopRinging(appCtx, eventId)
        val am = appCtx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = buildBroadcastPendingIntent(
            appCtx,
            action = ACTION_ALARM_FIRED,
            eventId = eventId,
            title = "",
            subtitle = "",
            fullScreen = false,
            flags = PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pi != null) {
            am.cancel(pi)
            pi.cancel()
        }
        appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(eventId)
            .apply()
    }

    fun getScheduledAlarm(context: Context, eventId: String): Map<String, Any>? {
        val raw = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(eventId, null) ?: return null
        return parseAlarmJson(raw, eventId)
    }

    fun listAllScheduledAlarms(context: Context): List<Map<String, Any>> {
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val result = mutableListOf<Map<String, Any>>()
        for ((key, rawVal) in prefs.all) {
            val str = rawVal as? String ?: continue
            val parsed = parseAlarmJson(str, key)
            if (parsed != null) {
                result.add(parsed)
            } else {
                prefs.edit().remove(key).apply()
            }
        }
        result.sortBy { (it["triggerAtEpochMs"] as? Long) ?: Long.MAX_VALUE }
        return result
    }

    private fun parseAlarmJson(raw: String, fallbackId: String): Map<String, Any>? {
        return try {
            val obj = JSONObject(raw)
            val triggerMs = obj.optLong("triggerAtEpochMs", 0L)
            if (triggerMs <= System.currentTimeMillis()) {
                return null
            }
            mapOf(
                "eventId" to obj.optString("eventId", fallbackId),
                "title" to obj.optString("title", ""),
                "subtitle" to obj.optString("subtitle", ""),
                "triggerAtEpochMs" to triggerMs,
                "minutesBefore" to obj.optInt("minutesBefore", 0),
                "fullScreen" to obj.optBoolean("fullScreen", false),
                "exactScheduled" to obj.optBoolean("exactScheduled", false)
            )
        } catch (_: Exception) {
            null
        }
    }

    fun clearAllAlarms(context: Context) {
        val appCtx = context.applicationContext
        LifeOsAlarmRinger.stopRinging(appCtx)
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        for (eventId in prefs.all.keys.toList()) {
            cancelAlarm(appCtx, eventId)
        }
        prefs.edit().clear().apply()
        appCtx.getSharedPreferences(PREFS_HYDRATION_DAEMON, Context.MODE_PRIVATE)
            .edit().clear().apply()
        appCtx.getSharedPreferences(PREFS_BG_ACTIONS, Context.MODE_PRIVATE)
            .edit().clear().apply()
        try {
            val nm = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancelAll()
        } catch (_: Exception) {
        }
    }

    fun rescheduleAllPersistedAlarms(context: Context) {
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        for ((key, rawVal) in prefs.all.entries.toList()) {
            if (key == DAEMON_WATER_NEXT_ID) {
                // Recomputed cleanly below in the current timezone/wall-clock from daemon configs
                continue
            }
            val str = rawVal as? String ?: continue
            try {
                val obj = JSONObject(str)
                val triggerMs = obj.optLong("triggerAtEpochMs", 0L)
                if (triggerMs <= now) {
                    prefs.edit().remove(key).apply()
                    continue
                }
                scheduleAlarm(
                    context = appCtx,
                    eventId = obj.optString("eventId", key),
                    title = obj.optString("title", "Báo thức LifeOS"),
                    subtitle = obj.optString("subtitle", ""),
                    triggerAtEpochMs = triggerMs,
                    minutesBefore = obj.optInt("minutesBefore", 0),
                    fullScreen = obj.optBoolean("fullScreen", false),
                    cupMl = obj.optInt("cupMl", 250)
                )
            } catch (_: Exception) {
            }
        }
        // Recompute hydration daemon wall-clock triggers after reboot/timezone/time change
        cancelAlarm(appCtx, DAEMON_WATER_NEXT_ID)
        ensureNextDaemonWaterAlarmScheduled(appCtx)
    }

    fun buildBroadcastPendingIntent(
        context: Context,
        action: String,
        eventId: String,
        title: String,
        subtitle: String,
        fullScreen: Boolean,
        flags: Int,
        cupMl: Int = 250
    ): PendingIntent? {
        val intent = Intent(context, LifeOsAlarmReceiver::class.java).apply {
            this.action = action
            data = Uri.parse("lifeos://alarm/$action/$eventId")
            putExtra("eventId", eventId)
            putExtra("title", title)
            putExtra("subtitle", subtitle)
            putExtra("fullScreen", fullScreen)
            putExtra("cupMl", cupMl)
        }
        return PendingIntent.getBroadcast(context, (action + eventId).hashCode(), intent, flags)
    }
}

class LifeOsAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val eventId = intent.getStringExtra("eventId") ?: return
        val title = intent.getStringExtra("title") ?: "Báo thức LifeOS"
        val subtitle = intent.getStringExtra("subtitle") ?: "Đã đến giờ hẹn"
        val fullScreen = intent.getBooleanExtra("fullScreen", false)
        val cupMl = intent.getIntExtra("cupMl", 250)

        LifeOsAlarmScheduler.acquireBriefWakeLock(context, 4_000L)

        when (action) {
            LifeOsAlarmScheduler.ACTION_ALARM_DISMISS -> {
                LifeOsAlarmRinger.stopRinging(context, eventId)
                return
            }
            LifeOsAlarmScheduler.ACTION_ALARM_SNOOZE -> {
                LifeOsAlarmRinger.stopRinging(context, eventId)
                val snoozeAtMs = System.currentTimeMillis() + 5 * 60_000L
                LifeOsAlarmScheduler.scheduleAlarm(
                    context = context,
                    eventId = eventId,
                    title = title,
                    subtitle = "Hoãn 5 phút · $subtitle",
                    triggerAtEpochMs = snoozeAtMs,
                    minutesBefore = 0,
                    fullScreen = true
                )
                return
            }
            LifeOsAlarmScheduler.ACTION_REMINDER_SNOOZE_15M -> {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                nm?.cancel(LifeOsAlarmScheduler.notificationIdFor(eventId))
                val snoozeId = if (eventId.startsWith("water_")) {
                    "water_snooze_15m"
                } else {
                    "${eventId}_snooze_15m"
                }
                LifeOsAlarmScheduler.scheduleAlarm(
                    context = context,
                    eventId = snoozeId,
                    title = title,
                    subtitle = "Đã dời 15 phút · $subtitle",
                    triggerAtEpochMs = System.currentTimeMillis() + 15 * 60_000L,
                    minutesBefore = 0,
                    fullScreen = false,
                    cupMl = cupMl
                )
                return
            }
            LifeOsAlarmScheduler.ACTION_WATER_QUICK_LOG -> {
                val appCtx = context.applicationContext
                val nm = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                nm?.cancel(LifeOsAlarmScheduler.WATER_NOTIFICATION_ID)

                val hPrefs = appCtx.getSharedPreferences(
                    LifeOsAlarmScheduler.PREFS_HYDRATION_DAEMON,
                    Context.MODE_PRIVATE
                )
                val today = LifeOsAlarmScheduler.todayDayKey()
                val prevDay = hPrefs.getString("dayKey", today) ?: today
                val prevWater = if (prevDay == today) hPrefs.getInt("waterMl", 0) else 0
                val targetMl = hPrefs.getInt("targetWaterMl", 2000)
                val addedMl = if (cupMl > 0) cupMl else hPrefs.getInt("preferredCupMl", 250)
                val nextWater = (prevWater + addedMl).coerceAtMost(10_000)

                hPrefs.edit()
                    .putString("dayKey", today)
                    .putInt("waterMl", nextWater)
                    .apply()

                LifeOsAlarmScheduler.enqueueBackgroundHealthAction(
                    appCtx,
                    JSONObject().apply {
                        put("type", "water_logged")
                        put("ml", addedMl)
                        put("loggedAtEpochMs", System.currentTimeMillis())
                    }
                )

                // If daily goal is reached from lock-screen tap, cancel remaining same-day water alarms & roll to tomorrow!
                if (nextWater >= targetMl) {
                    val aPrefs = appCtx.getSharedPreferences(LifeOsAlarmScheduler.PREFS_NAME, Context.MODE_PRIVATE)
                    for (k in aPrefs.all.keys.toList()) {
                        if (k.startsWith("water_")) {
                            LifeOsAlarmScheduler.cancelAlarm(appCtx, k)
                        }
                    }
                    LifeOsAlarmScheduler.ensureNextDaemonWaterAlarmScheduled(appCtx)

                    LifeOsAlarmScheduler.ensureNotificationChannel(appCtx)
                    val doneNotif = NotificationCompat.Builder(appCtx, LifeOsAlarmScheduler.HEALTH_CHANNEL_ID)
                        .setSmallIcon(R.drawable.ic_widget_leaf)
                        .setColor(Color.parseColor("#10B981"))
                        .setContentTitle("🎉 Đã đạt mục tiêu uống nước hôm nay!")
                        .setContentText("Tổng cộng $nextWater / $targetMl ml · Hẹn gặp lại bạn vào sáng mai.")
                        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                        .setAutoCancel(true)
                        .setTimeoutAfter(5_000L)
                        .build()
                    nm?.notify(LifeOsAlarmScheduler.WATER_NOTIFICATION_ID + 1, doneNotif)
                } else {
                    LifeOsAlarmScheduler.ensureNextDaemonWaterAlarmScheduled(appCtx)
                }
                LifeOsWidgetStore.refreshAllWidgets(appCtx)
                return
            }
            LifeOsAlarmScheduler.ACTION_ALARM_FIRED -> {
                context.applicationContext
                    .getSharedPreferences(LifeOsAlarmScheduler.PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .remove(eventId)
                    .apply()

                if (fullScreen && !eventId.startsWith("water_")) {
                    LifeOsAlarmRinger.startRinging(context)
                }

                LifeOsAlarmScheduler.showStandardReminderNotification(
                    context = context,
                    eventId = eventId,
                    title = title,
                    subtitle = subtitle,
                    fullScreen = fullScreen,
                    cupMl = cupMl
                )

                // Autonomous background rollover for multi-day operation without opening the app!
                if (eventId.startsWith("water_")) {
                    LifeOsAlarmScheduler.ensureNextDaemonWaterAlarmScheduled(context)
                }
            }
        }
    }
}

class LifeOsBootAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val act = intent?.action ?: return
        if (act == Intent.ACTION_BOOT_COMPLETED ||
            act == Intent.ACTION_MY_PACKAGE_REPLACED ||
            act == Intent.ACTION_TIME_CHANGED ||
            act == Intent.ACTION_TIMEZONE_CHANGED ||
            act == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            LifeOsAlarmScheduler.acquireBriefWakeLock(context, 5_000L)
            LifeOsAlarmScheduler.rescheduleAllPersistedAlarms(context)
        }
    }
}
