package vn.lifeos.app.life_os

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Pure Android SDK 16kHz Mono PCM16 recorder providing:
 * 1. Non-blocking Microphone Self-Test (`runMicrophoneSelfTest`) with zero disk writes.
 * 2. Bounded 300ms (`4,800` samples) circular pre-roll local PCM capture (`startCapture`/`stopCapture`)
 *    ready for future local ASR pipelines.
 *
 * Arbitrates microphone ownership exclusively via [VoiceSessionCoordinatorNative] so `AudioRecord`
 * NEVER runs concurrently with `SpeechRecognizer`.
 */
object LifeOsPcmAudioRecorder {

    const val SAMPLE_RATE_HZ = 16_000
    const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
    const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    const val PRE_ROLL_DURATION_MS = 300
    const val PRE_ROLL_SAMPLES = (SAMPLE_RATE_HZ * PRE_ROLL_DURATION_MS) / 1000 // 4,800 samples
    private const val FRAME_SAMPLES = 320 // 20ms at 16kHz
    private const val MIN_DBFS = -96.0
    private const val ACTIVE_FRAME_THRESHOLD_DBFS = -58.0
    private const val ENERGY_CALLBACK_INTERVAL_MS = 50L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val workerLock = Any()

    private val isRunning = AtomicBoolean(false)

    @Volatile
    private var activeSessionId: String? = null

    @Volatile
    private var activeWorkerThread: Thread? = null

    @Volatile
    private var activeCaptureSummary: Map<String, Any?> = emptyMap()

    private val preRollRing = ShortArray(PRE_ROLL_SAMPLES)
    private var preRollWriteIndex = 0
    private var preRollCount = 0

