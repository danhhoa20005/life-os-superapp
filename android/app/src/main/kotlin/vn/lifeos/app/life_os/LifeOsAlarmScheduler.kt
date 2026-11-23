package vn.lifeos.app.life_os

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import org.json.JSONObject

/**
 * Real Android OS Alarm & Reminder Scheduler backed by `AlarmManager` + persistent store + boot receiver.
 * Delivers high-priority / full-screen calendar alarms even when the Flutter app is closed or rebooted.
 */
object LifeOsAlarmScheduler {
    const val PREFS_NAME = "lifeos_scheduled_alarms_v1"
    const val CHANNEL_ID = "lifeos_calendar_alarms_v1"
    const val ACTION_ALARM_FIRED = "vn.lifeos.app.ACTION_CALENDAR_ALARM_FIRED"
    const val ACTION_OPEN_RINGING_UI = "vn.lifeos.app.ALARM_RINGING"

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
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Nhắc lịch & Báo thức sự kiện LifeOS",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Đổ chuông nhắc nhở sự kiện lịch trình đúng giờ đã hẹn"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 250, 500, 250, 700)
                setSound(alarmSound, attrs)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }
    }

    fun scheduleAlarm(
        context: Context,
        eventId: String,
        title: String,
        subtitle: String,
        triggerAtEpochMs: Long,
        minutesBefore: Int,
        fullScreen: Boolean
    ): Map<String, Any> {
        val appCtx = context.applicationContext
        ensureNotificationChannel(appCtx)
        val am = appCtx.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val safeTriggerMs = if (triggerAtEpochMs < System.currentTimeMillis() + 3000L) {
            System.currentTimeMillis() + 5000L
        } else {
            triggerAtEpochMs
        }

        val pi = buildBroadcastPendingIntent(
            appCtx,
            eventId = eventId,
            title = title,
            subtitle = subtitle,
            fullScreen = fullScreen,
            flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )!!

        var exactUsed = false
        try {
            if (canScheduleExact(appCtx)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, safeTriggerMs, pi)
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
            put("exactScheduled", exactUsed)
        }
        appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(eventId, meta.toString())
            .apply()

        return mapOf(
            "eventId" to eventId,
            "triggerAtEpochMs" to safeTriggerMs,
            "minutesBefore" to minutesBefore,
            "fullScreen" to fullScreen,
            "exactScheduled" to exactUsed
        )
    }

    fun cancelAlarm(context: Context, eventId: String) {
        val appCtx = context.applicationContext
        val am = appCtx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = buildBroadcastPendingIntent(
            appCtx,
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
        return try {
            val obj = JSONObject(raw)
            val triggerMs = obj.optLong("triggerAtEpochMs", 0L)
            if (triggerMs <= System.currentTimeMillis()) {
                return null
            }
            mapOf(
                "eventId" to obj.optString("eventId", eventId),
                "title" to obj.optString("title", ""),
                "subtitle" to obj.optString("subtitle", ""),
                "triggerAtEpochMs" to triggerMs,
                "minutesBefore" to obj.optInt("minutesBefore", 15),
                "fullScreen" to obj.optBoolean("fullScreen", false),
                "exactScheduled" to obj.optBoolean("exactScheduled", false)
            )
        } catch (_: Exception) {
            null
        }
    }

    fun clearAllAlarms(context: Context) {
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        for (eventId in prefs.all.keys.toList()) {
            cancelAlarm(appCtx, eventId)
        }
    }

    fun rescheduleAllPersistedAlarms(context: Context) {
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        for ((key, rawVal) in prefs.all) {
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
                    title = obj.optString("title", "Sự kiện LifeOS"),
                    subtitle = obj.optString("subtitle", ""),
                    triggerAtEpochMs = triggerMs,
                    minutesBefore = obj.optInt("minutesBefore", 15),
                    fullScreen = obj.optBoolean("fullScreen", false)
                )
            } catch (_: Exception) {
            }
        }
    }

    private fun buildBroadcastPendingIntent(
        context: Context,
        eventId: String,
        title: String,
        subtitle: String,
        fullScreen: Boolean,
        flags: Int
    ): PendingIntent? {
        val intent = Intent(context, LifeOsAlarmReceiver::class.java).apply {
            action = ACTION_ALARM_FIRED
            data = Uri.parse("lifeos://alarm/$eventId")
            putExtra("eventId", eventId)
            putExtra("title", title)
            putExtra("subtitle", subtitle)
            putExtra("fullScreen", fullScreen)
        }
        return PendingIntent.getBroadcast(context, eventId.hashCode(), intent, flags)
    }
}

class LifeOsAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val eventId = intent?.getStringExtra("eventId") ?: return
        val title = intent.getStringExtra("title") ?: "Nhắc lịch trình LifeOS"
        val subtitle = intent.getStringExtra("subtitle") ?: "Đến giờ sự kiện đã đặt"
        val fullScreen = intent.getBooleanExtra("fullScreen", false)

        LifeOsAlarmScheduler.ensureNotificationChannel(context)
        context.applicationContext
            .getSharedPreferences(LifeOsAlarmScheduler.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(eventId)
            .apply()

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = LifeOsAlarmScheduler.ACTION_OPEN_RINGING_UI
            putExtra("eventId", eventId)
            putExtra("title", title)
            putExtra("subtitle", subtitle)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val launchPi = PendingIntent.getActivity(
            context,
            eventId.hashCode(),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, LifeOsAlarmScheduler.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_widget_leaf)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(launchPi)

        if (fullScreen) {
            builder.setFullScreenIntent(launchPi, true)
        }

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(eventId.hashCode(), builder.build())
    }
}

class LifeOsBootAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val act = intent?.action ?: return
        if (act == Intent.ACTION_BOOT_COMPLETED ||
            act == Intent.ACTION_MY_PACKAGE_REPLACED ||
            act == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            LifeOsAlarmScheduler.rescheduleAllPersistedAlarms(context)
        }
    }
}
