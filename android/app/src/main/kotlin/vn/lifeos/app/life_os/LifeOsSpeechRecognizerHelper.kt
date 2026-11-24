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

/**
 * Google-First Production Vietnamese Speech Recognition Coordinator for Android 10–16
 * (Samsung One UI, Xiaomi HyperOS/MIUI, OPPO ColorOS, Vivo OriginOS, Pixel/AOSP).
 *
 * Architectural guarantees:
 * 1. **100% Google Vietnamese Engine Priority**: Binds directly to exported Google Speech services
 *    (`com.google.android.tts` — Speech Services by Google, then `com.google.android.googlequicksearchbox` —
 *    Google App) FIRST, completely bypassing non-Vietnamese OEM speech bloatware (Bixby, MiBrain,
 *    HeyTap, Vivo AIEngine) and broken English-only `OnDeviceSpeechRecognizer` stubs.
 * 2. **Zero AudioFocus Contention**: Stops only in-app `LifeOsSoundboxSpeaker` TTS and never grabs
 *    `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE` against `com.google.android.tts`'s remote UID.
 * 3. **Clean Standard `RecognizerIntent` Contract**: Avoids non-standard `String[]` extras and
 *    unsupported `vi-VN` biasing bundles that trigger `ClassCastException` or `ERROR_CLIENT` on API 33+.
 * 4. **Bidirectional Google Fallback**:
 *    - Inline mode cascades `com.google.android.tts` -> `com.google.android.googlequicksearchbox` ->
 *      Google-backed `SystemBrokerDefault` -> Google-targeted `ACTION_RECOGNIZE_SPEECH` popup.
 *    - Dialog mode explicitly targets Google's `ACTION_RECOGNIZE_SPEECH` Activity first (preventing
 *      OEM popup hijacking), and falls back to inline Google Speech if the dialog Activity is absent.
 * 5. **Deferred Safe Destroy (`60ms`) & Stop Watchdog (`1350ms`)**: Prevents Binder crashes on rapid
 *    re-taps and rescues spoken partial transcripts cleanly.
 */
