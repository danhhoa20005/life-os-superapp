package vn.lifeos.app.life_os

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.io.File

class MainActivity : FlutterActivity() {
    private val methodChannelName = "vn.lifeos.app/bank_listener_methods"
    private val eventChannelName = "vn.lifeos.app/bank_listener_events"
    private val appUpdaterChannelName = "vn.lifeos.app/app_updater"
    private val homeWidgetsChannelName = "vn.lifeos.app/home_widgets"
    private val voiceMethodChannelName = "vn.lifeos.app/voice_assistant"
    private val voiceEventChannelName = "vn.lifeos.app/voice_events"
    private val secureVaultChannelName = "vn.lifeos.app/secure_vault"
    private val alarmSchedulerChannelName = "vn.lifeos.app/alarm_scheduler"
    private val deviceCalendarChannelName = "vn.lifeos.app/device_calendar"

    private var pendingWidgetAction: String? = null
    private var pendingAlarmPayload: Map<String, String>? = null
    private var homeWidgetsMethodChannel: MethodChannel? = null
    private var alarmMethodChannel: MethodChannel? = null
    private var pendingCalendarPermissionResult: MethodChannel.Result? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var voiceEventSink: EventChannel.EventSink? = null

    companion object {
        private const val REQ_RECORD_AUDIO = 7201
        private const val REQ_SPEECH_INTENT = 7202
        private const val REQ_POST_NOTIFICATIONS = 7203
        private const val REQ_CALENDAR_PERMISSIONS = 7204
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureBankingNotificationChannel()
        captureWidgetIntent(intent)
        captureAlarmIntent(intent)
    }

