# LifeOS Voice Engine 2.0 — Regression & Quality Gate Report

**Date:** 2026-11-25
**Branch:** `agy/v3.27.0-upgrade` (local branch; `main` untouched at `v3.26.0+44`)
**Release / Deploy Status:** Local build & verification ONLY — NO `git push`, NO tag, NO GitHub Release, NO production deploy.

---

## 1. Automated Gate Summary

| Gate | Command / Check | Result | Measured Details |
|---|---|---|---|
| **G1 — Dart Formatting** | `dart format --output=none --set-exit-if-changed lib test` | **PASS** | `330` files formatted, `0` diffs |
| **G2 — Static Analysis** | `flutter analyze --fatal-infos --fatal-warnings --no-pub` | **PASS** | `0` errors, `0` warnings, `0` infos (`14.0s`) |
| **G3 — LifeOS CI Guards** | Regex/AST scan across `lib/` | **PASS** | `ExtendsCubit=0`, `showSnackBar=0`, `TextOverflow=0`, `FirebaseInPresentation=0`, `DomainFlutterImports=0` |
| **G4 — Full Flutter Regression Suite** | `flutter test --no-pub --timeout 45s` | **PASS** | **`371 / 371` PASSED** (`0` failures, `0` skipped, `1m 58s`) |
| **G5 — Android Kotlin & Manifest Compile** | `.\gradlew.bat :app:processGithubDebugMainManifest :app:compileGithubDebugKotlin` | **PASS** | `BUILD SUCCESSFUL` (`0` errors, `0` warnings) |
| **G6 — Local Android Release APK Build** | `flutter build apk --release --flavor github --no-pub` | **PASS** | `build/app/outputs/flutter-apk/app-github-release.apk` (`93,337,875 bytes` / **`89.01 MB`**; icon font tree-shaken `96.0%`) |
| **G7 — Python Offline ASR / VAD PoC** | `python tools/voice_asr_poc/benchmark_asr.py` | **PASS (`MEASURED_HOST`)** | `36` utterances / `6,386` PCM16 20ms frames; `0/36` premature mid-pause cuts |
| **G8 — Physical Android Hardware Matrix** | `adb devices` (Android 10–16 OEMs) | **`NOT_RUN — DEVICE REQUIRED`** | `0` physical devices/emulators attached; protocol in [DEVICE_TEST_MATRIX.md](file:///g:/superapp/docs/voice/DEVICE_TEST_MATRIX.md) |

---

## 2. Voice Engine 2.0 Test Suite Breakdown

| Test File | Scope Covered | Status |
|---|---|---|
| [voice_engine_v2_deterministic_test.dart](file:///g:/superapp/test/features/voice/voice_engine_v2_deterministic_test.dart) | 10-state FSM, `VOICE-001` finalizing gate, `VOICE-002` session/attempt/sequence isolation, `VOICE-003` permission unfocused guard, `VOICE-004` monotonic timers, `VOICE-005` explicit stop & opt-in auto-endpoint, `VOICE-006` truthful waveform, `VOICE-007` strict offline guard, `VOICE-008` 24h TTL capability cache, single retry on `recognizerBusy`, PII-free diagnostics JSON | **PASS (19/19)** |
| [transcript_manager_test.dart](file:///g:/superapp/test/features/voice/transcript_manager_test.dart) | `VOICE-009` overlap deduplication, shrinking partial revisions, multi-turn append, empty-final rescue, user-edit protection | **PASS (10/10)** |
| [local_asr_model_manager_test.dart](file:///g:/superapp/test/features/voice/local_asr_model_manager_test.dart) | SHA-256 verification, corrupted file rejection + staging cleanup, HTTP Range `.part` resume, atomic upgrade & rollback, `CC-BY-NC-ND-4.0` commercial license block, storage pre-check | **PASS (5/5)** |
| [voice_diagnostics_page_test.dart](file:///g:/superapp/test/features/voice/voice_diagnostics_page_test.dart) | `/voice-diagnostics` telemetry cards, monotonic latencies, model license badges (`Hạn chế giấy phép`), zero overflow at `360x800 @ 1.25x` | **PASS (1/1)** |
| [mic_optimization_and_reliability_test.dart](file:///g:/superapp/test/features/voice/mic_optimization_and_reliability_test.dart) | Multi-segment combiner, OEM diagnostics labels, explicit-stop capture, truthful RMS waveform, multi-turn append, `Chi tiết thu âm` engine switch, `finalizing` safety guard rescue at `360x800 @ 1.12%` | **PASS** |
| [voice_vietnamese_corpus_nlp_test.dart](file:///g:/superapp/test/unit/voice_vietnamese_corpus_nlp_test.dart) | 36-utterance Vietnamese financial & omni corpus (`100%` Exact Amount, `100%` Intent, `100%` Date/Time) + 87 noisy ASR variants + Section 15 7-sentence explicit check | **PASS** |
| [smart_voice_auto_endpoint_and_confirm_test.dart](file:///g:/superapp/test/features/financial_ai/smart_voice_auto_endpoint_and_confirm_test.dart) | 1-tap start, mid-clause pause stability, explicit stop -> finalizing -> review -> explicit confirm (never auto-saves), session token isolation, permission denial recovery UI | **PASS** |
| [v327_voice_fsm_banking_privacy_test.dart](file:///g:/superapp/test/unit/v327_voice_fsm_banking_privacy_test.dart) | Background lifecycle pause cancellation, 250ms rapid-tap debounce, stale session isolation, editable transcript, banking ACK & privacy checks | **PASS** |
| [smart_money_split_ai_and_voice_fix_test.dart](file:///g:/superapp/test/features/financial_ai/smart_money_split_ai_and_voice_fix_test.dart) & [voice_nlp_and_auto_ledger_test.dart](file:///g:/superapp/test/unit/voice_nlp_and_auto_ledger_test.dart) | Group split math, manual typing cancels active mic cleanly, ledger write confirmation | **PASS** |
| [ux_golden_qa_test.dart](file:///g:/superapp/test/widget/ux_golden_qa_test.dart) & [audit_v3_25_stability_and_integrity_test.dart](file:///g:/superapp/test/integration/audit_v3_25_stability_and_integrity_test.dart) | All 8 core screen goldens + isolated partial batch retry without duplicates | **PASS** |

---

## 3. Defects Caught & Resolved During Verification

1. **`VoiceLiveWaveform` Fixed-Length List (`UnsupportedError`):** Changed `_history` to `List<double>.filled(_barCount, 0.0, growable: true)`.
2. **Modal Occlusion Beneath Floating Dock:** Added `useRootNavigator: true` in `showVoiceSmartCaptureSheet` so `LifeOsFloatingGlassDock` never covers bottom sheet buttons on `360x800`.
3. **`ListTile` Material Ancestor Assertion:** Wrapped `SwitchListTile.adaptive` in transparent `Material` (`VoiceSmartCaptureSheet`) and upgraded `_DiagCardShell` to `Material` (`VoiceDiagnosticsPage`).
4. **Native Diagnostics Hydration:** Added `nativeDiagnosticsProvider` to `VoiceSessionCoordinator._refreshDiagnosticsData` so real permission, SDK, device, audio route, and native engine strings flow into both UI surfaces.
5. **Deterministic Tap Debounce:** Replaced host-wall `Stopwatch` with `Timer(250ms)` (cancelled in `dispose()`) for deterministic debounce across real devices and `FakeAsync`.
6. **Cross-Zone `sl.reset()` Dispose Deadlock:** Made `VoiceSessionCoordinator.dispose()`, `VoiceNativeChannelDataSource.dispose()`, and `VoiceAssistantBloc.close()` cancel subscriptions and close broadcast controllers non-blockingly (`unawaited(...)`), cutting full-repo test runtime from 32m timeouts down to **`1m 58s` (`371/371 PASS`)**.
7. **Isolated Widget Test Fallback:** Added standalone fallback `VoiceAssistantBloc` creation in `VoiceSmartCaptureSheet` and `FinancialAiAssistantPage` when `GetIt` is uninitialized in isolated tests.