    /**
     * Captures live PCM16 audio for [durationMs] on a background thread (zero disk writes) and
     * invokes [onResult] on the main thread with acoustic diagnostics.
     */
    fun runMicrophoneSelfTest(
        context: Context,
        durationMs: Long = 1200L,
        onResult: (Map<String, Any?>) -> Unit
    ) {
        val appCtx = context.applicationContext
        val clampedDurationMs = durationMs.coerceIn(300L, 5000L)
        val audioRoute = LifeOsAudioFocusCoordinator.detectCurrentAudioRoute(appCtx)

        val hasPerm = ContextCompat.checkSelfPermission(
            appCtx,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPerm) {
            postToMain {
                onResult(
                    mapOf(
                        "success" to false,
                        "errorCode" to "PERMISSION_DENIED",
                        "message" to "Chưa cấp quyền Micro để kiểm tra tín hiệu âm thanh.",
                        "peakDbfs" to MIN_DBFS,
                        "avgDbfs" to MIN_DBFS,
                        "activeFrames" to 0,
                        "zeroFrames" to 0,
                        "totalFrames" to 0,
                        "durationMs" to 0L,
                        "sampleRateHz" to SAMPLE_RATE_HZ,
                        "audioRoute" to audioRoute,
                        "isMicMuted" to false,
                        "isClientSilenced" to false
                    )
                )
            }
            return
        }

        val testSessionId = "self_test_${UUID.randomUUID()}"
        val session = VoiceSessionCoordinatorNative.claimSession(
            ownerId = VoiceSessionCoordinatorNative.OWNER_PCM_SELF_TEST,
            sessionId = testSessionId,
            attemptId = 1,
            engineId = "pcm_self_test",
            runCancelOnMain = false,
            cancelHook = { cancelWorkerInternal(testSessionId) }
        )

        val focusCoordinator = LifeOsAudioFocusCoordinator(appCtx)
        val focusGranted = focusCoordinator.requestFocus {
            cancelWorkerInternal(testSessionId)
        }
        if (!focusGranted) {
            focusCoordinator.abandonFocus()
            VoiceSessionCoordinatorNative.releaseSession(testSessionId, 1)
            postToMain {
                onResult(
                    mapOf(
                        "success" to false,
                        "errorCode" to "AUDIO_FOCUS_DENIED",
                        "message" to "Không thể kiểm tra Micro khi đang có cuộc gọi hoặc ứng dụng âm thanh chiếm quyền.",
                        "peakDbfs" to MIN_DBFS,
                        "avgDbfs" to MIN_DBFS,
                        "activeFrames" to 0,
                        "zeroFrames" to 0,
                        "totalFrames" to 0,
                        "durationMs" to 0L,
                        "sampleRateHz" to SAMPLE_RATE_HZ,
                        "audioRoute" to audioRoute,
                        "isMicMuted" to isOsMicMuted(appCtx),
                        "isClientSilenced" to false
                    )
                )
            }
            return
        }

        val worker = Thread({
            var recorder: AudioRecord? = null
            var peakAbs = 0
            var sumSquaresTotal = 0.0
            var totalSamples = 0L
            var activeFrames = 0
            var zeroFrames = 0
            var totalFrames = 0
            var detectedClientSilenced = false
            var errorCode: String? = null
            var errorMsg: String? = null
            val startedAtMs = SystemClock.elapsedRealtime()

            try {
                recorder = openAudioRecord(appCtx)
                if (recorder == null) {
                    errorCode = "AUDIO_RECORD_INIT_FAILED"
                    errorMsg = "Không thể khởi tạo phần cứng Micro ở chuẩn 16kHz PCM16."
                } else {
                    recorder.startRecording()
                    val frameBuf = ShortArray(FRAME_SAMPLES)
                    while (isRunning.get() &&
                        activeSessionId == testSessionId &&
                        !session.isTerminal &&
                        (SystemClock.elapsedRealtime() - startedAtMs) < clampedDurationMs
                    ) {
                        val read = recorder.read(frameBuf, 0, frameBuf.size)
                        if (read < 0) {
                            errorCode = "AUDIO_READ_FAILED"
                            errorMsg = "Lỗi đọc dữ liệu âm thanh từ Micro (mã $read)."
                            break
                        }
                        if (read == 0) continue

                        totalFrames += 1
                        var framePeak = 0
                        var frameSumSq = 0.0
                        for (i in 0 until read) {
                            val s = frameBuf[i].toInt()
                            val absVal = abs(s)
                            if (absVal > framePeak) framePeak = absVal
                            if (absVal > peakAbs) peakAbs = absVal
                            frameSumSq += s.toDouble() * s.toDouble()
                        }
                        sumSquaresTotal += frameSumSq
                        totalSamples += read

                        if (framePeak == 0) {
                            zeroFrames += 1
                        } else {
                            val frameRms = sqrt(frameSumSq / read.toDouble())
                            val frameDbfs = rmsToDbfs(frameRms)
                            if (frameDbfs > ACTIVE_FRAME_THRESHOLD_DBFS) {
                                activeFrames += 1
                            }
                        }

                        if (!detectedClientSilenced && isActiveRecordingSilenced(appCtx)) {
                            detectedClientSilenced = true
                        }
                    }
                }
            } catch (_: Exception) {
                errorCode = "AUDIO_TEST_EXCEPTION"
                errorMsg = "Kiểm tra Micro bị gián đoạn bất ngờ."
            } finally {
                try {
                    recorder?.stop()
                } catch (_: Exception) {
                }
                try {
                    recorder?.release()
                } catch (_: Exception) {
                }
                focusCoordinator.abandonFocus()
                synchronized(workerLock) {
                    if (activeSessionId == testSessionId) {
                        isRunning.set(false)
                        activeSessionId = null
                        activeWorkerThread = null
                    }
                }
                VoiceSessionCoordinatorNative.releaseSession(testSessionId, 1)
            }

            val elapsedMs = (SystemClock.elapsedRealtime() - startedAtMs).coerceAtLeast(0L)
            val peakDbfs = if (peakAbs > 0) {
                (20.0 * log10(peakAbs.toDouble() / 32768.0)).coerceIn(MIN_DBFS, 0.0)
            } else {
                MIN_DBFS
            }
            val avgDbfs = if (totalSamples > 0L && sumSquaresTotal > 0.0) {
                rmsToDbfs(sqrt(sumSquaresTotal / totalSamples.toDouble()))
            } else {
                MIN_DBFS
            }
            val micOpened = errorCode == null && totalFrames > 0
            val micMuted = isOsMicMuted(appCtx) ||
                detectedClientSilenced ||
                (totalFrames > 0 && zeroFrames == totalFrames)
            val hasSignal = micOpened &&
                !micMuted &&
                !detectedClientSilenced &&
                zeroFrames < totalFrames &&
                activeFrames > 0 &&
                peakAbs > 0
            val routeAtEnd = LifeOsAudioFocusCoordinator.detectCurrentAudioRoute(appCtx)
            val succeeded = hasSignal

            val summaryMsg = when {
                errorMsg != null -> errorMsg
                micMuted || detectedClientSilenced ->
                    "Mở được mic nhưng toàn bộ khung PCM bằng 0 hoặc đang bị tắt tiếng/chặn quyền riêng tư."
                hasSignal ->
                    "Micro hoạt động tốt (đỉnh ${"%.1f".format(peakDbfs)} dBFS, $activeFrames khung có tín hiệu)."
                else ->
                    "Mở được mic (${routeAtEnd}) nhưng chưa thu được tín hiệu âm thanh vượt ngưỡng."
            }

            postToMain {
                onResult(
                    mapOf(
                        "success" to succeeded,
                        "passed" to succeeded,
                        "micOpened" to micOpened,
                        "hasSignal" to hasSignal,
                        "speechRecognized" to false,
                        "peakDbfs" to peakDbfs,
                        "avgDbfs" to avgDbfs,
                        "activeFrames" to activeFrames,
                        "zeroFrames" to zeroFrames,
                        "totalFrames" to totalFrames,
                        "durationMs" to elapsedMs,
                        "sampleRateHz" to SAMPLE_RATE_HZ,
                        "audioRoute" to routeAtEnd,
                        "isMicMuted" to micMuted,
                        "isClientSilenced" to detectedClientSilenced,
                        "errorCode" to errorCode,
                        "message" to summaryMsg
                    )
                )
            }
        }, "LifeOsPcmSelfTest")

        synchronized(workerLock) {
            isRunning.set(true)
            activeSessionId = testSessionId
            activeWorkerThread = worker
        }
        worker.start()
    }

