# PROGRESS TRACKER — LIFEOS SUPER APP v3.27.0

| Phase / Wave | Scope | Owner | Status | Notes |
|---|---|---|---|---|
| **Phase 0** | Deep Source Audit (`firestore.rules`, `functions/`, `lib/`, `android/`, `tools/financial_ai/`, `pubspec.yaml`) + `docs/audit/` Baseline Suite | Engineering Lead + Security Architect + AI/Native Auditor | `VERIFIED` | 22 real issues (`9` P0, `8` P1, `4` P2, `1` P3) logged with exact file:line evidence. |
| **Wave 1A (Phases 1 & 2)** | `firestore.rules` P0 Hardening, Family Fund 9-State Lifecycle, Settlement/Split/Vehicle/Task Fixes, `BigInt` Split & `sum==0` Debt Simplifier, Cloud Functions fixes, 11 Emulator Attack Tests & 2,000+ Property Tests | `DEV-SEC-FUNDS-RULES` (isolated worktree) | `IN_PROGRESS` | Dispatched on local checkpoint `agy/v3.27.0-upgrade`. |
| **Wave 1B (Phase 4)** | Expanded Disjoint OOD Datasets (`>=250` unseen/model), Explicit `__ood__` + Bias Retraining for Both Models, Unified Runtime OOD Gate, Full Metrics Evaluator | `DEV-AI-OOD-EVAL` (isolated worktree) | `IN_PROGRESS` | Targeting Macro F1 `>= 95%` & OOD Rejection `>= 95%` on disjoint sets. |
| **Wave 1C (Phases 3, 5, 10, 11, 13)** | Android `github`/`play` Flavors, `FLAG_SECURE`, Encrypted Bank Queue + Sign-Out Wipe, 9-State Voice FSM, Alarm/Calendar/Vault Hardening, Safe Account Deletion | `DEV-ANDROID-VOICE-PRIVACY-FLAVORS` (isolated worktree) | `IN_PROGRESS` | Dispatched in parallel with zero file overlap. |
| **Wave 2 (Phases 14–16)** | Merge Integration, `Life Timeline`, `pubspec.yaml`, `.github/workflows/ci.yml`, `dart format`, Full Test + Coverage, Live Emulator, Web + GitHub APK + Play AAB Builds | Engineering Lead | `PENDING` | Runs immediately after Wave 1 completion. |
| **Wave 3 (Phase 23)** | Complete `docs/audit/` Handover Suite + `CHANGELOG.md` | Engineering Lead | `PENDING` | Final truth-verified reporting. |
