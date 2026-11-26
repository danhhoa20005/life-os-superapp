package vn.lifeos.app.life_os

enum class WidgetVoiceEngineChoice {
    ON_DEVICE_ONLY,
    GOOGLE_SERVICE_INLINE,
    SYSTEM_DIALOG,
    BLOCKED_OFFLINE_UNAVAILABLE
}

data class WidgetVoiceCapabilityInput(
    val storedModeWire: String?,
    val sdkInt: Int,
    val isOnDeviceRecognitionAvailable: Boolean,
    val vietnameseOnDeviceInstalled: Boolean?,
    val isNetworkAvailable: Boolean = true
)

data class WidgetVoiceDecision(
    val normalizedModeWire: String,
    val choice: WidgetVoiceEngineChoice,
    val engineModeArg: String,
    val preferSystemDialog: Boolean,
    val strictOffline: Boolean,
    val allowNetworkFallback: Boolean,
    val statusMessageVi: String,
    val showManualInputPrompt: Boolean
)

interface WidgetVoiceRecognizerGateway {
    fun startOnDevice(sessionId: String, attemptId: Int, locale: String)
    fun startNetworkSpeech(sessionId: String, attemptId: Int, engineMode: String, locale: String)
    fun launchSystemDialog(sessionId: String, attemptId: Int, locale: String)
    fun showOfflineManualInput(messageVi: String)
}

/**
 * Pure Kotlin voice-engine decision policy shared between Flutter preferences and Android Home Widgets.
 * Enforces strict offline isolation so `offline_strict` NEVER invokes network speech or system dialog.
 */
object LifeOsWidgetVoicePolicy {
    const val PREF_BASE_KEY_VOICE_MODE = "ux_preferred_voice_engine_mode_v2"
    const val FLUTTER_PREF_KEY_VOICE_MODE = "flutter.ux_preferred_voice_engine_mode_v2"
    const val DEFAULT_MODE_WIRE = "google_service"

    fun scopedVaultKey(userId: String?): String {
        val cleaned = userId?.trim().orEmpty()
        return if (cleaned.isEmpty()) {
            PREF_BASE_KEY_VOICE_MODE
        } else {
            "${PREF_BASE_KEY_VOICE_MODE}__u_$cleaned"
        }
    }

    fun isVoiceEngineModeVaultKey(key: String): Boolean {
        return key == PREF_BASE_KEY_VOICE_MODE || key.startsWith("${PREF_BASE_KEY_VOICE_MODE}__u_")
    }

    fun extractUserIdFromScopedKey(key: String): String? {
        if (!key.contains("__u_")) return null
        return key.substringAfter("__u_", "").trim().takeIf { it.isNotEmpty() }
    }

    fun normalizeEngineMode(raw: String?): String {
        return when (raw?.trim()?.lowercase()) {
            "offline_strict", "on_device" -> "offline_strict"
            "system_dialog", "system_speech_dialog" -> "system_dialog"
            "hybrid_auto", "auto" -> "hybrid_auto"
            "online_google" -> "online_google"
            "google_service" -> "google_service"
            else -> DEFAULT_MODE_WIRE
        }
    }

    fun resolveStoredVoiceMode(
        vaultScopedValue: String?,
        widgetPrefsValue: String?,
        vaultDefaultValue: String?,
        flutterSharedPrefsValue: String?
    ): String {
        val raw = listOf(
            vaultScopedValue,
            widgetPrefsValue,
            vaultDefaultValue,
            flutterSharedPrefsValue
        ).firstOrNull { !it.isNullOrBlank() }
        return normalizeEngineMode(raw)
    }

