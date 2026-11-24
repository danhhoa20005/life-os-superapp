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
import android.speech.RecognizerIntent
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
    private val permissionsChannelName = "vn.lifeos.app/permissions"

    private var pendingWidgetAction: String? = null
    private var pendingAlarmPayload: Map<String, String>? = null
    private var homeWidgetsMethodChannel: MethodChannel? = null
    private var alarmMethodChannel: MethodChannel? = null
    private var voiceMethodChannel: MethodChannel? = null
    private var pendingCalendarPermissionResult: MethodChannel.Result? = null
    private var pendingBatchPermissionsResult: MethodChannel.Result? = null
    private var pendingSinglePermissionKind: String? = null
    private var speechHelper: LifeOsSpeechRecognizerHelper? = null
    private var activeVoiceSessionToken: String? = null
    private var voiceEventSink: EventChannel.EventSink? = null

    companion object {
        private const val REQ_RECORD_AUDIO = 7201
        private const val REQ_SPEECH_INTENT = 7202
        private const val REQ_POST_NOTIFICATIONS = 7203
        private const val REQ_CALENDAR_PERMISSIONS = 7204
        private const val REQ_BATCH_PERMISSIONS = 7209
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            } else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                )
            }
            pendingAlarmPayload = mapOf(
                "eventId" to (intent.getStringExtra("eventId") ?: ""),
                "title" to (intent.getStringExtra("title") ?: "Báo thức LifeOS"),
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
                        val list = LifeOsBankSignalQueueDb
                            .getInstance(applicationContext)
                            .claimDrainableBatch(200)
                        result.success(list)
                    }
                    "acknowledgeQueuedNotifications" -> {
                        val keys = call.argument<List<String>>("keys") ?: emptyList()
                        val acked = LifeOsBankSignalQueueDb
                            .getInstance(applicationContext)
                            .acknowledgeKeys(keys)
                        result.success(acked)
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

        // 2. Native Home Screen Widgets Bridge (4 Interactive Home-Screen Widgets + Background Queue Drain)
        val widgetsCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, homeWidgetsChannelName)
        homeWidgetsMethodChannel = widgetsCh
        LifeOsWidgetStore.onBackgroundWidgetCommandPing = {
            runOnUiThread {
                try {
                    homeWidgetsMethodChannel?.invokeMethod("onBackgroundWidgetCommand", null)
                } catch (_: Exception) {
                }
            }
        }
        widgetsCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidgets" -> {
                    val prefs = applicationContext.getSharedPreferences(
                        LifeOsWidgetStore.PREFS_NAME,
                        Context.MODE_PRIVATE
                    )
                    val editor = prefs.edit()
                        .putString("net_worth_formatted", call.argument<String>("netWorth") ?: "0 ₫")
                        .putString("monthly_income_formatted", call.argument<String>("monthlyIncome") ?: "+0 ₫")
                        .putString("monthly_expense_formatted", call.argument<String>("monthlyExpense") ?: "-0 ₫")
                        .putString("today_expense_formatted", call.argument<String>("todayExpense") ?: "0 ₫")
                        .putString("safe_daily_formatted", call.argument<String>("safeDaily") ?: "0 ₫")
                        .putString("wealth_badge", call.argument<String>("wealthBadge") ?: "Auto-Sync")
                        .putString("group_title", call.argument<String>("groupTitle") ?: "Tổ ấm & Hội nhóm")
                        .putString("group_status", call.argument<String>("groupStatus") ?: "Chọn số người rồi chạm mức chia nhanh bên dưới")
                        .putString("runway_label", call.argument<String>("runwayLabel") ?: "Quỹ dự phòng ổn định · Tự động cập nhật")
                        .putInt("daily_used_pct", call.argument<Int>("dailyUsedPct") ?: 15)
                        .putInt("pending_auto_signals", 0)

                    call.argument<Number>("netWorthMinor")?.toLong()?.let { editor.putLong("net_worth_minor", it) }
                    call.argument<Number>("monthlyIncomeMinor")?.toLong()?.let { editor.putLong("monthly_income_minor", it) }
                    call.argument<Number>("monthlyExpenseMinor")?.toLong()?.let { editor.putLong("monthly_expense_minor", it) }
                    call.argument<Number>("todayExpenseMinor")?.toLong()?.let { editor.putLong("today_expense_minor", it) }
                    call.argument<Number>("safeDailyMinor")?.toLong()?.let { editor.putLong("safe_daily_minor", it) }
                    call.argument<Int>("groupMemberCount")?.let {
                        editor.putInt("group_member_count", it.coerceIn(2, 20))
                    }
                    call.argument<Boolean>("hideBalances")?.let {
                        editor.putBoolean("hide_balances", it)
                    }
                    editor.apply()

                    LifeOsWidgetStore.refreshAllWidgets(applicationContext)
                    result.success(true)
                }
                "drainQueuedWidgetCommands" -> {
                    result.success(LifeOsWidgetStore.drainQueuedCommands(applicationContext))
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

        // 3. Native Vietnamese Speech Recognition (Multi-Engine Google Speech + System Dialog Fallback)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, voiceEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    voiceEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    voiceEventSink = null
                }
            })

        val voiceCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceMethodChannelName)
        voiceMethodChannel = voiceCh
        ensureSpeechHelper()
        voiceCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    val token = call.argument<String>("sessionToken")
                    val preferSystemDialog = call.argument<Boolean>("preferSystemDialog") ?: false
                    if (!token.isNullOrBlank()) {
                        activeVoiceSessionToken = token
                    }
                    if (preferSystemDialog) {
                        ensureSpeechHelper().startListening(preferSystemDialog = true)
                        result.success("LISTENING_STARTED")
                        return@setMethodCallHandler
                    }
                    val hasAudioPerm = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (!hasAudioPerm) {
                        emitVoiceEvent(mapOf("type" to "state", "status" to "requesting_permission"))
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            REQ_RECORD_AUDIO
                        )
                        result.success("PERMISSION_REQUESTED")
                        return@setMethodCallHandler
                    }
                    ensureSpeechHelper().startListening(preferSystemDialog = false)
                    result.success("LISTENING_STARTED")
                }
                "stopListening" -> {
                    speechHelper?.stopListening()
                    result.success(true)
                }
                "cancelListening" -> {
                    val token = call.argument<String>("sessionToken")
                    if (token.isNullOrBlank() || activeVoiceSessionToken == null || token == activeVoiceSessionToken) {
                        speechHelper?.cancelListening()
                    }
                    result.success(true)
                }
                "hasRecordPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "openMicrophoneSettings" -> {
                    try {
                        val settingsIntent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null)
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(settingsIntent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
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
                        // APP-03: Verify APK packageName & signing certificate lineage BEFORE launching installer!
                        val certError = verifyApkPackageAndSigningCert(apkFile)
                        if (certError != null) {
                            try {
                                apkFile.delete()
                            } catch (_: Exception) {
                            }
                            result.error("CERT_MISMATCH", certError, null)
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

        // 6. Native OS Calendar Alarm & Background Reminder Engine (`AlarmManager` + Lock-Screen Actions + Boot Persistence)
        val alarmCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, alarmSchedulerChannelName)
        alarmMethodChannel = alarmCh
        LifeOsAlarmScheduler.onBackgroundHealthActionPing = {
            try {
                alarmMethodChannel?.invokeMethod("onBackgroundHealthAction", null)
            } catch (_: Exception) {
            }
        }
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
                    val cupMl = call.argument<Int>("cupMl") ?: 250
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
                            fullScreen = fullScreen,
                            cupMl = cupMl
                        )
                        result.success(scheduled)
                    }
                }
                "showImmediateReminderNotification" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQ_POST_NOTIFICATIONS
                        )
                        result.success(false)
                    } else {
                        val eventId = call.argument<String>("eventId") ?: "water_test_now"
                        val title = call.argument<String>("title") ?: "Đến giờ uống nước"
                        val subtitle = call.argument<String>("subtitle") ?: "Uống 1 cốc nước để cơ thể khỏe khoắn nhé!"
                        val cupMl = call.argument<Int>("cupMl") ?: 250
                        LifeOsAlarmScheduler.showStandardReminderNotification(
                            context = applicationContext,
                            eventId = eventId,
                            title = title,
                            subtitle = subtitle,
                            fullScreen = false,
                            cupMl = cupMl
                        )
                        result.success(true)
                    }
                }
                "syncHydrationDaemon" -> {
                    LifeOsAlarmScheduler.syncHydrationDaemonConfig(
                        context = applicationContext,
                        enabled = call.argument<Boolean>("enabled") ?: false,
                        intervalMinutes = call.argument<Int>("intervalMinutes") ?: 90,
                        startHour = call.argument<Int>("startHour") ?: 7,
                        startMinute = call.argument<Int>("startMinute") ?: 0,
                        endHour = call.argument<Int>("endHour") ?: 21,
                        endMinute = call.argument<Int>("endMinute") ?: 0,
                        targetWaterMl = call.argument<Int>("targetWaterMl") ?: 2000,
                        waterMl = call.argument<Int>("waterMl") ?: 0,
                        preferredCupMl = call.argument<Int>("preferredCupMl") ?: 250,
                        dayKey = call.argument<String>("dayKey") ?: ""
                    )
                    result.success(true)
                }
                "syncMedicationDaemon" -> {
                    val medId = call.argument<String>("medId") ?: ""
                    if (medId.isNotBlank()) {
                        LifeOsAlarmScheduler.syncMedicationDaemonItem(
                            context = applicationContext,
                            medId = medId,
                            enabled = call.argument<Boolean>("enabled") ?: false,
                            name = call.argument<String>("name") ?: "Thuốc",
                            dosage = call.argument<String>("dosage") ?: "1 liều",
                            hour = call.argument<Int>("hour") ?: 8,
                            minute = call.argument<Int>("minute") ?: 0
                        )
                    }
                    result.success(true)
                }
                "drainBackgroundHealthActions" -> {
                    result.success(LifeOsAlarmScheduler.drainQueuedBackgroundHealthActions(applicationContext))
                }
                "getBackgroundReadiness" -> {
                    result.success(
                        mapOf(
                            "notificationsGranted" to LifeOsAlarmScheduler.isPostNotificationsGranted(applicationContext),
                            "exactAlarmGranted" to LifeOsAlarmScheduler.canScheduleExact(applicationContext),
                            "batteryOptimizationIgnored" to LifeOsAlarmScheduler.isBatteryOptimizationIgnored(applicationContext)
                        )
                    )
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQ_POST_NOTIFICATIONS
                        )
                        result.success(true)
                    } else if (!LifeOsAlarmScheduler.isPostNotificationsGranted(applicationContext)) {
                        LifeOsAlarmScheduler.openAppNotificationSettings(applicationContext)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                "openNotificationSettings" -> {
                    LifeOsAlarmScheduler.openAppNotificationSettings(applicationContext)
                    result.success(true)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    LifeOsAlarmScheduler.requestIgnoreBatteryOptimizations(applicationContext)
                    result.success(true)
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
                "stopRingingAlarm" -> {
                    val eventId = call.argument<String>("eventId")
                    LifeOsAlarmRinger.stopRinging(applicationContext, eventId)
                    result.success(true)
                }
                "startTestRinging" -> {
                    LifeOsAlarmRinger.startRinging(applicationContext)
                    result.success(true)
                }
                "listScheduledAlarms" -> {
                    result.success(LifeOsAlarmScheduler.listAllScheduledAlarms(applicationContext))
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

        // 8. Unified Device Permissions Hub Bridge (`vn.lifeos.app/permissions`)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkAll" -> {
                        result.success(collectPermissionsSnapshot())
                    }
                    "requestEssential" -> {
                        val missing = mutableListOf<String>()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                        ) {
                            missing.add(Manifest.permission.POST_NOTIFICATIONS)
                        }
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            missing.add(Manifest.permission.RECORD_AUDIO)
                        }
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                            missing.add(Manifest.permission.READ_CALENDAR)
                        }
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                            missing.add(Manifest.permission.WRITE_CALENDAR)
                        }
                        if (missing.isEmpty()) {
                            if (!LifeOsAlarmScheduler.isPostNotificationsGranted(applicationContext)) {
                                LifeOsAlarmScheduler.openAppNotificationSettings(applicationContext)
                            }
                            result.success(collectPermissionsSnapshot())
                        } else {
                            pendingBatchPermissionsResult?.success(collectPermissionsSnapshot())
                            pendingBatchPermissionsResult = result
                            pendingSinglePermissionKind = null
                            ActivityCompat.requestPermissions(
                                this,
                                missing.toTypedArray(),
                                REQ_BATCH_PERMISSIONS
                            )
                        }
                    }
                    "requestSingle" -> {
                        val kind = call.argument<String>("kind") ?: ""
                        when (kind) {
                            "notifications" -> {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                                    ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                                ) {
                                    pendingBatchPermissionsResult?.success(collectPermissionsSnapshot())
                                    pendingBatchPermissionsResult = result
                                    pendingSinglePermissionKind = "notifications"
                                    ActivityCompat.requestPermissions(
                                        this,
                                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                        REQ_BATCH_PERMISSIONS
                                    )
                                } else {
                                    if (!LifeOsAlarmScheduler.isPostNotificationsGranted(applicationContext)) {
                                        LifeOsAlarmScheduler.openAppNotificationSettings(applicationContext)
                                    }
                                    result.success(collectPermissionsSnapshot())
                                }
                            }
                            "microphone" -> {
                                if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                                    pendingBatchPermissionsResult?.success(collectPermissionsSnapshot())
                                    pendingBatchPermissionsResult = result
                                    pendingSinglePermissionKind = "microphone"
                                    ActivityCompat.requestPermissions(
                                        this,
                                        arrayOf(Manifest.permission.RECORD_AUDIO),
                                        REQ_BATCH_PERMISSIONS
                                    )
                                } else {
                                    result.success(collectPermissionsSnapshot())
                                }
                            }
                            "calendar" -> {
                                if (!LifeOsDeviceCalendar.hasPermission(applicationContext)) {
                                    pendingBatchPermissionsResult?.success(collectPermissionsSnapshot())
                                    pendingBatchPermissionsResult = result
                                    pendingSinglePermissionKind = "calendar"
                                    ActivityCompat.requestPermissions(
                                        this,
                                        arrayOf(
                                            Manifest.permission.READ_CALENDAR,
                                            Manifest.permission.WRITE_CALENDAR
                                        ),
                                        REQ_BATCH_PERMISSIONS
                                    )
                                } else {
                                    result.success(collectPermissionsSnapshot())
                                }
                            }
                            "exactAlarm" -> {
                                if (!LifeOsAlarmScheduler.canScheduleExact(applicationContext)) {
                                    LifeOsAlarmScheduler.openExactAlarmSettings(applicationContext)
                                }
                                result.success(collectPermissionsSnapshot())
                            }
                            "batteryUnrestricted" -> {
                                if (!LifeOsAlarmScheduler.isBatteryOptimizationIgnored(applicationContext)) {
                                    LifeOsAlarmScheduler.requestIgnoreBatteryOptimizations(applicationContext)
                                }
                                result.success(collectPermissionsSnapshot())
                            }
                            "bankNotificationListener" -> {
                                if (!isNotificationServiceEnabled()) {
                                    try {
                                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        }
                                        startActivity(intent)
                                    } catch (_: Exception) {
                                    }
                                }
                                result.success(collectPermissionsSnapshot())
                            }
                            "appSettings" -> {
                                openAppDetailsSettings()
                                result.success(collectPermissionsSnapshot())
                            }
                            else -> result.success(collectPermissionsSnapshot())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun collectPermissionsSnapshot(): Map<String, Boolean> {
        val micGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        return mapOf(
            "notifications" to LifeOsAlarmScheduler.isPostNotificationsGranted(applicationContext),
            "microphone" to micGranted,
            "calendar" to LifeOsDeviceCalendar.hasPermission(applicationContext),
            "exactAlarm" to LifeOsAlarmScheduler.canScheduleExact(applicationContext),
            "batteryUnrestricted" to LifeOsAlarmScheduler.isBatteryOptimizationIgnored(applicationContext),
            "bankNotificationListener" to isNotificationServiceEnabled()
        )
    }

    private fun openAppDetailsSettings() {
        try {
            val settingsIntent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null)
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(settingsIntent)
        } catch (_: Exception) {
        }
    }

    private fun emitVoiceEvent(payload: Map<String, Any?>) {
        runOnUiThread {
            try {
                voiceMethodChannel?.invokeMethod("onVoiceEvent", payload)
            } catch (_: Exception) {
            }
            try {
                voiceEventSink?.success(payload)
            } catch (_: Exception) {
            }
        }
    }

    private fun ensureSpeechHelper(): LifeOsSpeechRecognizerHelper {
        val existing = speechHelper
        if (existing != null) return existing
        val created = LifeOsSpeechRecognizerHelper(
            activity = this,
            onStateChanged = { status ->
                emitVoiceEvent(mapOf("type" to "state", "status" to status))
            },
            onRmsChanged = { rms ->
                emitVoiceEvent(mapOf("type" to "rms", "rms" to rms))
            },
            onPartialTranscript = { text ->
                emitVoiceEvent(mapOf("type" to "partial", "text" to text))
            },
            onFinalTranscript = { text ->
                emitVoiceEvent(mapOf("type" to "final", "text" to text))
            },
            onError = { code, message ->
                emitVoiceEvent(mapOf("type" to "error", "code" to code, "message" to message))
            },
            onLaunchSystemDialog = { dialogIntent ->
                try {
                    @Suppress("DEPRECATION")
                    startActivityForResult(dialogIntent, REQ_SPEECH_INTENT)
                    true
                } catch (_: Exception) {
                    false
                }
            }
        )
        speechHelper = created
        return created
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_RECORD_AUDIO) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                ensureSpeechHelper().startListening(preferSystemDialog = false)
            } else {
                val permanentlyDenied = !ActivityCompat.shouldShowRequestPermissionRationale(
                    this,
                    Manifest.permission.RECORD_AUDIO
                )
                emitVoiceEvent(mapOf("type" to "state", "status" to "idle"))
                emitVoiceEvent(
                    mapOf(
                        "type" to "error",
                        "code" to if (permanentlyDenied) "PERMISSION_PERMANENTLY_DENIED" else "PERMISSION_DENIED",
                        "message" to if (permanentlyDenied) {
                            "Quyền Micro đang bị tắt trong Cài đặt máy. Bấm Cấp quyền Micro hoặc dùng Thu âm hệ thống."
                        } else {
                            "Chưa cấp quyền Micro để thu âm trực tiếp. Bấm Cấp quyền Micro hoặc dùng Thu âm hệ thống."
                        }
                    )
                )
            }
        } else if (requestCode == REQ_CALENDAR_PERMISSIONS) {
            val cb = pendingCalendarPermissionResult
            pendingCalendarPermissionResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            cb?.success(granted || LifeOsDeviceCalendar.hasPermission(applicationContext))
        } else if (requestCode == REQ_BATCH_PERMISSIONS) {
            val cb = pendingBatchPermissionsResult
            val singleKind = pendingSinglePermissionKind
            pendingBatchPermissionsResult = null
            pendingSinglePermissionKind = null
            val allGranted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (!allGranted && singleKind != null && permissions.isNotEmpty()) {
                val canAskAgain = permissions.any {
                    ActivityCompat.shouldShowRequestPermissionRationale(this, it)
                }
                if (!canAskAgain) {
                    if (singleKind == "notifications") {
                        LifeOsAlarmScheduler.openAppNotificationSettings(applicationContext)
                    } else {
                        openAppDetailsSettings()
                    }
                }
            }
            cb?.success(collectPermissionsSnapshot())
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SPEECH_INTENT) {
            if (resultCode == Activity.RESULT_OK) {
                val matches = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val text = matches?.firstOrNull().orEmpty().trim()
                if (text.isNotEmpty()) {
                    emitVoiceEvent(mapOf("type" to "final", "text" to text))
                    return
                }
            }
            emitVoiceEvent(mapOf("type" to "state", "status" to "idle"))
            emitVoiceEvent(
                mapOf(
                    "type" to "error",
                    "code" to "DIALOG_CANCELED",
                    "message" to "Đã dừng hộp thoại thu âm. Chạm Mic để nói lại hoặc nhập bên dưới."
                )
            )
        }
    }

    override fun onDestroy() {
        LifeOsAlarmScheduler.onBackgroundHealthActionPing = null
        LifeOsWidgetStore.onBackgroundWidgetCommandPing = null
        voiceMethodChannel = null
        speechHelper?.destroy()
        speechHelper = null
        super.onDestroy()
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val cn = ComponentName(this, BankNotificationListenerService::class.java)
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(cn.flattenToString())
    }

    /**
     * APP-03: Validates that a downloaded OTA APK matches this app's `packageName` AND is signed
     * by the exact same signing certificate SHA-256 before handing off to Android PackageInstaller.
     */
    private fun verifyApkPackageAndSigningCert(apkFile: File): String? {
        return try {
            val archiveInfo = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageArchiveInfo(
                    apkFile.absolutePath,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                @Suppress("DEPRECATION")
                packageManager.getPackageArchiveInfo(apkFile.absolutePath, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageArchiveInfo(apkFile.absolutePath, PackageManager.GET_SIGNATURES)
            }) ?: return "Tệp APK không hợp lệ hoặc bị hỏng."

            if (archiveInfo.packageName != packageName) {
                return "Tên gói APK (${archiveInfo.packageName}) không khớp với ứng dụng LifeOS ($packageName)."
            }

            val installedBytes = getSigningCertBytesForInstalledApp()
            val archiveBytes = extractCertBytes(archiveInfo)
            if (installedBytes != null && archiveBytes != null) {
                val md = java.security.MessageDigest.getInstance("SHA-256")
                val installedHash = md.digest(installedBytes)
                val archiveHash = java.security.MessageDigest.getInstance("SHA-256").digest(archiveBytes)
                if (!installedHash.contentEquals(archiveHash)) {
                    return "Chứng chỉ ký của gói APK mới không khớp với phiên bản đang cài đặt (APP-03)."
                }
            }
            null
        } catch (e: Exception) {
            "Không thể xác minh chữ ký số của tệp APK: ${e.message}"
        }
    }

    private fun getSigningCertBytesForInstalledApp(): ByteArray? {
        return try {
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            }
            extractCertBytes(info)
        } catch (_: Exception) {
            null
        }
    }

    private fun extractCertBytes(pkgInfo: android.content.pm.PackageInfo): ByteArray? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = pkgInfo.signingInfo ?: return null
            val sigs = if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
            sigs?.firstOrNull()?.toByteArray()
        } else {
            @Suppress("DEPRECATION")
            pkgInfo.signatures?.firstOrNull()?.toByteArray()
        }
    }
}