    /**
     * Starts continuous 16kHz Mono PCM16 capture with a 300ms (`4,800` sample) circular pre-roll
     * buffer for local ASR readiness. Coordinates exclusive mic access via [VoiceSessionCoordinatorNative].
     */
    fun startCapture(
        context: Context,
        sessionId: String = UUID.randomUUID().toString(),
        onPcmEnergy: ((Double) -> Unit)? = null
    ): Boolean {
        val appCtx = context.applicationContext
        val hasPerm = ContextCompat.checkSelfPermission(
            appCtx,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPerm) return false

        val session = VoiceSessionCoordinatorNative.claimSession(
            ownerId = VoiceSessionCoordinatorNative.OWNER_PCM_LOCAL_CAPTURE,
            sessionId = sessionId,
            attemptId = 1,
            engineId = "pcm_local_capture",
            runCancelOnMain = false,
            cancelHook = { cancelWorkerInternal(sessionId) }
        )

        val focusCoordinator = LifeOsAudioFocusCoordinator(appCtx)
        if (!focusCoordinator.requestFocus { cancelWorkerInternal(sessionId) }) {
            focusCoordinator.abandonFocus()
            VoiceSessionCoordinatorNative.releaseSession(sessionId, 1)
            return false
        }

        val recorder = openAudioRecord(appCtx)
        if (recorder == null) {
            focusCoordinator.abandonFocus()
            VoiceSessionCoordinatorNative.releaseSession(sessionId, 1)
            return false
        }

        synchronized(workerLock) {
            preRollWriteIndex = 0
            preRollCount = 0
            preRollRing.fill(0)
            activeCaptureSummary = emptyMap()
            isRunning.set(true)
            activeSessionId = sessionId
        }

        val worker = Thread({
            val startedAtMs = SystemClock.elapsedRealtime()
            var peakAbs = 0
            var sumSquaresTotal = 0.0
            var totalSamples = 0L
            var lastEnergyEmitMs = 0L
            val frameBuf = ShortArray(FRAME_SAMPLES)

            try {
                recorder.startRecording()
                while (isRunning.get() &&
                    activeSessionId == sessionId &&
                    !session.isTerminal
                ) {
                    val read = recorder.read(frameBuf, 0, frameBuf.size)
                    if (read <= 0) {
                        if (read < 0) break
                        continue
                    }

                    var frameSumSq = 0.0
                    synchronized(workerLock) {
                        for (i in 0 until read) {
                            val sample = frameBuf[i]
                            preRollRing[preRollWriteIndex] = sample
                            preRollWriteIndex = (preRollWriteIndex + 1) % PRE_ROLL_SAMPLES
                            if (preRollCount < PRE_ROLL_SAMPLES) {
                                preRollCount += 1
                            }
                            val s = sample.toInt()
                            val absVal = abs(s)
                            if (absVal > peakAbs) peakAbs = absVal
                            frameSumSq += s.toDouble() * s.toDouble()
                        }
                    }
                    sumSquaresTotal += frameSumSq
                    totalSamples += read

                    if (onPcmEnergy != null) {
                        val nowMs = SystemClock.elapsedRealtime()
                        if ((nowMs - lastEnergyEmitMs) >= ENERGY_CALLBACK_INTERVAL_MS) {
                            lastEnergyEmitMs = nowMs
                            val dbfs = rmsToDbfs(sqrt(frameSumSq / read.toDouble()))
                            postToMain { onPcmEnergy.invoke(dbfs) }
                        }
                    }
                }
            } catch (_: Exception) {
            } finally {
                try {
                    recorder.stop()
                } catch (_: Exception) {
                }
                try {
                    recorder.release()
                } catch (_: Exception) {
                }
                focusCoordinator.abandonFocus()

                val elapsedMs = (SystemClock.elapsedRealtime() - startedAtMs).coerceAtLeast(0L)
                val peakDbfs = if (peakAbs > 0) {
                    (20.0 * log10(peakAbs.toDouble() / 32768.0)).coerceIn(MIN_DBFS, 0.0)
                } else {
                    MIN_DBFS
                }
                val avgDbfs = if (totalSamples > 0L && sumSquaresTotal > 0.0) {
                    rmsToDbfs(sqrt(sumSquaresTotal / totalSamples.toDouble()))
                } else {
                    MIN_DBFS
                }

                synchronized(workerLock) {
                    activeCaptureSummary = mapOf(
                        "stopped" to true,
                        "sessionId" to sessionId,
                        "capturedSamples" to totalSamples,
                        "preRollSamples" to preRollCount,
                        "peakDbfs" to peakDbfs,
                        "avgDbfs" to avgDbfs,
                        "durationMs" to elapsedMs,
                        "sampleRateHz" to SAMPLE_RATE_HZ
                    )
                    if (activeSessionId == sessionId) {
                        isRunning.set(false)
                        activeSessionId = null
                        activeWorkerThread = null
                    }
                }
                VoiceSessionCoordinatorNative.releaseSession(sessionId, 1)
            }
        }, "LifeOsPcmCapture")

        synchronized(workerLock) {
            activeWorkerThread = worker
        }
        worker.start()
        return true
    }

