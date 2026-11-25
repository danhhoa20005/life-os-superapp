package vn.lifeos.app.life_os

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Process-wide singleton coordinator enforcing single-owner microphone arbitration across
 * `MainActivity`, `LifeOsWidgetQuickOverlayActivity`, and `LifeOsPcmAudioRecorder`.
 *
 * Also provides:
 * - Strictly monotonic session telemetry (`SystemClock.elapsedRealtime()`).
 * - Backward-compatible + v2 enriched event envelopes (`buildEventEnvelope`).
 * - Environment-keyed 24h TTL capability cache (`lifeos_voice_engine_caps_v2`).
 */
object VoiceSessionCoordinatorNative {

    const val OWNER_MAIN_ACTIVITY = "main_activity"
    const val OWNER_WIDGET_OVERLAY = "widget_overlay"
    const val OWNER_PCM_SELF_TEST = "pcm_self_test"
    const val OWNER_PCM_LOCAL_CAPTURE = "pcm_local_capture"

    private const val CAPS_PREFS_V2 = "lifeos_voice_engine_caps_v2"
    private const val LEGACY_CAPS_PREFS = "lifeos_voice_engine_caps"
    private const val KEY_CAP_PREFIX = "cap_"
    const val DEFAULT_CACHE_TTL_MS = 24L * 60L * 60L * 1000L

    private val stateLock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val fallbackSequence = AtomicInteger(0)

    data class SessionState(
        val sessionId: String,
        val attemptId: Int,
        val ownerId: String,
        @Volatile var engineId: String,
        val sequenceNumber: AtomicInteger = AtomicInteger(0),
        val startedAtMonotonicMs: Long = SystemClock.elapsedRealtime(),
        @Volatile var readyAtMonotonicMs: Long? = null,
        @Volatile var firstPartialAtMonotonicMs: Long? = null,
        @Volatile var finalAtMonotonicMs: Long? = null,
        @Volatile var retryCount: Int = 0,
        @Volatile var fallbackCount: Int = 0,
        @Volatile var lastErrorCode: String? = null,
        @Volatile var isTerminal: Boolean = false,
        var runCancelOnMain: Boolean = true,
        var cancelHook: (() -> Unit)? = null
    )

    @Volatile
    private var activeSession: SessionState? = null

    @Volatile
    private var latestSessionMetrics: SessionState? = null

    /**
     * Claims process-wide microphone ownership for `(ownerId, sessionId, attemptId)`.
     * If another session (same or different owner) is active, its cancel hook is invoked
     * FIRST and awaited before granting ownership to the new claimant.
     */
    fun claimSession(
        ownerId: String,
        sessionId: String,
        attemptId: Int,
        engineId: String,
        runCancelOnMain: Boolean = true,
        cancelHook: (() -> Unit)? = null
    ): SessionState {
        // Immediately silence Soundbox TTS before any mic handoff occurs.
        LifeOsSoundboxSpeaker.setMicrophoneActive(true)

        val prevCancel: (() -> Unit)?
        val prevOnMain: Boolean
        val nextSession = SessionState(
            sessionId = sessionId,
            attemptId = attemptId,
            ownerId = ownerId,
            engineId = engineId,
            startedAtMonotonicMs = SystemClock.elapsedRealtime(),
            runCancelOnMain = runCancelOnMain,
            cancelHook = cancelHook
        )

        synchronized(stateLock) {
            val prev = activeSession
            if (prev != null && !prev.isTerminal) {
                prev.isTerminal = true
                prevCancel = prev.cancelHook
                prevOnMain = prev.runCancelOnMain
                prev.cancelHook = null
                latestSessionMetrics = prev
            } else {
                prevCancel = null
                prevOnMain = false
            }
            activeSession = nextSession
            latestSessionMetrics = nextSession
        }

        if (prevCancel != null) {
            invokeCancelHookAndWait(prevCancel, prevOnMain)
        }

        // Re-assert mic lock after previous cancel hook finishes.
        LifeOsSoundboxSpeaker.setMicrophoneActive(true)
        return nextSession
    }

