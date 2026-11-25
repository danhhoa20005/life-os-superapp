# LifeOS Voice Engine 2.0 — Root Cause Analysis (`VOICE-001`..`VOICE-009`)

**Baseline Audited:** LifeOS `v3.26.0+44` (`4bc371ef1c3f0b0029f28a6d44228f32f6b6aabd`) & `v3.27.0` (`agy/v3.27.0-upgrade`)
**Audit Date:** 2026-11-25
**Scope:** End-to-end voice capture stack across Android Kotlin (`MainActivity`, `LifeOsSpeechRecognizerHelper`, `LifeOsHomeWidgets`, `LifeOsSoundboxSpeaker`, `AndroidManifest.xml`) and Flutter/Dart (`VoiceSmartCaptureSheet`, `FinancialAiAssistantPage`, `NativeVoiceAssistantBridge`, `VoiceSessionCoordinator`).

---

## 1. Summary of Root Causes & Fixes

| ID | Defect | Legacy Root Cause | Voice Engine 2.0 Root Fix | Verification Status |
|---|---|---|---|---|
| **VOICE-001** | Premature finalization | Calling `stopListening()` transitioned UI straight to `review`/`idle` while Android `SpeechRecognizer.stopListening()` only acknowledged the command asynchronously; `onResults()` arrived late or dropped. | Enforced strict FSM `listening -> finalizing -> review` (`VoiceSessionPhase.finalizing`); confirm/retry/edit-overwrite blocked while finalizing; bounded `2200ms` finalizing watchdog rescues partial if OEM never sends `onResults`. | VERIFIED (Unit + Widget) |
| **VOICE-002** | Session isolation & mic contention | Multiple UI entry points (`VoiceSmartCaptureSheet`, `FinancialAiAssistantPage`, `LifeOsWidgetQuickOverlayActivity`) could race over `SpeechRecognizer`, and stale callbacks from session N mutated session N+1. | Single-owner process-wide mutex in `VoiceSessionCoordinatorNative.kt` + Dart `VoiceSessionCoordinator` with monotonic `(sessionId, attemptId, sequenceNumber, generationToken)`; stale events & late `dispose()` cancels are rejected. | VERIFIED (Unit + Widget + Kotlin Compile) |
| **VOICE-003** | Permission race condition | `MainActivity` used a blind `160ms` `Handler.postDelayed` after `onRequestPermissionsResult` without checking window focus; `VoiceSmartCaptureSheet.didChangeAppLifecycleState(paused)` aborted active sessions while the Android OS permission dialog or system voice dialog was in front. | Removed blind delay; `MainActivity` gates launch on `hasWindowFocus()`; `VoiceSessionCoordinator` tracks `isAwaitingExternalActivity` so OS dialogs/permission prompts are never cancelled on `paused`, while returning unfocused fails safely instead of opening a zombie mic. | VERIFIED (Unit + Widget + Kotlin Compile) |
| **VOICE-004** | Timer conflict & wall-clock skew | Multiple uncoordinated `Timer`s (`silenceTimer`, `processingGuard`, `deadStreamWatchdog`) raced against Android recognizer timeouts and used wall-clock `DateTime.now()`/`Stopwatch()`. | Single `VoiceSessionCoordinator` owns all timers (`preparingTimeout`, `finalizingTimeout`, `maxUtteranceDuration`, opt-in `autoEndpointTimer`, single busy `retryTimer`) keyed by `(sessionId, attemptId, generationToken)` and measured via monotonic clocks (`SystemClock.elapsedRealtime()` on Kotlin, `MonotonicClock` on Dart). | VERIFIED (Unit + Widget) |
| **VOICE-005** | Premature `850ms` endpointing | Default auto-stop after `850ms` cut off natural Vietnamese pauses and multi-clause financial dictation (`"Ăn phở 55 nghìn... và cà phê 35 nghìn"`). | Made `VoiceEndpointMode.explicitStopOnly` the default across all surfaces; opt-in `smartAutoEndpoint` requires speech onset, minimum speech duration (`400ms`), and patient Vietnamese trailing silence (`2000ms` normal / `3200ms` dangling clause). | VERIFIED (Unit + Widget + Corpus) |
| **VOICE-006** | Unreliable RMS waveform & dead-stream switching | Legacy helper treated flat/zero `onRmsChanged` values on OEM devices as a "dead mic" after `2.2s` and silently forced an engine switch mid-sentence; UI animated fake spikes when RMS was unavailable. | Deleted the RMS dead-stream watchdog completely; `VoiceLiveWaveform` strictly distinguishes real PCM16/RMS samples from indeterminate listening (flat baseline + honest label, never fabricating speech peaks). | VERIFIED (Unit + Widget + Kotlin Compile) |
| **VOICE-007** | False offline guarantee | Legacy `EXTRA_PREFER_OFFLINE` on `SpeechRecognizer` silently fell back to Google Cloud online speech when offline packs were absent; strict offline mode did not block online engines. | Removed false `EXTRA_PREFER_OFFLINE` guarantees; implemented Android API 31+ `isOnDeviceRecognitionAvailable` / `createOnDeviceSpeechRecognizer` and API 33+ `checkRecognitionSupport` for `vi-VN`; `EngineSelectionPolicy` hard-blocks all online engines in `offlineStrict` mode. | VERIFIED (Unit + Kotlin Compile) |
| **VOICE-008** | Permanent capability blacklisting | Legacy `SharedPreferences` permanently blacklisted inline Google Speech after a single transient error without TTL or environment invalidation. | Replaced with 24h TTL capability cache (`VoiceCapabilityRepositoryImpl` + `lifeos_voice_engine_caps_v2`) keyed by `(androidSdkInt, osBuildFingerprint, recognitionServiceVersion, locale, audioRoute)`, plus 1-tap reset in `/voice-diagnostics`. | VERIFIED (Unit + Kotlin Compile) |
| **VOICE-009** | Transcript duplication & loss | String concatenation across cumulative partials, shrinking revisions, multi-turn appends, and manual edits duplicated prefixes or lost clauses on empty final callbacks. | Introduced dedicated pure-Dart `TranscriptManager` maintaining `{committedPrefix, currentPartial, manualText, lastMergedFinal}` with overlap deduplication, shrinking partial revision support, empty-final partial rescue, and user-edit protection. | VERIFIED (10 dedicated unit tests) |