    /**
     * Stops active local PCM capture (if matching [sessionId] or any active capture when null)
     * and waits deterministically for `AudioRecord.release()`.
     */
    fun stopCapture(sessionId: String? = null): Map<String, Any?> {
        val targetId = synchronized(workerLock) {
            val current = activeSessionId
            if (current == null || (sessionId != null && sessionId != current)) {
                return if (activeCaptureSummary.isNotEmpty() &&
                    (sessionId == null || activeCaptureSummary["sessionId"] == sessionId)
                ) {
                    activeCaptureSummary
                } else {
                    mapOf(
                        "stopped" to false,
                        "sessionId" to (sessionId ?: ""),
                        "capturedSamples" to 0L,
                        "preRollSamples" to 0,
                        "peakDbfs" to MIN_DBFS,
                        "avgDbfs" to MIN_DBFS,
                        "durationMs" to 0L,
                        "sampleRateHz" to SAMPLE_RATE_HZ
                    )
                }
            }
            current
        }

        cancelWorkerInternal(targetId)
        VoiceSessionCoordinatorNative.releaseSession(targetId, 1)
        return synchronized(workerLock) {
            activeCaptureSummary.ifEmpty {
                mapOf(
                    "stopped" to true,
                    "sessionId" to targetId,
                    "capturedSamples" to 0L,
                    "preRollSamples" to preRollCount,
                    "peakDbfs" to MIN_DBFS,
                    "avgDbfs" to MIN_DBFS,
                    "durationMs" to 0L,
                    "sampleRateHz" to SAMPLE_RATE_HZ
                )
            }
        }
    }

