# LifeOS Voice Engine 2.0 — Known Limitations & Honest Boundaries

**Date:** 2026-11-25

---

## 1. Environment & Physical Hardware Boundaries

1. **Physical Android Devices Not Executed (`NOT_RUN — DEVICE REQUIRED`):**
   - `adb devices` showed `0` connected physical Android phones/emulators during this engineering cycle.
   - All Dart FSM, BLoC, widget, NLP corpus, Kotlin manifest/compilation, and local APK packaging gates passed deterministically, but real-microphone acoustic behavior (OEM `SpeechRecognizer` quirks, Bluetooth SCO routing, `SensorPrivacyManager` hardware toggle, and ARM64 NEON thermal/battery profiles) **must** be validated against [DEVICE_TEST_MATRIX.md](file:///g:/superapp/docs/voice/DEVICE_TEST_MATRIX.md) before public Play Store / GitHub release rollout.
2. **Host Offline ASR Engines Not Installed in Sandbox:**
   - Prebuilt PyPI `win_amd64` wheels were confirmed for `sherpa-onnx 2.0.3`, `vosk 0.3.41/0.3.45`, `onnxruntime 1.32.0`, and `faster-whisper 1.2.1`, but downloading multi-MB native binaries timed out in the restricted network sandbox.
   - Host benchmark measurements therefore cover the `16 kHz` PCM16 ring buffer + adaptive Energy/ZCR VAD pipeline and the full 36-utterance Dart Vietnamese financial/omni NLP stack (`MEASURED_HOST`); live offline ASR WER/CER and ARM64 RTF remain `NOT_MEASURED — DEVICE REQUIRED`.

---

## 2. Platform & Model Architectural Limitations

3. **Android API < 31 Strict Offline Support:**
   - `SpeechRecognizer.createOnDeviceSpeechRecognizer` was introduced in Android 12 (API 31), and `checkRecognitionSupport` for verifying installed language packs (`vi-VN`) was added in Android 13 (API 33).
   - On Android 7–11 (API 24–30), `androidOnDevice` is honestly reported unavailable; strict offline recognition requires an optional commercially-licensed on-demand local ASR model (e.g., `vosk-model-small-vn-0.4`, Apache-2.0) or switching to Online / Hybrid mode.
4. **OEM `SpeechRecognizer` Silence Timeout Non-Compliance:**
   - Android `SpeechRecognizer` extras (`EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS`) are advisory hints that some OEM recognition services ignore, ending recognition early via `onEndOfSpeech` + `onResults`.
   - Voice Engine 2.0 mitigates this by preserving prior clauses in `TranscriptManager` (`VOICE-009`), allowing 1-tap multi-turn append via the Mic button without wiping earlier text, and disabling premature client-side `850ms` auto-stopping by default (`VOICE-005`).
5. **Non-Streaming Offline Models (Whisper):**
   - OpenAI Whisper (`tiny`/`base` quantized, MIT) is an utterance-level encoder-decoder architecture and **cannot** produce true frame-by-frame streaming partials. In LifeOS's catalog (`LocalAsrModelCatalog`), it is explicitly flagged `supportsStreaming: false` (`VAD Chunked (non-streaming)`) so users and developers are never misled.
6. **Non-Commercial Vietnamese Zipformer License Restriction:**
   - `hynt/Zipformer-30M-RNNT-6000h` is licensed under `CC-BY-NC-ND-4.0`, prohibiting commercial use and derivative redistribution. Even though Sherpa-ONNX runtime is `Apache-2.0`, LifeOS hard-blocks commercial download/bundling of this checkpoint via `LocalAsrModelManager` (`commercialAllowed: false`).
7. **Local Native JNI Binding Packaging Deferred Until Commercial Model Rollout:**
   - `LocalAsrModelManager` (download, HTTP Range resume, SHA-256 verification, atomic swap, rollback, license enforcement) and `LocalAsrEngine` (adapter contract + `LifeOsPcmAudioRecorder` 16kHz PCM16 capture) are fully wired and tested; actual native `.so` bindings (`libvosk.so` / `libwhisper.so`) are intentionally kept out of the base APK until on-demand native dynamic feature delivery or commercial offline pack sign-off on physical ARM64 devices.
8. **Noisy ASR Homophone Edge Cases (`80/87 = 91.95%` Variant Amount Accuracy):**
   - Clean 36-utterance corpus achieves `100.00%` (`29/29` Exact Amount, `36/36` Intent, `6/6` Date/Time). Under aggressive simulated ASR corruption (dropped diacritics + split digits like `"bon muoi lam"` / extreme garbling), `7/87` heavily corrupted variants require quick inline correction in the always-editable `review` screen before confirmation.