    fun decide(input: WidgetVoiceCapabilityInput): WidgetVoiceDecision {
        val mode = normalizeEngineMode(input.storedModeWire)
        return when (mode) {
            "offline_strict" -> {
                val canUseOnDevice = input.sdkInt >= 31 &&
                    input.isOnDeviceRecognitionAvailable &&
                    input.vietnameseOnDeviceInstalled != false
                if (canUseOnDevice) {
                    WidgetVoiceDecision(
                        normalizedModeWire = "offline_strict",
                        choice = WidgetVoiceEngineChoice.ON_DEVICE_ONLY,
                        engineModeArg = "offline_strict",
                        preferSystemDialog = false,
                        strictOffline = true,
                        allowNetworkFallback = false,
                        statusMessageVi = "Đang khởi động nhận diện Offline tiếng Việt (Chỉ trên máy)...",
                        showManualInputPrompt = false
                    )
                } else {
                    val guidance = if (input.sdkInt < 31 || !input.isOnDeviceRecognitionAvailable) {
                        "Chế độ Chỉ Offline yêu cầu Android 12+ và bộ nhận diện trên máy. Hãy tải gói tiếng Việt ngoại tuyến hoặc gõ nội dung bên dưới."
                    } else {
                        "Chưa tải gói tiếng Việt ngoại tuyến trên thiết bị. Hãy vào Cài đặt giọng nói để tải gói tiếng Việt, hoặc gõ nội dung bên dưới."
                    }
                    WidgetVoiceDecision(
                        normalizedModeWire = "offline_strict",
                        choice = WidgetVoiceEngineChoice.BLOCKED_OFFLINE_UNAVAILABLE,
                        engineModeArg = "offline_strict",
                        preferSystemDialog = false,
                        strictOffline = true,
                        allowNetworkFallback = false,
                        statusMessageVi = guidance,
                        showManualInputPrompt = true
                    )
                }
            }
            "system_dialog" -> WidgetVoiceDecision(
                normalizedModeWire = "system_dialog",
                choice = WidgetVoiceEngineChoice.SYSTEM_DIALOG,
                engineModeArg = "system_dialog",
                preferSystemDialog = true,
                strictOffline = false,
                allowNetworkFallback = true,
                statusMessageVi = "Đang mở Hộp thoại Google tiếng Việt...",
                showManualInputPrompt = false
            )
            "hybrid_auto" -> {
                val canOfflineFallback = !input.isNetworkAvailable &&
                    input.sdkInt >= 31 &&
                    input.isOnDeviceRecognitionAvailable &&
                    input.vietnameseOnDeviceInstalled != false
                if (canOfflineFallback) {
                    WidgetVoiceDecision(
                        normalizedModeWire = "hybrid_auto",
                        choice = WidgetVoiceEngineChoice.ON_DEVICE_ONLY,
                        engineModeArg = "offline_strict",
                        preferSystemDialog = false,
                        strictOffline = true,
                        allowNetworkFallback = false,
                        statusMessageVi = "Đang dùng nhận diện Offline tiếng Việt trên thiết bị...",
                        showManualInputPrompt = false
                    )
                } else {
                    WidgetVoiceDecision(
                        normalizedModeWire = "hybrid_auto",
                        choice = WidgetVoiceEngineChoice.GOOGLE_SERVICE_INLINE,
                        engineModeArg = "hybrid_auto",
                        preferSystemDialog = false,
                        strictOffline = false,
                        allowNetworkFallback = true,
                        statusMessageVi = "Đang khởi động nhận diện giọng nói tự động...",
                        showManualInputPrompt = false
                    )
                }
            }
            else -> WidgetVoiceDecision(
                normalizedModeWire = mode,
                choice = WidgetVoiceEngineChoice.GOOGLE_SERVICE_INLINE,
                engineModeArg = "google_service",
                preferSystemDialog = false,
                strictOffline = false,
                allowNetworkFallback = true,
                statusMessageVi = "Đang khởi động Google Speech tiếng Việt...",
                showManualInputPrompt = false
            )
        }
    }

    fun executeBeforePermission(
        hasAudioPermission: Boolean,
        input: WidgetVoiceCapabilityInput,
        sessionId: String,
        attemptId: Int,
        locale: String = "vi-VN",
        requestMicPermission: () -> Unit,
        gateway: WidgetVoiceRecognizerGateway
    ): WidgetVoiceDecision {
        val decision = decide(input)
        if (decision.choice == WidgetVoiceEngineChoice.BLOCKED_OFFLINE_UNAVAILABLE) {
            gateway.showOfflineManualInput(decision.statusMessageVi)
            return decision
        }
        if (!hasAudioPermission) {
            requestMicPermission()
            return decision
        }
        dispatchDecision(decision, sessionId, attemptId, locale, gateway)
        return decision
    }

    fun executeAfterPermission(
        permissionGranted: Boolean,
        input: WidgetVoiceCapabilityInput,
        sessionId: String,
        attemptId: Int,
        locale: String = "vi-VN",
        onPermissionDenied: () -> Unit,
        gateway: WidgetVoiceRecognizerGateway
    ): WidgetVoiceDecision? {
        if (!permissionGranted) {
            onPermissionDenied()
            return null
        }
        val decision = decide(input)
        dispatchDecision(decision, sessionId, attemptId, locale, gateway)
        return decision
    }

    private fun dispatchDecision(
        decision: WidgetVoiceDecision,
        sessionId: String,
        attemptId: Int,
        locale: String,
        gateway: WidgetVoiceRecognizerGateway
    ) {
        when (decision.choice) {
            WidgetVoiceEngineChoice.ON_DEVICE_ONLY ->
                gateway.startOnDevice(sessionId, attemptId, locale)
            WidgetVoiceEngineChoice.GOOGLE_SERVICE_INLINE ->
                gateway.startNetworkSpeech(sessionId, attemptId, decision.engineModeArg, locale)
            WidgetVoiceEngineChoice.SYSTEM_DIALOG ->
                gateway.launchSystemDialog(sessionId, attemptId, locale)
            WidgetVoiceEngineChoice.BLOCKED_OFFLINE_UNAVAILABLE ->
                gateway.showOfflineManualInput(decision.statusMessageVi)
        }
    }
}