    /**
     * Drains the bounded 300ms (`4,800` sample) circular pre-roll buffer in chronological order.
     */
    fun drainPreRollBuffer(): ShortArray {
        synchronized(workerLock) {
            if (preRollCount <= 0) return ShortArray(0)
            val result = ShortArray(preRollCount)
            val start = if (preRollCount < PRE_ROLL_SAMPLES) 0 else preRollWriteIndex
            for (i in 0 until preRollCount) {
                result[i] = preRollRing[(start + i) % PRE_ROLL_SAMPLES]
            }
            preRollWriteIndex = 0
            preRollCount = 0
            return result
        }
    }

    private fun cancelWorkerInternal(expectedSessionId: String) {
        val threadToJoin: Thread?
        synchronized(workerLock) {
            if (activeSessionId != expectedSessionId) return
            isRunning.set(false)
            threadToJoin = activeWorkerThread
        }
        if (threadToJoin != null && threadToJoin !== Thread.currentThread()) {
            try {
                threadToJoin.join(500L)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun openAudioRecord(context: Context): AudioRecord? {
        if (ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }

        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE_HZ, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (minBuf <= 0) return null
        val bufferSizeBytes = max(minBuf * 2, FRAME_SAMPLES * 2 * 10).coerceAtMost(65_536)

        val sources = intArrayOf(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            MediaRecorder.AudioSource.MIC
        )
        for (source in sources) {
            val candidate = try {
                AudioRecord(
                    source,
                    SAMPLE_RATE_HZ,
                    CHANNEL_CONFIG,
                    AUDIO_FORMAT,
                    bufferSizeBytes
                )
            } catch (_: Exception) {
                null
            }
            if (candidate != null && candidate.state == AudioRecord.STATE_INITIALIZED) {
                return candidate
            }
            try {
                candidate?.release()
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun isOsMicMuted(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            am?.isMicrophoneMute == true
        } catch (_: Exception) {
            false
        }
    }

    private fun isActiveRecordingSilenced(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
            am.activeRecordingConfigurations.any { it.isClientSilenced }
        } catch (_: Exception) {
            false
        }
    }

    private fun rmsToDbfs(rms: Double): Double {
        if (rms <= 0.0) return MIN_DBFS
        return (20.0 * log10(rms / 32768.0)).coerceIn(MIN_DBFS, 0.0)
    }

    private fun postToMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }
}
