# PERFORMANCE & BUILD SIZE REPORT — LIFEOS SUPER APP v3.27.0

- **Date:** `2026-11-25`
- **Build Environment:** Windows 11 · Flutter `3.47.0` (stable) · Dart `3.13.0` · OpenJDK `21.0.10` · Android Gradle R8 + Resource Shrinking + C++17 NDK

---

## 1. Release Build Size Reduction (`-62.20%` on Primary Android `arm64-v8a`)

| Artifact | Size (MB) | Exact Bytes | Delta vs Baseline (`97.59 MB`) | SHA-256 Checksum |
|---|---:|---:|---:|---|
| **Baseline `v3.26.0` Fat Unminified APK** | `97.59 MB` | `102,332,969` | — | `1a9daacbb86872b26879a6d53ec89a6baf69efe5dd272a51ed350a0e8c8613f3` |
| **`app-arm64-v8a-github-release.apk` (Primary 64-bit)** | **`36.89 MB`** | **`38,681,905`** | **`-60.70 MB` (`-62.20%`)** | `8d08b0fc205d80ef4b529a92f48d53bf31fb7758d308b9ac6509c5fc1a8eeb9a` |
| **`app-armeabi-v7a-github-release.apk` (32-bit ARM)** | **`35.32 MB`** | **`37,031,681`** | **`-62.27 MB` (`-63.81%`)** | `855ed2b169f04de09dba5125c2e3acfda5b65ce5978e503099e58ab47fc975f8` |
| **`app-x86_64-github-release.apk` (x86_64)** | **`38.50 MB`** | **`40,366,629`** | **`-59.09 MB` (`-60.55%`)** | `6747052a35258183a1212a1d92674f5d91dfea7ad0a030dd07a46217a07e99f8` |
| **`app-play-release.aab` (Multi-ABI Play Bundle)** | **`84.07 MB`** | **`88,152,677`** | Play delivers ~35–37 MB/ABI | `a35658979a6fb415c533a48bafd126486161480ea87bf03cc5422e906f989342` |
| **Web Production Bundle (`build/web`)** | **PASS** | Compiled release | MaterialIcons `-95.9%` | Verified locally |

### Measured Optimization Contributors
1. **Split-ABI Packaging (`--split-per-abi` & Play `.aab`):** Removed bundling unused `x86_64` (`26.27 MB`) and `armeabi-v7a` (`22.99 MB`) native libraries in 64-bit ARM downloads while keeping full C++17 NDK `liblifeos_fasttext.so`.
2. **R8 Code & Resource Shrinking (`isMinifyEnabled = true`, `isShrinkResources = true`):** Shrunk DEX bytecode & Android resources cleanly with verified `proguard-rules.pro` keep rules for `vn.lifeos.app.life_os.**` and Flutter Engine Play Core `-dontwarn` rules.
3. **2D Flat Icon System (`assets/icons/`):** Replaced 32 glossy 3D PNGs (`~3.5 MB`) with crisp `256×256` Nano Banana 2D Flat Duotone PNGs (**`0.80 MB` total, `-2.7 MB`**).
4. **Raster Illustration Right-Sizing (`assets/images/`, `assets/bank_cards/`):** Reduced oversized hero/card rasters from `8.73 MB` to **`5.50 MB` (`-3.23 MB`)**.
5. **Icon Font Tree-Shaking:** `MaterialIcons-Regular.otf` reduced from `1,645,184 B` to **`63,748 B` (`-96.1%`)** on Android and **`67,876 B` (`-95.9%`)** on Web.

---

## 2. Measured Runtime Latency & Device Benchmark Status

| Metric | Measured Result | Environment / Method | Status |
|---|---|---|---|
| Financial AI INT8 Dart Worker Isolate Inference | Cold `23.23 ms` · Warm **P50 `0.407 ms`** · **P95 `0.761 ms`** (`100` runs) | Local Dart VM (`dart_runtime_benchmark.json`) | **PASS** |
| Money Split AI INT8 Inference | Cold `5.23 ms` · Warm **P50 `0.379 ms`** · **P95 `0.677 ms`** (`800` runs) | Local Python Quantized Reader | **PASS** |
| Unbounded Financial Rollup (`10,000` tx) | Single-pass `O(N)` pure-Dart integer aggregation | `fix_001_007_008_ledger_aggregation_vault_test.dart` | **PASS** |
| 2,000+ Seeded `BigInt` Split + Debt DP Fuzz | Exact conservation (`0` VND drift) | `v327_financial_security_property_test.dart` | **PASS** |
| Physical Android Cold Startup (`< 2.5s`), 60/120 Hz GPU Frame Trace & Long-Run Memory Profile | **NOT_RUN** | Requires physical USB Android handset (none attached) | **NOT_RUN** |
