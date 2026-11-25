package vn.lifeos.app.life_os

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.text.NumberFormat
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

/**
 * Native Vietnamese "Loa Báo Tiền Về" (Voice Soundbox) powered by Android TextToSpeech.
 * Works 24/7 inside BankNotificationListenerService even when the Flutter UI is closed.
 *
 * Hardened v2:
 * - Mutual exclusion with active microphone sessions (`setMicrophoneActive(true)` stops TTS
 *   immediately and suppresses bank credit speech while the user is dictating).
 * - Recovers cleanly from `TextToSpeech` initialization failures (`tts = null`, `isReady = false`).
 * - Coordinates transient ducking AudioFocus (`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`).
 */
object LifeOsSoundboxSpeaker {
    private val lock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val utteranceCounter = AtomicLong(0L)

    @Volatile
    private var microphoneActive: Boolean = false

    @Volatile
    private var tts: TextToSpeech? = null

    @Volatile
    private var isReady: Boolean = false

    @Volatile
    private var pendingUtterance: String? = null

    private var appContext: Context? = null
    private var isInitializing: Boolean = false
    private var initGeneration: Long = 0L
    private var initCompleted: Boolean = false
    private var pendingInitStatus: Int? = null
    private var activeUtteranceId: String? = null

    private var duckFocusRequest: AudioFocusRequest? = null
    private var duckLegacyListener: AudioManager.OnAudioFocusChangeListener? = null
    private var hasDuckFocus: Boolean = false

    private val CREDIT_SIGNED_REGEX = Regex(
        "\\+\\s*(\\d{1,3}(?:[.,]\\d{3})+(?:[.,]00)?|\\d{4,15})(?:\\s*(?:VND|VNĐ|đ|₫|d))?",
        RegexOption.IGNORE_CASE
    )
    private val CREDIT_VERB_REGEX = Regex(
        "\\b(nh[aậ]n\\s*đ[uư][oợ]c|c[oộ]ng|ghi\\s*c[oó])\\s+(\\d{1,3}(?:[.,]\\d{3})+|\\d{4,15})\\s*(?:VND|VNĐ|đ|₫)",
        RegexOption.IGNORE_CASE
    )

    private fun bankSpokenName(pkg: String): String {
        return when (pkg) {
            "com.VCB" -> "Vietcombank"
            "com.mbmobile" -> "MB Bank"
            "com.techcombank.bb.app" -> "Techcombank"
            "mobile.acb.com.vn" -> "ACB"
            "com.vietinbank.ipay" -> "VietinBank"
            "com.tpb.mb.gprsandroid" -> "TPBank"
            "com.vnpay.bidv" -> "BIDV"
            "com.vnpay.vpbankonline" -> "VPBank"
            "com.mservice.momotransfer" -> "MoMo"
            "vn.com.vng.zalopay" -> "ZaloPay"
            else -> "tài khoản"
        }
    }

    private fun parsePositiveVnd(raw: String): Long? {
        var cleaned = raw.trim()
        if (cleaned.endsWith(".00") || cleaned.endsWith(",00")) {
            cleaned = cleaned.substring(0, cleaned.length - 3)
        }
        val digits = cleaned.replace(Regex("[^0-9]"), "")
        return digits.toLongOrNull()?.takeIf { it > 0L }
    }

    fun setMicrophoneActive(active: Boolean) {
        microphoneActive = active
        if (active) {
            stopSpeaking()
        }
    }

    fun isMicrophoneActive(): Boolean = microphoneActive

    fun onBankNotificationCaptured(context: Context, packageName: String, combinedText: String) {
        if (microphoneActive) return
        var rawAmount: String? = CREDIT_SIGNED_REGEX.find(combinedText)?.groupValues?.getOrNull(1)
        if (rawAmount == null) {
            rawAmount = CREDIT_VERB_REGEX.find(combinedText)?.groupValues?.getOrNull(2)
        }
        val amount = rawAmount?.let { parsePositiveVnd(it) } ?: return
        val formatted = NumberFormat.getIntegerInstance(Locale.forLanguageTag("vi-VN")).format(amount)
        val bank = bankSpokenName(packageName)
        speak(context, "Đã nhận $formatted đồng vào $bank")
    }

    fun speak(context: Context, message: String) {
        if (microphoneActive || message.isBlank()) return
        val appCtx = context.applicationContext

        val shouldCreateTts: Boolean
        val generation: Long
        synchronized(lock) {
            if (microphoneActive) return
            appContext = appCtx
            if (tts == null && !isInitializing) {
                initGeneration += 1L
                generation = initGeneration
                isInitializing = true
                isReady = false
                initCompleted = false
                pendingInitStatus = null
                pendingUtterance = message
                shouldCreateTts = true
            } else {
                generation = initGeneration
                shouldCreateTts = false
                if (isReady && tts != null) {
                    speakNowLocked(appCtx, tts!!, message)
                } else {
                    pendingUtterance = message
                }
            }
        }

        if (!shouldCreateTts) return

        val created = try {
            TextToSpeech(appCtx) { status ->
                handleInitCallback(generation, status)
            }
        } catch (_: Exception) {
            synchronized(lock) {
                if (initGeneration == generation) {
                    tts = null
                    isReady = false
                    isInitializing = false
                    initCompleted = false
                    pendingInitStatus = null
                    pendingUtterance = null
                }
            }
            return
        }

        synchronized(lock) {
            if (initGeneration != generation) {
                try {
                    created.shutdown()
                } catch (_: Exception) {
                }
                return
            }
            tts = created
            if (initCompleted) {
                finalizeInitLocked(created, pendingInitStatus ?: TextToSpeech.ERROR)
            }
        }
    }

