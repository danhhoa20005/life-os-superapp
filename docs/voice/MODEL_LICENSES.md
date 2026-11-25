# LifeOS Voice Engine 2.0 — Runtime & Model License Audit

**Last Audited:** 2026-11-25
**Enforcement Implementation:** [voice_model_package.dart](file:///g:/superapp/lib/features/voice_assistant/domain/entities/voice_model_package.dart) & [local_asr_model_manager.dart](file:///g:/superapp/lib/features/voice_assistant/data/datasources/local_asr_model_manager.dart)

---

## 1. Strict Separation: Runtime Engine License vs. Model Weights License

An open-source runtime license (Apache-2.0 / MIT) does **NOT** grant commercial rights to redistribute third-party acoustic model weights. LifeOS tracks `runtimeLicenseSpdx`, `modelLicenseSpdx`, and `commercialAllowed` independently in `LocalAsrModelSpec`.

| Package / Component | Role | Runtime License (SPDX) | Model Weights License (SPDX) | Commercial Bundling / Distribution | Distribution Policy in LifeOS |
|---|---|---|---|---|---|
| **Android `SpeechRecognizer` / `createOnDeviceSpeechRecognizer`** | OS Platform Engine | Android SDK / AOSP (OS-provided) | OS / Vendor provided | Allowed (OS API) | Primary default (zero APK bloat) |
| **Vosk (`libvosk`) + `vosk-model-small-vn-0.4`** | Streaming Offline ASR | `Apache-2.0` | `Apache-2.0` | **ALLOWED** (`commercialAllowed: true`) | Optional On-Demand Download (~32 MB), SHA-256 verified |
| **Whisper.cpp / `faster-whisper` + OpenAI Whisper `tiny` / `base` (quantized)** | VAD-Chunked Non-Streaming Offline ASR | `MIT` | `MIT` | **ALLOWED** (`commercialAllowed: true`) | Optional On-Demand Download (~42 MB quantized), clearly labeled non-streaming |
| **Silero VAD (`silero_vad.onnx`)** | Neural Voice Activity Detection | `MIT` | `MIT` | **ALLOWED** (`commercialAllowed: true`) | Optional On-Demand Download (~1.8 MB), SHA-256 verified |
| **Sherpa-ONNX Runtime (`k2-fsa/sherpa-onnx`)** | ONNX ASR Runtime | `Apache-2.0` | *(Runtime only)* | **ALLOWED** (runtime only) | May only be paired with commercially-licensed weights |
| **`hynt/Zipformer-30M-RNNT-6000h` (Vietnamese)** | Research Offline Vietnamese ASR Weights | `Apache-2.0` (Sherpa-ONNX) | **`CC-BY-NC-ND-4.0`** (NonCommercial-NoDerivatives) | **BLOCKED (`commercialAllowed: false`)** | **Hard-blocked** by `LocalAsrModelManager.downloadModel(enforceCommercialLicense: true)` and disabled in `/voice-diagnostics` UI with warning badge |

---

## 2. Hard Enforcement Rules

1. **Zero Commercial Bundling of Non-Commercial Weights:**
   - `hynt/Zipformer-30M-RNNT-6000h` carries `CC-BY-NC-ND-4.0` (forbids commercial use and derivative works). It is **NOT** bundled in `assets/`, **NOT** packaged in APKs, and throws `LocalAsrLicenseBlockedException` if commercial download is attempted.
2. **Zero Bloated Offline ASR Models in APK:**
   - No ASR weights are embedded in `assets/` (preserving APK size). Users opt in via On-Demand Model Manager with pre-download storage check, `.part` HTTP Range resume, SHA-256 verification, atomic swap, and rollback backup.
3. **Automated License Guard Test:**
   - Verified in [local_asr_model_manager_test.dart](file:///g:/superapp/test/features/voice/local_asr_model_manager_test.dart) (`LocalAsrModelManager blocks CC-BY-NC-ND-4.0 non-commercial model and enforces storage pre-check`) and [voice_diagnostics_page_test.dart](file:///g:/superapp/test/features/voice/voice_diagnostics_page_test.dart) (`Hạn chế giấy phép` UI badge).
