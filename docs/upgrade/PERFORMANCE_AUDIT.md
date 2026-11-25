# PERFORMANCE, MEMORY & APK SIZE AUDIT — LIFE OS (BEFORE vs AFTER)

## 1. Measured Release APK Size Reduction (`-59.7%` on Primary `arm64-v8a`)

| Artifact | Size (MB) | Exact Bytes | Delta vs Baseline | SHA-256 Checksum |
|---|---:|---:|---:|---|
| **Baseline (`v3.26.0` Fat Unminified APK)** | **`97.59 MB`** | `102,332,969` | — | `1a9daacbb86872b26879a6d53ec89a6baf69efe5dd272a51ed350a0e8c8613f3` |
| **Upgraded `app-arm64-v8a-release.apk` (Primary 64-bit)** | **`39.30 MB`** | **`41,203,797`** | **`-58.29 MB` (`-59.73%`)** | `4d69ece154bbf605ea22180ba391ef65b4b1cba70ba53256c9a51bd73678f602` |
| **Upgraded `app-armeabi-v7a-release.apk` (32-bit ARM)** | **`37.71 MB`** | **`39,537,189`** | **`-59.88 MB` (`-61.36%`)** | `58d80fbd17b320328a8f55a5d8dccc4b919b261b14c68788cfcaebbc7932f475` |
| **Upgraded `app-x86_64-release.apk` (x86_64)** | **`40.90 MB`** | **`42,888,521`** | **`-56.69 MB` (`-58.09%`)** | `f64f67f73ed2f60d5ec5f860d4837432cc6acca87af200a583059649441c87db` |

### Root-Cause Optimizations Applied
1. **`--split-per-abi` ABI Isolation:** Eliminated bundling `x86_64` (`26.27 MB`) and `armeabi-v7a` (`22.99 MB`) native `.so` binaries inside 64-bit ARM user downloads while preserving full C++17 NDK `liblifeos_fasttext.so` on every ABI.
2. **R8 Code Shrinking & Resource Shrinking (`android/app/build.gradle.kts` + `proguard-rules.pro`):** Enabled `isMinifyEnabled = true` and `isShrinkResources = true` with explicit keep rules for `vn.lifeos.app.life_os.**` (JNI FastText FFI, `BankNotificationListenerService`, `LifeOsHomeWidgetProvider`, `LifeOsAlarmReceiver`, `LifeOsBootReceiver`, `LifeOsSecureVault`) and Flutter Engine optional Play Core deferred-component `-dontwarn` rules.
3. **Raster Asset Right-Sizing:** Optimized 10 oversized raster illustrations/skins in `assets/images` & `assets/bank_cards`, reducing raw raster asset payload from **`8.73 MB` to `5.50 MB` (`-3.23 MB`)** with zero missing `AppAssets` references (`32/32` 3D icons + `7/7` bank skins verified by widget tests).
4. **Icon Font Tree-Shaking:** `MaterialIcons-Regular.otf` shrunk from `1,645,184 bytes` to `63,468 bytes` (`-96.1%`) on Android and `67,596 bytes` (`-95.9%`) on Web.

---

## 2. Runtime, Memory, Firestore & 60/120 Hz Frame Discipline
1. **Unbounded Financial Accuracy Without UI List Bloat:** UI transaction feeds remain paginated while `FinancialAggregationEngine` + `monthly_summaries` compute exact rollups across `100`, `101`, `500`, `1,000`, and `10,000` transactions in pure Dart (`O(N)` single-pass integer arithmetic).
2. **On-Device AI Latency & Memory Footprint:** `vn_money_split_fasttext_v1.ftq` is quantized (`INT8`, `384.89 KB`), running sub-millisecond inference on-device with zero network roundtrip and zero GPU/NPU memory spike.
3. **Offline-First Non-Blocking UX:** `OfflineOutboxService` queues mutations locally keyed by `operationId` with bounded exponential backoff (`pendingSync -> syncing -> synced / conflict / failed`).
4. **Modularized Widget Trees & Controller Hygiene:** Extracted oversized monolithic UI files (`lifeos_design_system.dart`, `today_page.dart`, `finance_page.dart`, `assets_page.dart`, `MainActivity.kt`) into focused sub-widgets/helpers, isolating `RepaintBoundary` charts, honoring `TickerMode` on inactive shell tabs, and respecting OS `Reduce Motion`.
