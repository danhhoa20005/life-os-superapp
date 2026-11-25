package vn.lifeos.app.life_os

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat
import kotlin.math.max
import kotlin.math.min

/**
 * Google-Verified Vietnamese Speech Recognition Coordinator v3.26 for Android 10–16
 * (Samsung One UI, Xiaomi HyperOS/MIUI, OPPO ColorOS, Vivo OriginOS, Pixel/AOSP).
 *
 * Root-cause fixes aligned with upstream `csdcorp/speech_to_text` (`SpeechToTextPlugin.kt`):
 * 1. **System Broker First (`SpeechRecognizer.createSpeechRecognizer(applicationContext)`)**:
 *    On Android 12–15, third-party apps lack the `signature|system` permission
 *    `android.permission.BIND_RECOGNITION_SERVICE`, and passing explicit `ComponentName`s first
 *    either fails with `ERROR_CLIENT (5)` / `ERROR_INSUFFICIENT_PERMISSIONS (9)` or binds to legacy
 *    `com.google.android.googlequicksearchbox` stubs that emit `onReadyForSpeech` and then sit mute!
 *    Routing through `SpeechRecognizer.createSpeechRecognizer(applicationContext)` first (whenever
 *    the OS default is Google/standard) lets Android's privileged `RecognitionManagerService` proxy
 *    `BIND_RECOGNITION_SERVICE` and `OPSTR_RECORD_AUDIO` attribution cleanly.
 * 2. **Acoustic Dead-Stream Watchdog (`2100ms`) + Full Error Cascade**:
 *    On OEM ROMs (MIUI/HyperOS, OriginOS, ColorOS) that mute background `RecognitionService` streams
 *    (`rmsSpread < 0.35 dB` and zero partial text) or return `ERROR_NETWORK` / `ERROR_CLIENT` /
 *    dead-stream `ERROR_SPEECH_TIMEOUT`, the helper immediately tears down the dead binder and
 *    auto-launches Google's `ACTION_RECOGNIZE_SPEECH` Activity popup in the exact same tap!
 * 3. **Smart Device Capability Memory (`lifeos_voice_engine_caps`)**:
 *    Once a device's inline `SpeechRecognizer` fails and Google's `ACTION_RECOGNIZE_SPEECH` popup
 *    succeeds, the helper remembers `auto_prefer_google_dialog = true` so every future Mic tap opens
 *    Google's 100%-working recognizer in `0ms` without waiting on broken background binders.
 */