    private fun invokeCancelHookAndWait(cancelHook: () -> Unit, runOnMain: Boolean) {
        if (!runOnMain || Looper.myLooper() == Looper.getMainLooper()) {
            try {
                cancelHook.invoke()
            } catch (_: Exception) {
            }
            return
        }
        val latch = CountDownLatch(1)
        mainHandler.post {
            try {
                cancelHook.invoke()
            } catch (_: Exception) {
            } finally {
                latch.countDown()
            }
        }
        try {
            latch.await(600L, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    /**
     * Releases microphone ownership ONLY if [sessionId] (and optional [attemptId]) matches the
     * current active session, preventing stale teardowns from clearing a newer owner's mic lock.
     */
    fun releaseSession(sessionId: String?, attemptId: Int? = null) {
        if (sessionId.isNullOrBlank()) return
        val shouldClearMicLock: Boolean
        synchronized(stateLock) {
            val current = activeSession
            if (current != null &&
                current.sessionId == sessionId &&
                (attemptId == null || current.attemptId == attemptId)
            ) {
                current.isTerminal = true
                current.cancelHook = null
                latestSessionMetrics = current
                activeSession = null
                shouldClearMicLock = true
            } else {
                shouldClearMicLock = false
            }
        }
        if (shouldClearMicLock) {
            LifeOsSoundboxSpeaker.setMicrophoneActive(false)
        }
    }

    /**
     * Cancels the currently active session ONLY if it is held by a different [requestingOwnerId].
     */
    fun preemptIfOwnedByOther(requestingOwnerId: String) {
        val prevCancel: (() -> Unit)?
        val prevOnMain: Boolean
        var released = false
        synchronized(stateLock) {
            val current = activeSession
            if (current != null && !current.isTerminal && current.ownerId != requestingOwnerId) {
                current.isTerminal = true
                prevCancel = current.cancelHook
                prevOnMain = current.runCancelOnMain
                current.cancelHook = null
                latestSessionMetrics = current
                activeSession = null
                released = true
            } else {
                prevCancel = null
                prevOnMain = false
            }
        }
        if (prevCancel != null) {
            invokeCancelHookAndWait(prevCancel, prevOnMain)
        }
        if (released && activeSession == null) {
            LifeOsSoundboxSpeaker.setMicrophoneActive(false)
        }
    }

    fun isOwnedBy(ownerId: String): Boolean {
        val current = activeSession ?: return false
        return !current.isTerminal && current.ownerId == ownerId
    }

    fun isSessionActive(sessionId: String?, attemptId: Int? = null): Boolean {
        if (sessionId.isNullOrBlank()) return false
        val current = activeSession ?: return false
        if (current.isTerminal || current.sessionId != sessionId) return false
        return attemptId == null || current.attemptId == attemptId
    }

    fun updateSessionEngine(sessionId: String, attemptId: Int, engineId: String) {
        synchronized(stateLock) {
            val current = activeSession
            if (current != null && current.sessionId == sessionId && current.attemptId == attemptId) {
                current.engineId = engineId
            }
        }
    }

    fun markReady(sessionId: String, attemptId: Int) {
        synchronized(stateLock) {
            val current = activeSession
            if (current != null &&
                current.sessionId == sessionId &&
                current.attemptId == attemptId &&
                current.readyAtMonotonicMs == null
            ) {
                current.readyAtMonotonicMs = SystemClock.elapsedRealtime()
            }
        }
    }

    fun markFirstPartial(sessionId: String, attemptId: Int) {
        synchronized(stateLock) {
            val current = activeSession
            if (current != null &&
                current.sessionId == sessionId &&
                current.attemptId == attemptId &&
                current.firstPartialAtMonotonicMs == null
            ) {
                current.firstPartialAtMonotonicMs = SystemClock.elapsedRealtime()
            }
        }
    }

    fun markFinal(sessionId: String, attemptId: Int) {
        synchronized(stateLock) {
            val current = activeSession
            if (current != null &&
                current.sessionId == sessionId &&
                current.attemptId == attemptId
            ) {
                current.finalAtMonotonicMs = SystemClock.elapsedRealtime()
            }
        }
    }

    fun incrementRetry(sessionId: String, attemptId: Int) {
        synchronized(stateLock) {
            val current = activeSession
            if (current != null &&
                current.sessionId == sessionId &&
                current.attemptId == attemptId
            ) {
                current.retryCount += 1
            }
        }
    }

    fun incrementFallback(sessionId: String, attemptId: Int) {
        synchronized(stateLock) {
            val current = activeSession
            if (current != null &&
                current.sessionId == sessionId &&
                current.attemptId == attemptId
            ) {
                current.fallbackCount += 1
            }
        }
    }

    fun setLastErrorCode(sessionId: String, attemptId: Int, errorCode: String) {
        synchronized(stateLock) {
            val current = activeSession
            if (current != null &&
                current.sessionId == sessionId &&
                current.attemptId == attemptId
            ) {
                current.lastErrorCode = errorCode
            } else if (latestSessionMetrics?.sessionId == sessionId) {
                latestSessionMetrics?.lastErrorCode = errorCode
            }
        }
    }

    fun getDiagnosticsMetrics(): Map<String, Any?> {
        synchronized(stateLock) {
            val live = activeSession?.takeIf { !it.isTerminal }
            val ref = live ?: latestSessionMetrics
            val timeToReadyMs = if (ref?.readyAtMonotonicMs != null) {
                (ref.readyAtMonotonicMs!! - ref.startedAtMonotonicMs).coerceAtLeast(0L)
            } else {
                null
            }
            val timeToFirstPartialMs = if (ref?.firstPartialAtMonotonicMs != null) {
                (ref.firstPartialAtMonotonicMs!! - ref.startedAtMonotonicMs).coerceAtLeast(0L)
            } else {
                null
            }
            val timeToFinalMs = if (ref?.finalAtMonotonicMs != null) {
                (ref.finalAtMonotonicMs!! - ref.startedAtMonotonicMs).coerceAtLeast(0L)
            } else {
                null
            }
            return mapOf(
                "activeSessionId" to live?.sessionId,
                "activeAttemptId" to live?.attemptId,
                "activeOwnerId" to live?.ownerId,
                "lastErrorCode" to ref?.lastErrorCode,
                "timeToReadyMs" to timeToReadyMs,
                "timeToFirstPartialMs" to timeToFirstPartialMs,
                "timeToFinalMs" to timeToFinalMs,
                "retryCount" to (ref?.retryCount ?: 0),
                "fallbackCount" to (ref?.fallbackCount ?: 0)
            )
        }
    }

    /**
     * Builds an event payload containing BOTH v2 fields (`sessionId`, `attemptId`, `ownerId`,
     * `sequenceNumber`, `engineId`, `eventType`, `monotonicTimestampMs`) AND backward-compatible
     * legacy fields (`type`, `sessionToken`, plus event-specific fields from [extra]).
     */
    fun buildEventEnvelope(
        sessionId: String,
        attemptId: Int,
        ownerId: String,
        engineId: String,
        eventType: String,
        extra: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> {
        val seq = synchronized(stateLock) {
            val match = when {
                activeSession?.sessionId == sessionId -> activeSession
                latestSessionMetrics?.sessionId == sessionId -> latestSessionMetrics
                else -> null
            }
            match?.sequenceNumber?.incrementAndGet() ?: fallbackSequence.incrementAndGet()
        }

        val out = LinkedHashMap<String, Any?>(10 + extra.size)
        // Legacy wire keys consumed by `MethodChannelVoiceAssistantDriver.parseRawVoiceEvent`
        out["type"] = eventType
        out["sessionToken"] = sessionId
        // V2 structured telemetry & ordering keys
        out["sessionId"] = sessionId
        out["attemptId"] = attemptId
        out["ownerId"] = ownerId
        out["sequenceNumber"] = seq
        out["engineId"] = engineId
        out["eventType"] = eventType
        out["monotonicTimestampMs"] = SystemClock.elapsedRealtime()

        for ((k, v) in extra) {
            out[k] = v
        }
        return out
    }

    // -------------------------------------------------------------------------
    // TTL Capability Cache (`lifeos_voice_engine_caps_v2`, VOICE-008)
    // -------------------------------------------------------------------------

    fun resolveRecognitionServiceVersionCode(
        context: Context,
        engineId: String? = null
    ): Long {
        val appCtx = context.applicationContext
        val pkgName = when {
            engineId != null && engineId.startsWith("service:") ->
                engineId.removePrefix("service:").substringBefore('/').trim()
            engineId == "system_speech_dialog" || engineId == "on_device_speech_recognizer" ->
                "com.google.android.tts"
            else -> {
                val defaultFlat = try {
                    Settings.Secure.getString(
                        appCtx.contentResolver,
                        "voice_recognition_service"
                    ).orEmpty()
                } catch (_: Exception) {
                    ""
                }
                val defaultPkg = defaultFlat.substringBefore('/').trim()
                if (defaultPkg.isNotEmpty()) defaultPkg else "com.google.android.tts"
            }
        }
        if (pkgName.isEmpty()) return 0L
        return try {
            val pm = appCtx.packageManager
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(pkgName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkgName, 0)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
        } catch (_: Exception) {
            0L
        }
    }

    private fun buildCapabilityKey(
        engineId: String,
        sdkInt: Int,
        osBuild: String,
        serviceVersion: Long,
        locale: String,
        audioRoute: String
    ): String {
        val raw = "$engineId|$sdkInt|$osBuild|$serviceVersion|$locale|$audioRoute"
        val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray(Charsets.UTF_8))
        val hex = StringBuilder(digest.size * 2)
        for (b in digest) {
            hex.append(String.format("%02x", b))
        }
        return "$KEY_CAP_PREFIX$hex"
    }

    fun recordOutcome(
        context: Context,
        engineId: String,
        locale: String = "vi-VN",
        audioRoute: String = LifeOsAudioFocusCoordinator.detectCurrentAudioRoute(context),
        success: Boolean,
        errorCode: String? = null,
        serviceVersion: Long? = null
    ) {
        try {
            val appCtx = context.applicationContext
            val prefs = appCtx.getSharedPreferences(CAPS_PREFS_V2, Context.MODE_PRIVATE)
            val sdkInt = Build.VERSION.SDK_INT
            val osBuild = Build.FINGERPRINT ?: "unknown"
            val resolvedVer = serviceVersion ?: resolveRecognitionServiceVersionCode(appCtx, engineId)
            val key = buildCapabilityKey(engineId, sdkInt, osBuild, resolvedVer, locale, audioRoute)
            val nowEpochMs = System.currentTimeMillis()

            val existingRaw = prefs.getString(key, null)
            var prevSuccess = 0
            var prevError = 0
            if (!existingRaw.isNullOrBlank()) {
                try {
                    val obj = JSONObject(existingRaw)
                    val checkedAt = obj.optLong("checkedAtEpochMs", 0L)
                    val ttl = obj.optLong("ttlMs", DEFAULT_CACHE_TTL_MS)
                    val validEnv = obj.optString("engineId") == engineId &&
                        obj.optInt("sdkInt", -1) == sdkInt &&
                        obj.optString("osBuild") == osBuild &&
                        obj.optLong("serviceVersion", -1L) == resolvedVer &&
                        obj.optString("locale") == locale &&
                        obj.optString("audioRoute") == audioRoute
                    val withinTtl = nowEpochMs >= checkedAt && (nowEpochMs - checkedAt) <= ttl
                    if (validEnv && withinTtl) {
                        prevSuccess = obj.optInt("recentSuccessCount", 0)
                        prevError = obj.optInt("recentErrorCount", 0)
                    }
                } catch (_: Exception) {
                }
            }

            val nextSuccess = if (success) prevSuccess + 1 else prevSuccess
            val nextError = if (success) prevError else prevError + 1
            val payload = JSONObject().apply {
                put("engineId", engineId)
                put("sdkInt", sdkInt)
                put("osBuild", osBuild)
                put("serviceVersion", resolvedVer)
                put("locale", locale)
                put("audioRoute", audioRoute)
                put("checkedAtEpochMs", nowEpochMs)
                put("ttlMs", DEFAULT_CACHE_TTL_MS)
                put("recentSuccessCount", nextSuccess)
                put("recentErrorCount", nextError)
                if (errorCode != null) {
                    put("lastErrorCode", errorCode)
                }
            }
            prefs.edit().putString(key, payload.toString()).apply()
        } catch (_: Exception) {
        }
    }

    /**
     * Returns all valid (non-expired, environment-matching) capability cache entries and prunes
     * any expired or environment-mismatched entries automatically.
     */
    fun getCapabilitySnapshot(
        context: Context,
        locale: String = "vi-VN",
        audioRoute: String = LifeOsAudioFocusCoordinator.detectCurrentAudioRoute(context)
    ): Map<String, Any?> {
        val appCtx = context.applicationContext
        purgeLegacyCapabilityPrefs(appCtx)
        val prefs = appCtx.getSharedPreferences(CAPS_PREFS_V2, Context.MODE_PRIVATE)
        val sdkInt = Build.VERSION.SDK_INT
        val osBuild = Build.FINGERPRINT ?: "unknown"
        val nowEpochMs = System.currentTimeMillis()
        val editor = prefs.edit()
        var mutated = false
        val validEntries = mutableListOf<Map<String, Any?>>()

        for ((key, rawVal) in prefs.all) {
            if (!key.startsWith(KEY_CAP_PREFIX)) continue
            val rawStr = rawVal as? String
            if (rawStr.isNullOrBlank()) {
                editor.remove(key)
                mutated = true
                continue
            }
            val parsed = try {
                JSONObject(rawStr)
            } catch (_: Exception) {
                editor.remove(key)
                mutated = true
                continue
            }

            val entryEngineId = parsed.optString("engineId", "")
            val entrySdk = parsed.optInt("sdkInt", -1)
            val entryBuild = parsed.optString("osBuild", "")
            val entrySvcVer = parsed.optLong("serviceVersion", -1L)
            val entryLocale = parsed.optString("locale", "")
            val entryRoute = parsed.optString("audioRoute", "")
            val checkedAt = parsed.optLong("checkedAtEpochMs", 0L)
            val ttl = parsed.optLong("ttlMs", DEFAULT_CACHE_TTL_MS)
            val currentSvcVer = resolveRecognitionServiceVersionCode(appCtx, entryEngineId)

            val envMatches = entryEngineId.isNotEmpty() &&
                entrySdk == sdkInt &&
                entryBuild == osBuild &&
                entrySvcVer == currentSvcVer &&
                entryLocale == locale &&
                entryRoute == audioRoute
            val withinTtl = nowEpochMs >= checkedAt && (nowEpochMs - checkedAt) <= ttl

            if (!envMatches || !withinTtl) {
                editor.remove(key)
                mutated = true
                continue
            }

            validEntries.add(
                mapOf(
                    "engineId" to entryEngineId,
                    "sdkInt" to entrySdk,
                    "osBuild" to entryBuild,
                    "serviceVersion" to entrySvcVer,
                    "locale" to entryLocale,
                    "audioRoute" to entryRoute,
                    "checkedAtEpochMs" to checkedAt,
                    "ttlMs" to ttl,
                    "recentSuccessCount" to parsed.optInt("recentSuccessCount", 0),
                    "recentErrorCount" to parsed.optInt("recentErrorCount", 0),
                    "lastErrorCode" to parsed.optString("lastErrorCode", "").takeIf { it.isNotEmpty() }
                )
            )
        }

        if (mutated) {
            editor.apply()
        }

        return mapOf(
            "schemaVersion" to 2,
            "ttlMs" to DEFAULT_CACHE_TTL_MS,
            "locale" to locale,
            "audioRoute" to audioRoute,
            "entries" to validEntries
        )
    }

    fun resetCapabilityCache(context: Context) {
        try {
            val appCtx = context.applicationContext
            appCtx.getSharedPreferences(CAPS_PREFS_V2, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .apply()
            purgeLegacyCapabilityPrefs(appCtx)
        } catch (_: Exception) {
        }
    }

    private fun purgeLegacyCapabilityPrefs(appContext: Context) {
        try {
            val legacy = appContext.getSharedPreferences(LEGACY_CAPS_PREFS, Context.MODE_PRIVATE)
            if (legacy.all.isNotEmpty()) {
                legacy.edit().clear().apply()
            }
        } catch (_: Exception) {
        }
    }
}
