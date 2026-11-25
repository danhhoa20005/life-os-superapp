# KNOWN LIMITATIONS — LIFEOS SUPER APP v3.27.0

1. **Firestore Rules CEL Cannot Sum Arbitrary Map Values (`split_bills`):**
   - Firestore Security Rules v2 CEL does not support iterating over arbitrary map values to verify `sum(sharesByUserId.values()) == totalAmountMinor`.
   - **Mitigation:** `firestore.rules` enforces `memberIds.hasAll(sharesByUserId.keys())`, positive `totalAmountMinor`, creator/payer attribution, and allows any billed member to transition a bill to `'disputed'`, while Dart domain & `BigInt` Hamilton apportionment enforce exact conservation client-side. Full server-side sum enforcement requires deploying an optional Blaze Cloud Function callable.
2. **Android Offline Speech Recognition Depends on OS Google Speech Service:**
   - Even with formal 9-state FSM and fallback handling, Android `SpeechRecognizer` offline Vietnamese recognition depends on whether the handset OEM/user has downloaded the Google Vietnamese offline speech pack; when unavailable, recognition falls back to online speech service and always preserves manual transcript editing.
3. **Money Split AI Hard Near-OOD Single-Person Sentences (`92.73%` on Stratum E):**
   - On 110 hard near-OOD single-person transactions containing high lexical overlap with split verbs (e.g., `"chuyển khoản ..."`), Money Split AI rejects `102/110` (`92.73%`), pushing overall 5-stratum OOD rejection to `97.73%` (`431/441`). Runtime rule guards (`SmartMoneySplitAiEngine` requiring explicit split/allocation structural cues) prevent false group-bill creation.
4. **Physical Device Benchmarks & OEM ROM Behavior (`NOT_RUN`):**
   - Cold startup latency, 60/120 Hz real GPU frame timing, Android Doze alarm wakeups across Xiaomi/OPPO/Samsung OEM battery managers, live microphone acoustics, live camera receipt capture, and real `FLAG_SECURE` screenshot blocking have not been executed on a physical handset because no USB Android device is attached to this host.
5. **Cloud Encryption Scope:**
   - Local Document Vault attachments, local bank SQLite queue entries, and exported `.lfbk` archives are encrypted with `AES-256-GCM`; Firestore cloud documents rely on TLS + Google Cloud encryption at rest + RBAC rules (not end-to-end zero-knowledge encryption).
6. **External Banking Integration:**
   - Android `NotificationListenerService` parses locally observed notification text (marked `PROVISIONAL` until confirmed or upgraded). Direct verified bank webhook ingestion (`SePay`) is implemented and verified on Firebase Emulator/Sandbox, and requires live partner credentials + deployed Cloud Functions (Blaze) for real-time production bank feeds.
