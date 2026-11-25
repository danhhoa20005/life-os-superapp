# LifeOS Voice Engine 2.0 — Audio Pipeline & Hardware Arbitration

**Native Modules:** [LifeOsAudioFocusCoordinator.kt](file:///g:/superapp/android/app/src/main/kotlin/vn/lifeos/app/LifeOsAudioFocusCoordinator.kt), [LifeOsPcmAudioRecorder.kt](file:///g:/superapp/android/app/src/main/kotlin/vn/lifeos/app/LifeOsPcmAudioRecorder.kt), [LifeOsSoundboxSpeaker.kt](file:///g:/superapp/android/app/src/main/kotlin/vn/lifeos/app/LifeOsSoundboxSpeaker.kt), [VoiceSessionCoordinatorNative.kt](file:///g:/superapp/android/app/src/main/kotlin/vn/lifeos/app/VoiceSessionCoordinatorNative.kt)
**Dart DSP / VAD Module:** [voice_activity_detector.dart](file:///g:/superapp/lib/features/voice_assistant/domain/services/voice_activity_detector.dart)

---

## 1. PCM16 Capture Specification (Self-Test & Local Offline Pipeline)

| Parameter | Value | Rationale |
|---|---|---|
| Sample Rate | `16,000 Hz` | Universal standard for Vietnamese ASR (Vosk, Whisper, Sherpa-ONNX) and Silero VAD |
| Channel Config | `CHANNEL_IN_MONO` (1 channel) | Minimal bandwidth & memory footprint |
| Encoding | `ENCODING_PCM_16BIT` (signed 16-bit little-endian) | Exact `32,000 bytes/sec` (`640 bytes` per `20 ms` frame = `320` samples) |
| Audio Source | `MediaRecorder.AudioSource.VOICE_RECOGNITION` (fallback `MIC`) | Enables OS acoustic echo cancellation / noise suppression tuned for speech |
| Pre-Roll Ring Buffer | `300 ms` (`4,800` samples = `9,600 bytes`) | Captures initial Vietnamese syllable onset before VAD gate opens without losing leading consonants |
| Storage Policy | **In-memory circular buffer only — ZERO raw audio files written to disk** | Strict user privacy; zero residual audio files after session end |

---

## 2. Mutual Exclusion: `SpeechRecognizer` vs. `AudioRecord`

Android does **NOT** reliably support opening `AudioRecord` concurrently with `SpeechRecognizer` across OEM audio HALs (Samsung, Xiaomi, OPPO, Vivo).

- `VoiceSessionCoordinatorNative` enforces **strict mutual exclusion**:
  - When `SpeechRecognizer` is active (`androidSpeech` / `androidOnDevice`), `AudioRecord` is **never** opened simultaneously.
  - `LifeOsPcmAudioRecorder` (`AudioRecord`) is ONLY acquired during:
    1. Explicit `/voice-diagnostics` **Microphone Self-Test** (`runMicrophoneSelfTest`, `~1200ms`, zero disk writes), or
    2. Explicit **Local Offline ASR** (`localAsr`) capture mode where `SpeechRecognizer` is inactive.

---

## 3. AudioFocus, Route Detection & Microphone Privacy Checks

1. **Exclusive Transient AudioFocus (`LifeOsAudioFocusCoordinator.kt`):**
   - Acquires `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE` (`AudioAttributes.USAGE_ASSISTANT` / `CONTENT_TYPE_SPEECH`) before starting capture; releases unconditionally on stop/cancel/error/destroy.
   - On `AUDIOFOCUS_LOSS` / `AUDIOFOCUS_LOSS_TRANSIENT` (e.g., incoming phone call), emits `audioFocusLost` so the session terminates gracefully while preserving any captured transcript.
2. **Audio Route Detection (`AudioManager.getDevices(GET_DEVICES_INPUTS)` / communication device):**
   - Reports real route in telemetry & capability cache key: `built_in_mic`, `wired_headset`, `usb_headset`, `bluetooth_sco`, `bluetooth_ble`, `unknown`.
3. **Android 12+ (API 31+) OS Microphone Privacy & Silencing Check:**
   - Queries `SensorPrivacyManager` (`TOGGLE_TYPE_SOFTWARE` / `Sensors.MICROPHONE`) and `AudioRecordingConfiguration.isClientSilenced` to surface an explicit hardware/OS mic-mute warning instead of hanging silently.
4. **Soundbox Banking TTS Suppression (`LifeOsSoundboxSpeaker.kt`):**
   - `VoiceSessionCoordinatorNative` flips `LifeOsSoundboxSpeaker.setMicrophoneActive(true)` for the full duration of any mic session, suppressing banking notification TTS announcements and preventing acoustic feedback loops.

---

## 4. VAD & Truthful Waveform Contract

- **Real PCM16 Path (`AdaptiveEnergyZcrVad`):** Computes per-20ms frame RMS dBFS + Zero-Crossing Rate (ZCR) against an adaptive noise floor tracker (`noiseFloorDbfs`), distinguishing speech onset from steady fan/traffic noise without premature cuts on `650ms` mid-sentence pauses.
- **Android `SpeechRecognizer` Path:** Never runs a dead-stream RMS watchdog. If valid RMS callbacks arrive, `VoiceLiveWaveform` plots real history; if OEM returns constant/no RMS, `VoiceLiveWaveform` displays an honest flat listening baseline + explicit Vietnamese caption rather than synthetic spikes.
