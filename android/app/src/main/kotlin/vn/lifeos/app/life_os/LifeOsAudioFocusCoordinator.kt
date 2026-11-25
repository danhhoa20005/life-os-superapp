package vn.lifeos.app.life_os

import android.content.Context
import android.hardware.SensorPrivacyManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Coordinates transient exclusive AudioFocus for active voice capture (`SpeechRecognizer` and
 * `AudioRecord`), exposes truthful input audio-route detection, and safely checks OS microphone
 * mute / privacy state using ONLY public Android SDK APIs.
 */
class LifeOsAudioFocusCoordinator(context: Context) {

    private val appContext: Context = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()

    private var focusRequest: AudioFocusRequest? = null
    private var legacyFocusListener: AudioManager.OnAudioFocusChangeListener? = null
    private var activeFocusGeneration: Long = 0L
    private var hasFocus: Boolean = false
    private var focusLostCallback: ((permanent: Boolean) -> Unit)? = null

    companion object {
        const val ROUTE_BLUETOOTH_SCO = "bluetooth_sco"
        const val ROUTE_BLUETOOTH_BLE = "bluetooth_ble"
        const val ROUTE_USB_HEADSET = "usb_headset"
        const val ROUTE_WIRED_HEADSET = "wired_headset"
        const val ROUTE_BUILT_IN_MIC = "built_in_mic"
        const val ROUTE_UNKNOWN = "unknown"

        /**
         * Detects the current audio input route via public Android [AudioManager] APIs.
         */
        fun detectCurrentAudioRoute(context: Context): String {
            return try {
                val am = context.applicationContext
                    .getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    ?: return ROUTE_UNKNOWN

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val commDevice = try {
                        am.communicationDevice
                    } catch (_: Exception) {
                        null
                    }
                    if (commDevice != null) {
                        val mappedComm = mapDeviceTypeToRoute(commDevice.type)
                        if (mappedComm != null && mappedComm != ROUTE_BUILT_IN_MIC) {
                            return mappedComm
                        }
                    }
                }

                @Suppress("DEPRECATION")
                val scoOn = try {
                    am.isBluetoothScoOn
                } catch (_: Exception) {
                    false
                }
                if (scoOn) {
                    return ROUTE_BLUETOOTH_SCO
                }

                val inputs = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
                if (inputs.isEmpty()) {
                    return ROUTE_UNKNOWN
                }

                // Prefer external routes if connected, falling back to built-in mic.
                for (device in inputs) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        device.type == AudioDeviceInfo.TYPE_BLE_HEADSET
                    ) {
                        return ROUTE_BLUETOOTH_BLE
                    }
                }
                for (device in inputs) {
                    if (device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET) {
                        return ROUTE_WIRED_HEADSET
                    }
                }
                for (device in inputs) {
                    if ((Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            device.type == AudioDeviceInfo.TYPE_USB_HEADSET) ||
                        device.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                        device.type == AudioDeviceInfo.TYPE_USB_ACCESSORY
                    ) {
                        return ROUTE_USB_HEADSET
                    }
                }
                for (device in inputs) {
                    if (device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
                        return ROUTE_BLUETOOTH_SCO
                    }
                }
                for (device in inputs) {
                    if (device.type == AudioDeviceInfo.TYPE_BUILTIN_MIC) {
                        return ROUTE_BUILT_IN_MIC
                    }
                }
                ROUTE_UNKNOWN
            } catch (_: Exception) {
                ROUTE_UNKNOWN
            }
        }

        private fun mapDeviceTypeToRoute(type: Int): String? {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                type == AudioDeviceInfo.TYPE_BLE_HEADSET
            ) {
                return ROUTE_BLUETOOTH_BLE
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                type == AudioDeviceInfo.TYPE_USB_HEADSET
            ) {
                return ROUTE_USB_HEADSET
            }
            return when (type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> ROUTE_BLUETOOTH_SCO
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_ACCESSORY -> ROUTE_USB_HEADSET
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> ROUTE_WIRED_HEADSET
                AudioDeviceInfo.TYPE_BUILTIN_MIC -> ROUTE_BUILT_IN_MIC
                else -> null
            }
        }

        /**
         * Checks whether the microphone is muted or blocked via public Android APIs.
         * Returns:
         * - `true` if `AudioManager.isMicrophoneMute` is true or an active recording is silenced by OS.
         * - `false` if not muted and (on API 31+) OS does not expose/support sensor privacy toggle.
         * - `null` if API 31+ sensor privacy toggle is supported and OS restricts reading its live state.
         */
        fun isMicrophonePrivacyBlocked(context: Context): Boolean? {
            return try {
                val appCtx = context.applicationContext
                val am = appCtx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    ?: return null

                if (am.isMicrophoneMute) {
                    return true
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val activeRecs = try {
                        am.activeRecordingConfigurations
                    } catch (_: Exception) {
                        emptyList()
                    }
                    if (activeRecs.any { it.isClientSilenced }) {
                        return true
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val spm = try {
                        appCtx.getSystemService(SensorPrivacyManager::class.java)
                    } catch (_: Exception) {
                        null
                    }
                    if (spm != null) {
                        val supportsToggle = try {
                            spm.supportsSensorToggle(SensorPrivacyManager.Sensors.MICROPHONE)
                        } catch (_: Exception) {
                            true
                        }
                        // Public SDK does not expose current toggle state; return null rather than guessing.
                        return if (supportsToggle) null else false
                    }
                    return null
                }

                false
            } catch (_: SecurityException) {
                null
            } catch (_: Exception) {
                null
            }
        }
    }

    /**
     * Requests `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE` for voice capture.
     * Never retries or fights indefinitely on focus loss; instead notifies [onFocusLost].
     */
    fun requestFocus(onFocusLost: (permanent: Boolean) -> Unit): Boolean {
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false

        // Do not fight an active cellular/VoIP call.
        val audioMode = try {
            am.mode
        } catch (_: Exception) {
            AudioManager.MODE_NORMAL
        }
        if (audioMode == AudioManager.MODE_IN_CALL || audioMode == AudioManager.MODE_RINGTONE) {
            return false
        }

        abandonFocus()

        val generation: Long
        val listener: AudioManager.OnAudioFocusChangeListener
        synchronized(lock) {
            activeFocusGeneration += 1L
            generation = activeFocusGeneration
            focusLostCallback = onFocusLost
            listener = AudioManager.OnAudioFocusChangeListener { focusChange ->
                handleAudioFocusChange(generation, focusChange)
            }
        }

        val result = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    .setAudioAttributes(attrs)
                    .setAcceptsDelayedFocusGain(false)
                    .setWillPauseWhenDucked(false)
                    .setOnAudioFocusChangeListener(listener, mainHandler)
                    .build()
                synchronized(lock) {
                    focusRequest = req
                    legacyFocusListener = null
                }
                am.requestAudioFocus(req)
            } else {
                synchronized(lock) {
                    focusRequest = null
                    legacyFocusListener = listener
                }
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    listener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
                )
            }
        } catch (_: Exception) {
            AudioManager.AUDIOFOCUS_REQUEST_FAILED
        }

        val granted = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        synchronized(lock) {
            if (activeFocusGeneration == generation) {
                hasFocus = granted
                if (!granted) {
                    focusRequest = null
                    legacyFocusListener = null
                    focusLostCallback = null
                }
            }
        }
        return granted
    }

    private fun handleAudioFocusChange(generation: Long, focusChange: Int) {
        val isLoss = focusChange == AudioManager.AUDIOFOCUS_LOSS ||
            focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
        if (!isLoss) return

        val permanent = focusChange == AudioManager.AUDIOFOCUS_LOSS
        val callback: ((Boolean) -> Unit)?
        synchronized(lock) {
            if (generation != activeFocusGeneration || !hasFocus) {
                return
            }
            callback = focusLostCallback
            focusLostCallback = null
        }

        // Release OS focus deterministically and never fight for the mic in a loop.
        abandonFocus()

        if (callback != null) {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                callback.invoke(permanent)
            } else {
                mainHandler.post { callback.invoke(permanent) }
            }
        }
    }

    /**
     * Deterministically abandons held AudioFocus. Safe to call multiple times from any thread.
     */
    fun abandonFocus() {
        val reqToAbandon: AudioFocusRequest?
        val legacyToAbandon: AudioManager.OnAudioFocusChangeListener?
        synchronized(lock) {
            activeFocusGeneration += 1L
            reqToAbandon = focusRequest
            legacyToAbandon = legacyFocusListener
            focusRequest = null
            legacyFocusListener = null
            focusLostCallback = null
            hasFocus = false
        }

        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (reqToAbandon != null) {
                    am.abandonAudioFocusRequest(reqToAbandon)
                }
            } else if (legacyToAbandon != null) {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(legacyToAbandon)
            }
        } catch (_: Exception) {
        }
    }
}