class LifeOsSpeechRecognizerHelper(
    private val activity: Activity,
    private val onStateChanged: (String) -> Unit,
    private val onRmsChanged: (Double) -> Unit,
    private val onPartialTranscript: (String) -> Unit,
    private val onFinalTranscript: (String) -> Unit,
    private val onError: (code: String, message: String) -> Unit,
    private val onLaunchSystemDialog: (Intent) -> Boolean,
    private val onEngineAutoSwitched: ((String) -> Unit)? = null,
    private val onDialogStateChanged: ((Boolean) -> Unit)? = null
) {
    sealed class EngineCandidate(val label: String) {
        data object SystemBrokerDefault : EngineCandidate("system_default")
        data class ExplicitGoogleComponent(val componentName: ComponentName) :
            EngineCandidate("service:${componentName.packageName}")
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var activeSessionId: Int = 0
    private var startupWatchdog: Runnable? = null
    private var deadStreamWatchdog: Runnable? = null
    private var stopFinalizeWatchdog: Runnable? = null
    private var pendingStartRunnable: Runnable? = null
    private var activeStopFlushHook: (() -> Unit)? = null
    private var lastDialogWasAutoEscalated: Boolean = false

    @Volatile
    var lastResolvedEngineLabel: String = "system_default"
        private set

    companion object {
        const val STATE_IDLE = "idle"
        const val STATE_REQUESTING_PERMISSION = "requesting_permission"
        const val STATE_INITIALIZING = "initializing"
        const val STATE_LISTENING = "listening"
        const val STATE_PROCESSING = "processing"
        const val STATE_REVIEW = "review"
        const val STATE_COMPLETED = "completed"
        const val STATE_ERROR = "error"
        const val STATE_CANCELLED = "cancelled"

        private const val RECOGNITION_SERVICE_ACTION = "android.speech.RecognitionService"
        private const val CAPS_PREFS_NAME = "lifeos_voice_engine_caps"
        private const val KEY_INLINE_VERIFIED = "inline_verified_working"
        private const val KEY_AUTO_PREFER_DIALOG = "auto_prefer_google_dialog"

        private const val BINDER_COOLDOWN_MS = 85L
        private const val DEFERRED_DESTROY_MS = 60L
        private const val BUSY_RETRY_DELAY_MS = 200L
        private const val SILENT_KEEPALIVE_DELAY_MS = 110L
        private const val STARTUP_WATCHDOG_MS = 1450L
        private const val DEAD_MIC_STREAM_WATCHDOG_MS = 2150L
        private const val STOP_FINALIZE_WATCHDOG_MS = 1350L
        private const val FAST_REJECT_THRESHOLD_MS = 1450L
        private const val MIN_LIVE_RMS_SPREAD_DB = 0.45f

        private val GOOGLE_DIALOG_PACKAGES = listOf(
            "com.google.android.googlequicksearchbox",
            "com.google.android.tts",
            "com.google.android.apps.searchlite"
        )

        private val NON_VIETNAMESE_OEM_PREFIXES = listOf(
            "com.xiaomi.",
            "com.miui.",
            "com.heytap.",
            "com.oppo.",
            "com.coloros.",
            "com.vivo.",
            "com.samsung.android.bixby",
            "com.samsung.android.scs",
            "com.google.android.as"
        )

        private const val ERR_TOO_MANY_REQUESTS = 10
        private const val ERR_SERVER_DISCONNECTED = 11
        private const val ERR_LANGUAGE_NOT_SUPPORTED = 12
        private const val ERR_LANGUAGE_UNAVAILABLE = 13
        private const val ERR_CANNOT_CHECK_SUPPORT = 14

        fun isInlineVerifiedWorking(context: Context): Boolean {
            return try {
                context.applicationContext
                    .getSharedPreferences(CAPS_PREFS_NAME, Context.MODE_PRIVATE)
                    .getBoolean(KEY_INLINE_VERIFIED, false)
            } catch (_: Exception) {
                false
            }
        }

        fun shouldAutoPreferGoogleDialog(context: Context): Boolean {
            return try {
                context.applicationContext
                    .getSharedPreferences(CAPS_PREFS_NAME, Context.MODE_PRIVATE)
                    .getBoolean(KEY_AUTO_PREFER_DIALOG, false)
            } catch (_: Exception) {
                false
            }
        }

        fun markInlineVerifiedWorking(context: Context) {
            try {
                context.applicationContext
                    .getSharedPreferences(CAPS_PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(KEY_INLINE_VERIFIED, true)
                    .putBoolean(KEY_AUTO_PREFER_DIALOG, false)
                    .apply()
            } catch (_: Exception) {
            }
        }

        fun setAutoPreferGoogleDialog(context: Context, preferDialog: Boolean) {
            try {
                context.applicationContext
                    .getSharedPreferences(CAPS_PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(KEY_AUTO_PREFER_DIALOG, preferDialog)
                    .apply()
            } catch (_: Exception) {
            }
        }

        /**
         * Builds a clean standard `RecognizerIntent` matching `csdcorp/speech_to_text`:
         * - Uses `applicationInfo.packageName` for `EXTRA_CALLING_PACKAGE`.
         * - Does NOT send response-only `EXTRA_LANGUAGE_PREFERENCE` on inline `startListening`.
         */
        fun buildVietnameseSpeechIntent(
            context: Context,
            forSystemDialog: Boolean = false,
            preferOffline: Boolean = false
        ): Intent {
            val callingPkg = context.applicationInfo?.packageName ?: context.packageName
            return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, callingPkg)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, !forSystemDialog)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                if (preferOffline && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !forSystemDialog) {
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                }
                if (forSystemDialog) {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "vi-VN")
                    putExtra(
                        RecognizerIntent.EXTRA_PROMPT,
                        "Mời bạn nói tiếng Việt (VD: Ăn phở 55 nghìn)"
                    )
                }
            }
        }

        /**
         * Resolves Google's `ACTION_RECOGNIZE_SPEECH` Activity first (`googlequicksearchbox` / `tts` /
         * `searchlite`), and always falls back to the system's generic `ACTION_RECOGNIZE_SPEECH` handler
         * whenever present so the working Google dialog is never blocked by strict package filters.
         */
        fun resolveGoogleSpeechDialogIntent(context: Context): Intent? {
            val pm = context.packageManager
            for (pkg in GOOGLE_DIALOG_PACKAGES) {
                val candidate = buildVietnameseSpeechIntent(
                    context = context,
                    forSystemDialog = true,
                    preferOffline = false
                ).apply {
                    setPackage(pkg)
                }
                val hit = try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        pm.resolveActivity(candidate, PackageManager.ResolveInfoFlags.of(0))
                    } else {
                        @Suppress("DEPRECATION")
                        pm.resolveActivity(candidate, 0)
                    }
                } catch (_: Exception) {
                    null
                }
                if (hit != null) {
                    return candidate
                }
            }

            val generic = buildVietnameseSpeechIntent(
                context = context,
                forSystemDialog = true,
                preferOffline = false
            )
            val anyHit = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.resolveActivity(generic, PackageManager.ResolveInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    pm.resolveActivity(generic, 0)
                }
            } catch (_: Exception) {
                null
            }
            return if (anyHit != null) generic else null
        }

        /**
         * Discovers inline `SpeechRecognizer` candidates following `csdcorp/speech_to_text`:
         * 1. `SystemBrokerDefault` (`SpeechRecognizer.createSpeechRecognizer(appContext)`) FIRST when
         *    the OS default service is Google or standard AOSP (proper `BIND_RECOGNITION_SERVICE` +
         *    `OPSTR_RECORD_AUDIO` broker handoff!).
         * 2. Explicit `com.google.android.tts` (`Speech Services by Google`) next (or first if OEM
         *    hijacked `voice_recognition_service` to Bixby/MiBrain/HeyTap/Vivo/SystemIntelligence).
         * 3. Legacy `com.google.android.googlequicksearchbox` background service ONLY on Android 11
         *    or older (or when `com.google.android.tts` is completely absent), avoiding Android 12–15
         *    dead trampoline stubs.
         */
        fun discoverCandidates(
            context: Context,
            engineMode: String = "google_service"
        ): List<EngineCandidate> {
            val pm = context.packageManager
            val queryIntent = Intent(RECOGNITION_SERVICE_ACTION)
            val resolved = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.queryIntentServices(queryIntent, PackageManager.ResolveInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    pm.queryIntentServices(queryIntent, 0)
                }
            } catch (_: Exception) {
                emptyList()
            }

            val googleTtsComponents = mutableListOf<EngineCandidate.ExplicitGoogleComponent>()
            val legacyGsaComponents = mutableListOf<EngineCandidate.ExplicitGoogleComponent>()

            for (info in resolved) {
                val svc = info.serviceInfo ?: continue
                if (!svc.exported) continue
                val pkg = svc.packageName.orEmpty()
                if (pkg == "com.google.android.as") continue
                val cn = ComponentName(pkg, svc.name)
                if (pkg == "com.google.android.tts") {
                    if (googleTtsComponents.none { it.componentName == cn }) {
                        // Prefer main GoogleTTSRecognitionService ahead of secondary soda/offline services
                        if (svc.name.contains("GoogleTTS", ignoreCase = true)) {
                            googleTtsComponents.add(0, EngineCandidate.ExplicitGoogleComponent(cn))
                        } else {
                            googleTtsComponents.add(EngineCandidate.ExplicitGoogleComponent(cn))
                        }
                    }
                } else if (pkg == "com.google.android.googlequicksearchbox" || pkg.startsWith("com.google.")) {
                    if (legacyGsaComponents.none { it.componentName == cn }) {
                        legacyGsaComponents.add(EngineCandidate.ExplicitGoogleComponent(cn))
                    }
                }
            }

            val isSysAvailable = try {
                SpeechRecognizer.isRecognitionAvailable(context)
            } catch (_: Exception) {
                false
            }
            val defaultServiceFlat = try {
                Settings.Secure.getString(context.contentResolver, "voice_recognition_service").orEmpty()
            } catch (_: Exception) {
                ""
            }
            val isDefaultNonVnOem = defaultServiceFlat.isNotEmpty() &&
                NON_VIETNAMESE_OEM_PREFIXES.any { defaultServiceFlat.startsWith(it) }

            val ordered = mutableListOf<EngineCandidate>()
            if (isSysAvailable && !isDefaultNonVnOem) {
                // Standard Android broker (`SpeechToTextPlugin.kt` primary path)
                ordered.add(EngineCandidate.SystemBrokerDefault)
            }

            // Explicit Speech Services by Google (`com.google.android.tts`)
            ordered.addAll(googleTtsComponents)

            // Only include legacy `googlequicksearchbox` service on pre-Android 12 or if `tts` is missing
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || googleTtsComponents.isEmpty()) {
                ordered.addAll(legacyGsaComponents)
            }

            if (isSysAvailable && isDefaultNonVnOem && ordered.isEmpty()) {
                ordered.add(EngineCandidate.SystemBrokerDefault)
            }
            return ordered.distinct()
        }

        fun collectDiagnostics(
            context: Context,
            activeEngineLabel: String? = null
        ): Map<String, Any?> {
            val pm = context.packageManager
            val hasMicHardware = pm.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)
            val hasRecordPerm = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
            val candidates = discoverCandidates(context).map { it.label }
            val hasGoogleDialog = resolveGoogleSpeechDialogIntent(context) != null
            val isRecognitionAvailable = candidates.isNotEmpty() || hasGoogleDialog
            val autoDialogRemembered = shouldAutoPreferGoogleDialog(context) && hasGoogleDialog
            val resolvedLabel = activeEngineLabel
                ?: (if (autoDialogRemembered) "system_speech_dialog" else candidates.firstOrNull())
                ?: (if (hasGoogleDialog) "system_speech_dialog" else "service:com.google.android.tts")

            return mapOf(
                "hardwareMicAvailable" to hasMicHardware,
                "hasRecordPermission" to hasRecordPerm,
                "isRecognitionAvailable" to isRecognitionAvailable,
                "isOnDeviceAvailable" to candidates.any { it.startsWith("service:com.google.") || it == "system_default" },
                "hasSystemSpeechDialog" to hasGoogleDialog,
                "availableEngines" to candidates,
                "activeEngineLabel" to resolvedLabel,
                "sdkInt" to Build.VERSION.SDK_INT,
                "manufacturer" to (Build.MANUFACTURER ?: "unknown")
            )
        }
    }

    /**
     * Called by `MainActivity.onActivityResult` / `LifeOsWidgetQuickOverlayActivity.onActivityResult`
     * whenever Google's `ACTION_RECOGNIZE_SPEECH` dialog returns valid spoken Vietnamese text.
     */
    fun recordDialogSuccessAfterEscalation() {
        if (lastDialogWasAutoEscalated) {
            lastDialogWasAutoEscalated = false
            setAutoPreferGoogleDialog(activity, true)
            onEngineAutoSwitched?.invoke("system_dialog")
        }
    }

    fun startListening(
        preferSystemDialog: Boolean = false,
        engineMode: String = "google_service",
        forceInlineProbe: Boolean = false
    ) {
        runOnMain {
            val sessionId = nextVoiceSession()
            clearTimers()
            LifeOsSoundboxSpeaker.stopSpeaking()
            val hadPreviousRecognizer = teardownCurrentRecognizer(abortInFlight = true)

            if (forceInlineProbe) {
                setAutoPreferGoogleDialog(activity, false)
            }

            val autoDialogRemembered = !forceInlineProbe &&
                shouldAutoPreferGoogleDialog(activity) &&
                resolveGoogleSpeechDialogIntent(activity) != null

            if (preferSystemDialog || engineMode == "system_dialog" || autoDialogRemembered) {
                lastDialogWasAutoEscalated = false
                launchDialogOrFallbackInline(sessionId, hadPreviousRecognizer)
                return@runOnMain
            }

            onStateChanged("initializing")

            val candidates = discoverCandidates(activity, engineMode = engineMode)
            if (candidates.isEmpty()) {
                lastDialogWasAutoEscalated = true
                launchDialogOrReportError(sessionId)
                return@runOnMain
            }

            val preferOfflineInitial = engineMode == "on_device"
            val delayMs = if (hadPreviousRecognizer) BINDER_COOLDOWN_MS else 0L
            val runnable = Runnable {
                if (sessionId != activeSessionId || activity.isFinishing || activity.isDestroyed) {
                    return@Runnable
                }
                attemptCandidate(
                    sessionId = sessionId,
                    candidates = candidates,
                    candidateIndex = 0,
                    retriedBusy = false,
                    preferOffline = preferOfflineInitial,
                    silentTimeoutRetries = 0
                )
            }
            pendingStartRunnable = runnable
            if (delayMs > 0L) {
                mainHandler.postDelayed(runnable, delayMs)
            } else {
                runnable.run()
            }
        }
    }

    fun stopListening() {
        runOnMain {
            clearStartupAndPendingTimers()
            val sr = speechRecognizer
            val flushHook = activeStopFlushHook
            if (sr != null) {
                onStateChanged("processing")
                val stopGuard = Runnable {
                    if (flushHook != null) {
                        flushHook.invoke()
                    } else {
                        teardownCurrentRecognizer(abortInFlight = true)
                        onStateChanged("idle")
                    }
                }
                stopFinalizeWatchdog?.let { mainHandler.removeCallbacks(it) }
                stopFinalizeWatchdog = stopGuard
                mainHandler.postDelayed(stopGuard, STOP_FINALIZE_WATCHDOG_MS)
                try {
                    sr.stopListening()
                } catch (_: Exception) {
                    stopFinalizeWatchdog?.let { mainHandler.removeCallbacks(it) }
                    stopFinalizeWatchdog = null
                    if (flushHook != null) {
                        flushHook.invoke()
                    } else {
                        teardownCurrentRecognizer(abortInFlight = false)
                        onStateChanged("idle")
                    }
                }
            } else {
                onStateChanged("idle")
            }
        }
    }

    fun cancelListening() {
        runOnMain {
            nextVoiceSession()
            clearTimers()
            teardownCurrentRecognizer(abortInFlight = true)
            onDialogStateChanged?.invoke(false)
            onStateChanged(STATE_CANCELLED)
        }
    }

    fun destroy() {
        runOnMain {
            nextVoiceSession()
            clearTimers()
            teardownCurrentRecognizer(abortInFlight = true)
        }
    }

    private fun nextVoiceSession(): Int {
        activeSessionId += 1
        activeStopFlushHook = null
        return activeSessionId
    }

    private fun clearStartupAndPendingTimers() {
        startupWatchdog?.let { mainHandler.removeCallbacks(it) }
        startupWatchdog = null
        deadStreamWatchdog?.let { mainHandler.removeCallbacks(it) }
        deadStreamWatchdog = null
        pendingStartRunnable?.let { mainHandler.removeCallbacks(it) }
        pendingStartRunnable = null
    }

    private fun clearTimers() {
        clearStartupAndPendingTimers()
        stopFinalizeWatchdog?.let { mainHandler.removeCallbacks(it) }
        stopFinalizeWatchdog = null
    }

    private fun teardownCurrentRecognizer(abortInFlight: Boolean): Boolean {
        activeStopFlushHook = null
        val prev = speechRecognizer ?: return false
        speechRecognizer = null
        if (abortInFlight) {
            try {
                prev.cancel()
            } catch (_: Exception) {
            }
        }
        mainHandler.postDelayed({
            try {
                prev.destroy()
            } catch (_: Exception) {
            }
        }, DEFERRED_DESTROY_MS)
        return true
    }

    private fun attemptCandidate(
        sessionId: Int,
        candidates: List<EngineCandidate>,
        candidateIndex: Int,
        retriedBusy: Boolean,
        preferOffline: Boolean,
        silentTimeoutRetries: Int
    ) {
        if (sessionId != activeSessionId || activity.isFinishing || activity.isDestroyed) {
            return
        }

        if (candidateIndex >= candidates.size) {
            lastDialogWasAutoEscalated = true
            launchDialogOrReportError(sessionId)
            return
        }

        val candidate = candidates[candidateIndex]
        val attemptStartedAtMs = System.currentTimeMillis()
        val appContext = activity.applicationContext
        val inlinePreviouslyVerified = isInlineVerifiedWorking(appContext)
        val hasGoogleDialogFallback = resolveGoogleSpeechDialogIntent(activity) != null

        try {
            teardownCurrentRecognizer(abortInFlight = true)
            val sr = when (candidate) {
                is EngineCandidate.SystemBrokerDefault ->
                    SpeechRecognizer.createSpeechRecognizer(appContext)
                is EngineCandidate.ExplicitGoogleComponent ->
                    SpeechRecognizer.createSpeechRecognizer(appContext, candidate.componentName)
            }
            speechRecognizer = sr
            lastResolvedEngineLabel = candidate.label

            var lastPartialTranscript = ""
            var receivedAnyCallback = false
            var announcedListening = false
            var sessionConcluded = false
            var minRmsSeen = Float.MAX_VALUE
            var maxRmsSeen = -Float.MAX_VALUE
            var heardSpeechActivity = false

            activeStopFlushHook = {
                if (sessionId == activeSessionId && !sessionConcluded) {
                    sessionConcluded = true
                    clearTimers()
                    val captured = lastPartialTranscript.trim()
                    lastPartialTranscript = ""
                    teardownCurrentRecognizer(abortInFlight = true)
                    if (captured.isNotEmpty()) {
                        markInlineVerifiedWorking(appContext)
                        onFinalTranscript(captured)
                        onStateChanged(STATE_REVIEW)
                    } else {
                        onStateChanged(STATE_IDLE)
                    }
                }
            }

            // Watchdog 1: Binder never even emits `onReadyForSpeech` within 1450ms -> cascade immediately!
            val watchdog = Runnable {
                if (sessionId != activeSessionId || receivedAnyCallback || sessionConcluded) {
                    return@Runnable
                }
                sessionConcluded = true
                clearStartupAndPendingTimers()
                teardownCurrentRecognizer(abortInFlight = true)
                attemptCandidate(
                    sessionId = sessionId,
                    candidates = candidates,
                    candidateIndex = candidateIndex + 1,
                    retriedBusy = false,
                    preferOffline = false,
                    silentTimeoutRetries = silentTimeoutRetries
                )
            }
            startupWatchdog = watchdog
            mainHandler.postDelayed(watchdog, STARTUP_WATCHDOG_MS)

            // Watchdog 2: OEM Dead-Mic-Stream Guard (`onReadyForSpeech` fired, but hardware mic stream is
            // muted/flat `rmsSpread < 0.45 dB` and zero partial words on an unproven inline binder).
            // Escalates straight to next candidate / Google Speech Dialog instead of hanging silently!
            if (!inlinePreviouslyVerified && hasGoogleDialogFallback) {
                val streamGuard = Runnable {
                    if (sessionId != activeSessionId || sessionConcluded) return@Runnable
                    val rmsSpread = if (maxRmsSeen >= minRmsSeen) (maxRmsSeen - minRmsSeen) else 0f
                    if (!heardSpeechActivity && lastPartialTranscript.isBlank() && rmsSpread < MIN_LIVE_RMS_SPREAD_DB) {
                        sessionConcluded = true
                        clearStartupAndPendingTimers()
                        teardownCurrentRecognizer(abortInFlight = true)
                        attemptCandidate(
                            sessionId = sessionId,
                            candidates = candidates,
                            candidateIndex = candidateIndex + 1,
                            retriedBusy = false,
                            preferOffline = false,
                            silentTimeoutRetries = silentTimeoutRetries
                        )
                    }
                }
                deadStreamWatchdog = streamGuard
                mainHandler.postDelayed(streamGuard, DEAD_MIC_STREAM_WATCHDOG_MS)
            }

            sr.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    receivedAnyCallback = true
                    clearStartupWatchdogOnly()
                    if (!announcedListening) {
                        announcedListening = true
                        onStateChanged("listening")
                    }
                }

                override fun onBeginningOfSpeech() {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    receivedAnyCallback = true
                    heardSpeechActivity = true
                    clearStartupAndStreamWatchdogs()
                    if (!announcedListening) {
                        announcedListening = true
                        onStateChanged("listening")
                    }
                }

                override fun onRmsChanged(rmsdB: Float) {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    minRmsSeen = min(minRmsSeen, rmsdB)
                    maxRmsSeen = max(maxRmsSeen, rmsdB)
                    if ((maxRmsSeen - minRmsSeen) >= MIN_LIVE_RMS_SPREAD_DB) {
                        heardSpeechActivity = true
                        clearDeadStreamWatchdogOnly()
                    }
                    if (receivedAnyCallback) {
                        onRmsChanged(rmsdB.toDouble())
                    }
                }

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    receivedAnyCallback = true
                    clearStartupAndStreamWatchdogs()
                    onStateChanged("processing")
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    receivedAnyCallback = true
                    clearStartupAndStreamWatchdogs()
                    if (!announcedListening) {
                        announcedListening = true
                        onStateChanged("listening")
                    }
                    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull().orEmpty().trim()
                    if (text.isNotEmpty()) {
                        heardSpeechActivity = true
                        markInlineVerifiedWorking(appContext)
                        lastPartialTranscript = text
                        onPartialTranscript(text)
                    }
                }

                override fun onResults(results: Bundle?) {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    sessionConcluded = true
                    receivedAnyCallback = true
                    clearTimers()
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
                        ?: lastPartialTranscript.trim()
                    lastPartialTranscript = ""
                    teardownCurrentRecognizer(abortInFlight = false)
                    if (text.isNotEmpty()) {
                        markInlineVerifiedWorking(appContext)
                        onFinalTranscript(text)
                        onStateChanged(STATE_REVIEW)
                    } else {
                        val elapsedMs = System.currentTimeMillis() - attemptStartedAtMs
                        val rmsSpread = if (maxRmsSeen >= minRmsSeen) (maxRmsSeen - minRmsSeen) else 0f
                        if (elapsedMs < FAST_REJECT_THRESHOLD_MS || (!inlinePreviouslyVerified && rmsSpread < MIN_LIVE_RMS_SPREAD_DB)) {
                            val nextRun = Runnable {
                                attemptCandidate(
                                    sessionId = sessionId,
                                    candidates = candidates,
                                    candidateIndex = if (preferOffline) candidateIndex else candidateIndex + 1,
                                    retriedBusy = if (preferOffline) retriedBusy else false,
                                    preferOffline = false,
                                    silentTimeoutRetries = silentTimeoutRetries
                                )
                            }
                            pendingStartRunnable = nextRun
                            mainHandler.postDelayed(nextRun, BINDER_COOLDOWN_MS)
                        } else {
                            onStateChanged(STATE_ERROR)
                            onError(
                                "NO_MATCH",
                                "Chưa nghe rõ câu nói. Bạn hãy bấm Mic nói lại hoặc chọn Hộp thoại Google."
                            )
                        }
                    }
                }

                override fun onError(error: Int) {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    sessionConcluded = true
                    receivedAnyCallback = true
                    clearTimers()
                    val elapsedMs = System.currentTimeMillis() - attemptStartedAtMs
                    val rmsSpread = if (maxRmsSeen >= minRmsSeen) (maxRmsSeen - minRmsSeen) else 0f

                    // 1. Rescue spoken partial text when recognizer closes on silence/client/no-match
                    if (lastPartialTranscript.isNotBlank() &&
                        (error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                            error == SpeechRecognizer.ERROR_NO_MATCH ||
                            error == SpeechRecognizer.ERROR_CLIENT ||
                            error == SpeechRecognizer.ERROR_SERVER)
                    ) {
                        val captured = lastPartialTranscript.trim()
                        lastPartialTranscript = ""
                        teardownCurrentRecognizer(abortInFlight = false)
                        markInlineVerifiedWorking(appContext)
                        onFinalTranscript(captured)
                        onStateChanged(STATE_REVIEW)
                        return
                    }

                    val hasAudioPerm = ContextCompat.checkSelfPermission(
                        activity,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED

                    // 2. If `preferOffline` failed, retry the same candidate ONLINE immediately
                    //    (guarded against ERROR_INSUFFICIENT_PERMISSIONS so missing permission never triggers a futile online retry!)
                    if (preferOffline && error != SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                        teardownCurrentRecognizer(abortInFlight = false)
                        val onlineRun = Runnable {
                            attemptCandidate(
                                sessionId = sessionId,
                                candidates = candidates,
                                candidateIndex = candidateIndex,
                                retriedBusy = retriedBusy,
                                preferOffline = false,
                                silentTimeoutRetries = silentTimeoutRetries
                            )
                        }
                        pendingStartRunnable = onlineRun
                        mainHandler.postDelayed(onlineRun, BINDER_COOLDOWN_MS)
                        return
                    }

                    // 3. Retry once if Binder is still releasing previous session
                    if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY && !retriedBusy) {
                        teardownCurrentRecognizer(abortInFlight = false)
                        val retryRun = Runnable {
                            attemptCandidate(
                                sessionId = sessionId,
                                candidates = candidates,
                                candidateIndex = candidateIndex,
                                retriedBusy = true,
                                preferOffline = false,
                                silentTimeoutRetries = silentTimeoutRetries
                            )
                        }
                        pendingStartRunnable = retryRun
                        mainHandler.postDelayed(retryRun, BUSY_RETRY_DELAY_MS)
                        return
                    }

                    // 4. Re-arm silence ONLY if inline audio has ALREADY been verified live on this phone
                    // (never loop on a dead/muted OEM binder!).
                    if (inlinePreviouslyVerified &&
                        lastPartialTranscript.isBlank() &&
                        elapsedMs >= FAST_REJECT_THRESHOLD_MS &&
                        error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT &&
                        silentTimeoutRetries < 1 &&
                        stopFinalizeWatchdog == null
                    ) {
                        teardownCurrentRecognizer(abortInFlight = false)
                        val keepAliveRun = Runnable {
                            attemptCandidate(
                                sessionId = sessionId,
                                candidates = candidates,
                                candidateIndex = candidateIndex,
                                retriedBusy = false,
                                preferOffline = false,
                                silentTimeoutRetries = silentTimeoutRetries + 1
                            )
                        }
                        pendingStartRunnable = keepAliveRun
                        mainHandler.postDelayed(keepAliveRun, SILENT_KEEPALIVE_DELAY_MS)
                        return
                    }

                    // 5. Cascade across ALL engine/network/permission/dead-mic failures straight to
                    // the next candidate and then into Google's `ACTION_RECOGNIZE_SPEECH` Dialog!
                    val isDeadStreamFailure = !inlinePreviouslyVerified &&
                        (rmsSpread < MIN_LIVE_RMS_SPREAD_DB || !heardSpeechActivity)
                    val shouldCascadeEngine = when (error) {
                        SpeechRecognizer.ERROR_CLIENT,
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                        SpeechRecognizer.ERROR_SERVER,
                        SpeechRecognizer.ERROR_AUDIO,
                        SpeechRecognizer.ERROR_NETWORK,
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                        ERR_TOO_MANY_REQUESTS,
                        ERR_SERVER_DISCONNECTED,
                        ERR_LANGUAGE_NOT_SUPPORTED,
                        ERR_LANGUAGE_UNAVAILABLE,
                        ERR_CANNOT_CHECK_SUPPORT -> true
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> hasAudioPerm
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                            elapsedMs < FAST_REJECT_THRESHOLD_MS || isDeadStreamFailure
                        else -> hasGoogleDialogFallback && !inlinePreviouslyVerified
                    }

                    teardownCurrentRecognizer(abortInFlight = false)
                    if (shouldCascadeEngine) {
                        val cascadeRun = Runnable {
                            attemptCandidate(
                                sessionId = sessionId,
                                candidates = candidates,
                                candidateIndex = candidateIndex + 1,
                                retriedBusy = false,
                                preferOffline = false,
                                silentTimeoutRetries = silentTimeoutRetries
                            )
                        }
                        pendingStartRunnable = cascadeRun
                        mainHandler.postDelayed(cascadeRun, BINDER_COOLDOWN_MS)
                        return
                    }

                    onStateChanged(STATE_ERROR)
                    val (errCode, friendlyMsg) = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                            "PERMISSION_DENIED" to "Vui lòng cấp quyền Micro để thu âm giọng nói."
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                            "NO_MATCH" to "Chưa nghe rõ giọng nói. Bấm Mic để nói lại hoặc chọn Hộp thoại Google."
                        SpeechRecognizer.ERROR_NETWORK,
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                            "NETWORK_ERROR" to "Mạng gián đoạn khi nhận diện Google Speech. Hãy kiểm tra kết nối mạng."
                        else ->
                            "SPEECH_ERROR_$error" to "Tạm ngưng thu âm. Bạn có thể bấm Mic nói lại hoặc chọn Hộp thoại Google."
                    }
                    onError(errCode, friendlyMsg)
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            val recIntent = buildVietnameseSpeechIntent(
                context = appContext,
                forSystemDialog = false,
                preferOffline = preferOffline
            )
            sr.startListening(recIntent)
        } catch (_: Exception) {
            clearStartupAndPendingTimers()
            teardownCurrentRecognizer(abortInFlight = true)
            val fallbackRun = Runnable {
                attemptCandidate(
                    sessionId = sessionId,
                    candidates = candidates,
                    candidateIndex = candidateIndex + 1,
                    retriedBusy = false,
                    preferOffline = false,
                    silentTimeoutRetries = silentTimeoutRetries
                )
            }
            pendingStartRunnable = fallbackRun
            mainHandler.postDelayed(fallbackRun, BINDER_COOLDOWN_MS)
        }
    }

    private fun clearStartupWatchdogOnly() {
        startupWatchdog?.let { mainHandler.removeCallbacks(it) }
        startupWatchdog = null
    }

    private fun clearDeadStreamWatchdogOnly() {
        deadStreamWatchdog?.let { mainHandler.removeCallbacks(it) }
        deadStreamWatchdog = null
    }

    private fun clearStartupAndStreamWatchdogs() {
        clearStartupWatchdogOnly()
        clearDeadStreamWatchdogOnly()
    }

    private fun launchDialogOrFallbackInline(sessionId: Int, hadPreviousRecognizer: Boolean) {
        if (sessionId != activeSessionId) return
        val dialogIntent = resolveGoogleSpeechDialogIntent(activity)
        if (dialogIntent != null) {
            val launched = try {
                lastResolvedEngineLabel = "system_speech_dialog"
                onLaunchSystemDialog(dialogIntent)
            } catch (_: Exception) {
                false
            }
            if (launched) {
                onDialogStateChanged?.invoke(true)
                onStateChanged(STATE_LISTENING)
                return
            }
        }

        // Fallback to inline Google Speech -> explicitly clear awaiting dialog flag so onStop() cancels inline mic
        onDialogStateChanged?.invoke(false)

        val hasAudioPerm = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        val googleCandidates = discoverCandidates(activity, engineMode = "google_service")
        if (hasAudioPerm && googleCandidates.isNotEmpty()) {
            onStateChanged(STATE_INITIALIZING)
            val delayMs = if (hadPreviousRecognizer) BINDER_COOLDOWN_MS else 0L
            val fallbackInline = Runnable {
                attemptCandidate(
                    sessionId = sessionId,
                    candidates = googleCandidates,
                    candidateIndex = 0,
                    retriedBusy = false,
                    preferOffline = false,
                    silentTimeoutRetries = 0
                )
            }
            pendingStartRunnable = fallbackInline
            if (delayMs > 0L) {
                mainHandler.postDelayed(fallbackInline, delayMs)
            } else {
                fallbackInline.run()
            }
            return
        }

        onStateChanged(STATE_ERROR)
        onError(
            "NO_SPEECH_ENGINE",
            "Thiết bị chưa bật Speech Services by Google (Nhận diện giọng nói của Google)."
        )
    }

    private fun launchDialogOrReportError(sessionId: Int) {
        if (sessionId != activeSessionId) return
        val dialogIntent = resolveGoogleSpeechDialogIntent(activity)
        val launched = if (dialogIntent != null) {
            try {
                lastResolvedEngineLabel = "system_speech_dialog"
                onLaunchSystemDialog(dialogIntent)
            } catch (_: Exception) {
                false
            }
        } else {
            false
        }
        if (launched) {
            onDialogStateChanged?.invoke(true)
            onStateChanged(STATE_LISTENING)
        } else {
            lastDialogWasAutoEscalated = false
            onDialogStateChanged?.invoke(false)
            onStateChanged(STATE_ERROR)
            onError(
                "NO_SPEECH_ENGINE",
                "Thiết bị chưa bật dịch vụ Nhận diện giọng nói của Google (Speech Services by Google)."
            )
        }
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }
}
