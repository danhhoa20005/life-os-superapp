# LIFE OS — AI & VOICE RUNTIME VERIFICATION REPORT (AI-01)

- **Date:** 27/11/2026
- **Branch:** `agy/v3.27.3-reaudit-remediation`
- **Scope:** Honest separation of verified on-device NLP models vs. unintegrated offline ASR acoustic runtimes.

## 1. Truthful Remediation of `AI-01` (Placeholder 16KB ASR Assets)

### Root Cause Confirmed
- The 4 files in `assets/models/` (`vosk_model_small_vn_0_4.bin`, `sherpa_onnx_whisper_tiny_int8.bin`, `silero_vad_v5.onnx`, `sherpa_onnx_zipformer_vi_30m_int8.bin`, ~16 KB each) are **NOT** full upstream acoustic models and there is **NO** linked native Vosk, Sherpa-ONNX, or Whisper C++/JNI inference runtime in the APK.
- Previously, `LocalAsrModelManager` inferred availability from file SHA-256 and `VoiceDiagnosticsPage` showed `'✓ Đã tải sẵn & Kích hoạt'`, which overstated actual offline ASR capability.

### Remediation Implemented (Honest Disable — Zero Fake Inference)
1. Added `verifiedInferenceCapable: bool` (default `false`) to `LocalAsrModelSpec` (`lib/features/voice_assistant/domain/entities/voice_model_package.dart`).
2. Marked all 4 placeholder catalog specs with **`runtimeIntegrated: false, verifiedInferenceCapable: false`**.
3. Updated `LocalAsrModelManager` (`lib/features/voice_assistant/data/datasources/local_asr_model_manager.dart`):
   - `hasVerifiedInstalledAsrModel()` returns **`false`** unless `spec.runtimeIntegrated && spec.verifiedInferenceCapable && status == LocalAsrModelStatus.installed && integrityOk`.
   - Placeholder specs return `LocalAsrModelStatus.runtimeUnavailable` and are NEVER auto-extracted or reported as `installed`.
4. Updated `VoiceDiagnosticsPage` (`lib/features/voice_assistant/presentation/pages/voice_diagnostics_page.dart`):
   - Removed `'✓ Đã tải sẵn & Kích hoạt'` for unintegrated models.
   - Displays truthful Vietnamese status: **`'Chưa tích hợp bộ chạy offline (Dùng Android trên máy hoặc nhập tay)'`**.
5. Strict Offline Mode (`offline_strict`) relies exclusively on verified **Android 13+ On-Device SpeechRecognizer** when the OS confirms the `vi-VN` pack is installed; otherwise, the app explicitly notifies the user that offline recognition is unavailable on their device and focuses manual text input (never silently routing audio to cloud Google Speech).

## 2. Verified vs. Unverified AI Capabilities Matrix

| Subsystem | Runtime & Weights | Automated Verification | Physical Device / Benchmark Status |
|---|---|---|---|
| **Vietnamese Financial Categorizer (FastText INT8)** | Real quantized model (`assets/models/vn_financial_fasttext_v1.ftq`, ~1.0 MB) + C++17 NDK FFI / Pure Dart inference | **PASS** (included in Flutter 469/469 tests & Dart benchmark) | Native ARM64 FFI latency verified in unit/build; real device thermal soak `NOT_RUN`. |
| **Vietnamese Money-Split Classifier (FastText INT8)** | Real quantized model (`assets/models/vn_money_split_fasttext_v1.ftq`, ~418 KB) | **PASS** (included in Flutter 469/469 tests) | Verified on synthetic & hard v2 test corpus. |
| **Bundled Vosk / Sherpa / Whisper / Silero VAD** | **NOT INTEGRATED** (16 KB placeholders honestly marked `runtimeUnavailable`, `verifiedInferenceCapable: false`) | **PASS** (tests assert `hasVerifiedInstalledAsrModel() == false` and truthful UI copy) | **BLOCKED / FUTURE MILESTONE:** Real upstream model download/bundling, native JNI runtime integration, license verification per model artifact, and 3-region audio WER/CER + amount exact-match benchmark in Airplane Mode are required before enabling. |
| **Android 13+ On-Device SpeechRecognizer** | OS-provided `SpeechRecognizer.createOnDeviceSpeechRecognizer` | Unit/policy tests **PASS** (`LifeOsWidgetVoicePolicyTest`, `voice_engine_v2_deterministic_test`) | Physical device Airplane Mode test `NOT_RUN`. |
| **Optional Gemini Cloud Advisor (`PRIV-01`)** | Opt-in REST client (`gemini_remote_datasource.dart`) | **PASS** (requires explicit `cloudAiConsentGranted`, strips personal habit labels & masks PII when `maskSensitiveInfo: true`) | Live network traffic audit on physical device `NOT_RUN`. |
