# MASTER PLAN — LIFE OS SUPER APP AUTONOMOUS UPGRADE (FROM v3.26.0+44)

- **Baseline Commit:** `4bc371ef1c3f0b0029f28a6d44228f32f6b6aabd` (`tag: v3.26.0`)
- **Toolchain Verified:** Flutter `3.47.0` (stable), Dart `3.13.0`, Node `v24.11.1`, npm `11.6.2`, OpenJDK `21.0.10 LTS`, Firebase CLI `15.27.0`
- **Architecture Mandates:** Feature-First Clean Architecture + 100% Event-Driven `flutter_bloc` (`0% Cubit`), `LifeOsTopToast` (`0% .showSnackBar(`), strictly zero `TextOverflow` usage in `lib/`, integer VND accounting, strict personal/family RBAC isolation.

## Execution Waves & Dependency Graph (DAG)

```mermaid
flowchart TD
    W0["Wave 0: Full Repo Audit + Baseline Verification + docs/upgrade/*"]
    W1A["Wave 1A: FIX-001 Aggregation + FIX-007 Ledger Integrity + FIX-008 AES-256-GCM Vault"]
    W1B["Wave 1B: FIX-002 Family Join + FIX-003 Invite Security + FIX-006 Debt Simplifier + Firestore Rules/Functions"]
    W1C["Wave 1C: FIX-004 Split Validation + FIX-005 Participant Engine + Local AI v3 (Multi-Intent, Negation, Temporal, Personalization, Banking)"]
    G1["Gate 1: Integration + Unit/Property/Fuzz Tests + Cloud Functions + Live Firebase Emulator"]
    W2A["Wave 2A: Smart Inbox + Global Command Palette + Smart Automation Studio + Encrypted Backup/Restore"]
    W2B["Wave 2B: AI Receipt OCR/Itemized Split + 7/30/90d Cashflow Forecast + Life Insights + Vehicle TCO/Fuel + Calendar Time-Blocking"]
    W2C["Wave 2C: Oversized File Refactoring + Offline Durable Outbox + R8/Asset/Split-ABI APK Optimization + CI/CD Hardening"]
    G2["Gate 2: Full Regression + Web/APK Build Verification + Benchmark + FINAL_REPORT.md"]

    W0 --> W1A & W1B & W1C
    W1A & W1B & W1C --> G1
    G1 --> W2A & W2B & W2C
    W2A & W2B & W2C --> G2
```

## Non-Negotiable Release & Safety Boundaries
1. **No unauthorized push/tag/release:** All commits/changes stay local unless explicitly authorized by the user.
2. **No destructive migrations:** Existing user wallets, transactions, family groups, and documents remain 100% readable and backward-compatible.
3. **Real emulator verification:** `firestore.rules` and `functions/` are verified against Google's live Cloud Firestore Emulator (`127.0.0.1:8188`).
