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
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat
import java.util.UUID

/**
 * LifeOS v2 Speech Recognition Coordinator (VOICE-001..008, Section 6 & 13):
 * - Public Android `SpeechRecognizer` API first (`createSpeechRecognizer` / API 31+ `createOnDeviceSpeechRecognizer`).
 * - Real API 33+ `checkRecognitionSupport` inspection without faking offline availability on API < 31.
 * - Strictly monotonic timeouts (`SystemClock.elapsedRealtime()`) and `(sessionId, attemptId, generation)` guards.
 * - Zero dead-mic RMS watchdogs, zero silent online fallback in offline mode, zero infinite retries.
 * - Deterministic AudioFocus & Soundbox TTS mutual exclusion on every entry and terminal exit.
 */
class LifeOsSpeechRecognizerHelper(
    private val activity: Activity,
    private val ownerId: String = VoiceSessionCoordinatorNative.OWNER_MAIN_ACTIVITY,
    private val onEnvelopeEvent: ((Map<String, Any?>) -> Unit)? = null,
    private val onStateChanged: (String) -> Unit = {},
    private val onRmsChanged: (Double) -> Unit = {},
    private val onPartialTranscript: (String) -> Unit = {},
    private val onFinalTranscript: (String) -> Unit = {},
    private val onError: (code: String, message: String) -> Unit = { _, _ -> },
    private val onLaunchSystemDialog: (intent: Intent, sessionId: String, attemptId: Int) -> Boolean,
    private val onEngineAutoSwitched: ((String) -> Unit)? = null,
    private val onDialogStateChanged: ((Boolean) -> Unit)? = null
) {

    sealed class EngineCandidate(val label: String) {
        data object OnDevice : EngineCandidate("on_device_speech_recognizer")
        data object SystemBrokerDefault : EngineCandidate("system_default")
        data class ExplicitGoogleComponent(val componentName: ComponentName) :
            EngineCandidate("service:${componentName.packageName}")
    }

    private val appContext: Context = activity.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioFocusCoordinator = LifeOsAudioFocusCoordinator(appContext)

    private var speechRecognizer: SpeechRecognizer? = null
    private var currentSessionId: String? = null
    private var currentAttemptId: Int = 0
    private var currentGeneration: Long = 0L
    private var currentEngineId: String = "system_default"
    private var currentLocale: String = "vi-VN"
    private var currentAudioRoute: String = LifeOsAudioFocusCoordinator.ROUTE_UNKNOWN
    private var attemptTerminated: Boolean = true
    private var isStopping: Boolean = false
    private var activePartialTranscript: String = ""

    private var startupTimeoutRunnable: Runnable? = null
    private var busyRetryRunnable: Runnable? = null
    private var finalizeTimeoutRunnable: Runnable? = null

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
        private const val STARTUP_TIMEOUT_MS = 2600L
        private const val BUSY_RETRY_DELAY_MS = 220L
        private const val FINALIZE_TIMEOUT_MS = 2500L
        private const val SUPPORT_CHECK_TIMEOUT_MS = 3000L

        private val GOOGLE_DIALOG_PACKAGES = listOf(
            "com.google.android.googlequicksearchbox",
            "com.google.android.tts",
            "com.google.android.apps.searchlite"
        )

        @Volatile
        private var lastKnownVietnameseOnDeviceSupported: Boolean? = null

        fun buildVietnameseSpeechIntent(
            context: Context,
            forSystemDialog: Boolean = false,
            localeTag: String = "vi-VN"
        ): Intent {
            val callingPkg = context.applicationInfo?.packageName ?: context.packageName
            val normalizedLocale = localeTag.ifBlank { "vi-VN" }
            return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, normalizedLocale)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, callingPkg)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, !forSystemDialog)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                if (forSystemDialog) {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, normalizedLocale)
                    putExtra(
                        RecognizerIntent.EXTRA_PROMPT,
                        "Mời bạn nói tiếng Việt (VD: Ăn phở 55 nghìn)"
                    )
                }
            }
        }

        fun resolveGoogleSpeechDialogIntent(
            context: Context,
            localeTag: String = "vi-VN"
        ): Intent? {
            val pm = context.packageManager
            for (pkg in GOOGLE_DIALOG_PACKAGES) {
                val candidate = buildVietnameseSpeechIntent(
                    context = context,
                    forSystemDialog = true,
                    localeTag = localeTag
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
                localeTag = localeTag
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

        fun isOnDeviceRecognitionAvailable(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
            return try {
                SpeechRecognizer.isOnDeviceRecognitionAvailable(context.applicationContext)
            } catch (_: Exception) {
                false
            }
        }

        /**
         * Queries real Android API 31+ / API 33+ on-device Vietnamese support.
         * Never guesses or reports `true` on API < 31.
         */
        fun checkVietnameseOnDeviceSupport(
            context: Context,
            localeTag: String = "vi-VN",
            callback: (Map<String, Any?>) -> Unit
        ) {
            val appCtx = context.applicationContext
            val mainHandler = Handler(Looper.getMainLooper())

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                lastKnownVietnameseOnDeviceSupported = false
                postMain(mainHandler) {
                    callback(
                        mapOf(
                            "isOnDeviceAvailable" to false,
                            "vietnameseInstalled" to false,
                            "vietnameseSupported" to false,
                            "pendingDownload" to false,
                            "sdkInt" to Build.VERSION.SDK_INT
                        )
                    )
                }
                return
            }

            val onDeviceAvail = isOnDeviceRecognitionAvailable(appCtx)
            if (!onDeviceAvail) {
                lastKnownVietnameseOnDeviceSupported = false
                postMain(mainHandler) {
                    callback(
                        mapOf(
                            "isOnDeviceAvailable" to false,
                            "vietnameseInstalled" to false,
                            "vietnameseSupported" to false,
                            "pendingDownload" to false,
                            "sdkInt" to Build.VERSION.SDK_INT
                        )
                    )
                }
                return
            }

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                // API 31–32 supports `createOnDeviceSpeechRecognizer`, but lacks `checkRecognitionSupport`.
                postMain(mainHandler) {
                    callback(
                        mapOf(
                            "isOnDeviceAvailable" to true,
                            "vietnameseInstalled" to null,
                            "vietnameseSupported" to null,
                            "pendingDownload" to false,
                            "sdkInt" to Build.VERSION.SDK_INT
                        )
                    )
                }
                return
            }

            postMain(mainHandler) {
                var completed = false
                var probe: SpeechRecognizer? = null
                val timeoutRunnable = Runnable {
                    if (completed) return@Runnable
                    completed = true
                    try {
                        probe?.destroy()
                    } catch (_: Exception) {
                    }
                    probe = null
                    callback(
                        mapOf(
                            "isOnDeviceAvailable" to true,
                            "vietnameseInstalled" to false,
                            "vietnameseSupported" to false,
                            "pendingDownload" to false,
                            "errorCode" to "SUPPORT_CHECK_TIMEOUT",
                            "sdkInt" to Build.VERSION.SDK_INT
                        )
                    )
                }

                try {
                    probe = SpeechRecognizer.createOnDeviceSpeechRecognizer(appCtx)
                    val intent = buildVietnameseSpeechIntent(
                        context = appCtx,
                        forSystemDialog = false,
                        localeTag = localeTag
                    )
                    mainHandler.postDelayed(timeoutRunnable, SUPPORT_CHECK_TIMEOUT_MS)

                    probe?.checkRecognitionSupport(
                        intent,
                        ContextCompat.getMainExecutor(appCtx),
                        object : RecognitionSupportCallback {
                            override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                                if (completed) return
                                completed = true
                                mainHandler.removeCallbacks(timeoutRunnable)
                                try {
                                    probe?.destroy()
                                } catch (_: Exception) {
                                }
                                probe = null

                                val installed = recognitionSupport.installedOnDeviceLanguages
                                val supported = recognitionSupport.supportedOnDeviceLanguages
                                val pending = recognitionSupport.pendingOnDeviceLanguages

                                val vnInstalled = installed.any { isVietnameseTag(it) }
                                val vnSupported = vnInstalled || supported.any { isVietnameseTag(it) }
                                val vnPending = pending.any { isVietnameseTag(it) }
                                lastKnownVietnameseOnDeviceSupported = vnSupported

                                callback(
                                    mapOf(
                                        "isOnDeviceAvailable" to true,
                                        "vietnameseInstalled" to vnInstalled,
                                        "vietnameseSupported" to vnSupported,
                                        "pendingDownload" to vnPending,
                                        "installedLanguages" to installed,
                                        "supportedLanguages" to supported,
                                        "pendingLanguages" to pending,
                                        "sdkInt" to Build.VERSION.SDK_INT
                                    )
                                )
                            }

                            override fun onError(error: Int) {
                                if (completed) return
                                completed = true
                                mainHandler.removeCallbacks(timeoutRunnable)
                                try {
                                    probe?.destroy()
                                } catch (_: Exception) {
                                }
                                probe = null

                                val (code, _) = classifySpeechError(error)
                                callback(
                                    mapOf(
                                        "isOnDeviceAvailable" to true,
                                        "vietnameseInstalled" to false,
                                        "vietnameseSupported" to false,
                                        "pendingDownload" to false,
                                        "errorCode" to code,
                                        "sdkInt" to Build.VERSION.SDK_INT
                                    )
                                )
                            }
                        }
                    )
                } catch (_: Exception) {
                    if (!completed) {
                        completed = true
                        mainHandler.removeCallbacks(timeoutRunnable)
                        try {
                            probe?.destroy()
                        } catch (_: Exception) {
                        }
                        probe = null
                        callback(
                            mapOf(
                                "isOnDeviceAvailable" to true,
                                "vietnameseInstalled" to false,
                                "vietnameseSupported" to false,
                                "pendingDownload" to false,
                                "errorCode" to "CANNOT_CHECK_SUPPORT",
                                "sdkInt" to Build.VERSION.SDK_INT
                            )
                        )
                    }
                }
            }
        }

        private fun isVietnameseTag(tag: String): Boolean {
            val norm = tag.trim().replace('_', '-').lowercase()
            return norm == "vi" || norm.startsWith("vi-")
        }

        private fun postMain(handler: Handler, block: () -> Unit) {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                block()
            } else {
                handler.post(block)
            }
        }

        /**
         * Discovers speech recognizer candidates using public Android APIs FIRST (`SystemBrokerDefault`),
         * with explicit Google services only as secondary candidates when not strictly offline.
         */
        fun discoverCandidates(
            context: Context,
            engineMode: String = "google_service",
            strictOffline: Boolean = false
        ): List<EngineCandidate> {
            val appCtx = context.applicationContext
            val offlineOnly = strictOffline ||
                engineMode == "on_device" ||
                engineMode == "offline_strict"

            if (offlineOnly) {
                return if (isOnDeviceRecognitionAvailable(appCtx)) {
                    listOf(EngineCandidate.OnDevice)
                } else {
                    emptyList()
                }
            }

            val ordered = mutableListOf<EngineCandidate>()
            val isSysAvailable = try {
                SpeechRecognizer.isRecognitionAvailable(appCtx)
            } catch (_: Exception) {
                false
            }
            if (isSysAvailable) {
                ordered.add(EngineCandidate.SystemBrokerDefault)
            }

            val pm = appCtx.packageManager
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

            ordered.addAll(googleTtsComponents)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || googleTtsComponents.isEmpty()) {
                ordered.addAll(legacyGsaComponents)
            }
            return ordered.distinct()
        }

        /**
         * Classifies ALL 13+ Android `SpeechRecognizer` error codes into stable error codes and
         * user-facing Vietnamese diagnostics messages.
         */
        fun classifySpeechError(error: Int): Pair<String, String> {
            return when (error) {
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                    "NETWORK_TIMEOUT" to "Hết thời gian kết nối mạng khi nhận diện giọng nói. Hãy thử lại."
                SpeechRecognizer.ERROR_NETWORK ->
                    "NETWORK_ERROR" to "Mạng gián đoạn khi nhận diện giọng nói. Vui lòng kiểm tra Wi-Fi hoặc 4G."
                SpeechRecognizer.ERROR_AUDIO ->
                    "AUDIO_ERROR" to "Không thu được tín hiệu âm thanh từ Micro. Kiểm tra Micro hoặc ứng dụng khác đang dùng mic."
                SpeechRecognizer.ERROR_SERVER ->
                    "SERVER_ERROR" to "Máy chủ nhận diện giọng nói tạm thời gián đoạn. Vui lòng thử lại."
                SpeechRecognizer.ERROR_CLIENT ->
                    "CLIENT_ERROR" to "Lỗi kết nối bộ nhận diện giọng nói trên thiết bị. Vui lòng thử lại."
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                    "SPEECH_TIMEOUT" to "Không nghe thấy giọng nói trong thời gian chờ. Bấm Mic để nói lại."
                SpeechRecognizer.ERROR_NO_MATCH ->
                    "NO_MATCH" to "Chưa nghe rõ câu nói. Bạn hãy nói rõ hơn hoặc gõ trực tiếp."
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                    "RECOGNIZER_BUSY" to "Bộ nhận diện giọng nói đang bận. Vui lòng thử lại sau giây lát."
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                    "PERMISSION_DENIED" to "Vui lòng cấp quyền Micro để thu âm giọng nói."
                SpeechRecognizer.ERROR_TOO_MANY_REQUESTS ->
                    "TOO_MANY_REQUESTS" to "Gửi quá nhiều yêu cầu nhận diện liên tiếp. Vui lòng đợi vài giây."
                SpeechRecognizer.ERROR_SERVER_DISCONNECTED ->
                    "SERVER_DISCONNECTED" to "Kết nối tới dịch vụ nhận diện giọng nói đã ngắt. Vui lòng thử lại."
                SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ->
                    "LANGUAGE_NOT_SUPPORTED" to "Bộ nhận diện hiện tại chưa hỗ trợ tiếng Việt."
                SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
                    "LANGUAGE_UNAVAILABLE" to "Gói ngôn ngữ tiếng Việt chưa sẵn sàng trên thiết bị. Hãy kiểm tra gói ngoại tuyến."
                SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT ->
                    "CANNOT_CHECK_SUPPORT" to "Không thể kiểm tra hỗ trợ ngôn ngữ trên dịch vụ nhận diện."
                SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS ->
                    "DOWNLOAD_EVENTS_UNAVAILABLE" to "Không thể theo dõi tiến trình tải gói ngôn ngữ."
                else ->
                    "SPEECH_ERROR_$error" to "Tạm ngưng thu âm (mã $error). Bạn có thể bấm Mic nói lại."
            }
        }

        fun collectDiagnostics(
            context: Context,
            activeEngineLabel: String? = null
        ): Map<String, Any?> {
            val appCtx = context.applicationContext
            val pm = appCtx.packageManager
            val hasMicHardware = pm.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)
            val hasRecordPerm = ContextCompat.checkSelfPermission(
                appCtx,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
            val candidates = discoverCandidates(appCtx).map { it.label }
            val hasGoogleDialog = resolveGoogleSpeechDialogIntent(appCtx) != null
            val onDeviceAvail = isOnDeviceRecognitionAvailable(appCtx)
            val isSysRecognitionAvail = try {
                SpeechRecognizer.isRecognitionAvailable(appCtx)
            } catch (_: Exception) {
                false
            }
            val isRecognitionAvailable = isSysRecognitionAvail ||
                onDeviceAvail ||
                candidates.isNotEmpty() ||
                hasGoogleDialog
            val resolvedLabel = activeEngineLabel
                ?: candidates.firstOrNull()
                ?: (if (onDeviceAvail) "on_device_speech_recognizer" else null)
                ?: (if (hasGoogleDialog) "system_speech_dialog" else "unavailable")

            val vnOnDeviceSupported: Boolean? = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || !onDeviceAvail) {
                false
            } else {
                lastKnownVietnameseOnDeviceSupported
            }

            val currentAudioRoute = LifeOsAudioFocusCoordinator.detectCurrentAudioRoute(appCtx)
            val micPrivacyBlocked = LifeOsAudioFocusCoordinator.isMicrophonePrivacyBlocked(appCtx)
            val sessionMetrics = VoiceSessionCoordinatorNative.getDiagnosticsMetrics()
            val capSnapshot = VoiceSessionCoordinatorNative.getCapabilitySnapshot(
                context = appCtx,
                locale = "vi-VN",
                audioRoute = currentAudioRoute
            )

            val out = LinkedHashMap<String, Any?>(28)
            // Legacy fields for `VoiceDiagnosticsSnapshot.fromMap`
            out["hardwareMicAvailable"] = hasMicHardware
            out["hasRecordPermission"] = hasRecordPerm
            out["isRecognitionAvailable"] = isRecognitionAvailable
            out["isOnDeviceAvailable"] = onDeviceAvail
            out["hasSystemSpeechDialog"] = hasGoogleDialog
            out["availableEngines"] = candidates
            out["activeEngineLabel"] = resolvedLabel
            out["sdkInt"] = Build.VERSION.SDK_INT
            out["manufacturer"] = Build.MANUFACTURER ?: "unknown"
            // V2 enriched diagnostics fields
            out["model"] = Build.MODEL ?: "unknown"
            out["osBuild"] = Build.FINGERPRINT ?: "unknown"
            out["hasMicPermission"] = hasRecordPerm
            out["micPrivacyBlocked"] = micPrivacyBlocked
            out["vietnameseOnDeviceSupported"] = vnOnDeviceSupported
            out["currentAudioRoute"] = currentAudioRoute
            out["capabilityCache"] = capSnapshot
            for ((k, v) in sessionMetrics) {
                out[k] = v
            }
            return out
        }
    }

    fun startListening(
        sessionId: String = UUID.randomUUID().toString(),
        attemptId: Int = 1,
        preferSystemDialog: Boolean = false,
        engineMode: String = "google_service",
        strictOffline: Boolean = false,
        locale: String = "vi-VN"
    ) {
        runOnMain {
            if (activity.isFinishing || activity.isDestroyed) return@runOnMain

            val resolvedSessionId = sessionId.ifBlank { UUID.randomUUID().toString() }
            val resolvedAttemptId = if (attemptId > 0) attemptId else 1
            val effectiveLocale = locale.ifBlank { "vi-VN" }
            val effectiveStrictOffline = strictOffline ||
                engineMode == "on_device" ||
                engineMode == "offline_strict"
            val useSystemDialog = !effectiveStrictOffline &&
                (preferSystemDialog || engineMode == "system_dialog")

            val initialEngineId = when {
                useSystemDialog -> "system_speech_dialog"
                effectiveStrictOffline -> "on_device_speech_recognizer"
                else -> "system_default"
            }

            // Claim process-wide ownership FIRST; any previous owner's cancelHook runs synchronously.
            currentGeneration += 1L
            val gen = currentGeneration
            VoiceSessionCoordinatorNative.claimSession(
                ownerId = ownerId,
                sessionId = resolvedSessionId,
                attemptId = resolvedAttemptId,
                engineId = initialEngineId,
                runCancelOnMain = true,
                cancelHook = { cancelFromCoordinator(resolvedSessionId, resolvedAttemptId, gen) }
            )

            clearTimers()
            teardownCurrentRecognizerSync(abortInFlight = true)

            currentSessionId = resolvedSessionId
            currentAttemptId = resolvedAttemptId
            currentEngineId = initialEngineId
            currentLocale = effectiveLocale
            currentAudioRoute = LifeOsAudioFocusCoordinator.detectCurrentAudioRoute(appContext)
            attemptTerminated = false
            isStopping = false
            activePartialTranscript = ""
            lastResolvedEngineLabel = initialEngineId

            if (useSystemDialog) {
                launchExplicitSystemDialog(resolvedSessionId, resolvedAttemptId, gen)
                return@runOnMain
            }

            // Permission check for inline recognition
            val hasAudioPerm = ContextCompat.checkSelfPermission(
                appContext,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
            if (!hasAudioPerm) {
                terminateWithError(
                    sessionId = resolvedSessionId,
                    attemptId = resolvedAttemptId,
                    generation = gen,
                    code = "PERMISSION_DENIED",
                    message = "Chưa cấp quyền Micro để thu âm giọng nói.",
                    recordToCache = false
                )
                return@runOnMain
            }

            // Strict offline / API 31+ On-Device path (NEVER falls back to online!)
            if (effectiveStrictOffline) {
                if (!isOnDeviceRecognitionAvailable(appContext)) {
                    terminateWithError(
                        sessionId = resolvedSessionId,
                        attemptId = resolvedAttemptId,
                        generation = gen,
                        code = "ON_DEVICE_UNAVAILABLE",
                        message = "Thiết bị chưa hỗ trợ nhận diện giọng nói ngoại tuyến (yêu cầu Android 12+ và gói ngôn ngữ ngoại tuyến).",
                        recordToCache = true
                    )
                    return@runOnMain
                }
                emitState(resolvedSessionId, resolvedAttemptId, initialEngineId, STATE_INITIALIZING)
                val focusOk = audioFocusCoordinator.requestFocus { permanent ->
                    handleAudioFocusLost(resolvedSessionId, resolvedAttemptId, gen, permanent)
                }
                if (!focusOk) {
                    terminateWithError(
                        sessionId = resolvedSessionId,
                        attemptId = resolvedAttemptId,
                        generation = gen,
                        code = "AUDIO_FOCUS_DENIED",
                        message = "Không thể sử dụng Micro vì đang có cuộc gọi hoặc ứng dụng âm thanh khác.",
                        recordToCache = false
                    )
                    return@runOnMain
                }
                startInlineAttempt(
                    sessionId = resolvedSessionId,
                    attemptId = resolvedAttemptId,
                    generation = gen,
                    candidates = listOf(EngineCandidate.OnDevice),
                    candidateIndex = 0,
                    retriedBusy = false,
                    strictOffline = true
                )
                return@runOnMain
            }

            val candidates = discoverCandidates(
                context = appContext,
                engineMode = engineMode,
                strictOffline = false
            )
            if (candidates.isEmpty()) {
                terminateWithError(
                    sessionId = resolvedSessionId,
                    attemptId = resolvedAttemptId,
                    generation = gen,
                    code = "NO_SPEECH_ENGINE",
                    message = "Thiết bị chưa bật dịch vụ Nhận diện giọng nói (Speech Services by Google).",
                    recordToCache = false
                )
                return@runOnMain
            }

            val primaryCandidate = candidates.first()
            currentEngineId = primaryCandidate.label
            lastResolvedEngineLabel = primaryCandidate.label
            VoiceSessionCoordinatorNative.updateSessionEngine(
                resolvedSessionId,
                resolvedAttemptId,
                primaryCandidate.label
            )
            emitState(resolvedSessionId, resolvedAttemptId, primaryCandidate.label, STATE_INITIALIZING)

            val focusOk = audioFocusCoordinator.requestFocus { permanent ->
                handleAudioFocusLost(resolvedSessionId, resolvedAttemptId, gen, permanent)
            }
            if (!focusOk) {
                terminateWithError(
                    sessionId = resolvedSessionId,
                    attemptId = resolvedAttemptId,
                    generation = gen,
                    code = "AUDIO_FOCUS_DENIED",
                    message = "Không thể sử dụng Micro vì đang có cuộc gọi hoặc ứng dụng âm thanh khác.",
                    recordToCache = false
                )
                return@runOnMain
            }

            startInlineAttempt(
                sessionId = resolvedSessionId,
                attemptId = resolvedAttemptId,
                generation = gen,
                candidates = candidates,
                candidateIndex = 0,
                retriedBusy = false,
                strictOffline = false
            )
        }
    }

    fun stopListening(sessionId: String? = null) {
        runOnMain {
            val activeId = currentSessionId ?: return@runOnMain
            if (sessionId != null && sessionId != activeId) return@runOnMain
            if (attemptTerminated) return@runOnMain

            val attemptId = currentAttemptId
            val gen = currentGeneration
            val engineId = currentEngineId
            val sr = speechRecognizer ?: return@runOnMain

            isStopping = true
            clearStartupAndBusyTimers()
            emitState(activeId, attemptId, engineId, STATE_PROCESSING)

            finalizeTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
            val timeoutGuard = Runnable {
                if (activeId != currentSessionId ||
                    attemptId != currentAttemptId ||
                    gen != currentGeneration ||
                    attemptTerminated
                ) {
                    return@Runnable
                }
                val rescued = activePartialTranscript.trim()
                if (rescued.isNotEmpty()) {
                    terminateWithFinalTranscript(activeId, attemptId, gen, engineId, rescued)
                } else {
                    terminateWithError(
                        sessionId = activeId,
                        attemptId = attemptId,
                        generation = gen,
                        code = "FINALIZE_TIMEOUT",
                        message = "Quá thời gian chờ hoàn tất nhận diện giọng nói. Bạn hãy bấm Mic nói lại.",
                        recordToCache = true
                    )
                }
            }
            finalizeTimeoutRunnable = timeoutGuard
            mainHandler.postDelayed(timeoutGuard, FINALIZE_TIMEOUT_MS)

            try {
                sr.stopListening()
            } catch (_: Exception) {
                finalizeTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
                finalizeTimeoutRunnable = null
                val rescued = activePartialTranscript.trim()
                if (rescued.isNotEmpty()) {
                    terminateWithFinalTranscript(activeId, attemptId, gen, engineId, rescued)
                } else {
                    terminateWithError(
                        sessionId = activeId,
                        attemptId = attemptId,
                        generation = gen,
                        code = "CLIENT_ERROR",
                        message = "Không thể dừng phiên nhận diện giọng nói đúng cách.",
                        recordToCache = false
                    )
                }
            }
        }
    }

    fun cancelListening(sessionId: String? = null) {
        runOnMain {
            val activeId = currentSessionId
            if (activeId == null) {
                clearTimers()
                teardownCurrentRecognizerSync(abortInFlight = true)
                audioFocusCoordinator.abandonFocus()
                onDialogStateChanged?.invoke(false)
                return@runOnMain
            }
            if (sessionId != null && sessionId != activeId) {
                return@runOnMain
            }
            cancelInternal(activeId, currentAttemptId, currentGeneration)
        }
    }

    /**
     * Completes an explicit external `ACTION_RECOGNIZE_SPEECH` system dialog session
     * invoked earlier by [startListening] with `system_dialog`.
     */
    fun completeExternalDialogSession(
        sessionId: String,
        attemptId: Int,
        success: Boolean,
        errorCode: String? = null
    ) {
        runOnMain {
            if (sessionId == currentSessionId && attemptId == currentAttemptId && !attemptTerminated) {
                attemptTerminated = true
                clearTimers()
                currentSessionId = null
            }
            if (success) {
                VoiceSessionCoordinatorNative.markFinal(sessionId, attemptId)
            } else if (errorCode != null) {
                VoiceSessionCoordinatorNative.setLastErrorCode(sessionId, attemptId, errorCode)
            }
            VoiceSessionCoordinatorNative.recordOutcome(
                context = appContext,
                engineId = "system_speech_dialog",
                locale = currentLocale,
                audioRoute = LifeOsAudioFocusCoordinator.detectCurrentAudioRoute(appContext),
                success = success,
                errorCode = errorCode
            )
            onDialogStateChanged?.invoke(false)
            VoiceSessionCoordinatorNative.releaseSession(sessionId, attemptId)
        }
    }

    fun destroy() {
        runOnMain {
            val activeId = currentSessionId
            if (activeId != null && !attemptTerminated) {
                cancelInternal(activeId, currentAttemptId, currentGeneration)
            } else {
                currentGeneration += 1L
                attemptTerminated = true
                clearTimers()
                teardownCurrentRecognizerSync(abortInFlight = true)
                audioFocusCoordinator.abandonFocus()
                onDialogStateChanged?.invoke(false)
            }
        }
    }

    private fun cancelFromCoordinator(
        expectedSessionId: String,
        expectedAttemptId: Int,
        expectedGeneration: Long
    ) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            if (expectedSessionId == currentSessionId &&
                expectedAttemptId == currentAttemptId &&
                expectedGeneration == currentGeneration &&
                !attemptTerminated
            ) {
                cancelInternal(expectedSessionId, expectedAttemptId, expectedGeneration)
            }
        } else {
            mainHandler.post {
                if (expectedSessionId == currentSessionId &&
                    expectedAttemptId == currentAttemptId &&
                    expectedGeneration == currentGeneration &&
                    !attemptTerminated
                ) {
                    cancelInternal(expectedSessionId, expectedAttemptId, expectedGeneration)
                }
            }
        }
    }

    private fun cancelInternal(
        sessionId: String,
        attemptId: Int,
        generation: Long
    ) {
        if (sessionId != currentSessionId || attemptId != currentAttemptId || generation != currentGeneration) {
            return
        }
        val wasTerminated = attemptTerminated
        val engineId = currentEngineId
        attemptTerminated = true
        isStopping = false
        activePartialTranscript = ""
        currentGeneration += 1L
        currentSessionId = null

        clearTimers()
        teardownCurrentRecognizerSync(abortInFlight = true)
        audioFocusCoordinator.abandonFocus()
        onDialogStateChanged?.invoke(false)
        VoiceSessionCoordinatorNative.releaseSession(sessionId, attemptId)

        if (!wasTerminated) {
            emitState(sessionId, attemptId, engineId, STATE_CANCELLED)
        }
    }

    private fun launchExplicitSystemDialog(
        sessionId: String,
        attemptId: Int,
        generation: Long
    ) {
        val dialogIntent = resolveGoogleSpeechDialogIntent(activity, currentLocale)
        if (dialogIntent == null) {
            terminateWithError(
                sessionId = sessionId,
                attemptId = attemptId,
                generation = generation,
                code = "NO_SPEECH_ENGINE",
                message = "Thiết bị chưa cài đặt hoặc chưa bật Hộp thoại giọng nói Google.",
                recordToCache = false
            )
            return
        }

        val launched = try {
            onLaunchSystemDialog(dialogIntent, sessionId, attemptId)
        } catch (_: Exception) {
            false
        }

        if (launched) {
            onDialogStateChanged?.invoke(true)
            emitState(sessionId, attemptId, "system_speech_dialog", STATE_LISTENING)
        } else {
            onDialogStateChanged?.invoke(false)
            terminateWithError(
                sessionId = sessionId,
                attemptId = attemptId,
                generation = generation,
                code = "DIALOG_LAUNCH_FAILED",
                message = "Không thể mở Hộp thoại thu âm hệ thống.",
                recordToCache = false
            )
        }
    }

    private fun startInlineAttempt(
        sessionId: String,
        attemptId: Int,
        generation: Long,
        candidates: List<EngineCandidate>,
        candidateIndex: Int,
        retriedBusy: Boolean,
        strictOffline: Boolean
    ) {
        if (sessionId != currentSessionId ||
            attemptId != currentAttemptId ||
            generation != currentGeneration ||
            attemptTerminated ||
            activity.isFinishing ||
            activity.isDestroyed
        ) {
            return
        }

        if (candidateIndex >= candidates.size) {
            terminateWithError(
                sessionId = sessionId,
                attemptId = attemptId,
                generation = generation,
                code = "NO_SPEECH_ENGINE",
                message = "Không khởi tạo được bộ nhận diện giọng nói trên thiết bị.",
                recordToCache = false
            )
            return
        }

        val candidate = candidates[candidateIndex]
        currentEngineId = candidate.label
        lastResolvedEngineLabel = candidate.label
        VoiceSessionCoordinatorNative.updateSessionEngine(sessionId, attemptId, candidate.label)

        try {
            teardownCurrentRecognizerSync(abortInFlight = true)
            val sr = createRecognizerForCandidate(candidate)
            speechRecognizer = sr

            var receivedReady = false
            var announcedListening = false

            clearStartupAndBusyTimers()
            val startupGuard = Runnable {
                if (sessionId != currentSessionId ||
                    attemptId != currentAttemptId ||
                    generation != currentGeneration ||
                    attemptTerminated ||
                    receivedReady
                ) {
                    return@Runnable
                }
                teardownCurrentRecognizerSync(abortInFlight = true)
                if (!strictOffline && candidateIndex + 1 < candidates.size) {
                    VoiceSessionCoordinatorNative.incrementFallback(sessionId, attemptId)
                    onEngineAutoSwitched?.invoke(candidates[candidateIndex + 1].label)
                    emitEnvelope(
                        sessionId = sessionId,
                        attemptId = attemptId,
                        engineId = candidates[candidateIndex + 1].label,
                        eventType = "engine_switched",
                        extra = mapOf("mode" to candidates[candidateIndex + 1].label)
                    )
                    startInlineAttempt(
                        sessionId = sessionId,
                        attemptId = attemptId,
                        generation = generation,
                        candidates = candidates,
                        candidateIndex = candidateIndex + 1,
                        retriedBusy = false,
                        strictOffline = false
                    )
                } else {
                    terminateWithError(
                        sessionId = sessionId,
                        attemptId = attemptId,
                        generation = generation,
                        code = "ENGINE_STARTUP_TIMEOUT",
                        message = "Bộ nhận diện giọng nói không phản hồi. Vui lòng thử lại.",
                        recordToCache = true
                    )
                }
            }
            startupTimeoutRunnable = startupGuard
            mainHandler.postDelayed(startupGuard, STARTUP_TIMEOUT_MS)

            sr.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    runOnMain {
                        if (!isAttemptCurrent(sessionId, attemptId, generation)) return@runOnMain
                        receivedReady = true
                        clearStartupTimeoutOnly()
                        VoiceSessionCoordinatorNative.markReady(sessionId, attemptId)
                        if (!announcedListening) {
                            announcedListening = true
                            emitState(sessionId, attemptId, candidate.label, STATE_LISTENING)
                        }
                    }
                }

                override fun onBeginningOfSpeech() {
                    runOnMain {
                        if (!isAttemptCurrent(sessionId, attemptId, generation)) return@runOnMain
                        receivedReady = true
                        clearStartupTimeoutOnly()
                        if (!announcedListening) {
                            announcedListening = true
                            emitState(sessionId, attemptId, candidate.label, STATE_LISTENING)
                        }
                    }
                }

                override fun onRmsChanged(rmsdB: Float) {
                    runOnMain {
                        if (!isAttemptCurrent(sessionId, attemptId, generation)) return@runOnMain
                        if (!receivedReady) return@runOnMain
                        emitRms(sessionId, attemptId, candidate.label, rmsdB.toDouble())
                    }
                }

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {
                    runOnMain {
                        if (!isAttemptCurrent(sessionId, attemptId, generation)) return@runOnMain
                        receivedReady = true
                        clearStartupTimeoutOnly()
                        emitState(sessionId, attemptId, candidate.label, STATE_PROCESSING)
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    runOnMain {
                        if (!isAttemptCurrent(sessionId, attemptId, generation)) return@runOnMain
                        receivedReady = true
                        clearStartupTimeoutOnly()
                        if (!announcedListening) {
                            announcedListening = true
                            emitState(sessionId, attemptId, candidate.label, STATE_LISTENING)
                        }
                        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull().orEmpty().trim()
                        if (text.isNotEmpty()) {
                            activePartialTranscript = text
                            VoiceSessionCoordinatorNative.markFirstPartial(sessionId, attemptId)
                            emitPartial(sessionId, attemptId, candidate.label, text)
                        }
                    }
                }

                override fun onResults(results: Bundle?) {
                    runOnMain {
                        if (!isAttemptCurrent(sessionId, attemptId, generation)) return@runOnMain
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
                            ?: activePartialTranscript.trim()
                        if (text.isNotEmpty()) {
                            terminateWithFinalTranscript(
                                sessionId = sessionId,
                                attemptId = attemptId,
                                generation = generation,
                                engineId = candidate.label,
                                transcript = text
                            )
                        } else {
                            terminateWithError(
                                sessionId = sessionId,
                                attemptId = attemptId,
                                generation = generation,
                                code = "NO_MATCH",
                                message = "Chưa nghe rõ câu nói. Bạn hãy bấm Mic để nói lại hoặc gõ trực tiếp.",
                                recordToCache = true
                            )
                        }
                    }
                }

                override fun onError(error: Int) {
                    runOnMain {
                        if (!isAttemptCurrent(sessionId, attemptId, generation)) return@runOnMain
                        clearStartupTimeoutOnly()

                        // Rescue already-transcribed partial speech on silence/no-match (or user-initiated stop).
                        val capturedPartial = activePartialTranscript.trim()
                        val shouldRescuePartial = capturedPartial.isNotEmpty() && (
                            error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                                error == SpeechRecognizer.ERROR_NO_MATCH ||
                                (isStopping && (error == SpeechRecognizer.ERROR_CLIENT || error == SpeechRecognizer.ERROR_SERVER))
                            )
                        if (shouldRescuePartial) {
                            terminateWithFinalTranscript(
                                sessionId = sessionId,
                                attemptId = attemptId,
                                generation = generation,
                                engineId = candidate.label,
                                transcript = capturedPartial
                            )
                            return@runOnMain
                        }

                        // ONLY ERROR_RECOGNIZER_BUSY gets max 1 bounded retry (220ms); zero retries for all other errors.
                        if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY && !retriedBusy) {
                            VoiceSessionCoordinatorNative.incrementRetry(sessionId, attemptId)
                            teardownCurrentRecognizerSync(abortInFlight = true)
                            val retryRun = Runnable {
                                if (!isAttemptCurrent(sessionId, attemptId, generation)) return@Runnable
                                startInlineAttempt(
                                    sessionId = sessionId,
                                    attemptId = attemptId,
                                    generation = generation,
                                    candidates = candidates,
                                    candidateIndex = candidateIndex,
                                    retriedBusy = true,
                                    strictOffline = strictOffline
                                )
                            }
                            busyRetryRunnable = retryRun
                            mainHandler.postDelayed(retryRun, BUSY_RETRY_DELAY_MS)
                            return@runOnMain
                        }

                        val (errCode, errMsg) = classifySpeechError(error)
                        terminateWithError(
                            sessionId = sessionId,
                            attemptId = attemptId,
                            generation = generation,
                            code = errCode,
                            message = errMsg,
                            recordToCache = true
                        )
                    }
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            val recIntent = buildVietnameseSpeechIntent(
                context = appContext,
                forSystemDialog = false,
                localeTag = currentLocale
            )
            sr.startListening(recIntent)
        } catch (_: Exception) {
            clearTimers()
            teardownCurrentRecognizerSync(abortInFlight = true)
            if (!strictOffline && candidateIndex + 1 < candidates.size) {
                VoiceSessionCoordinatorNative.incrementFallback(sessionId, attemptId)
                startInlineAttempt(
                    sessionId = sessionId,
                    attemptId = attemptId,
                    generation = generation,
                    candidates = candidates,
                    candidateIndex = candidateIndex + 1,
                    retriedBusy = false,
                    strictOffline = false
                )
            } else {
                terminateWithError(
                    sessionId = sessionId,
                    attemptId = attemptId,
                    generation = generation,
                    code = "CLIENT_ERROR",
                    message = "Không thể khởi chạy bộ nhận diện giọng nói trên thiết bị.",
                    recordToCache = true
                )
            }
        }
    }

    private fun createRecognizerForCandidate(candidate: EngineCandidate): SpeechRecognizer {
        return when (candidate) {
            is EngineCandidate.OnDevice -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    SpeechRecognizer.createOnDeviceSpeechRecognizer(appContext)
                } else {
                    throw IllegalStateException("On-device recognizer requires API 31+")
                }
            }
            is EngineCandidate.SystemBrokerDefault ->
                SpeechRecognizer.createSpeechRecognizer(appContext)
            is EngineCandidate.ExplicitGoogleComponent ->
                SpeechRecognizer.createSpeechRecognizer(appContext, candidate.componentName)
        }
    }

    private fun isAttemptCurrent(sessionId: String, attemptId: Int, generation: Long): Boolean {
        return sessionId == currentSessionId &&
            attemptId == currentAttemptId &&
            generation == currentGeneration &&
            !attemptTerminated
    }

    private fun handleAudioFocusLost(
        sessionId: String,
        attemptId: Int,
        generation: Long,
        permanent: Boolean
    ) {
        runOnMain {
            if (!isAttemptCurrent(sessionId, attemptId, generation)) return@runOnMain
            val msg = if (permanent) {
                "Thu âm tạm dừng vì ứng dụng khác chiếm quyền âm thanh."
            } else {
                "Thu âm tạm dừng do có cuộc gọi hoặc thông báo âm thanh ưu tiên."
            }
            terminateWithError(
                sessionId = sessionId,
                attemptId = attemptId,
                generation = generation,
                code = "AUDIO_FOCUS_LOST",
                message = msg,
                recordToCache = false
            )
        }
    }

    private fun terminateWithFinalTranscript(
        sessionId: String,
        attemptId: Int,
        generation: Long,
        engineId: String,
        transcript: String
    ) {
        if (!isAttemptCurrent(sessionId, attemptId, generation)) return
        attemptTerminated = true
        isStopping = false
        activePartialTranscript = ""
        currentSessionId = null
        clearTimers()
        teardownCurrentRecognizerSync(abortInFlight = false)
        audioFocusCoordinator.abandonFocus()

        VoiceSessionCoordinatorNative.markFinal(sessionId, attemptId)
        VoiceSessionCoordinatorNative.recordOutcome(
            context = appContext,
            engineId = engineId,
            locale = currentLocale,
            audioRoute = currentAudioRoute,
            success = true
        )

        emitFinal(sessionId, attemptId, engineId, transcript)
        emitState(sessionId, attemptId, engineId, STATE_REVIEW)
        VoiceSessionCoordinatorNative.releaseSession(sessionId, attemptId)
    }

    private fun terminateWithError(
        sessionId: String,
        attemptId: Int,
        generation: Long,
        code: String,
        message: String,
        recordToCache: Boolean
    ) {
        if (sessionId != currentSessionId || attemptId != currentAttemptId || generation != currentGeneration || attemptTerminated) {
            return
        }
        val engineId = currentEngineId
        attemptTerminated = true
        isStopping = false
        activePartialTranscript = ""
        currentSessionId = null
        clearTimers()
        teardownCurrentRecognizerSync(abortInFlight = true)
        audioFocusCoordinator.abandonFocus()

        VoiceSessionCoordinatorNative.setLastErrorCode(sessionId, attemptId, code)
        if (recordToCache) {
            VoiceSessionCoordinatorNative.recordOutcome(
                context = appContext,
                engineId = engineId,
                locale = currentLocale,
                audioRoute = currentAudioRoute,
                success = false,
                errorCode = code
            )
        }

        onStateChanged(STATE_ERROR)
        emitError(sessionId, attemptId, engineId, code, message)
        VoiceSessionCoordinatorNative.releaseSession(sessionId, attemptId)
    }

    private fun teardownCurrentRecognizerSync(abortInFlight: Boolean): Boolean {
        val prev = speechRecognizer ?: return false
        speechRecognizer = null
        if (abortInFlight) {
            try {
                prev.cancel()
            } catch (_: Exception) {
            }
        }
        try {
            prev.destroy()
        } catch (_: Exception) {
        }
        return true
    }

    private fun clearStartupTimeoutOnly() {
        startupTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        startupTimeoutRunnable = null
    }

    private fun clearStartupAndBusyTimers() {
        clearStartupTimeoutOnly()
        busyRetryRunnable?.let { mainHandler.removeCallbacks(it) }
        busyRetryRunnable = null
    }

    private fun clearTimers() {
        clearStartupAndBusyTimers()
        finalizeTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        finalizeTimeoutRunnable = null
    }

    private fun emitState(sessionId: String, attemptId: Int, engineId: String, status: String) {
        emitEnvelope(
            sessionId = sessionId,
            attemptId = attemptId,
            engineId = engineId,
            eventType = "state",
            extra = mapOf("status" to status)
        )
        onStateChanged(status)
    }

    private fun emitRms(sessionId: String, attemptId: Int, engineId: String, rms: Double) {
        emitEnvelope(
            sessionId = sessionId,
            attemptId = attemptId,
            engineId = engineId,
            eventType = "rms",
            extra = mapOf("rms" to rms)
        )
        onRmsChanged(rms)
    }

    private fun emitPartial(sessionId: String, attemptId: Int, engineId: String, text: String) {
        emitEnvelope(
            sessionId = sessionId,
            attemptId = attemptId,
            engineId = engineId,
            eventType = "partial",
            extra = mapOf("text" to text)
        )
        onPartialTranscript(text)
    }

    private fun emitFinal(sessionId: String, attemptId: Int, engineId: String, text: String) {
        emitEnvelope(
            sessionId = sessionId,
            attemptId = attemptId,
            engineId = engineId,
            eventType = "final",
            extra = mapOf("text" to text)
        )
        onFinalTranscript(text)
    }

    private fun emitError(
        sessionId: String,
        attemptId: Int,
        engineId: String,
        code: String,
        message: String
    ) {
        emitEnvelope(
            sessionId = sessionId,
            attemptId = attemptId,
            engineId = engineId,
            eventType = "error",
            extra = mapOf("code" to code, "message" to message)
        )
        onError(code, message)
    }

    private fun emitEnvelope(
        sessionId: String,
        attemptId: Int,
        engineId: String,
        eventType: String,
        extra: Map<String, Any?>
    ) {
        val sink = onEnvelopeEvent ?: return
        val envelope = VoiceSessionCoordinatorNative.buildEventEnvelope(
            sessionId = sessionId,
            attemptId = attemptId,
            ownerId = ownerId,
            engineId = engineId,
            eventType = eventType,
            extra = extra
        )
        sink.invoke(envelope)
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }
}
