package vn.lifeos.app.life_os

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LifeOsWidgetVoicePolicyTest {

    private class FakeVoiceGateway : WidgetVoiceRecognizerGateway {
        var onDeviceCalls = 0
        var networkSpeechCalls = 0
        var systemDialogCalls = 0
        var manualInputCalls = 0
        var lastManualMessage: String? = null
        var lastNetworkEngineMode: String? = null

        override fun startOnDevice(sessionId: String, attemptId: Int, locale: String) {
            onDeviceCalls += 1
        }

        override fun startNetworkSpeech(
            sessionId: String,
            attemptId: Int,
            engineMode: String,
            locale: String
        ) {
            networkSpeechCalls += 1
            lastNetworkEngineMode = engineMode
        }

        override fun launchSystemDialog(sessionId: String, attemptId: Int, locale: String) {
            systemDialogCalls += 1
        }

        override fun showOfflineManualInput(messageVi: String) {
            manualInputCalls += 1
            lastManualMessage = messageVi
        }
    }

    @Test
    fun strictOffline_beforeAndAfterPermission_neverInvokesNetworkRecognizerWhenOnDeviceReady() {
        val beforeGateway = FakeVoiceGateway()
        var permRequests = 0

        val input = WidgetVoiceCapabilityInput(
            storedModeWire = "offline_strict",
            sdkInt = 33,
            isOnDeviceRecognitionAvailable = true,
            vietnameseOnDeviceInstalled = true,
            isNetworkAvailable = true
        )

        // 1. Before permission check when permission is NOT yet granted
        val beforeDeniedPermDecision = LifeOsWidgetVoicePolicy.executeBeforePermission(
            hasAudioPermission = false,
            input = input,
            sessionId = "s1",
            attemptId = 1,
            requestMicPermission = { permRequests += 1 },
            gateway = beforeGateway
        )
        assertEquals(WidgetVoiceEngineChoice.ON_DEVICE_ONLY, beforeDeniedPermDecision.choice)
        assertTrue(beforeDeniedPermDecision.strictOffline)
        assertFalse(beforeDeniedPermDecision.allowNetworkFallback)
        assertEquals(1, permRequests)
        assertEquals(0, beforeGateway.networkSpeechCalls)
        assertEquals(0, beforeGateway.systemDialogCalls)
        assertEquals(0, beforeGateway.onDeviceCalls)

        // 2. Before permission path when permission IS already granted
        val beforeGrantedGateway = FakeVoiceGateway()
        val beforeGrantedDecision = LifeOsWidgetVoicePolicy.executeBeforePermission(
            hasAudioPermission = true,
            input = input,
            sessionId = "s2",
            attemptId = 1,
            requestMicPermission = { permRequests += 1 },
            gateway = beforeGrantedGateway
        )
        assertEquals(WidgetVoiceEngineChoice.ON_DEVICE_ONLY, beforeGrantedDecision.choice)
        assertEquals(1, beforeGrantedGateway.onDeviceCalls)
        assertEquals(0, beforeGrantedGateway.networkSpeechCalls)
        assertEquals(0, beforeGrantedGateway.systemDialogCalls)

        // 3. After permission granted path
        val afterGateway = FakeVoiceGateway()
        val afterDecision = LifeOsWidgetVoicePolicy.executeAfterPermission(
            permissionGranted = true,
            input = input,
            sessionId = "s3",
            attemptId = 1,
            onPermissionDenied = {},
            gateway = afterGateway
        )
        assertEquals(WidgetVoiceEngineChoice.ON_DEVICE_ONLY, afterDecision?.choice)
        assertEquals(1, afterGateway.onDeviceCalls)
        assertEquals(0, afterGateway.networkSpeechCalls)
        assertEquals(0, afterGateway.systemDialogCalls)
    }

    @Test
    fun strictOffline_whenLocalVietnameseUnavailable_neverFallsBackToNetworkOrSystemDialog() {
        val unavailableCases = listOf(
            WidgetVoiceCapabilityInput(
                storedModeWire = "offline_strict",
                sdkInt = 30, // API < 31
                isOnDeviceRecognitionAvailable = false,
                vietnameseOnDeviceInstalled = false,
                isNetworkAvailable = true
            ),
            WidgetVoiceCapabilityInput(
                storedModeWire = "offline_strict",
                sdkInt = 34,
                isOnDeviceRecognitionAvailable = false,
                vietnameseOnDeviceInstalled = false,
                isNetworkAvailable = true
            ),
            WidgetVoiceCapabilityInput(
                storedModeWire = "offline_strict",
                sdkInt = 34,
                isOnDeviceRecognitionAvailable = true,
                vietnameseOnDeviceInstalled = false, // Language pack missing
                isNetworkAvailable = true
            )
        )

        for ((idx, input) in unavailableCases.withIndex()) {
            val beforeGateway = FakeVoiceGateway()
            var permRequested = false
            val beforeDecision = LifeOsWidgetVoicePolicy.executeBeforePermission(
                hasAudioPermission = false,
                input = input,
                sessionId = "before_$idx",
                attemptId = 1,
                requestMicPermission = { permRequested = true },
                gateway = beforeGateway
            )
            assertEquals(WidgetVoiceEngineChoice.BLOCKED_OFFLINE_UNAVAILABLE, beforeDecision.choice)
            assertTrue(beforeDecision.showManualInputPrompt)
            assertFalse(beforeDecision.allowNetworkFallback)
            assertFalse(permRequested)
            assertEquals(0, beforeGateway.networkSpeechCalls)
            assertEquals(0, beforeGateway.systemDialogCalls)
            assertEquals(0, beforeGateway.onDeviceCalls)
            assertEquals(1, beforeGateway.manualInputCalls)

            val afterGateway = FakeVoiceGateway()
            val afterDecision = LifeOsWidgetVoicePolicy.executeAfterPermission(
                permissionGranted = true,
                input = input,
                sessionId = "after_$idx",
                attemptId = 1,
                onPermissionDenied = {},
                gateway = afterGateway
            )
            assertEquals(WidgetVoiceEngineChoice.BLOCKED_OFFLINE_UNAVAILABLE, afterDecision?.choice)
            assertEquals(0, afterGateway.networkSpeechCalls)
            assertEquals(0, afterGateway.systemDialogCalls)
            assertEquals(0, afterGateway.onDeviceCalls)
            assertEquals(1, afterGateway.manualInputCalls)
        }
    }

    @Test
    fun afterPermissionDenied_neverInvokesAnyRecognizer() {
        val gateway = FakeVoiceGateway()
        var deniedCalled = false
        val input = WidgetVoiceCapabilityInput(
            storedModeWire = "offline_strict",
            sdkInt = 33,
            isOnDeviceRecognitionAvailable = true,
            vietnameseOnDeviceInstalled = true
        )

        val result = LifeOsWidgetVoicePolicy.executeAfterPermission(
            permissionGranted = false,
            input = input,
            sessionId = "denied_1",
            attemptId = 1,
            onPermissionDenied = { deniedCalled = true },
            gateway = gateway
        )

        assertNull(result)
        assertTrue(deniedCalled)
        assertEquals(0, gateway.networkSpeechCalls)
        assertEquals(0, gateway.systemDialogCalls)
        assertEquals(0, gateway.onDeviceCalls)
    }

    @Test
    fun systemDialogAndHybridAutoAndGoogleService_routeFaithfully() {
        val dialogGateway = FakeVoiceGateway()
        val dialogDecision = LifeOsWidgetVoicePolicy.executeAfterPermission(
            permissionGranted = true,
            input = WidgetVoiceCapabilityInput("system_dialog", 33, true, true, true),
            sessionId = "d1",
            attemptId = 1,
            onPermissionDenied = {},
            gateway = dialogGateway
        )
        assertEquals(WidgetVoiceEngineChoice.SYSTEM_DIALOG, dialogDecision?.choice)
        assertEquals(1, dialogGateway.systemDialogCalls)
        assertEquals(0, dialogGateway.networkSpeechCalls)

        val hybridOfflineGateway = FakeVoiceGateway()
        val hybridOfflineDecision = LifeOsWidgetVoicePolicy.executeAfterPermission(
            permissionGranted = true,
            input = WidgetVoiceCapabilityInput("hybrid_auto", 33, true, true, isNetworkAvailable = false),
            sessionId = "h1",
            attemptId = 1,
            onPermissionDenied = {},
            gateway = hybridOfflineGateway
        )
        assertEquals(WidgetVoiceEngineChoice.ON_DEVICE_ONLY, hybridOfflineDecision?.choice)
        assertEquals(1, hybridOfflineGateway.onDeviceCalls)
        assertEquals(0, hybridOfflineGateway.networkSpeechCalls)

        val googleGateway = FakeVoiceGateway()
        val googleDecision = LifeOsWidgetVoicePolicy.executeAfterPermission(
            permissionGranted = true,
            input = WidgetVoiceCapabilityInput("google_service", 33, true, true, isNetworkAvailable = true),
            sessionId = "g1",
            attemptId = 1,
            onPermissionDenied = {},
            gateway = googleGateway
        )
        assertEquals(WidgetVoiceEngineChoice.GOOGLE_SERVICE_INLINE, googleDecision?.choice)
        assertEquals(1, googleGateway.networkSpeechCalls)
        assertEquals("google_service", googleGateway.lastNetworkEngineMode)
    }

    @Test
    fun resolveStoredVoiceMode_respectsAccountVaultPriorityAndNormalizesAllModes() {
        assertEquals(
            "offline_strict",
            LifeOsWidgetVoicePolicy.resolveStoredVoiceMode(
                vaultScopedValue = "offline_strict",
                widgetPrefsValue = "google_service",
                vaultDefaultValue = "google_service",
                flutterSharedPrefsValue = "system_dialog"
            )
        )
        assertEquals(
            "hybrid_auto",
            LifeOsWidgetVoicePolicy.resolveStoredVoiceMode(
                vaultScopedValue = null,
                widgetPrefsValue = null,
                vaultDefaultValue = null,
                flutterSharedPrefsValue = "hybrid_auto"
            )
        )
        assertEquals(
            "google_service",
            LifeOsWidgetVoicePolicy.resolveStoredVoiceMode(null, null, null, null)
        )
        assertEquals(
            "flutter.ux_preferred_voice_engine_mode_v2",
            LifeOsWidgetVoicePolicy.FLUTTER_PREF_KEY_VOICE_MODE
        )
    }
}