    private fun handleInitCallback(generation: Long, status: Int) {
        synchronized(lock) {
            if (initGeneration != generation) return
            initCompleted = true
            pendingInitStatus = status
            val instance = tts
            if (instance != null) {
                finalizeInitLocked(instance, status)
            }
        }
    }

    private fun finalizeInitLocked(instance: TextToSpeech, status: Int) {
        isInitializing = false
        if (status != TextToSpeech.SUCCESS) {
            // Reset cleanly so future attempts can re-initialize instead of failing permanently.
            tts = null
            isReady = false
            pendingUtterance = null
            activeUtteranceId = null
            abandonDuckFocusLocked()
            try {
                instance.shutdown()
            } catch (_: Exception) {
            }
            return
        }

        configureLanguageSafely(instance)
        try {
            instance.setSpeechRate(1.02f)
            instance.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
        } catch (_: Exception) {
        }

        try {
            instance.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}

                override fun onDone(utteranceId: String?) {
                    onUtteranceFinished(utteranceId)
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    onUtteranceFinished(utteranceId)
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    onUtteranceFinished(utteranceId)
                }

                override fun onStop(utteranceId: String?, interrupted: Boolean) {
                    onUtteranceFinished(utteranceId)
                }
            })
        } catch (_: Exception) {
        }

        isReady = true
        val queued = pendingUtterance
        pendingUtterance = null
        val ctx = appContext
        if (!microphoneActive && ctx != null && !queued.isNullOrBlank()) {
            speakNowLocked(ctx, instance, queued)
        }
    }

    private fun configureLanguageSafely(instance: TextToSpeech) {
        try {
            val viLocale = Locale.forLanguageTag("vi-VN")
            val viResult = instance.setLanguage(viLocale)
            if (viResult == TextToSpeech.LANG_MISSING_DATA ||
                viResult == TextToSpeech.LANG_NOT_SUPPORTED
            ) {
                val genericVi = Locale.forLanguageTag("vi")
                val genericResult = instance.setLanguage(genericVi)
                if (genericResult == TextToSpeech.LANG_MISSING_DATA ||
                    genericResult == TextToSpeech.LANG_NOT_SUPPORTED
                ) {
                    // Graceful fallback to device default locale without crashing.
                    instance.setLanguage(Locale.getDefault())
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun speakNowLocked(context: Context, instance: TextToSpeech, message: String) {
        if (microphoneActive) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val audioMode = try {
            am?.mode ?: AudioManager.MODE_NORMAL
        } catch (_: Exception) {
            AudioManager.MODE_NORMAL
        }
        if (audioMode == AudioManager.MODE_IN_CALL || audioMode == AudioManager.MODE_RINGTONE) {
            return
        }

        requestDuckFocusLocked(context)
        val utteranceId = "lifeos_soundbox_${utteranceCounter.incrementAndGet()}"
        activeUtteranceId = utteranceId
        try {
            val speakResult = instance.speak(message, TextToSpeech.QUEUE_ADD, null, utteranceId)
            if (speakResult == TextToSpeech.ERROR) {
                activeUtteranceId = null
                abandonDuckFocusLocked()
            }
        } catch (_: Exception) {
            activeUtteranceId = null
            abandonDuckFocusLocked()
        }
    }

    private fun onUtteranceFinished(utteranceId: String?) {
        synchronized(lock) {
            if (utteranceId == null || utteranceId == activeUtteranceId) {
                activeUtteranceId = null
                abandonDuckFocusLocked()
            }
        }
    }

    private fun requestDuckFocusLocked(context: Context) {
        if (hasDuckFocus) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val listener = AudioManager.OnAudioFocusChangeListener { change ->
            if (change == AudioManager.AUDIOFOCUS_LOSS ||
                change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
            ) {
                stopSpeaking()
            }
        }
        val status = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                    .setAudioAttributes(attrs)
                    .setAcceptsDelayedFocusGain(false)
                    .setOnAudioFocusChangeListener(listener, mainHandler)
                    .build()
                duckFocusRequest = req
                duckLegacyListener = null
                am.requestAudioFocus(req)
            } else {
                duckFocusRequest = null
                duckLegacyListener = listener
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    listener,
                    AudioManager.STREAM_NOTIFICATION,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                )
            }
        } catch (_: Exception) {
            AudioManager.AUDIOFOCUS_REQUEST_FAILED
        }
        hasDuckFocus = status == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (!hasDuckFocus) {
            duckFocusRequest = null
            duckLegacyListener = null
        }
    }

    private fun abandonDuckFocusLocked() {
        val ctx = appContext
        val req = duckFocusRequest
        val legacy = duckLegacyListener
        duckFocusRequest = null
        duckLegacyListener = null
        hasDuckFocus = false
        if (ctx == null) return
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (req != null) {
                    am.abandonAudioFocusRequest(req)
                }
            } else if (legacy != null) {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(legacy)
            }
        } catch (_: Exception) {
        }
    }

    fun stopSpeaking() {
        val currentTts: TextToSpeech?
        synchronized(lock) {
            pendingUtterance = null
            activeUtteranceId = null
            currentTts = tts
            abandonDuckFocusLocked()
        }
        try {
            currentTts?.stop()
        } catch (_: Exception) {
        }
    }

    fun shutdown() {
        val currentTts: TextToSpeech?
        synchronized(lock) {
            initGeneration += 1L
            isInitializing = false
            isReady = false
            initCompleted = false
            pendingInitStatus = null
            pendingUtterance = null
            activeUtteranceId = null
            currentTts = tts
            tts = null
            abandonDuckFocusLocked()
        }
        try {
            currentTts?.stop()
        } catch (_: Exception) {
        }
        try {
            currentTts?.shutdown()
        } catch (_: Exception) {
        }
    }
}