    private fun ensureBankingNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val channel = NotificationChannel(
                "lifeos_banking_realtime",
                "Biến động số dư Ngân hàng",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Thông báo tiền vào / tiền ra theo thời gian thực trên Life OS"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                enableVibration(true)
            }
            mgr.createNotificationChannel(channel)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (captureWidgetIntent(intent)) {
            val act = pendingWidgetAction
            if (act != null && homeWidgetsMethodChannel != null) {
                pendingWidgetAction = null
                homeWidgetsMethodChannel?.invokeMethod("onWidgetAction", act)
            }
        }
        if (captureAlarmIntent(intent)) {
            val payload = pendingAlarmPayload
            if (payload != null && alarmMethodChannel != null) {
                pendingAlarmPayload = null
                alarmMethodChannel?.invokeMethod("onAlarmRinging", payload)
            }
        }
    }

    private fun captureWidgetIntent(intent: Intent?): Boolean {
        val action = intent?.action ?: return false
        if (action.startsWith("vn.lifeos.app.WIDGET_ACTION_")) {
            pendingWidgetAction = action
            return true
        }
        return false
    }

    private fun captureAlarmIntent(intent: Intent?): Boolean {
        val action = intent?.action ?: return false
        if (action == LifeOsAlarmScheduler.ACTION_OPEN_RINGING_UI) {
            pendingAlarmPayload = mapOf(
                "eventId" to (intent.getStringExtra("eventId") ?: ""),
                "title" to (intent.getStringExtra("title") ?: "Nhắc lịch trình LifeOS"),
                "subtitle" to (intent.getStringExtra("subtitle") ?: "")
            )
            return true
        }
        return false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Bank Notification Listener + Offline Background Queue Drain
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> {
                        result.success(isNotificationServiceEnabled())
                    }
                    "openPermissionSettings" -> {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                    "updateConfig" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val soundbox = call.argument<Boolean>("voiceSoundboxEnabled")
                        val packages = call.argument<List<String>>("allowedPackages") ?: emptyList()
                        val prefs = applicationContext.getSharedPreferences(
                            BankNotificationListenerService.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        val editor = prefs.edit()
                            .putBoolean(BankNotificationListenerService.KEY_ENABLED, enabled)
                            .putStringSet(BankNotificationListenerService.KEY_PACKAGES, packages.toSet())
                        if (soundbox != null) {
                            editor.putBoolean(BankNotificationListenerService.KEY_SOUNDBOX_ENABLED, soundbox)
                        }
                        editor.apply()
                        result.success(null)
                    }
                    "speakSoundbox" -> {
                        val msg = call.argument<String>("message") ?: "Đã nhận 250.000 đồng vào tài khoản"
                        LifeOsSoundboxSpeaker.speak(applicationContext, msg)
                        result.success(true)
                    }
                    "drainQueuedNotifications" -> {
                        val prefs = applicationContext.getSharedPreferences(
                            BankNotificationListenerService.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        val raw = prefs.getString(BankNotificationListenerService.KEY_QUEUED_JSON, "[]") ?: "[]"
                        prefs.edit().putString(BankNotificationListenerService.KEY_QUEUED_JSON, "[]").apply()
                        val list = mutableListOf<Map<String, Any>>()
                        try {
                            val arr = JSONArray(raw)
                            for (i in 0 until arr.length()) {
                                val obj = arr.getJSONObject(i)
                                list.add(
                                    mapOf(
                                        "packageName" to obj.optString("packageName"),
                                        "title" to obj.optString("title"),
                                        "body" to obj.optString("body"),
                                        "postedAtEpochMs" to obj.optLong("postedAtEpochMs"),
                                        "notificationKey" to obj.optString("notificationKey")
                                    )
                                )
                            }
                        } catch (_: Exception) {
                        }
                        result.success(list)
                    }
                    "isPostNotificationsGranted" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                        } else {
                            true
                        }
                        result.success(granted)
                    }
                    "requestPostNotificationsPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQ_POST_NOTIFICATIONS
                            )
                        }
                        result.success(true)
                    }
                    "isBatteryOptimizationIgnored" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val ignored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && pm != null) {
                            pm.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true
                        }
                        result.success(ignored)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    BankNotificationListenerService.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    BankNotificationListenerService.eventSink = null
                }
            })

        // 2. Native Home Screen Widgets Bridge (4 Purpose-Built Widgets + 1-Tap Pinning)
        val widgetsCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, homeWidgetsChannelName)
        homeWidgetsMethodChannel = widgetsCh
        widgetsCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidgets" -> {
                    val prefs = applicationContext.getSharedPreferences(
                        LifeOsWidgetStore.PREFS_NAME,
                        Context.MODE_PRIVATE
                    )
                    prefs.edit()
                        .putString("net_worth_formatted", call.argument<String>("netWorth") ?: "0 ₫")
                        .putString("monthly_income_formatted", call.argument<String>("monthlyIncome") ?: "+0 ₫")
                        .putString("monthly_expense_formatted", call.argument<String>("monthlyExpense") ?: "-0 ₫")
                        .putString("today_expense_formatted", call.argument<String>("todayExpense") ?: "0 ₫")
                        .putString("safe_daily_formatted", call.argument<String>("safeDaily") ?: "0 ₫")
                        .putString("wealth_badge", call.argument<String>("wealthBadge") ?: "Auto-Sync")
                        .putString("group_title", call.argument<String>("groupTitle") ?: "HỘI NHÓM & GIA ĐÌNH · CHIA TIỀN NHANH")
                        .putString("group_status", call.argument<String>("groupStatus") ?: "Nói câu chia ăn uống, việc nhà, điện nước")
                        .putString("runway_label", call.argument<String>("runwayLabel") ?: "Quỹ dự phòng ổn định · Tự động bắt số dư")
                        .putInt("daily_used_pct", call.argument<Int>("dailyUsedPct") ?: 15)
                        .putInt("pending_auto_signals", 0)
                        .apply()
                    LifeOsWidgetStore.refreshAllWidgets(applicationContext)
                    result.success(true)
                }
                "requestPinWidget" -> {
                    val kind = call.argument<String>("widgetKind") ?: "voice"
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val mgr = AppWidgetManager.getInstance(applicationContext)
                    if (!mgr.isRequestPinAppWidgetSupported) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val providerClass = when (kind) {
                        "wealth" -> WealthNetWorthWidgetProvider::class.java
                        "group" -> GroupSplitWidgetProvider::class.java
                        "safe_spend" -> DailySafeSpendWidgetProvider::class.java
                        else -> VoiceQuickWidgetProvider::class.java
                    }
                    val ok = mgr.requestPinAppWidget(ComponentName(applicationContext, providerClass), null, null)
                    result.success(ok)
                }
                "consumePendingWidgetAction" -> {
                    val act = pendingWidgetAction
                    pendingWidgetAction = null
                    result.success(act)
                }
                else -> result.notImplemented()
            }
        }

        // 3. Native Vietnamese Speech Recognition (SpeechRecognizer + RecognizerIntent Fallback)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, voiceEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    voiceEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    voiceEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceMethodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startListening" -> {
                        val hasAudioPerm = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!hasAudioPerm) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.RECORD_AUDIO),
                                REQ_RECORD_AUDIO
                            )
                            result.success("PERMISSION_REQUESTED")
                            return@setMethodCallHandler
                        }
                        startVietnameseVoiceCapture()
                        result.success("LISTENING_STARTED")
                    }
                    "stopListening" -> {
                        try {
                            speechRecognizer?.stopListening()
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // 4. OTA Self-Updater & Native CSV / JSON Share Sheet
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUpdaterChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledAppVersion" -> {
                        try {
                            val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.getPackageInfo(
                                    packageName,
                                    PackageManager.PackageInfoFlags.of(0)
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getPackageInfo(packageName, 0)
                            }
                            val buildNumber = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                pkgInfo.longVersionCode.toInt()
                            } else {
                                @Suppress("DEPRECATION")
                                pkgInfo.versionCode
                            }
                            result.success(
                                mapOf(
                                    "versionName" to (pkgInfo.versionName ?: "1.0.0"),
                                    "buildNumber" to buildNumber,
                                    "packageName" to packageName,
                                    "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")
                                )
                            )
                        } catch (e: Exception) {
                            result.error("VERSION_ERROR", e.message, null)
                        }
                    }
                    "getUpdateCacheDir" -> {
                        val dir = File(cacheDir, "ota_updates")
                        if (!dir.exists()) {
                            dir.mkdirs()
                        }
                        result.success(dir.absolutePath)
                    }
                    "canRequestPackageInstalls" -> {
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(allowed)
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "Đường dẫn tệp APK trống.", null)
                            return@setMethodCallHandler
                        }
                        val apkFile = File(filePath)
                        if (!apkFile.exists()) {
                            result.error("FILE_NOT_FOUND", "Không tìm thấy tệp APK đã tải.", null)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            val permIntent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(permIntent)
                            result.success("PERMISSION_REQUIRED")
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apkFile
                            )
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(installIntent)
                            result.success("INSTALLER_LAUNCHED")
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    "openExternalUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("INVALID_URL", "URL trống.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(browserIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_URL_FAILED", e.message, null)
                        }
                    }
                    "shareTextFile" -> {
                        val fileName = call.argument<String>("fileName") ?: "SaoKe_LifeOS.csv"
                        val content = call.argument<String>("content") ?: ""
                        val mimeType = call.argument<String>("mimeType") ?: "text/csv"
                        val shareTitle = call.argument<String>("title") ?: "Xuất Sao kê Life OS"
                        try {
                            val exportFile = File(cacheDir, fileName)
                            val bytes = if (mimeType.contains("csv")) {
                                byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) +
                                    content.toByteArray(Charsets.UTF_8)
                            } else {
                                content.toByteArray(Charsets.UTF_8)
                            }
                            exportFile.writeBytes(bytes)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                exportFile
                            )
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = mimeType
                                putExtra(Intent.EXTRA_STREAM, uri)
                                putExtra(Intent.EXTRA_SUBJECT, shareTitle)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            val chooser = Intent.createChooser(sendIntent, shareTitle).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(chooser)
                            result.success(exportFile.absolutePath)
                        } catch (e: Exception) {
                            result.error("SHARE_FILE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 5. Hardware-Backed Android Keystore Vault (AES-256-GCM) + Private Document Vault
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureVaultChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "writeSecret" -> {
                        val key = call.argument<String>("key") ?: ""
                        val value = call.argument<String>("value") ?: ""
                        if (key.isBlank()) {
                            result.error("INVALID_KEY", "Key trống", null)
                        } else {
                            LifeOsSecureVault.writeSecret(applicationContext, key, value)
                            result.success(true)
                        }
                    }
                    "readSecret" -> {
                        val key = call.argument<String>("key") ?: ""
                        result.success(if (key.isBlank()) null else LifeOsSecureVault.readSecret(applicationContext, key))
                    }
                    "deleteSecret" -> {
                        val key = call.argument<String>("key") ?: ""
                        if (key.isNotBlank()) {
                            LifeOsSecureVault.deleteSecret(applicationContext, key)
                        }
                        result.success(true)
                    }
                    "clearAllSecrets" -> {
                        LifeOsSecureVault.clearAll(applicationContext)
                        val vaultDir = File(filesDir, "secure_doc_vault")
                        if (vaultDir.exists()) vaultDir.deleteRecursively()
                        result.success(true)
                    }
                    "getVaultDirectoryPath" -> {
                        val vaultDir = File(filesDir, "secure_doc_vault")
                        if (!vaultDir.exists()) vaultDir.mkdirs()
                        result.success(vaultDir.absolutePath)
                    }
                    else -> result.notImplemented()
                }
            }

        // 6. Native OS Calendar Alarm & Reminder Scheduler (`AlarmManager` + Boot Persistence)
        val alarmCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, alarmSchedulerChannelName)
        alarmMethodChannel = alarmCh
        alarmCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQ_POST_NOTIFICATIONS
                        )
                    }
                    val eventId = call.argument<String>("eventId") ?: ""
                    val title = call.argument<String>("title") ?: "Sự kiện LifeOS"
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val triggerAtEpochMs = call.argument<Number>("triggerAtEpochMs")?.toLong() ?: 0L
                    val minutesBefore = call.argument<Int>("minutesBefore") ?: 15
                    val fullScreen = call.argument<Boolean>("fullScreen") ?: false
                    if (eventId.isBlank() || triggerAtEpochMs <= 0L) {
                        result.error("INVALID_ALARM", "Thiếu mã sự kiện hoặc thời gian nhắc.", null)
                    } else {
                        val scheduled = LifeOsAlarmScheduler.scheduleAlarm(
                            context = applicationContext,
                            eventId = eventId,
                            title = title,
                            subtitle = subtitle,
                            triggerAtEpochMs = triggerAtEpochMs,
                            minutesBefore = minutesBefore,
                            fullScreen = fullScreen
                        )
                        result.success(scheduled)
                    }
                }
                "cancelAlarm" -> {
                    val eventId = call.argument<String>("eventId") ?: ""
                    if (eventId.isNotBlank()) {
                        LifeOsAlarmScheduler.cancelAlarm(applicationContext, eventId)
                    }
                    result.success(true)
                }
                "getScheduledAlarm" -> {
                    val eventId = call.argument<String>("eventId") ?: ""
                    result.success(if (eventId.isBlank()) null else LifeOsAlarmScheduler.getScheduledAlarm(applicationContext, eventId))
                }
                "clearAllAlarms" -> {
                    LifeOsAlarmScheduler.clearAllAlarms(applicationContext)
                    result.success(true)
                }
                "canScheduleExactAlarms" -> {
                    result.success(LifeOsAlarmScheduler.canScheduleExact(applicationContext))
                }
                "openExactAlarmSettings" -> {
                    LifeOsAlarmScheduler.openExactAlarmSettings(applicationContext)
                    result.success(true)
                }
                "consumeInitialAlarmPayload" -> {
                    val p = pendingAlarmPayload
                    pendingAlarmPayload = null
                    result.success(p)
                }
                else -> result.notImplemented()
            }
        }

        // 7. Native Android System Calendar Bridge (`CalendarContract` 2-Way Sync)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceCalendarChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> {
                        result.success(LifeOsDeviceCalendar.hasPermission(applicationContext))
                    }
                    "requestPermission" -> {
                        if (LifeOsDeviceCalendar.hasPermission(applicationContext)) {
                            result.success(true)
                        } else {
                            pendingCalendarPermissionResult?.success(false)
                            pendingCalendarPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(
                                    Manifest.permission.READ_CALENDAR,
                                    Manifest.permission.WRITE_CALENDAR
                                ),
                                REQ_CALENDAR_PERMISSIONS
                            )
                        }
                    }
                    "listCalendars" -> {
                        Thread {
                            try {
                                val cals = LifeOsDeviceCalendar.listCalendars(applicationContext)
                                runOnUiThread { result.success(cals) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("CALENDAR_LIST_ERR", e.message, null)
                                }
                            }
                        }.start()
                    }
                    "listEvents" -> {
                        val startMs = call.argument<Number>("windowStartMs")?.toLong()
                            ?: (System.currentTimeMillis() - 90L * 86_400_000L)
                        val endMs = call.argument<Number>("windowEndMs")?.toLong()
                            ?: (System.currentTimeMillis() + 365L * 86_400_000L)
                        Thread {
                            try {
                                val events = LifeOsDeviceCalendar.listEvents(
                                    applicationContext,
                                    startMs,
                                    endMs
                                )
                                runOnUiThread { result.success(events) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("CALENDAR_EVENTS_ERR", e.message, null)
                                }
                            }
                        }.start()
                    }
                    "upsertEvent" -> {
                        val existingId = call.argument<Number>("deviceEventId")?.toLong()
                        val preferredCalId = call.argument<Number>("deviceCalendarId")?.toLong()
                        val title = call.argument<String>("title") ?: "Sự kiện"
                        val description = call.argument<String>("description")
                        val location = call.argument<String>("location")
                        val startsAtMs = call.argument<Number>("startsAtMs")?.toLong()
                            ?: System.currentTimeMillis()
                        val endsAtMs = call.argument<Number>("endsAtMs")?.toLong()
                            ?: (startsAtMs + 3_600_000L)
                        val isAllDay = call.argument<Boolean>("isAllDay") ?: false
                        val timeZone = call.argument<String>("timeZone")
                        val rrule = call.argument<String>("rrule")
                        val reminderMinutesBefore = call.argument<Int>("reminderMinutesBefore") ?: 15

                        Thread {
                            try {
                                val savedId = LifeOsDeviceCalendar.upsertEvent(
                                    context = applicationContext,
                                    existingDeviceEventId = existingId,
                                    preferredDeviceCalendarId = preferredCalId,
                                    title = title,
                                    description = description,
                                    location = location,
                                    startsAtMs = startsAtMs,
                                    endsAtMs = endsAtMs,
                                    isAllDay = isAllDay,
                                    timeZone = timeZone,
                                    rrule = rrule,
                                    reminderMinutesBefore = reminderMinutesBefore
                                )
                                runOnUiThread { result.success(savedId) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("CALENDAR_UPSERT_ERR", e.message, null)
                                }
                            }
                        }.start()
                    }
                    "deleteEvent" -> {
                        val devEvId = call.argument<Number>("deviceEventId")?.toLong() ?: 0L
                        Thread {
                            try {
                                val ok = LifeOsDeviceCalendar.deleteEvent(applicationContext, devEvId)
                                runOnUiThread { result.success(ok) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("CALENDAR_DELETE_ERR", e.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startVietnameseVoiceCapture() {
        val recIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "vi-VN")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Nói khoản thu/chi hoặc câu chia tiền...")
        }

        if (SpeechRecognizer.isRecognitionAvailable(this)) {
            try {
                speechRecognizer?.destroy()
                val sr = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer = sr
                sr.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        voiceEventSink?.success(mapOf("type" to "state", "status" to "listening"))
                    }

                    override fun onBeginningOfSpeech() {}

                    override fun onRmsChanged(rmsdB: Float) {
                        voiceEventSink?.success(mapOf("type" to "rms", "rms" to rmsdB.toDouble()))
                    }

                    override fun onBufferReceived(buffer: ByteArray?) {}

                    override fun onEndOfSpeech() {
                        voiceEventSink?.success(mapOf("type" to "state", "status" to "processing"))
                    }

                    override fun onError(error: Int) {
                        voiceEventSink?.success(mapOf("type" to "error", "code" to error))
                    }

                    override fun onResults(results: Bundle?) {
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull().orEmpty()
                        voiceEventSink?.success(mapOf("type" to "final", "text" to text))
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull().orEmpty()
                        if (text.isNotEmpty()) {
                            voiceEventSink?.success(mapOf("type" to "partial", "text" to text))
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })
                sr.startListening(recIntent)
                return
            } catch (_: Exception) {
            }
        }

        // System Dialog Fallback
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(recIntent, REQ_SPEECH_INTENT)
            voiceEventSink?.success(mapOf("type" to "state", "status" to "listening"))
        } catch (_: Exception) {
            voiceEventSink?.success(
                mapOf(
                    "type" to "error",
                    "code" to -1,
                    "message" to "Thiết bị chưa cài dịch vụ nhận diện giọng nói Google."
                )
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_RECORD_AUDIO &&
            grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            startVietnameseVoiceCapture()
        } else if (requestCode == REQ_CALENDAR_PERMISSIONS) {
            val cb = pendingCalendarPermissionResult
            pendingCalendarPermissionResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            cb?.success(granted || LifeOsDeviceCalendar.hasPermission(applicationContext))
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SPEECH_INTENT && resultCode == Activity.RESULT_OK) {
            val matches = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            val text = matches?.firstOrNull().orEmpty()
            if (text.isNotEmpty()) {
                voiceEventSink?.success(mapOf("type" to "final", "text" to text))
            }
        }
    }

    override fun onDestroy() {
        try {
            speechRecognizer?.destroy()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val cn = ComponentName(this, BankNotificationListenerService::class.java)
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(cn.flattenToString())
    }
}
