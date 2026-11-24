package vn.lifeos.app.life_os

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat

/**
 * Production-hardened Vietnamese Speech Recognition Coordinator for Android 10–16
 * (Samsung One UI, Xiaomi HyperOS/MIUI, OPPO ColorOS, Vivo OriginOS, Pixel/AOSP).
 *
 * Key architectural guarantees (aligned with upstream `csdcorp/speech_to_text` & Android 14–16 Binder rules):
 * 1. **System-Broker First**: Uses `SpeechRecognizer.createSpeechRecognizer(context)` (default `null`
 *    component) FIRST whenever `isRecognitionAvailable` is true so Android's system-server broker
 *    handles `BIND_RECOGNITION_SERVICE` without signature-permission rejection on Android 12–16.
 *    Cascades to explicit exported Google/OEM `RecognitionService` components, then Android 13+
 *    `createOnDeviceSpeechRecognizer`, and finally Android's `ACTION_RECOGNIZE_SPEECH` system sheet.
 * 2. **Deferred Safe Destroy (`60ms`)**: Never calls `SpeechRecognizer.destroy()` synchronously inside
 *    `RecognitionListener.onResults`/`onError` stack frames, preventing Binder `Service not registered`
 *    crashes and stuck `ERROR_RECOGNIZER_BUSY` states on rapid re-taps.
 * 3. **Exclusive Transient Audio Focus + Soundbox Mute**: Pauses competing media/TTS streams cleanly
 *    before opening the mic and abandons audio focus immediately upon completion/teardown.
 * 4. **Stop-Completion Watchdog (`1350ms`)**: Guarantees `stopListening()` never hangs indefinitely
 *    in `"processing"` when OEM speech services drop the final `onResults` callback.
 * 5. **Pre-Speech Silence Keep-Alive**: Seamlessly re-arms up to 2 times if Android times out with
 *    `ERROR_SPEECH_TIMEOUT`/`ERROR_NO_MATCH` before the user utters their first syllable.
 * 6. **Android 13+ Contextual Biasing**: Supplies `EXTRA_BIASING_STRINGS` for Vietnamese currency
 *    units, slang (`k`, `cành`, `củ`, `tr`), and daily LifeOS domains.
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
        data object SystemBrokerDefault : EngineCandidate("system_default")
        data class ExplicitComponent(val componentName: ComponentName) :
            EngineCandidate("service:${componentName.packageName}")
        data object OnDeviceRecognizer : EngineCandidate("on_device_android13")
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var activeSessionId: Int = 0
    private var startupWatchdog: Runnable? = null
    private var stopFinalizeWatchdog: Runnable? = null
    private var pendingStartRunnable: Runnable? = null
    private var activeStopFlushHook: (() -> Unit)? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus: Boolean = false

    @Volatile
    var lastResolvedEngineLabel: String = "chưa khởi tạo"
        private set

    companion object {
        private const val RECOGNITION_SERVICE_ACTION = "android.speech.RecognitionService"
        private const val BINDER_COOLDOWN_MS = 90L
        private const val DEFERRED_DESTROY_MS = 60L
        private const val BUSY_RETRY_DELAY_MS = 220L
        private const val SILENT_KEEPALIVE_DELAY_MS = 95L
        private const val STARTUP_WATCHDOG_MS = 1850L
        private const val STOP_FINALIZE_WATCHDOG_MS = 1350L
        private const val MAX_INITIAL_SILENCE_RETRIES = 2

        private val PREFERRED_SPEECH_PACKAGES = listOf(
            "com.google.android.tts",
            "com.google.android.googlequicksearchbox",
            "com.samsung.android.bixby.agent",
            "com.samsung.android.scs",
            "com.xiaomi.mibrain.speech",
            "com.heytap.speechassist",
            "com.vivo.aiengine"
        )

        private val VIETNAMESE_BIASING_PHRASES = arrayListOf(
            "nghìn",
            "triệu",
            "chục nghìn",
            "trăm nghìn",
            "cành",
            "củ",
            "chia đều",
            "ăn sáng",
            "ăn trưa",
            "ăn tối",
            "phở bò",
            "cà phê",
            "trà sữa",
            "đổ xăng",
            "siêu thị",
            "chuyển khoản",
            "tiền điện",
            "tiền nhà",
            "nhận lương",
            "uống nước",
            "ml nước",
            "uống thuốc",
            "lịch họp",
            "nhắc việc"
        )

        // Android 12–14+ extended SpeechRecognizer error codes
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
                putExtra("android.speech.extra.EXTRA_ADDITIONAL_LANGUAGES", arrayOf("vi-VN", "vi"))
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, !forSystemDialog)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                if (preferOffline && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                }
                if (!forSystemDialog && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    putStringArrayListExtra(
                        RecognizerIntent.EXTRA_BIASING_STRINGS,
                        VIETNAMESE_BIASING_PHRASES
                    )
                }
                if (forSystemDialog) {
                    putExtra(
                        RecognizerIntent.EXTRA_PROMPT,
                        "Mời bạn nói tiếng Việt (VD: Ăn phở 55 nghìn)"
                    )
                }
            }
        }

        fun discoverCandidates(
            context: Context,
            engineMode: String = "auto"
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

            val explicitComponents = mutableListOf<EngineCandidate.ExplicitComponent>()
            for (pkg in PREFERRED_SPEECH_PACKAGES) {
                val match = resolved.firstOrNull { it.serviceInfo?.packageName == pkg }?.serviceInfo
                if (match != null && match.exported) {
                    explicitComponents.add(
                        EngineCandidate.ExplicitComponent(
                            ComponentName(match.packageName, match.name)
                        )
                    )
                }
            }
            for (info in resolved) {
                val svc = info.serviceInfo ?: continue
                if (!svc.exported) continue
                val cn = ComponentName(svc.packageName, svc.name)
                if (explicitComponents.none { it.componentName == cn }) {
                    explicitComponents.add(EngineCandidate.ExplicitComponent(cn))
                }
            }

            val isSysAvailable = try {
                SpeechRecognizer.isRecognitionAvailable(context)
            } catch (_: Exception) {
                false
            }
            val isOnDeviceAvailable = try {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
            } catch (_: Exception) {
                false
            }

            val ordered = mutableListOf<EngineCandidate>()
            when (engineMode) {
                "on_device" -> {
                    if (isOnDeviceAvailable) ordered.add(EngineCandidate.OnDeviceRecognizer)
                    if (isSysAvailable) ordered.add(EngineCandidate.SystemBrokerDefault)
                    ordered.addAll(explicitComponents)
                }
                "google_service" -> {
                    ordered.addAll(
                        explicitComponents.filter {
                            it.componentName.packageName.startsWith("com.google.")
                        }
                    )
                    if (isSysAvailable) ordered.add(EngineCandidate.SystemBrokerDefault)
                    if (isOnDeviceAvailable) ordered.add(EngineCandidate.OnDeviceRecognizer)
                }
                else -> {
                    // 1. Android OS System Broker Default FIRST (avoids Android 12–16 BIND_RECOGNITION_SERVICE errors!)
                    if (isSysAvailable) {
                        ordered.add(EngineCandidate.SystemBrokerDefault)
                    }
                    // 2. Explicit Google / OEM services next (rescues ROMs with broken default stubs)
                    ordered.addAll(explicitComponents)
                    // 3. Android 13+ On-Device offline recognizer fallback
                    if (isOnDeviceAvailable) {
                        ordered.add(EngineCandidate.OnDeviceRecognizer)
                    }
                }
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
            val isRecognitionAvailable = try {
                SpeechRecognizer.isRecognitionAvailable(context)
            } catch (_: Exception) {
                false
            }
            val isOnDeviceAvailable = try {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
            } catch (_: Exception) {
                false
            }
            val dialogIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            val hasSystemDialog = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.resolveActivity(dialogIntent, PackageManager.ResolveInfoFlags.of(0)) != null
                } else {
                    @Suppress("DEPRECATION")
                    pm.resolveActivity(dialogIntent, 0) != null
                }
            } catch (_: Exception) {
                false
            }
            val candidates = discoverCandidates(context)
                .map { it.label }

            return mapOf(
                "hardwareMicAvailable" to hasMicHardware,
                "hasRecordPermission" to hasRecordPerm,
                "isRecognitionAvailable" to isRecognitionAvailable,
                "isOnDeviceAvailable" to isOnDeviceAvailable,
                "hasSystemSpeechDialog" to hasSystemDialog,
                "availableEngines" to candidates,
                "activeEngineLabel" to (activeEngineLabel ?: "auto"),
                "sdkInt" to Build.VERSION.SDK_INT,
                "manufacturer" to (Build.MANUFACTURER ?: "unknown")
            )
        }
    }

    fun startListening(
        preferSystemDialog: Boolean = false,
        engineMode: String = "auto"
    ) {
        runOnMain {
            val sessionId = nextVoiceSession()
            clearTimers()
            LifeOsSoundboxSpeaker.stopSpeaking()
            val hadPreviousRecognizer = teardownCurrentRecognizer(abortInFlight = true)

            if (preferSystemDialog || engineMode == "system_dialog") {
                abandonAudioFocus()
                launchDialogOrReportError(sessionId)
                return@runOnMain
            }

            requestTransientAudioFocus()
            onStateChanged("initializing")

            val candidates = discoverCandidates(activity, engineMode = engineMode)
            val delayMs = if (hadPreviousRecognizer) BINDER_COOLDOWN_MS else 0L
            val runnable = Runnable {
                if (sessionId != activeSessionId || activity.isFinishing || activity.isDestroyed) {
                    abandonAudioFocus()
                    return@Runnable
                }
                attemptCandidate(
                    sessionId = sessionId,
                    candidates = candidates,
                    candidateIndex = 0,
                    retriedBusy = false,
                    triedOffline = engineMode == "on_device",
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
                    // OEM engine never delivered final `onResults` after `sr.stopListening()` -> flush cleanly!
                    if (flushHook != null) {
                        flushHook.invoke()
                    } else {
                        teardownCurrentRecognizer(abortInFlight = true)
                        abandonAudioFocus()
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
                        abandonAudioFocus()
                        onStateChanged("idle")
                    }
                }
            } else {
                abandonAudioFocus()
                onStateChanged("idle")
            }
        }
    }

    fun cancelListening() {
        runOnMain {
            nextVoiceSession()
            clearTimers()
            teardownCurrentRecognizer(abortInFlight = true)
            abandonAudioFocus()
            onStateChanged("idle")
        }
    }

    fun destroy() {
        runOnMain {
            nextVoiceSession()
            clearTimers()
            teardownCurrentRecognizer(abortInFlight = true)
            abandonAudioFocus()
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

    /**
     * Detaches the current [SpeechRecognizer] immediately and destroys it asynchronously after
     * [DEFERRED_DESTROY_MS] on the Main Looper — avoiding Android Binder corruption when invoked
     * from inside [RecognitionListener.onResults] or [RecognitionListener.onError].
     */
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

    private fun requestTransientAudioFocus() {
        if (hasAudioFocus) return
        val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    .setAudioAttributes(attrs)
                    .setAcceptsDelayedFocusGain(false)
                    .setOnAudioFocusChangeListener { }
                    .build()
                audioFocusRequest = req
                hasAudioFocus = audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                @Suppress("DEPRECATION")
                hasAudioFocus = audioManager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_VOICE_CALL,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
                ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        } catch (_: Exception) {
        }
    }

    private fun abandonAudioFocus() {
        if (!hasAudioFocus && audioFocusRequest == null) return
        hasAudioFocus = false
        val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
                audioFocusRequest = null
            } else {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(null)
            }
        } catch (_: Exception) {
        }
    }

    private fun attemptCandidate(
        sessionId: Int,
        candidates: List<EngineCandidate>,
        candidateIndex: Int,
        retriedBusy: Boolean,
        triedOffline: Boolean,
        silentTimeoutRetries: Int
    ) {
        if (sessionId != activeSessionId || activity.isFinishing || activity.isDestroyed) {
            abandonAudioFocus()
            return
        }

        if (candidateIndex >= candidates.size) {
            abandonAudioFocus()
            launchDialogOrReportError(sessionId)
            return
        }

        val candidate = candidates[candidateIndex]
        try {
            teardownCurrentRecognizer(abortInFlight = true)
            val sr = when (candidate) {
                is EngineCandidate.SystemBrokerDefault ->
                    SpeechRecognizer.createSpeechRecognizer(activity)
                is EngineCandidate.ExplicitComponent ->
                    SpeechRecognizer.createSpeechRecognizer(activity, candidate.componentName)
                is EngineCandidate.OnDeviceRecognizer -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
                    } else {
                        SpeechRecognizer.createSpeechRecognizer(activity)
                    }
                }
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
                    abandonAudioFocus()
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
                // Candidate hung silently without binding -> cascade to next candidate immediately!
                teardownCurrentRecognizer(abortInFlight = true)
                attemptCandidate(
                    sessionId = sessionId,
                    candidates = candidates,
                    candidateIndex = candidateIndex + 1,
                    retriedBusy = false,
                    triedOffline = false,
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
                    abandonAudioFocus()
                    if (text.isNotEmpty()) {
                        onFinalTranscript(text)
                    } else if (silentTimeoutRetries < MAX_INITIAL_SILENCE_RETRIES) {
                        // Empty results before user started talking -> keep mic alive seamlessly!
                        requestTransientAudioFocus()
                        val keepAliveRun = Runnable {
                            attemptCandidate(
                                sessionId = sessionId,
                                candidates = candidates,
                                candidateIndex = candidateIndex,
                                retriedBusy = false,
                                triedOffline = triedOffline,
                                silentTimeoutRetries = silentTimeoutRetries + 1
                            )
                        }
                        pendingStartRunnable = keepAliveRun
                        mainHandler.postDelayed(keepAliveRun, SILENT_KEEPALIVE_DELAY_MS)
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

                    // 1. Rescue spoken partial text when recognizer closes on silence/client/no-match!
                    if (lastPartialTranscript.isNotBlank() &&
                        (error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                            error == SpeechRecognizer.ERROR_NO_MATCH ||
                            error == SpeechRecognizer.ERROR_CLIENT ||
                            error == SpeechRecognizer.ERROR_SERVER)
                    ) {
                        val captured = lastPartialTranscript.trim()
                        lastPartialTranscript = ""
                        teardownCurrentRecognizer(abortInFlight = false)
                        abandonAudioFocus()
                        onFinalTranscript(captured)
                        return
                    }

                    // 2. Seamless Pre-Speech Keep-Alive: if user paused thinking before first word,
                    // re-arm silently up to 2 times instead of killing the mic!
                    if (lastPartialTranscript.isBlank() &&
                        (error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                            error == SpeechRecognizer.ERROR_NO_MATCH) &&
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
                                triedOffline = triedOffline,
                                silentTimeoutRetries = silentTimeoutRetries + 1
                            )
                        }
                        pendingStartRunnable = keepAliveRun
                        mainHandler.postDelayed(keepAliveRun, SILENT_KEEPALIVE_DELAY_MS)
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
                                triedOffline = triedOffline,
                                silentTimeoutRetries = silentTimeoutRetries
                            )
                        }
                        pendingStartRunnable = retryRun
                        mainHandler.postDelayed(retryRun, BUSY_RETRY_DELAY_MS)
                        return
                    }

                    // 4. Retry once with offline language pack preference on network failure
                    if ((error == SpeechRecognizer.ERROR_NETWORK ||
                            error == SpeechRecognizer.ERROR_NETWORK_TIMEOUT ||
                            error == SpeechRecognizer.ERROR_SERVER ||
                            error == ERR_SERVER_DISCONNECTED) &&
                        !triedOffline &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        candidate !is EngineCandidate.OnDeviceRecognizer
                    ) {
                        teardownCurrentRecognizer(abortInFlight = false)
                        val offlineRun = Runnable {
                            attemptCandidate(
                                sessionId = sessionId,
                                candidates = candidates,
                                candidateIndex = candidateIndex,
                                retriedBusy = retriedBusy,
                                triedOffline = true,
                                silentTimeoutRetries = silentTimeoutRetries
                            )
                        }
                        pendingStartRunnable = offlineRun
                        mainHandler.postDelayed(offlineRun, BINDER_COOLDOWN_MS)
                        return
                    }

                    val hasAudioPerm = ContextCompat.checkSelfPermission(
                        activity,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED

                    // 5. Cascade to next candidate / System Speech Dialog if this engine rejected binding or vi-VN!
                    val shouldCascadeEngine = when (error) {
                        SpeechRecognizer.ERROR_CLIENT,
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                        ERR_TOO_MANY_REQUESTS,
                        ERR_SERVER_DISCONNECTED,
                        ERR_LANGUAGE_NOT_SUPPORTED,
                        ERR_LANGUAGE_UNAVAILABLE,
                        ERR_CANNOT_CHECK_SUPPORT -> true
                        // Direct service binding may emit ERROR_INSUFFICIENT_PERMISSIONS even when RECORD_AUDIO
                        // is granted if an OEM service guards binding with a signature permission!
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> hasAudioPerm
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
                                triedOffline = false,
                                silentTimeoutRetries = silentTimeoutRetries
                            )
                        }
                        pendingStartRunnable = cascadeRun
                        mainHandler.postDelayed(cascadeRun, BINDER_COOLDOWN_MS)
                        return
                    }

                    abandonAudioFocus()
                    onStateChanged("idle")
                    val (errCode, friendlyMsg) = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                            "PERMISSION_DENIED" to "Vui lòng cấp quyền Micro để thu âm giọng nói."
                        SpeechRecognizer.ERROR_AUDIO ->
                            "AUDIO_BUSY" to "Micro đang bận bởi ứng dụng khác hoặc tai nghe Bluetooth. Hãy thử bấm nói lại."
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                            "NO_MATCH" to "Chưa nghe rõ giọng nói. Bấm Mic để nói lại nhé."
                        SpeechRecognizer.ERROR_NETWORK,
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                            "NETWORK_ERROR" to "Mạng gián đoạn khi nhận diện giọng nói. Hãy kiểm tra kết nối hoặc dùng Thu âm hệ thống."
                        else ->
                            "SPEECH_ERROR_$error" to "Tạm ngưng thu âm. Bạn có thể bấm Mic nói lại hoặc dùng Thu âm hệ thống."
                    }
                    onError(errCode, friendlyMsg)
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            val recIntent = buildVietnameseSpeechIntent(
                context = activity,
                forSystemDialog = false,
                preferOffline = triedOffline || candidate is EngineCandidate.OnDeviceRecognizer
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
                    triedOffline = false,
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

    private fun launchDialogOrReportError(sessionId: Int) {
        if (sessionId != activeSessionId) return
        val dialogIntent = buildVietnameseSpeechIntent(
            context = activity,
            forSystemDialog = true,
            preferOffline = false
        )
        val launched = try {
            lastResolvedEngineLabel = "system_speech_dialog"
            onLaunchSystemDialog(dialogIntent)
        } catch (_: Exception) {
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
