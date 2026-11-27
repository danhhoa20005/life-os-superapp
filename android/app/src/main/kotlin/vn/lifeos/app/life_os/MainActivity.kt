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
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

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
    private val receiptPickerChannelName = "vn.lifeos.app/receipt_picker"
    private val privacyScreenChannelName = "vn.lifeos.app/privacy_screen"

    private var pendingWidgetAction: String? = null
    private var pendingAlarmPayload: Map<String, String>? = null
    private var isAlarmLockScreenActive: Boolean = false
    private var homeWidgetsMethodChannel: MethodChannel? = null
    private var alarmMethodChannel: MethodChannel? = null
    private var voiceMethodChannel: MethodChannel? = null
    private var pendingCalendarPermissionResult: MethodChannel.Result? = null
    private var pendingBatchPermissionsResult: MethodChannel.Result? = null
    private var pendingSinglePermissionKind: String? = null
    private var pendingReceiptPickerResult: MethodChannel.Result? = null
    private var pendingCameraReceiptFile: File? = null
    private var speechHelper: LifeOsSpeechRecognizerHelper? = null
    private var speechHelperOwnerId: String = VoiceSessionCoordinatorNative.OWNER_MAIN_ACTIVITY
    private var activeVoiceSessionId: String? = null
    private var activeVoiceAttemptId: Int = 0
    private var activeVoiceOwnerId: String = VoiceSessionCoordinatorNative.OWNER_MAIN_ACTIVITY
    private var activeVoiceEngineMode: String = "google_service"
    private var activeVoiceStrictOffline: Boolean = false
    private var activeVoiceLocale: String = "vi-VN"
    private var voiceStartGeneration: Long = 0L

    private var pendingPermissionSessionId: String? = null
    private var pendingPermissionAttemptId: Int = 0
    private var pendingPermissionOwnerId: String = VoiceSessionCoordinatorNative.OWNER_MAIN_ACTIVITY
    private var pendingPermissionEngineMode: String = "google_service"
    private var pendingPermissionStrictOffline: Boolean = false
    private var pendingPermissionLocale: String = "vi-VN"
    private var pendingPermissionGeneration: Long = -1L

    private var pendingDialogSessionId: String? = null
    private var pendingDialogAttemptId: Int = 0
    private var pendingDialogOwnerId: String = VoiceSessionCoordinatorNative.OWNER_MAIN_ACTIVITY
    private var pendingDialogGeneration: Long = -1L

    private var isAwaitingVoicePermissionOrDialog: Boolean = false
    private var isActivityResumed: Boolean = false
    private var pendingResumeAfterFocus: Runnable? = null
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
        LifeOsSpeechRecognizerHelper.preloadVietnameseOfflineModel(applicationContext)
        LifeOsSoundboxSpeaker.warmUp(applicationContext)
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
                intent.action = null
                alarmMethodChannel?.invokeMethod("onAlarmRinging", payload)
            }
        } else {
            clearAlarmLockScreenFlags()
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
            isAlarmLockScreenActive = true
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

    private fun clearAlarmLockScreenFlags() {
        isAlarmLockScreenActive = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
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
                        val sanitizedPackages = BankNotificationListenerService.sanitizeAllowedPackages(packages)
                        val prefs = applicationContext.getSharedPreferences(
                            BankNotificationListenerService.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        val editor = prefs.edit()
                            .putBoolean(BankNotificationListenerService.KEY_ENABLED, enabled)
                            .putStringSet(BankNotificationListenerService.KEY_PACKAGES, sanitizedPackages)
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
                    "clearBankSignalQueue" -> {
                        val cleared = LifeOsBankSignalQueueDb
                            .getInstance(applicationContext)
                            .clearAll()
                        BankNotificationListenerService.clearListenerPreferences(applicationContext)
                        result.success(cleared)
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
                        .putBoolean(LifeOsWidgetStore.KEY_IS_SIGNED_OUT, false)
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
                    val clearImmediately = call.argument<Boolean>("clearImmediately") ?: false
                    result.success(
                        LifeOsWidgetStore.drainQueuedCommands(
                            applicationContext,
                            clearImmediately = clearImmediately
                        )
                    )
                }
                "acknowledgeWidgetCommands" -> {
                    val ids = call.argument<List<String>>("commandIds")
                        ?: listOfNotNull(call.argument<String>("commandId"))
                    val feedback = call.argument<String>("feedback")
                    val count = LifeOsWidgetStore.acknowledgeQueuedCommands(
                        applicationContext,
                        ids,
                        feedback
                    )
                    result.success(count)
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
                "clearWidgets" -> {
                    LifeOsWidgetStore.clearSensitiveDataOnSignOut(applicationContext)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 3. Native Vietnamese Speech Recognition (v2 Coordinator + API 31/33 On-Device + PCM Self-Test)
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
        ensureSpeechHelper(VoiceSessionCoordinatorNative.OWNER_MAIN_ACTIVITY)
        voiceCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    val rawSessionId = call.argument<String>("sessionId")
                        ?: call.argument<String>("sessionToken")
                    val sessionId = rawSessionId?.takeIf { it.isNotBlank() }
                        ?: UUID.randomUUID().toString()
                    val argAttemptId = call.argument<Number>("attemptId")?.toInt()
                    val attemptId = if (argAttemptId != null && argAttemptId > 0) {
                        argAttemptId
                    } else if (sessionId == activeVoiceSessionId) {
                        activeVoiceAttemptId + 1
                    } else {
                        1
                    }
                    val ownerId = call.argument<String>("ownerId")?.takeIf { it.isNotBlank() }
                        ?: VoiceSessionCoordinatorNative.OWNER_MAIN_ACTIVITY
                    val preferSystemDialog = call.argument<Boolean>("preferSystemDialog") ?: false
                    val engineMode = call.argument<String>("engineMode") ?: "google_service"
                    val strictOffline = call.argument<Boolean>("strictOffline")
                        ?: (engineMode == "on_device" || engineMode == "offline_strict")
                    val locale = call.argument<String>("locale")?.takeIf { it.isNotBlank() } ?: "vi-VN"

                    voiceStartGeneration += 1
                    val generation = voiceStartGeneration
                    pendingResumeAfterFocus = null
                    activeVoiceSessionId = sessionId
                    activeVoiceAttemptId = attemptId
                    activeVoiceOwnerId = ownerId
                    activeVoiceEngineMode = engineMode
                    activeVoiceStrictOffline = strictOffline
                    activeVoiceLocale = locale

                    if (!strictOffline && (preferSystemDialog || engineMode == "system_dialog")) {
                        pendingPermissionGeneration = -1L
                        pendingPermissionSessionId = null
                        isAwaitingVoicePermissionOrDialog = false
                        ensureSpeechHelper(ownerId).startListening(
                            sessionId = sessionId,
                            attemptId = attemptId,
                            preferSystemDialog = true,
                            engineMode = "system_dialog",
                            strictOffline = false,
                            locale = locale
                        )
                        result.success("LISTENING_STARTED")
                        return@setMethodCallHandler
                    }

                    val hasAudioPerm = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (!hasAudioPerm) {
                        VoiceSessionCoordinatorNative.preemptIfOwnedByOther(ownerId)
                        speechHelper?.cancelListening(null)
                        isAwaitingVoicePermissionOrDialog = true
                        pendingPermissionSessionId = sessionId
                        pendingPermissionAttemptId = attemptId
                        pendingPermissionOwnerId = ownerId
                        pendingPermissionEngineMode = engineMode
                        pendingPermissionStrictOffline = strictOffline
                        pendingPermissionLocale = locale
                        pendingPermissionGeneration = generation
                        emitVoiceEnvelope(
                            VoiceSessionCoordinatorNative.buildEventEnvelope(
                                sessionId = sessionId,
                                attemptId = attemptId,
                                ownerId = ownerId,
                                engineId = engineMode,
                                eventType = "state",
                                extra = mapOf(
                                    "status" to LifeOsSpeechRecognizerHelper.STATE_REQUESTING_PERMISSION
                                )
                            )
                        )
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            REQ_RECORD_AUDIO
                        )
                        result.success("PERMISSION_REQUESTED")
                        return@setMethodCallHandler
                    }

                    pendingPermissionGeneration = -1L
                    pendingPermissionSessionId = null
                    isAwaitingVoicePermissionOrDialog = false
                    ensureSpeechHelper(ownerId).startListening(
                        sessionId = sessionId,
                        attemptId = attemptId,
                        preferSystemDialog = false,
                        engineMode = engineMode,
                        strictOffline = strictOffline,
                        locale = locale
                    )
                    result.success("LISTENING_STARTED")
                }
                "stopListening" -> {
                    val requestedId = call.argument<String>("sessionId")
                        ?: call.argument<String>("sessionToken")
                    val currentId = activeVoiceSessionId
                    if (requestedId != null) {
                        if (requestedId == currentId) {
                            pendingResumeAfterFocus = null
                            speechHelper?.stopListening(requestedId)
                        }
                    } else if (currentId != null && VoiceSessionCoordinatorNative.isOwnedBy(activeVoiceOwnerId)) {
                        pendingResumeAfterFocus = null
                        speechHelper?.stopListening(currentId)
                    }
                    result.success(true)
                }
                "cancelListening" -> {
                    val requestedId = call.argument<String>("sessionId")
                        ?: call.argument<String>("sessionToken")
                    val matchesActive = requestedId == null ||
                        requestedId == activeVoiceSessionId ||
                        requestedId == pendingPermissionSessionId ||
                        requestedId == pendingDialogSessionId
                    if (matchesActive) {
                        voiceStartGeneration += 1
                        pendingPermissionGeneration = -1L
                        pendingPermissionSessionId = null
                        pendingDialogGeneration = -1L
                        pendingDialogSessionId = null
                        pendingResumeAfterFocus = null
                        isAwaitingVoicePermissionOrDialog = false
                        val targetId = requestedId ?: activeVoiceSessionId
                        speechHelper?.cancelListening(targetId)
                        if (targetId != null) {
                            LifeOsPcmAudioRecorder.stopCapture(targetId)
                        }
                        if (requestedId == null || requestedId == activeVoiceSessionId) {
                            activeVoiceSessionId = null
                        }
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
                "getDiagnostics", "getVoiceDiagnosticsV2" -> {
                    result.success(
                        LifeOsSpeechRecognizerHelper.collectDiagnostics(
                            context = this,
                            activeEngineLabel = speechHelper?.lastResolvedEngineLabel
                        )
                    )
                }
                "checkRecognitionSupport" -> {
                    val locale = call.argument<String>("locale")?.takeIf { it.isNotBlank() } ?: "vi-VN"
                    val replied = AtomicBoolean(false)
                    LifeOsSpeechRecognizerHelper.checkVietnameseOnDeviceSupport(this, locale) { info ->
                        if (replied.compareAndSet(false, true)) {
                            result.success(info)
                        }
                    }
                }
                "resetCapabilityCache" -> {
                    VoiceSessionCoordinatorNative.resetCapabilityCache(applicationContext)
                    result.success(true)
                }
                "runMicrophoneSelfTest" -> {
                    val durationMs = call.argument<Number>("durationMs")?.toLong() ?: 1200L
                    val replied = AtomicBoolean(false)
                    LifeOsPcmAudioRecorder.runMicrophoneSelfTest(
                        context = applicationContext,
                        durationMs = durationMs
                    ) { info ->
                        if (replied.compareAndSet(false, true)) {
                            result.success(info)
                        }
                    }
                }
                "startLocalPcmCapture" -> {
                    val sessionId = (call.argument<String>("sessionId")
                        ?: call.argument<String>("sessionToken"))
                        ?.takeIf { it.isNotBlank() }
                        ?: UUID.randomUUID().toString()
                    val started = LifeOsPcmAudioRecorder.startCapture(
                        context = applicationContext,
                        sessionId = sessionId
                    ) { dbfs ->
                        emitVoiceEnvelope(
                            VoiceSessionCoordinatorNative.buildEventEnvelope(
                                sessionId = sessionId,
                                attemptId = 1,
                                ownerId = VoiceSessionCoordinatorNative.OWNER_PCM_LOCAL_CAPTURE,
                                engineId = "pcm_local_capture",
                                eventType = "rms",
                                extra = mapOf("rms" to dbfs)
                            )
                        )
                    }
                    result.success(
                        mapOf(
                            "started" to started,
                            "sessionId" to sessionId,
                            "sampleRateHz" to LifeOsPcmAudioRecorder.SAMPLE_RATE_HZ,
                            "audioRoute" to LifeOsAudioFocusCoordinator.detectCurrentAudioRoute(applicationContext)
                        )
                    )
                }
                "stopLocalPcmCapture" -> {
                    val sessionId = call.argument<String>("sessionId")
                        ?: call.argument<String>("sessionToken")
                    result.success(LifeOsPcmAudioRecorder.stopCapture(sessionId))
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
                    "getDistributionFlavor" -> {
                        result.success(BuildConfig.DISTRIBUTION_FLAVOR)
                    }
                    "isGitHubOtaEnabled" -> {
                        result.success(BuildConfig.ENABLE_GITHUB_OTA)
                    }
                    "getUpdateCacheDir" -> {
                        if (!BuildConfig.ENABLE_GITHUB_OTA) {
                            result.error(
                                "OTA_DISABLED_PLAY_FLAVOR",
                                "Phiên bản Google Play không hỗ trợ tải tệp APK trong ứng dụng.",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        val dir = File(cacheDir, "ota_updates")
                        if (!dir.exists()) {
                            dir.mkdirs()
                        }
                        result.success(dir.absolutePath)
                    }
                    "canRequestPackageInstalls" -> {
                        if (!BuildConfig.ENABLE_GITHUB_OTA) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(allowed)
                    }
                    "verifyApkSignature" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.success(
                                mapOf(
                                    "signatureStatus" to ApkSignatureStatus.UNREADABLE.name,
                                    "status" to ApkSignatureStatus.UNREADABLE.name,
                                    "valid" to false,
                                    "errorCode" to "INVALID_PATH",
                                    "reason" to "Đường dẫn tệp APK trống."
                                )
                            )
                            return@setMethodCallHandler
                        }
                        val apkFile = File(filePath)
                        if (!apkFile.exists()) {
                            result.success(
                                mapOf(
                                    "signatureStatus" to ApkSignatureStatus.UNREADABLE.name,
                                    "status" to ApkSignatureStatus.UNREADABLE.name,
                                    "valid" to false,
                                    "errorCode" to "FILE_NOT_FOUND",
                                    "reason" to "Không tìm thấy tệp APK đã tải."
                                )
                            )
                            return@setMethodCallHandler
                        }
                        val verification = LifeOsApkSignatureVerifier.verifyApk(
                            context = this,
                            apkFile = apkFile,
                            distributionFlavor = BuildConfig.DISTRIBUTION_FLAVOR
                        )
                        result.success(
                            mapOf(
                                "signatureStatus" to verification.status.name,
                                "status" to verification.status.name,
                                "valid" to verification.isMatch,
                                "errorCode" to verification.errorCode,
                                "reason" to verification.reasonVi
                            )
                        )
                    }
                    "installApk" -> {
                        if (!BuildConfig.ENABLE_GITHUB_OTA) {
                            result.error(
                                "OTA_DISABLED_PLAY_FLAVOR",
                                "Phiên bản Google Play không hỗ trợ tự cài đặt tệp APK.",
                                null
                            )
                            return@setMethodCallHandler
                        }
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
                        // APP-03: Tri-state APK signature check (MATCH / MISMATCH / UNREADABLE).
                        // Only MATCH may proceed to PackageInstaller!
                        val verification = LifeOsApkSignatureVerifier.verifyApk(
                            context = this,
                            apkFile = apkFile,
                            distributionFlavor = BuildConfig.DISTRIBUTION_FLAVOR
                        )
                        if (verification.status != ApkSignatureStatus.MATCH) {
                            try {
                                apkFile.delete()
                            } catch (_: Exception) {
                            }
                            val errCode = verification.errorCode ?: if (verification.status == ApkSignatureStatus.UNREADABLE) {
                                "CERT_UNREADABLE"
                            } else {
                                "CERT_MISMATCH"
                            }
                            val errReason = verification.reasonVi
                                ?: "Không thể xác minh chữ ký số của tệp APK mới (APP-03)."
                            result.error(
                                errCode,
                                errReason,
                                mapOf(
                                    "signatureStatus" to verification.status.name,
                                    "status" to verification.status.name,
                                    "reason" to errReason,
                                    "errorCode" to errCode
                                )
                            )
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
                            if (LifeOsWidgetVoicePolicy.isVoiceEngineModeVaultKey(key)) {
                                LifeOsWidgetStore.syncPreferredVoiceEngineMode(
                                    context = applicationContext,
                                    modeWire = value,
                                    userId = LifeOsWidgetVoicePolicy.extractUserIdFromScopedKey(key)
                                )
                            }
                            result.success(true)
                        }
                    }
                    "readSecret" -> {
                        val key = call.argument<String>("key") ?: ""
                        val value = if (key.isBlank()) null else LifeOsSecureVault.readSecret(applicationContext, key)
                        if (key.isNotBlank() && LifeOsWidgetVoicePolicy.isVoiceEngineModeVaultKey(key)) {
                            LifeOsWidgetStore.syncPreferredVoiceEngineMode(
                                context = applicationContext,
                                modeWire = value,
                                userId = LifeOsWidgetVoicePolicy.extractUserIdFromScopedKey(key)
                            )
                        } else if (key.isNotBlank()) {
                            val uid = LifeOsWidgetVoicePolicy.extractUserIdFromScopedKey(key)
                            if (uid != null && LifeOsWidgetStore.getActiveUserId(applicationContext) != uid) {
                                val userVoiceMode = LifeOsSecureVault.readSecret(
                                    applicationContext,
                                    LifeOsWidgetVoicePolicy.scopedVaultKey(uid)
                                )
                                LifeOsWidgetStore.syncPreferredVoiceEngineMode(
                                    context = applicationContext,
                                    modeWire = userVoiceMode,
                                    userId = uid
                                )
                            }
                        }
                        result.success(value)
                    }
                    "deleteSecret" -> {
                        val key = call.argument<String>("key") ?: ""
                        if (key.isNotBlank()) {
                            LifeOsSecureVault.deleteSecret(applicationContext, key)
                            if (LifeOsWidgetVoicePolicy.isVoiceEngineModeVaultKey(key)) {
                                LifeOsWidgetStore.syncPreferredVoiceEngineMode(
                                    context = applicationContext,
                                    modeWire = null,
                                    userId = LifeOsWidgetVoicePolicy.extractUserIdFromScopedKey(key)
                                )
                            }
                        }
                        result.success(true)
                    }
                    "clearAllSecrets" -> {
                        LifeOsSecureVault.clearAll(applicationContext)
                        LifeOsWidgetStore.clearPreferredVoiceEngineMode(applicationContext)
                        result.success(true)
                    }
                    "clearUserSecrets" -> {
                        val userId = call.argument<String>("userId")?.trim() ?: ""
                        if (userId.isEmpty() || userId == "." || userId == "..") {
                            result.success(false)
                        } else {
                            LifeOsSecureVault.clearForUser(applicationContext, userId)
                            if (LifeOsWidgetStore.getActiveUserId(applicationContext) == userId) {
                                LifeOsWidgetStore.clearPreferredVoiceEngineMode(applicationContext)
                            }
                            result.success(true)
                        }
                    }
                    "getVaultDirectoryPath" -> {
                        result.success(LifeOsSecureVault.getVaultDirectory(applicationContext).absolutePath)
                    }
                    "getLegacyVaultDirectoryPath" -> {
                        result.success(LifeOsSecureVault.getLegacyVaultDirectory(applicationContext).absolutePath)
                    }
                    "encryptBytes" -> {
                        val plainBytes = call.argument<ByteArray>("plainBytes")
                        val aad = call.argument<String>("aad") ?: ""
                        if (plainBytes == null) {
                            result.error("INVALID_BYTES", "Dữ liệu cần mã hóa trống.", null)
                        } else {
                            try {
                                result.success(LifeOsSecureVault.encryptBytes(applicationContext, plainBytes, aad))
                            } catch (e: Exception) {
                                result.error("VAULT_ENCRYPT_FAILED", e.message, null)
                            }
                        }
                    }
                    "decryptBytes" -> {
                        val cipherPack = call.argument<ByteArray>("cipherPack")
                        val aad = call.argument<String>("aad") ?: ""
                        if (cipherPack == null) {
                            result.error("INVALID_CIPHER", "Gói mã hóa trống.", null)
                        } else {
                            try {
                                result.success(LifeOsSecureVault.decryptBytes(applicationContext, cipherPack, aad))
                            } catch (e: Exception) {
                                result.error("VAULT_DECRYPT_FAILED", e.message, null)
                            }
                        }
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
                    clearAlarmLockScreenFlags()
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
                    intent?.action = null
                    if (p == null) {
                        clearAlarmLockScreenFlags()
                    }
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

        // 9. Native Receipt Image Picker & Camera Capture (`vn.lifeos.app/receipt_picker`)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, receiptPickerChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFromGallery" -> {
                        pendingReceiptPickerResult?.success(null)
                        pendingReceiptPickerResult = result
                        if (!LifeOsReceiptPickerHelper.launchGalleryPicker(this)) {
                            pendingReceiptPickerResult = null
                            result.success(null)
                        }
                    }
                    "captureFromCamera" -> {
                        pendingReceiptPickerResult?.success(null)
                        pendingReceiptPickerResult = result
                        val file = LifeOsReceiptPickerHelper.launchCameraCapture(this)
                        if (file == null) {
                            pendingReceiptPickerResult = null
                            result.success(null)
                        } else {
                            pendingCameraReceiptFile = file
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 10. FLAG_SECURE Recent-Apps Privacy Screen Shield (`vn.lifeos.app/privacy_screen`)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, privacyScreenChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setPrivacyScreenEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                setRecentsScreenshotEnabled(!enabled)
                            }
                        }
                        result.success(true)
                    }
                    "isPrivacyScreenEnabled" -> {
                        val hasFlag = (window.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE) != 0
                        result.success(hasFlag)
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

    private fun emitVoiceEnvelope(envelope: Map<String, Any?>) {
        runOnUiThread {
            try {
                voiceMethodChannel?.invokeMethod("onVoiceEvent", envelope)
            } catch (_: Exception) {
            }
            try {
                voiceEventSink?.success(envelope)
            } catch (_: Exception) {
            }
        }
    }

    private fun ensureSpeechHelper(
        ownerId: String = VoiceSessionCoordinatorNative.OWNER_MAIN_ACTIVITY
    ): LifeOsSpeechRecognizerHelper {
        val existing = speechHelper
        if (existing != null && speechHelperOwnerId == ownerId) {
            return existing
        }
        existing?.destroy()
        speechHelperOwnerId = ownerId
        val created = LifeOsSpeechRecognizerHelper(
            activity = this,
            ownerId = ownerId,
            onEnvelopeEvent = { envelope ->
                emitVoiceEnvelope(envelope)
            },
            onLaunchSystemDialog = { dialogIntent, sessionId, attemptId ->
                try {
                    isAwaitingVoicePermissionOrDialog = true
                    pendingDialogSessionId = sessionId
                    pendingDialogAttemptId = attemptId
                    pendingDialogOwnerId = ownerId
                    pendingDialogGeneration = voiceStartGeneration
                    @Suppress("DEPRECATION")
                    startActivityForResult(dialogIntent, REQ_SPEECH_INTENT)
                    true
                } catch (_: Exception) {
                    isAwaitingVoicePermissionOrDialog = false
                    pendingDialogSessionId = null
                    pendingDialogGeneration = -1L
                    false
                }
            },
            onDialogStateChanged = { awaiting ->
                isAwaitingVoicePermissionOrDialog = awaiting
            }
        )
        speechHelper = created
        return created
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true
        maybeRunPendingVoiceAfterFocus()
    }

    override fun onPause() {
        isActivityResumed = false
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            maybeRunPendingVoiceAfterFocus()
        }
    }

    private fun maybeRunPendingVoiceAfterFocus() {
        val task = pendingResumeAfterFocus ?: return
        if (isFinishing || isDestroyed || !isActivityResumed || !hasWindowFocus()) return
        pendingResumeAfterFocus = null
        task.run()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_RECORD_AUDIO) {
            isAwaitingVoicePermissionOrDialog = false
            val requestGeneration = pendingPermissionGeneration
            val requestSessionId = pendingPermissionSessionId
            val requestAttemptId = pendingPermissionAttemptId
            val requestOwnerId = pendingPermissionOwnerId
            val requestEngineMode = pendingPermissionEngineMode
            val requestStrictOffline = pendingPermissionStrictOffline
            val requestLocale = pendingPermissionLocale
            pendingPermissionGeneration = -1L
            pendingPermissionSessionId = null

            val stillCurrentSession = requestSessionId != null &&
                voiceStartGeneration == requestGeneration &&
                activeVoiceSessionId == requestSessionId &&
                !isFinishing &&
                !isDestroyed
            if (!stillCurrentSession) {
                return
            }

            val granted = (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) &&
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED

            if (granted) {
                emitVoiceEnvelope(
                    VoiceSessionCoordinatorNative.buildEventEnvelope(
                        sessionId = requestSessionId,
                        attemptId = requestAttemptId,
                        ownerId = requestOwnerId,
                        engineId = requestEngineMode,
                        eventType = "state",
                        extra = mapOf("status" to LifeOsSpeechRecognizerHelper.STATE_INITIALIZING)
                    )
                )
                val resumeTask = Runnable {
                    if (!isFinishing &&
                        !isDestroyed &&
                        voiceStartGeneration == requestGeneration &&
                        activeVoiceSessionId == requestSessionId
                    ) {
                        ensureSpeechHelper(requestOwnerId).startListening(
                            sessionId = requestSessionId,
                            attemptId = requestAttemptId,
                            preferSystemDialog = false,
                            engineMode = requestEngineMode,
                            strictOffline = requestStrictOffline,
                            locale = requestLocale
                        )
                    }
                }
                if (hasWindowFocus() && isActivityResumed) {
                    resumeTask.run()
                } else {
                    pendingResumeAfterFocus = resumeTask
                }
            } else {
                val permanentlyDenied = !ActivityCompat.shouldShowRequestPermissionRationale(
                    this,
                    Manifest.permission.RECORD_AUDIO
                )
                val code = if (permanentlyDenied) "PERMISSION_PERMANENTLY_DENIED" else "PERMISSION_DENIED"
                val message = if (permanentlyDenied) {
                    "Quyền Micro đang bị tắt trong Cài đặt máy. Bấm Cấp quyền Micro để bật lại."
                } else {
                    "Chưa cấp quyền Micro để thu âm trực tiếp. Bấm Cấp quyền Micro để thử lại."
                }
                activeVoiceSessionId = null
                emitVoiceEnvelope(
                    VoiceSessionCoordinatorNative.buildEventEnvelope(
                        sessionId = requestSessionId,
                        attemptId = requestAttemptId,
                        ownerId = requestOwnerId,
                        engineId = requestEngineMode,
                        eventType = "error",
                        extra = mapOf("code" to code, "message" to message)
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
            val dialogSessionId = pendingDialogSessionId
            val dialogAttemptId = pendingDialogAttemptId
            val dialogOwnerId = pendingDialogOwnerId
            val dialogGeneration = pendingDialogGeneration
            pendingDialogSessionId = null
            pendingDialogAttemptId = 0
            pendingDialogGeneration = -1L
            isAwaitingVoicePermissionOrDialog = false

            val stillValid = dialogSessionId != null &&
                dialogSessionId == activeVoiceSessionId &&
                dialogAttemptId == activeVoiceAttemptId &&
                dialogGeneration == voiceStartGeneration
            if (!stillValid) {
                if (dialogSessionId != null) {
                    speechHelper?.completeExternalDialogSession(
                        sessionId = dialogSessionId,
                        attemptId = dialogAttemptId,
                        success = false,
                        errorCode = "STALE_RESULT"
                    )
                }
                return
            }

            if (resultCode == Activity.RESULT_OK) {
                val matches = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val text = matches?.firstOrNull().orEmpty().trim()
                if (text.isNotEmpty()) {
                    speechHelper?.completeExternalDialogSession(
                        sessionId = dialogSessionId,
                        attemptId = dialogAttemptId,
                        success = true
                    )
                    activeVoiceSessionId = null
                    emitVoiceEnvelope(
                        VoiceSessionCoordinatorNative.buildEventEnvelope(
                            sessionId = dialogSessionId,
                            attemptId = dialogAttemptId,
                            ownerId = dialogOwnerId,
                            engineId = "system_speech_dialog",
                            eventType = "final",
                            extra = mapOf("text" to text)
                        )
                    )
                    emitVoiceEnvelope(
                        VoiceSessionCoordinatorNative.buildEventEnvelope(
                            sessionId = dialogSessionId,
                            attemptId = dialogAttemptId,
                            ownerId = dialogOwnerId,
                            engineId = "system_speech_dialog",
                            eventType = "state",
                            extra = mapOf("status" to LifeOsSpeechRecognizerHelper.STATE_REVIEW)
                        )
                    )
                    return
                }
            }

            speechHelper?.completeExternalDialogSession(
                sessionId = dialogSessionId,
                attemptId = dialogAttemptId,
                success = false,
                errorCode = "DIALOG_CANCELED"
            )
            activeVoiceSessionId = null
            // Emit ONE terminal outcome (`cancelled`), NEVER double-emitting both `cancelled` and `error`.
            emitVoiceEnvelope(
                VoiceSessionCoordinatorNative.buildEventEnvelope(
                    sessionId = dialogSessionId,
                    attemptId = dialogAttemptId,
                    ownerId = dialogOwnerId,
                    engineId = "system_speech_dialog",
                    eventType = "state",
                    extra = mapOf("status" to LifeOsSpeechRecognizerHelper.STATE_CANCELLED)
                )
            )
        } else if (requestCode == LifeOsReceiptPickerHelper.REQ_PICK_GALLERY) {
            val cb = pendingReceiptPickerResult
            pendingReceiptPickerResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                cb?.success(LifeOsReceiptPickerHelper.copyUriToReceiptCache(applicationContext, data.data!!))
            } else {
                cb?.success(null)
            }
        } else if (requestCode == LifeOsReceiptPickerHelper.REQ_CAPTURE_CAMERA) {
            val cb = pendingReceiptPickerResult
            val file = pendingCameraReceiptFile
            pendingReceiptPickerResult = null
            pendingCameraReceiptFile = null
            if (resultCode == Activity.RESULT_OK && file != null && file.exists() && file.length() > 0L) {
                cb?.success(
                    mapOf(
                        "filePath" to file.absolutePath,
                        "fileName" to file.name,
                        "sizeBytes" to file.length()
                    )
                )
            } else {
                try {
                    file?.delete()
                } catch (_: Exception) {
                }
                cb?.success(null)
            }
        }
    }

    override fun onStop() {
        // Release active inline SpeechRecognizer when app moves to background or lock screen,
        // and clear lockscreen flags once backgrounded.
        if (!isChangingConfigurations) {
            clearAlarmLockScreenFlags()
            if (!isAwaitingVoicePermissionOrDialog) {
                voiceStartGeneration += 1
                pendingResumeAfterFocus = null
                pendingPermissionGeneration = -1L
                pendingPermissionSessionId = null
                pendingDialogGeneration = -1L
                pendingDialogSessionId = null
                val currentId = activeVoiceSessionId
                activeVoiceSessionId = null
                speechHelper?.cancelListening(currentId)
                if (currentId != null) {
                    LifeOsPcmAudioRecorder.stopCapture(currentId)
                    VoiceSessionCoordinatorNative.releaseSession(currentId)
                }
            }
        }
        super.onStop()
    }

    override fun onDestroy() {
        voiceStartGeneration += 1
        pendingResumeAfterFocus = null
        isAwaitingVoicePermissionOrDialog = false
        pendingPermissionGeneration = -1L
        pendingPermissionSessionId = null
        pendingDialogGeneration = -1L
        pendingDialogSessionId = null
        val currentId = activeVoiceSessionId
        activeVoiceSessionId = null
        LifeOsAlarmScheduler.onBackgroundHealthActionPing = null
        LifeOsWidgetStore.onBackgroundWidgetCommandPing = null
        voiceMethodChannel = null
        speechHelper?.destroy()
        speechHelper = null
        if (currentId != null) {
            LifeOsPcmAudioRecorder.stopCapture(currentId)
            VoiceSessionCoordinatorNative.releaseSession(currentId)
        }
        super.onDestroy()
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val cn = ComponentName(this, BankNotificationListenerService::class.java)
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(cn.flattenToString())
    }
}