class LifeOsSpeechRecognizerHelper(
    private val activity: Activity,
    private val onStateChanged: (String) -> Unit,
    private val onRmsChanged: (Double) -> Unit,
    private val onPartialTranscript: (String) -> Unit,
    private val onFinalTranscript: (String) -> Unit,
    private val onError: (code: String, message: String) -> Unit,
    private val onLaunchSystemDialog: (Intent) -> Boolean
) {
    sealed class EngineCandidate(val label: String) {
        data class ExplicitGoogleComponent(val componentName: ComponentName) :
            EngineCandidate("service:${componentName.packageName}")
        data object SystemBrokerDefault : EngineCandidate("system_default")
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var activeSessionId: Int = 0
    private var startupWatchdog: Runnable? = null
    private var stopFinalizeWatchdog: Runnable? = null
    private var pendingStartRunnable: Runnable? = null
    private var activeStopFlushHook: (() -> Unit)? = null

    @Volatile
    var lastResolvedEngineLabel: String = "service:com.google.android.tts"
        private set

    companion object {
        private const val RECOGNITION_SERVICE_ACTION = "android.speech.RecognitionService"
        private const val BINDER_COOLDOWN_MS = 90L
        private const val DEFERRED_DESTROY_MS = 60L
        private const val BUSY_RETRY_DELAY_MS = 220L
        private const val SILENT_KEEPALIVE_DELAY_MS = 110L
        private const val STARTUP_WATCHDOG_MS = 1650L
        private const val STOP_FINALIZE_WATCHDOG_MS = 1350L
        private const val FAST_REJECT_THRESHOLD_MS = 1400L
        private const val MAX_INITIAL_SILENCE_RETRIES = 1

        private val GOOGLE_SPEECH_PACKAGES = listOf(
            "com.google.android.tts",
            "com.google.android.googlequicksearchbox"
        )

        private val NON_VIETNAMESE_OEM_PREFIXES = listOf(
            "com.xiaomi.",
            "com.miui.",
            "com.heytap.",
            "com.oppo.",
            "com.coloros.",
            "com.vivo.",
            "com.samsung.android.bixby",
            "com.samsung.android.scs"
        )

        private const val ERR_TOO_MANY_REQUESTS = 10
        private const val ERR_SERVER_DISCONNECTED = 11
        private const val ERR_LANGUAGE_NOT_SUPPORTED = 12
        private const val ERR_LANGUAGE_UNAVAILABLE = 13
        private const val ERR_CANNOT_CHECK_SUPPORT = 14

        fun buildVietnameseSpeechIntent(
            context: Context,
            forSystemDialog: Boolean = false,
            preferOffline: Boolean = false
        ): Intent {
            return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "vi-VN")
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, !forSystemDialog)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                if (preferOffline && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                }
                if (forSystemDialog) {
                    putExtra(
                        RecognizerIntent.EXTRA_PROMPT,
                        "Mời bạn nói tiếng Việt (VD: Ăn phở 55 nghìn)"
                    )
                }
            }
        }

        /**
         * Resolves Google's `ACTION_RECOGNIZE_SPEECH` Activity first so OEM Bixby/MiBrain popups
         * never hijack Vietnamese voice input; falls back to generic system Activity only if needed.
         */
        fun resolveGoogleSpeechDialogIntent(context: Context): Intent? {
            val pm = context.packageManager
            for (pkg in listOf("com.google.android.googlequicksearchbox", "com.google.android.tts")) {
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
            if (anyHit != null) {
                val resolvedPkg = anyHit.activityInfo?.packageName.orEmpty()
                if (NON_VIETNAMESE_OEM_PREFIXES.none { resolvedPkg.startsWith(it) }) {
                    return generic
                }
            }
            return null
        }

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

            val googleComponents = mutableListOf<EngineCandidate.ExplicitGoogleComponent>()
            for (pkg in GOOGLE_SPEECH_PACKAGES) {
                val matches = resolved.mapNotNull { it.serviceInfo }
                    .filter { it.packageName == pkg && it.exported }
                for (svc in matches) {
                    val cn = ComponentName(svc.packageName, svc.name)
                    if (googleComponents.none { it.componentName == cn }) {
                        googleComponents.add(EngineCandidate.ExplicitGoogleComponent(cn))
                    }
                }
            }
            // Catch any additional exported `com.google.*` recognition service
            for (info in resolved) {
                val svc = info.serviceInfo ?: continue
                if (!svc.exported || !svc.packageName.startsWith("com.google.")) continue
                // Skip Android System Intelligence (`com.google.android.as`) which lacks vi-VN pack
                if (svc.packageName == "com.google.android.as") continue
                val cn = ComponentName(svc.packageName, svc.name)
                if (googleComponents.none { it.componentName == cn }) {
                    googleComponents.add(EngineCandidate.ExplicitGoogleComponent(cn))
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
            // 1. Always prioritize explicit Google Speech Services (`com.google.android.tts`, `googlequicksearchbox`)!
            ordered.addAll(googleComponents)

            // 2. Include Android System Broker Default ONLY after Google explicit services (rescue for Pixel/AOSP
            //    where system broker proxies to Google, while skipping known non-Vietnamese OEM stubs when Google exists).
            if (isSysAvailable && (!isDefaultNonVnOem || googleComponents.isEmpty())) {
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
            val candidates = discoverCandidates(context)
                .map { it.label }
            val hasGoogleDialog = resolveGoogleSpeechDialogIntent(context) != null
            val isRecognitionAvailable = candidates.isNotEmpty() || hasGoogleDialog

            return mapOf(
                "hardwareMicAvailable" to hasMicHardware,
                "hasRecordPermission" to hasRecordPerm,
                "isRecognitionAvailable" to isRecognitionAvailable,
                "isOnDeviceAvailable" to candidates.any { it.startsWith("service:com.google.") },
                "hasSystemSpeechDialog" to hasGoogleDialog,
                "availableEngines" to candidates,
                "activeEngineLabel" to (activeEngineLabel ?: candidates.firstOrNull() ?: "service:com.google.android.tts"),
                "sdkInt" to Build.VERSION.SDK_INT,
                "manufacturer" to (Build.MANUFACTURER ?: "unknown")
            )
        }
    }

    fun startListening(
        preferSystemDialog: Boolean = false,
        engineMode: String = "google_service"
    ) {
        runOnMain {
            val sessionId = nextVoiceSession()
            clearTimers()
            LifeOsSoundboxSpeaker.stopSpeaking()
            val hadPreviousRecognizer = teardownCurrentRecognizer(abortInFlight = true)

            if (preferSystemDialog || engineMode == "system_dialog") {
                launchDialogOrFallbackInline(sessionId, hadPreviousRecognizer)
                return@runOnMain
            }

            onStateChanged("initializing")

            val candidates = discoverCandidates(activity, engineMode = engineMode)
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
            onStateChanged("idle")
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
            launchDialogOrReportError(sessionId)
            return
        }

        val candidate = candidates[candidateIndex]
        val attemptStartedAtMs = System.currentTimeMillis()

        try {
            teardownCurrentRecognizer(abortInFlight = true)
            val sr = when (candidate) {
                is EngineCandidate.ExplicitGoogleComponent ->
                    SpeechRecognizer.createSpeechRecognizer(activity, candidate.componentName)
                is EngineCandidate.SystemBrokerDefault ->
                    SpeechRecognizer.createSpeechRecognizer(activity)
            }
            speechRecognizer = sr
            lastResolvedEngineLabel = candidate.label

            var lastPartialTranscript = ""
            var receivedAnyCallback = false
            var announcedListening = false
            var sessionConcluded = false

            activeStopFlushHook = {
                if (sessionId == activeSessionId && !sessionConcluded) {
                    sessionConcluded = true
                    clearTimers()
                    val captured = lastPartialTranscript.trim()
                    lastPartialTranscript = ""
                    teardownCurrentRecognizer(abortInFlight = true)
                    if (captured.isNotEmpty()) {
                        onFinalTranscript(captured)
                    } else {
                        onStateChanged("idle")
                    }
                }
            }

            val watchdog = Runnable {
                if (sessionId != activeSessionId || receivedAnyCallback || sessionConcluded) {
                    return@Runnable
                }
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
                    clearStartupWatchdogOnly()
                    if (!announcedListening) {
                        announcedListening = true
                        onStateChanged("listening")
                    }
                }

                override fun onRmsChanged(rmsdB: Float) {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    if (receivedAnyCallback) {
                        onRmsChanged(rmsdB.toDouble())
                    }
                }

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    receivedAnyCallback = true
                    clearStartupWatchdogOnly()
                    onStateChanged("processing")
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    receivedAnyCallback = true
                    clearStartupWatchdogOnly()
                    if (!announcedListening) {
                        announcedListening = true
                        onStateChanged("listening")
                    }
                    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull().orEmpty().trim()
                    if (text.isNotEmpty()) {
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
                        onFinalTranscript(text)
                    } else if (System.currentTimeMillis() - attemptStartedAtMs < FAST_REJECT_THRESHOLD_MS) {
                        // Immediate empty result (< 1.4s) means this candidate rejected vi-VN -> cascade!
                        val nextRun = Runnable {
                            if (preferOffline) {
                                attemptCandidate(
                                    sessionId = sessionId,
                                    candidates = candidates,
                                    candidateIndex = candidateIndex,
                                    retriedBusy = retriedBusy,
                                    preferOffline = false,
                                    silentTimeoutRetries = silentTimeoutRetries
                                )
                            } else {
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
                        pendingStartRunnable = nextRun
                        mainHandler.postDelayed(nextRun, BINDER_COOLDOWN_MS)
                    } else {
                        onStateChanged("idle")
                        onError(
                            "NO_MATCH",
                            "Chưa nghe rõ câu nói. Bạn hãy bấm Mic nói lại hoặc gõ bên dưới."
                        )
                    }
                }

                override fun onError(error: Int) {
                    if (sessionId != activeSessionId || sessionConcluded) return
                    sessionConcluded = true
                    receivedAnyCallback = true
                    clearTimers()
                    val elapsedMs = System.currentTimeMillis() - attemptStartedAtMs

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
                        onFinalTranscript(captured)
                        return
                    }

                    // 2. If `preferOffline` failed (e.g. Vietnamese offline pack not downloaded yet),
                    // retry the exact same Google Speech candidate ONLINE (`preferOffline = false`) immediately!
                    if (preferOffline) {
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

                    // 4. Genuine silence timeout (>= 1.4s) while user paused thinking -> re-arm once cleanly
                    if (lastPartialTranscript.isBlank() &&
                        elapsedMs >= FAST_REJECT_THRESHOLD_MS &&
                        error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT &&
                        silentTimeoutRetries < MAX_INITIAL_SILENCE_RETRIES &&
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

                    val hasAudioPerm = ContextCompat.checkSelfPermission(
                        activity,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED

                    // 5. Cascade to next Google candidate / Google System Speech Dialog if this candidate
                    // rejected binding, lacked vi-VN support, or fast-rejected in < 1.4s!
                    val shouldCascadeEngine = when (error) {
                        SpeechRecognizer.ERROR_CLIENT,
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                        SpeechRecognizer.ERROR_SERVER,
                        SpeechRecognizer.ERROR_AUDIO,
                        ERR_TOO_MANY_REQUESTS,
                        ERR_SERVER_DISCONNECTED,
                        ERR_LANGUAGE_NOT_SUPPORTED,
                        ERR_LANGUAGE_UNAVAILABLE,
                        ERR_CANNOT_CHECK_SUPPORT -> true
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> hasAudioPerm
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> elapsedMs < FAST_REJECT_THRESHOLD_MS
                        else -> false
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

                    onStateChanged("idle")
                    val (errCode, friendlyMsg) = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                            "PERMISSION_DENIED" to "Vui lòng cấp quyền Micro để thu âm giọng nói."
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                            "NO_MATCH" to "Chưa nghe rõ giọng nói. Bấm Mic để nói lại nhé."
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
                context = activity,
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
                onStateChanged("listening")
                return
            }
        }

        // If device has Google TTS background service without Search App's dialog Activity,
        // seamlessly run Google Speech inline instead of failing!
        val hasAudioPerm = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        val googleCandidates = discoverCandidates(activity, engineMode = "google_service")
        if (hasAudioPerm && googleCandidates.isNotEmpty()) {
            onStateChanged("initializing")
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

        onStateChanged("idle")
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
            onStateChanged("listening")
        } else {
            onStateChanged("idle")
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
