# LifeOS Voice Engine 2.0 — Diagnostics & Support Guide

**Route:** `/voice-diagnostics` ([voice_diagnostics_page.dart](file:///g:/superapp/lib/features/voice_assistant/presentation/pages/voice_diagnostics_page.dart))
**Entry Points:**
1. **Settings Hub:** `Cài đặt` -> `Chẩn đoán & Mô hình Giọng nói` ([activity_and_settings_pages.dart](file:///g:/superapp/lib/features/notifications/presentation/pages/activity_and_settings_pages.dart))
2. **Voice Capture Sheet:** Expand `Chi tiết thu âm` -> `Chẩn đoán, Kiểm tra Micro & Mô hình Offline`

---

## 1. Displayed Telemetry Fields

### A. Device, Permission & Audio Route (`voice_diag_device_card`)
- **Android SDK:** `API <sdkInt>` (or `Không phải Android` on host/non-Android platforms)
- **Manufacturer / Model:** e.g., `Samsung · SM-...`
- **Microphone Permission:** `Đã cấp` / `Chưa cấp`
- **OS Mic Privacy Lock (API 31+):** `Đang mở` / `Đang bật khóa` / `Không xác định`
- **Audio Route:** `Micro tích hợp`, `Tai nghe có dây`, `Tai nghe USB`, `Bluetooth SCO`, `Bluetooth BLE`
- **Vietnamese Language Support:** `supported` / `unavailable` (probed via API 33+ `checkRecognitionSupport` where available)
- **Available Engines:** Reported native services + registered adapters

### B. Active Session FSM & Monotonic Latencies (`voice_diag_session_card`)
- `Active Session ID`, `Engine Attempt ID`, `Trạng thái FSM`
- `Mã lỗi gần nhất` (normalized `VoiceErrorKind` / Android error code)
- `Time to Ready` (`readyAtMonotonicMs - startedAtMonotonicMs`)
- `Time to First Partial` (`firstPartialAtMonotonicMs - startedAtMonotonicMs`)
- `Time to Final` (`finalAtMonotonicMs - startedAtMonotonicMs`)
- `Retry / Fallback` counters

---

## 2. Diagnostic Actions

1. **Kiểm tra Microphone (`voice_diag_mic_selftest_btn`):**
   - Calls native `runMicrophoneSelfTest` (`LifeOsPcmAudioRecorder.kt`): captures ~1.2 seconds of `16 kHz Mono PCM16` directly in RAM (zero disk writes), verifies non-zero frames, computes `peakDbfs` / `avgDbfs`, reports active `audioRoute`, and checks Android `isClientSilenced`.
2. **Xóa bộ nhớ Engine (`voice_diag_reset_caps_btn`):**
   - Clears the 24-hour TTL capability cache (`VoiceCapabilityRepositoryImpl` + Android `lifeos_voice_engine_caps_v2`) and forces fresh engine probing on the next session.
3. **Chế độ Nhận diện & Tự dừng thông minh:**
   - Switch between `Chỉ Offline`, `Tự động kết hợp`, `Google Speech (Trực tiếp)`, and `Hộp thoại hệ thống`; toggle experimental `Tự dừng thông minh`.
4. **Quản lý Mô hình Offline (`voice_diag_models_card`):**
   - Inspect runtime license vs. weights license, download SHA-256 verified commercially-allowed models on demand, delete, or roll back; non-commercial models (`CC-BY-NC-ND-4.0`) are visibly disabled (`Hạn chế giấy phép`).

---

## 3. Sanitized Report Export (`Xuất báo cáo ẩn PII`)

Tapping `Xuất báo cáo ẩn PII` copies `VoiceDiagnosticsReport.toSanitizedJson()` to the clipboard.

**Hard Privacy Guarantees (Verified by Unit Tests):**
- **ZERO** user transcripts or partial utterances
- **ZERO** monetary amounts, wallet names, or account numbers
- **ZERO** emails, phone numbers, family member names, or user IDs
- **ZERO** raw PCM audio bytes or file paths containing user data
- Exports strictly technical metadata: SDK level, manufacturer/model, permission/privacy booleans, audio route, FSM phase, monotonic latency ms, retry/fallback counts, capability cache entries, and bounded event timeline (event type + phase + error code + monotonic timestamp only).
