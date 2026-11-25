# LifeOS Voice Engine 2.0 — Physical Android Device Test Matrix

**Current Physical Device Status:** `adb devices` reported `0` attached physical devices / emulators in this workstation environment.
**Honest Verification Status:** All rows below are explicitly marked **`NOT_RUN — DEVICE REQUIRED`** until executed on physical Android hardware. Unit, BLoC, widget, corpus NLP, Kotlin manifest/compilation, and local APK build verification are documented separately in [REGRESSION_TEST_REPORT.md](file:///g:/superapp/docs/voice/REGRESSION_TEST_REPORT.md).

---

## 1. Required Device Matrix (Android 10–16)

| Device Tier / OEM | OS / API Level | Audio Routes to Verify | Engines to Verify | Status |
|---|---|---|---|---|
| **Google Pixel / AOSP** | Android 15–16 (API 35–36) | Built-in mic, Bluetooth SCO/BLE, USB-C headset | `androidOnDevice` (API 33+ `checkRecognitionSupport`), `androidSpeech`, `systemDialog`, PCM16 self-test | `NOT_RUN — DEVICE REQUIRED` |
| **Samsung Galaxy (One UI)** | Android 13–15 (API 33–35) | Built-in mic, Galaxy Buds (Bluetooth SCO/BLE) | `androidSpeech` (Samsung vs Google default recognizer), `androidOnDevice`, OS Mic Privacy Toggle (`SensorPrivacyManager`) | `NOT_RUN — DEVICE REQUIRED` |
| **Xiaomi / Redmi (MIUI / HyperOS)** | Android 12–14 (API 31–34) | Built-in mic, wired/USB headset | `androidSpeech`, `systemDialog`, `LifeOsWidgetQuickOverlayActivity` (permission & dialog return without `noHistory`), battery/background pause | `NOT_RUN — DEVICE REQUIRED` |
| **OPPO / Realme (ColorOS)** | Android 11–14 (API 30–34) | Built-in mic, Bluetooth headset | `androidSpeech` (verify OEM flat RMS does NOT trigger false engine switch), `finalizing` watchdog rescue, Soundbox TTS suppression | `NOT_RUN — DEVICE REQUIRED` |
| **Vivo (Funtouch / OriginOS)** | Android 11–13 (API 30–33) | Built-in mic | `androidSpeech`, `systemDialog`, rapid-tap & screen rotation durability | `NOT_RUN — DEVICE REQUIRED` |
| **Low-End Android Phone (3–4 GB RAM)** | Android 10–11 (API 29–30) | Built-in mic | `androidSpeech`, `systemDialog`, strict offline refusal messaging (API < 31 without local model), memory & thermal stability | `NOT_RUN — DEVICE REQUIRED` |

---

## 2. Physical Device Execution Protocol (QA Sign-Off Checklist)

When physical devices are connected via ADB (`adb devices`), execute the following 10 scenarios per device and record Pass/Fail + sanitized `/voice-diagnostics` JSON:

1. **Cold Start 1-Tap Capture:** Tap Mic on `TodayPage` -> grant `RECORD_AUDIO` -> verify window-focus permission handoff (no freeze, no auto-cancel while OS prompt is visible).
2. **Explicit Stop & Finalizing Gate (`VOICE-001`):** Dictate *"Ăn sáng ba mươi lăm nghìn"* -> pause 1.2s mid-sentence -> verify mic does NOT cut off -> tap `Dừng` -> verify `finalizing` spinner/state waits for final result before enabling `Xác nhận & Lưu`.
3. **Long Multi-Clause Vietnamese Dictation:** Dictate *"Mua cà phê bốn mươi lăm nghìn và đổ xăng bảy mươi nghìn"* -> confirm both line items parse accurately (`45.000 ₫`, `70.000 ₫`) and nothing saves before tapping `Xác nhận & Lưu`.
4. **Strict Offline Mode Integrity (`VOICE-007`):** Enable Airplane Mode -> switch to `Chỉ Offline` -> verify OS on-device recognition works (if `vi-VN` pack installed on API 31+) OR fails cleanly with explicit Vietnamese error (never silently calling online speech).
5. **Home Widget Quick Voice Overlay:** Launch voice capture from Android Home Widget -> verify permission/system dialog returns properly to overlay -> verify explicit confirmation is required before saving.
6. **Hardware / Call / Soundbox Interruption:** Trigger incoming call or banking notification TTS during active listening -> verify Soundbox TTS is suppressed while mic is open, and incoming call (`AUDIOFOCUS_LOSS`) stops mic cleanly while preserving captured transcript.
7. **OS Microphone Privacy Toggle (Android 12+):** Disable OS Microphone Access quick-tile -> run `/voice-diagnostics` **Kiểm tra Microphone** -> verify `isMicPrivacyBlocked` / silenced PCM detection reports clear Vietnamese guidance.
8. **Bluetooth Headset Handoff:** Connect/disconnect Bluetooth headset mid-session -> verify `audioRouteChanged` telemetry updates and capability cache keys separate routes.
9. **50-Session Soak Reliability:** Run 50 consecutive start -> dictate -> stop -> confirm/cancel cycles -> verify zero `ERROR_RECOGNIZER_BUSY` deadlocks, zero memory growth, and zero stuck `listening`/`finalizing` states.
10. **PII-Free Diagnostics Export:** Tap `Xuất báo cáo ẩn PII` in `/voice-diagnostics` -> inspect clipboard JSON to verify zero transcripts, zero amounts, and zero account/user identifiers.