---

## 2. Additional Critical Defects Uncovered During Wave-0 & Wave-2 Audits

1. **`AndroidManifest.xml` (`android:noHistory="true"` on `LifeOsWidgetQuickOverlayActivity`):**
   - **Impact:** Launching the runtime `RECORD_AUDIO` permission dialog or Android system speech recognizer dialog from the home widget immediately destroyed `LifeOsWidgetQuickOverlayActivity`, dropping `onActivityResult` completely.
   - **Fix:** Removed `android:noHistory="true"` from `LifeOsWidgetQuickOverlayActivity` in [AndroidManifest.xml](file:///g:/superapp/android/app/src/main/AndroidManifest.xml) and refactored the overlay to share `VoiceSessionCoordinatorNative` and require explicit save confirmation (no blind auto-commit of financial records).

2. **`LifeOsSoundboxSpeaker` TTS vs. Microphone Hardware Contention:**
   - **Impact:** Incoming banking notification TTS could speak aloud while the user was recording voice expenses, polluting ASR audio and competing for AudioFocus.
   - **Fix:** Added `@Volatile microphoneActive` gate in [LifeOsSoundboxSpeaker.kt](file:///g:/superapp/android/app/src/main/kotlin/vn/lifeos/app/LifeOsSoundboxSpeaker.kt) (suppressing TTS while mic is active), added transient ducking AudioFocus, fixed permanent `initFailed` lockout, and coordinated exclusive transient focus via [LifeOsAudioFocusCoordinator.kt](file:///g:/superapp/android/app/src/main/kotlin/vn/lifeos/app/LifeOsAudioFocusCoordinator.kt).

3. **Nested Navigator Modal Occlusion (`useRootNavigator: false`):**
   - **Impact:** `showVoiceSmartCaptureSheet` previously opened `showModalBottomSheet` inside a `StatefulShellRoute` tab navigator, placing the bottom of the sheet (`y = 714..800`) *underneath* `LifeOsFloatingGlassDock` on `360x800` phones.
   - **Fix:** Enabled `useRootNavigator: true` in [voice_smart_capture_sheet.dart](file:///g:/superapp/lib/core/widgets/voice_smart_capture_sheet.dart) so the voice modal always renders cleanly above the bottom dock.

4. **Home Widget / Deep-Link Entry Leak (`actionVoiceSplit`):**
   - **Impact:** `AppRouter` previously injected a hardcoded dummy Vietnamese transcript into `VoiceSmartCaptureSheet` for `actionVoiceSplit`.
   - **Fix:** Removed dummy transcript injection in [app_router.dart](file:///g:/superapp/lib/app/app_router.dart) so voice split launches cleanly into live capture.

5. **Fixed-Length Waveform Buffer Crash & Unchecked `dispose()` BLoC Dispatch:**
   - **Impact:** `List<double>.filled(..., growable: false)` threw `UnsupportedError` on the first real RMS sample; late `dispose()` could dispatch to a closed `VoiceAssistantBloc` during app teardown.
   - **Fix:** Switched `_history` to `growable: true` in [voice_live_waveform.dart](file:///g:/superapp/lib/features/voice_assistant/presentation/widgets/voice_live_waveform.dart) and guarded `dispose()`/`didChangeAppLifecycleState` with `!_voiceBloc.isClosed`.
