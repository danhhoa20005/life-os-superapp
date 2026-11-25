# LifeOS Voice Engine 2.0 — Voice UX Guidelines

**Design Philosophy:** *Simple on the surface, powerful underneath.* Truthful feedback, explicit user control, zero financial anxiety.

---

## 1. Unified States Across All Voice Surfaces

Both [voice_smart_capture_sheet.dart](file:///g:/superapp/lib/core/widgets/voice_smart_capture_sheet.dart) and [financial_ai_assistant_page.dart](file:///g:/superapp/lib/features/financial_ai/presentation/pages/financial_ai_assistant_page.dart) bind to the shared `VoiceAssistantBloc` and render consistent, honest Vietnamese states:

| FSM Phase | Headline / Status | Allowed Controls | Blocked Controls |
|---|---|---|---|
| `requestingPermission` | `Đang chờ cấp quyền Micro...` | `Hủy` | `Xác nhận & Lưu`, duplicate `Start` |
| `preparing` | `Đang chuẩn bị Micro...` / `Đang mở kênh Micro tiếng Việt...` | `Hủy` | `Xác nhận & Lưu` |
| `listening` | `Đang nghe tiếng Việt...` | `Dừng` (explicit stop), `Hủy`, live waveform, manual typing (cancels mic first) | `Xác nhận & Lưu` |
| `finalizing` | `Đang xử lý câu nói...` | `Hủy` | `Xác nhận & Lưu`, `Nói lại`, `Google`, engine switch chips, transcript overwrite |
| `review` | `Kiểm tra & Xác nhận lại` | `Xác nhận & Lưu`, `Nói lại`, `Mic` (append), inline text edit, wallet/split edit | None |
| `submitting` | `Đang lưu dữ liệu...` | None (prevents double-submit; idempotent `operationId`) | All destructive / duplicate actions |
| `error` | Explicit localized reason (never raw stack/code) | `Cấp quyền Micro` / `Mở Cài đặt Micro`, `Thu âm hệ thống` (if not strict offline), `Nói lại`, manual keyboard input | Never wipes previously captured transcript |

---

## 2. Core Behavioral Safeguards

1. **Explicit Stop by Default (`VOICE-005`):**
   - Users see clear `Dừng` (`voice_stop_session_btn`) and `Hủy` (`voice_cancel_session_btn`) buttons directly inside the top recording card (always visible at `360x800 @ 112%–125%`).
   - Smart Auto-Endpoint (`Tự dừng thông minh sau khoảng nghỉ`) is **OFF by default** and opt-in under `Chi tiết thu âm` or `/voice-diagnostics`.
2. **Truthful Audio Feedback (`VOICE-006`):**
   - Real audio amplitude drives rolling bars in `VoiceLiveWaveform`.
   - When an OEM recognizer omits RMS callbacks, the UI displays an honest flat baseline with the note *"Đang lắng nghe (thiết bị không báo mức âm lượng từng khung)"* — never fake bouncing bars.
3. **Strict Offline Mode Integrity (`VOICE-007`):**
   - When `Chỉ Offline` (`offlineStrict`) is active, cloud fallback actions (`Google` shortcut and `Thu âm hệ thống`) are hidden, and the coordinator strictly refuses to start online engines.
4. **Zero Auto-Commit of Financial Actions:**
   - Every transaction, batch receipt, group bill split, and cross-domain reminder enters `review` with structured confirmation cards (`voice_confirmation_preview_card`). Financial mutations run **only** after explicit confirmation (`Xác nhận & Lưu`) and surface an `Hoàn tác` (Undo) action on single transactions.
5. **Accessibility & Ergonomics:**
   - Root navigator modal (`useRootNavigator: true`) ensures the bottom navigation dock never obscures voice controls.
   - `48dp` minimum tap targets, `Wrap`/`Expanded`/`FittedBox` layouts verified at `360x800 @ 112%–125%`, `FontFeature.tabularFigures()` for all numbers, `LifeOsTopToast` (zero `SnackBar`), and zero infinite `CircularProgressIndicator` animations during `finalizing`.
