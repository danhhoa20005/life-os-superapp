# LifeOS Voice Engine 2.0 — ASR Model & Engine Comparison

**Date:** 2026-11-25
**Strict Honesty Policy:** Host-measured numbers (`MEASURED_HOST`), official upstream documentation figures (`UPSTREAM_REFERENCE`), and unexecuted physical-device measurements (`NOT_RUN — DEVICE REQUIRED`) are strictly separated below. No synthetic WER/RTF claims are fabricated.

---

## 1. Engine & Model Comparison Matrix

| Engine / Candidate | Execution Mode | True Streaming Partials? | Vietnamese (`vi-VN`) Support | Footprint / APK Delta | Runtime License | Weights License | Commercial Use | Verification Status |
|---|---|---|---|---|---|---|---|---|
| **Android `SpeechRecognizer` (Google Speech Services)** | Online / Hybrid | Yes (OEM dependent) | Strong (`vi-VN` native) | `0 MB` (OS-provided) | Android SDK | Google / OS | Allowed (OS API) | `MEASURED_HOST` (Dart/Kotlin integration) · `NOT_RUN — DEVICE REQUIRED` (live mic WER/latency) |
| **Android `createOnDeviceSpeechRecognizer` (API 31+ / 33+)** | Strict On-Device Offline | Yes (API 31+) | Probed via API 33+ `checkRecognitionSupport` | `0 MB` (OS language pack) | Android SDK | Google / OS | Allowed (OS API) | `MEASURED_HOST` (strict offline guard & Kotlin compile) · `NOT_RUN — DEVICE REQUIRED` (physical API 31–36) |
| **Android System Voice Dialog (`ACTION_RECOGNIZE_SPEECH`)** | External OS Dialog | No (returns final only) | Strong (`vi-VN`) | `0 MB` | Android SDK | OS | Allowed (OS API) | `MEASURED_HOST` (single-terminal result guard) · `NOT_RUN — DEVICE REQUIRED` |
| **Vosk (`libvosk`) + `vosk-model-small-vn-0.4`** | Local Offline (On-Demand) | **Yes** (Kaldi TDNN-F) | Dedicated VN model (upstream Vivos test WER `15.7%` — `UPSTREAM_REFERENCE`) | `~32.1 MB` zip (`0 MB` in base APK; on-demand download) | `Apache-2.0` | `Apache-2.0` | **ALLOWED** | `UPSTREAM_REFERENCE` + `MEASURED_HOST` (PyPI `vosk 0.3.41/0.3.45` win_amd64 wheel confirmed; not installed in sandbox) · `NOT_RUN — DEVICE REQUIRED` |
| **Whisper (`whisper.cpp` / `faster-whisper`) + `tiny`/`base` quantized** | Local Offline (On-Demand) | **No** (encoder-decoder; requires VAD chunking, NOT true streaming) | Multilingual (weaker VN diacritics at `tiny` scale) | `~32–42 MB` quantized (`0 MB` in base APK) | `MIT` | `MIT` | **ALLOWED** | `UPSTREAM_REFERENCE` + `MEASURED_HOST` (PyPI `faster-whisper 1.2.1` + `ctranslate2 4.9.1` wheel confirmed) · `NOT_RUN — DEVICE REQUIRED` |
| **Sherpa-ONNX + `sherpa-onnx-zipformer-vi-30M-int8` (`hynt/Zipformer-30M-RNNT-6000h`)** | Local Offline (Research Only) | **Yes** (RNN-T streaming) | Dedicated VN 6000h model | `~25.22 MB` archive (`UPSTREAM_REFERENCE`) | `Apache-2.0` | **`CC-BY-NC-ND-4.0`** | **BLOCKED (Non-Commercial)** | **Hard-blocked** from commercial bundling & downloads (`LocalAsrLicenseBlockedException`) |
| **Silero VAD (`silero_vad.onnx`)** | Neural VAD companion | Frame-level (`32 ms` / `512` samples @ `16 kHz`) | Language-agnostic | `~1.8 MB` (`0 MB` in base APK) | `MIT` | `MIT` | **ALLOWED** | `UPSTREAM_REFERENCE` · Host Energy/ZCR VAD benchmarked (`MEASURED_HOST`: `139.5 us` P50/frame) |

---

## 2. Architecture Recommendation for LifeOS Production

1. **Primary Default (Online / Hybrid):** Android public `SpeechRecognizer` (`androidSpeech`) with explicit-stop default (`VOICE-005`), single-owner mutex (`VOICE-002`), and 24h TTL capability cache (`VOICE-008`). Zero APK bloat and strongest Vietnamese financial dictation accuracy when online.
2. **Primary Strict-Offline Tier (Android 12–16 / API 31+):** Android OS `createOnDeviceSpeechRecognizer` verified via API 33+ `checkRecognitionSupport` for `vi-VN` (`VOICE-007`). Zero APK bloat and zero third-party license risk.
3. **Optional On-Demand Offline Tier (Commercial-Safe):** `vosk-model-small-vn-0.4` (`Apache-2.0` runtime + `Apache-2.0` weights, true streaming) or quantized Whisper (`MIT` runtime + `MIT` weights, explicitly labeled VAD-chunked non-streaming) downloaded strictly on demand via `LocalAsrModelManager` with SHA-256 verification and rollback.
4. **Blocked Tier:** Any `CC-BY-NC-ND-4.0` weights (including `hynt/Zipformer-30M-RNNT-6000h`) remain strictly forbidden in commercial builds until an Apache-2.0 / MIT Vietnamese Zipformer weight checkpoint is licensed or trained.
