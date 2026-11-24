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
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat

/**
 * Multi-engine Vietnamese Speech Recognition coordinator for Android 10–15 (Samsung One UI,
 * Xiaomi HyperOS/MIUI, OPPO ColorOS, Vivo OriginOS, Pixel/AOSP).
 *
 * Fixes key real-device failures:
 * 1. Prioritizes Google Speech Services (`com.google.android.tts` / `com.google.android.googlequicksearchbox`)
 *    over broken OEM default `RecognitionService` stubs, then cascades to system default and finally
 *    to Android's `RecognizerIntent.ACTION_RECOGNIZE_SPEECH` dialog.
 * 2. Avoids broken `EXTRA_SPEECH_INPUT_*_SILENCE_LENGTH_MILLIS` extras that cause immediate
 *    `ERROR_NO_MATCH` / `ERROR_CLIENT` on Android 12–15 Google Speech Services.
 * 3. Enforces Main-Looper execution, monotonic `sessionId` callback isolation, an `85ms` Binder
 *    teardown cooldown between sessions, a `4000ms` silent-hang watchdog, and 1x retry on
 *    `ERROR_RECOGNIZER_BUSY` / offline fallback on `ERROR_NETWORK`.
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
    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var activeSessionId: Int = 0
    private var startupWatchdog: Runnable? = null
    private var pendingStartRunnable: Runnable? = null

    companion object {
        private const val RECOGNITION_SERVICE_ACTION = "android.speech.RecognitionService"
        private const val BINDER_COOLDOWN_MS = 85L
        private const val BUSY_RETRY_DELAY_MS = 220L
        private const val STARTUP_WATCHDOG_MS = 4200L

        private val PREFERRED_GOOGLE_PACKAGES = listOf(
            "com.google.android.tts",
            "com.google.android.googlequicksearchbox"
        )

        // Android 12+ additional SpeechRecognizer error codes
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
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
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

        fun discoverCandidateComponents(context: Context): List<ComponentName?> {
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

            val candidates = mutableListOf<ComponentName?>()
            for (pkg in PREFERRED_GOOGLE_PACKAGES) {
                val match = resolved.firstOrNull { it.serviceInfo?.packageName == pkg }?.serviceInfo
                if (match != null && match.exported) {
                    candidates.add(ComponentName(match.packageName, match.name))
                }
            }
            // System default SpeechRecognizer (null ComponentName) as fallback before system dialog
            candidates.add(null)
            return candidates.distinct()
        }
    }

    fun startListening(preferSystemDialog: Boolean = false) {
        runOnMain {
            val sessionId = activeVoiceSession()
            clearTimers()
            val hadPreviousRecognizer = teardownCurrentRecognizer()

            if (preferSystemDialog) {
                launchDialogOrReportError(sessionId)
                return@runOnMain
            }

            val candidates = discoverCandidateComponents(activity)
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
                    triedOffline = false
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
            clearTimers()
            val sr = speechRecognizer
            if (sr != null) {
                try {
                    sr.stopListening()
                } catch (_: Exception) {
                    onStateChanged("idle")
                }
            } else {
                onStateChanged("idle")
            }
        }
    }

    fun cancelListening() {
        runOnMain {
            activeVoiceSession()
            clearTimers()
            teardownCurrentRecognizer()
            onStateChanged("idle")
        }
    }

    fun destroy() {
        runOnMain {
            activeVoiceSession()
            clearTimers()
            teardownCurrentRecognizer()
        }
    }

    private fun activeVoiceSession(): Int {
        activeSessionId += 1
        return activeSessionId
    }

    private fun clearTimers() {
        startupWatchdog?.let { mainHandler.removeCallbacks(it) }
        startupWatchdog = null
        pendingStartRunnable?.let { mainHandler.removeCallbacks(it) }
        pendingStartRunnable = null
    }

    private fun teardownCurrentRecognizer(): Boolean {
        val prev = speechRecognizer ?: return false
        speechRecognizer = null
        try {
            prev.setRecognitionListener(null)
        } catch (_: Exception) {
        }
        try {
            prev.cancel()
        } catch (_: Exception) {
        }
        try {
            prev.destroy()
        } catch (_: Exception) {
        }
        return true
    }

    private fun attemptCandidate(
        sessionId: Int,
        candidates: List<ComponentName?>,
        candidateIndex: Int,
        retriedBusy: Boolean,
        triedOffline: Boolean
    ) {
        if (sessionId != activeSessionId || activity.isFinishing || activity.isDestroyed) return

        if (candidateIndex >= candidates.size) {
            launchDialogOrReportError(sessionId)
            return
        }

        val component = candidates[candidateIndex]
        if (component == null && !SpeechRecognizer.isRecognitionAvailable(activity)) {
            launchDialogOrReportError(sessionId)
            return
        }

        try {
            teardownCurrentRecognizer()
            val sr = if (component != null) {
                SpeechRecognizer.createSpeechRecognizer(activity, component)
            } else {
                SpeechRecognizer.createSpeechRecognizer(activity)
            }
            speechRecognizer = sr

            var lastPartialTranscript = ""
            var receivedAnyCallback = false

            val watchdog = Runnable {
                if (sessionId != activeSessionId || receivedAnyCallback) return@Runnable
                // Recognizer service hung silently without binding or emitting Ready/Error -> cascade!
                teardownCurrentRecognizer()
                attemptCandidate(
                    sessionId = sessionId,
                    candidates = candidates,
                    candidateIndex = candidateIndex + 1,
                    retriedBusy = false,
                    triedOffline = false
                )
            }
            startupWatchdog = watchdog
            mainHandler.postDelayed(watchdog, STARTUP_WATCHDOG_MS)

            sr.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    if (sessionId != activeSessionId) return
                    receivedAnyCallback = true
                    clearWatchdogOnly()
                    onStateChanged("listening")
                }

                override fun onBeginningOfSpeech() {
                    if (sessionId != activeSessionId) return
                    receivedAnyCallback = true
                    clearWatchdogOnly()
                    onStateChanged("listening")
                }

                override fun onRmsChanged(rmsdB: Float) {
                    if (sessionId != activeSessionId) return
                    if (receivedAnyCallback) {
                        onRmsChanged(rmsdB.toDouble())
                    }
                }

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {
                    if (sessionId != activeSessionId) return
                    receivedAnyCallback = true
                    clearWatchdogOnly()
                    onStateChanged("processing")
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    if (sessionId != activeSessionId) return
                    receivedAnyCallback = true
                    clearWatchdogOnly()
                    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull().orEmpty().trim()
                    if (text.isNotEmpty()) {
                        lastPartialTranscript = text
                        onPartialTranscript(text)
                    }
                }

                override fun onResults(results: Bundle?) {
                    if (sessionId != activeSessionId) return
                    receivedAnyCallback = true
                    clearTimers()
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
                        ?: lastPartialTranscript
                    lastPartialTranscript = ""
                    teardownCurrentRecognizer()
                    if (text.isNotEmpty()) {
                        onFinalTranscript(text)
                    } else {
                        onStateChanged("idle")
                        onError(
                            "NO_MATCH",
                            "Chưa nghe rõ câu nói. Bạn hãy bấm Mic nói lại hoặc gõ bên dưới."
                        )
                    }
                }

                override fun onError(error: Int) {
                    if (sessionId != activeSessionId) return
                    receivedAnyCallback = true
                    clearTimers()

                    // 1. Preserve spoken partial text when recognizer closes on silence/client timeout!
                    if (lastPartialTranscript.isNotBlank() &&
                        (error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                            error == SpeechRecognizer.ERROR_NO_MATCH ||
                            error == SpeechRecognizer.ERROR_CLIENT)
                    ) {
                        val captured = lastPartialTranscript
                        lastPartialTranscript = ""
                        teardownCurrentRecognizer()
                        onFinalTranscript(captured)
                        return
                    }

                    // 2. Retry once if Binder is still releasing previous session
                    if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY && !retriedBusy) {
                        teardownCurrentRecognizer()
                        val retryRun = Runnable {
                            attemptCandidate(
                                sessionId = sessionId,
                                candidates = candidates,
                                candidateIndex = candidateIndex,
                                retriedBusy = true,
                                triedOffline = triedOffline
                            )
                        }
                        pendingStartRunnable = retryRun
                        mainHandler.postDelayed(retryRun, BUSY_RETRY_DELAY_MS)
                        return
                    }

                    // 3. Retry once with offline language pack preference on network failure
                    if ((error == SpeechRecognizer.ERROR_NETWORK ||
                            error == SpeechRecognizer.ERROR_NETWORK_TIMEOUT) &&
                        !triedOffline &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                    ) {
                        teardownCurrentRecognizer()
                        attemptCandidate(
                            sessionId = sessionId,
                            candidates = candidates,
                            candidateIndex = candidateIndex,
                            retriedBusy = retriedBusy,
                            triedOffline = true
                        )
                        return
                    }

                    val hasAudioPerm = ContextCompat.checkSelfPermission(
                        activity,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED

                    // 4. Cascade to next engine / System Speech Dialog if this engine rejected binding or vi-VN!
                    val shouldCascadeEngine = when (error) {
                        SpeechRecognizer.ERROR_CLIENT,
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                        ERR_TOO_MANY_REQUESTS,
                        ERR_SERVER_DISCONNECTED,
                        ERR_LANGUAGE_NOT_SUPPORTED,
                        ERR_LANGUAGE_UNAVAILABLE,
                        ERR_CANNOT_CHECK_SUPPORT -> true
                        // OEM services sometimes return ERROR_INSUFFICIENT_PERMISSIONS even when RECORD_AUDIO is granted
                        // because they guard their service with a signature-only OEM permission!
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> hasAudioPerm
                        else -> false
                    }

                    teardownCurrentRecognizer()
                    if (shouldCascadeEngine) {
                        attemptCandidate(
                            sessionId = sessionId,
                            candidates = candidates,
                            candidateIndex = candidateIndex + 1,
                            retriedBusy = false,
                            triedOffline = false
                        )
                        return
                    }

                    onStateChanged("idle")
                    val (errCode, friendlyMsg) = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                            "PERMISSION_DENIED" to "Vui lòng cấp quyền Micro để thu âm giọng nói."
                        SpeechRecognizer.ERROR_AUDIO ->
                            "AUDIO_BUSY" to "Micro đang bận bởi ứng dụng khác. Hãy thử bấm nói lại."
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                            "NO_MATCH" to "Chưa nghe rõ giọng nói. Bấm Mic để nói lại nhé."
                        SpeechRecognizer.ERROR_NETWORK,
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                            "NETWORK_ERROR" to "Mạng gián đoạn khi nhận diện giọng nói. Hãy kiểm tra kết nối hoặc tải gói tiếng Việt offline."
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
                preferOffline = triedOffline
            )
            onStateChanged("listening")
            sr.startListening(recIntent)
        } catch (_: Exception) {
            clearTimers()
            teardownCurrentRecognizer()
            attemptCandidate(
                sessionId = sessionId,
                candidates = candidates,
                candidateIndex = candidateIndex + 1,
                retriedBusy = false,
                triedOffline = false
            )
        }
    }

    private fun clearWatchdogOnly() {
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
