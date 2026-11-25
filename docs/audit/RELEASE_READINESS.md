# RELEASE READINESS REPORT — LIFEOS SUPER APP v3.27.0+45

- **Date:** `2026-11-25`
- **Local Integration Branch:** `agy/v3.27.0-upgrade` (`main` preserved untouched at `4bc371e`)
- **Release Readiness Decision:** **`PARTIAL` — `VERIFIED` ON ALL LOCAL/EMULATOR/BUILD GATES; `BLOCKED` ON EXTERNAL SIGNING KEYSTORE, PHYSICAL DEVICE HARDWARE SIGN-OFF & USER AUTHORIZATION TO PUSH/DEPLOY**

---

## 1. Dual-Flavor Distribution Verification (`githubRelease` vs `playRelease`)

| Check | `githubRelease` (GitHub OTA APK) | `playRelease` (Google Play `.aab`) | Status |
|---|---|---|---|
| Artifact Built Locally | `app-arm64-v8a-github-release.apk` (`36.89 MB`), `armeabi-v7a` (`35.32 MB`), `x86_64` (`38.50 MB`) | `app-play-release.aab` (`84.07 MB`) | **PASS** |
| `REQUEST_INSTALL_PACKAGES` in Merged Manifest | **`True`** (Required for verified GitHub OTA self-update) | **`False`** (Stripped via `tools:node="remove"` & flavor manifest isolation) | **VERIFIED** |
| `USE_EXACT_ALARM` in Merged Manifest | **`False`** (Removed; uses Play-compliant `SCHEDULE_EXACT_ALARM`) | **`False`** (Stripped via `tools:node="remove"`) | **VERIFIED** |
| In-App GitHub APK OTA Updater (`BuildConfig.ENABLE_GITHUB_OTA`) | Enabled (`true`) with SHA-256 + X.509 signature + version downgrade guard | Disabled (`false` — `NativeAppUpdaterBridge` throws `OTA_DISABLED_PLAY_FLAVOR`) | **VERIFIED** |
| `android:allowBackup` & Android 12+ Transfer Exclusions | `allowBackup="false"`; excludes `secure_doc_vault`, `lifeos_hardware_vault_prefs_v1.xml`, `lifeos_bank_signal_queue.db*`, `lifeos_bank_listener_prefs.xml` | Identical | **VERIFIED** |

---

## 2. CI/CD Pipeline Hardening (`.github/workflows/ci.yml`)
- Top-level `permissions: contents: read`; `contents: write` scoped exclusively to `publish-android-ota-release`.
- Pinned toolchain (`Flutter 3.47.0`, `Java 17` for Android build, `Java 21` for Firestore Emulator, `Node 22` for Cloud Functions).
- Gates enforced on every push/PR: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos --fatal-warnings`, `flutter test --coverage`, `flutter build web --release`, `flutter build apk --debug --flavor github`, `flutter build appbundle --debug --flavor play`, `functions` typecheck & unit tests, and live Auth + Firestore Emulator `24/24` security & integration suite.
- Tagged release (`refs/tags/v*`) runs **fail-closed**: aborts immediately if `LIFEOS_RELEASE_KEYSTORE_BASE64` / passwords are missing (never falls back to debug signing), builds both signed `github` split-ABI APKs and `play` `.aab`, verifies certs via `apksigner`, checks package identity via `aapt2`, and recomputes SHA-256 directly from the signed APK artifact.

---

## 3. Go-Live Checklist for User When Authorizing Release
1. **Optional Hardware Smoke Test:** Sideload `build/app/outputs/flutter-apk/app-arm64-v8a-github-release.apk` (`36.89 MB`) on an Android phone to sign off live microphone, camera receipt picker, `FLAG_SECURE` recents privacy, notification listener & Doze alarms.
2. **Merge & Deploy Rules:** Review `agy/v3.27.0-upgrade`, merge to `main`, and deploy `firestore.rules` (works on Spark free tier; deploy `functions/` if Blaze is enabled).
3. **Production Keystore & Tag:** Ensure GitHub Secrets (`LIFEOS_RELEASE_KEYSTORE_BASE64`, `LIFEOS_RELEASE_STORE_PASSWORD`, `LIFEOS_RELEASE_KEY_ALIAS`, `LIFEOS_RELEASE_KEY_PASSWORD`) are configured, then push `main` and tag `v3.27.0`.
