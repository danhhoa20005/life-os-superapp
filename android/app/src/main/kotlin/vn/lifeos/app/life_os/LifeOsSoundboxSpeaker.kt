package vn.lifeos.app.life_os

import android.content.Context
import android.speech.tts.TextToSpeech
import java.text.NumberFormat
import java.util.Locale

/**
 * Native Vietnamese "Loa Báo Tiền Về" (Voice Soundbox) powered by Android TextToSpeech.
 * Works 24/7 inside BankNotificationListenerService even when the Flutter UI is closed.
 */
object LifeOsSoundboxSpeaker {
    @Volatile
    private var tts: TextToSpeech? = null

    @Volatile
    private var isReady: Boolean = false

    @Volatile
    private var pendingUtterance: String? = null

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

    fun onBankNotificationCaptured(context: Context, packageName: String, combinedText: String) {
        var rawAmount: String? = CREDIT_SIGNED_REGEX.find(combinedText)?.groupValues?.getOrNull(1)
        if (rawAmount == null) {
            rawAmount = CREDIT_VERB_REGEX.find(combinedText)?.groupValues?.getOrNull(2)
        }
        val amount = rawAmount?.let { parsePositiveVnd(it) } ?: return
        val formatted = NumberFormat.getIntegerInstance(Locale("vi", "VN")).format(amount)
        val bank = bankSpokenName(packageName)
        speak(context, "Đã nhận $formatted đồng vào $bank")
    }

    @Synchronized
    fun speak(context: Context, message: String) {
        if (message.isBlank()) return
        val appCtx = context.applicationContext
        if (tts == null) {
            pendingUtterance = message
            tts = TextToSpeech(appCtx) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val viLocale = Locale("vi", "VN")
                    tts?.language = viLocale
                    tts?.setSpeechRate(1.02f)
                    isReady = true
                    val queued = pendingUtterance
                    pendingUtterance = null
                    if (!queued.isNullOrBlank()) {
                        tts?.speak(queued, TextToSpeech.QUEUE_ADD, null, "lifeos_soundbox_${System.currentTimeMillis()}")
                    }
                }
            }
            return
        }
        if (isReady) {
            tts?.speak(message, TextToSpeech.QUEUE_ADD, null, "lifeos_soundbox_${System.currentTimeMillis()}")
        } else {
            pendingUtterance = message
        }
    }
}
