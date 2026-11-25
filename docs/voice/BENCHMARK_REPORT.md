# LifeOS Voice Engine 2.0 — Benchmark Report

**Date:** 2026-11-25
**Host Environment:** Windows 11 (`AMD64`), Dart/Flutter Host Test Harness, Python `3.14.7`
**Source Artifacts:** [poc_benchmark_report.json](file:///g:/superapp/tools/voice_asr_poc/results/poc_benchmark_report.json), [vi_financial_corpus.json](file:///g:/superapp/tools/voice_asr_poc/corpus/vi_financial_corpus.json), [voice_vietnamese_corpus_nlp_test.dart](file:///g:/superapp/test/unit/voice_vietnamese_corpus_nlp_test.dart)

---

## 1. Vietnamese 36-Utterance Corpus NLP Benchmark (`MEASURED_HOST`)

Evaluated across `36` realistic Vietnamese financial, group-split, transfer, calendar, task, health, and mid-sentence-pause utterances plus `87` simulated noisy ASR variants:

| Metric | Baseline (Pre-Voice 2.0) | Voice Engine 2.0 (`MEASURED_HOST`) | Delta |
|---|---|---|---|
| **Exact Amount Accuracy (Clean Corpus)** | `27 / 29` (`93.10%`) | **`29 / 29` (`100.00%`)** | `+6.90 pp` |
| **Intent Classification Accuracy** | `33 / 36` (`91.67%`) | **`36 / 36` (`100.00%`)** | `+8.33 pp` |
| **Date / Time Cue Recognition** | `5 / 6` (`83.33%`) | **`6 / 6` (`100.00%`)** | `+16.67 pp` |
| **Remaining Corpus Gaps** | `5` gaps (`một triệu hai`, `ba lăm cành`, `nạp ... sang`, `đi khám`, `gặp` vs `gấp`) | **`0` gaps** | `-5` gaps |
| **Noisy ASR Variant Amount Accuracy** | — | **`80 / 87` (`91.95%`)** | Baseline established |
| **Spoken Normalization Latency (P50 / P95)** | — | **`0.154 ms / 0.345 ms`** (unloaded) · `0.186 ms / 0.610 ms` (full-suite load) | Sub-millisecond |
| **SmartOmniIntentParser Latency (P50 / P95)** | — | **`0.954 ms / 4.547 ms`** (unloaded) · `1.194 ms / 11.065 ms` (full-suite load) | `< 5 ms` unloaded |
| **Financial Analyzer Latency (P50 / P95)** | — | **`0.659 ms / 1.912 ms`** (unloaded) · `0.839 ms / 4.783 ms` (full-suite load) | `< 2 ms` unloaded |

### Explicit Section 15 7-Sentence Verification (`7/7 PASS`)
1. `"Ăn sáng ba mươi lăm nghìn."` -> Expense `35.000 ₫`
2. `"Mua cà phê bốn mươi lăm nghìn và đổ xăng bảy mươi nghìn."` -> Batch Expense `45.000 ₫` + `70.000 ₫`
3. `"Chuyển một triệu hai cho mẹ."` -> Expense/Transfer `1.200.000 ₫`
4. `"Ăn lẩu bốn trăm năm mươi nghìn chia đều ba người."` -> Group Bill Split `450.000 ₫` / `3` people (`150.000 ₫` each)
5. `"Nhắc uống ba trăm ml nước lúc mười giờ sáng mai."` -> Hydration / Reminder `300 ml` + time cue
6. `"Đặt lịch khám răng chín giờ thứ bảy tuần này."` -> Calendar Event + date/time cue
7. `"Ghi chú mua sữa và bánh mì chiều nay."` -> Grocery / Task item + time cue

---

## 2. Host 16 kHz PCM16 Ring Buffer & Adaptive Energy/ZCR VAD Benchmark (`MEASURED_HOST`)

Measured via `python tools/voice_asr_poc/benchmark_asr.py` on `36` synthesized Vietnamese utterance cadence envelopes (`6,386` 20ms frames @ `16,000 Hz`, Mono, `16-bit PCM`):

| Metric | Measured Value (`MEASURED_HOST`) |
|---|---|
| Total 20ms PCM16 frames processed | `6,386` frames (`36` utterances) |
| Per-frame VAD processing latency (Mean / P50 / P95) | **`138.81 us` / `139.5 us` / `195.0 us`** (budget: `20,000 us`/frame -> `< 1%` budget) |
| Speech onset detection absolute lag (P50 / P95) | `20.0 ms` / `60.0 ms` (`36/36` detected) |
| Endpoint hangover detection lag (P50 / P95, `850ms` hangover) | `811.0 ms` / `821.0 ms` (`36/36` detected) |
| **Premature cuts on `650ms` mid-sentence pauses** | **`0 / 36` (`0.00%`)** |
| Peak RAM (`tracemalloc`, 30s PCM16 ring buffer = `960,000 bytes`) | **`938.36 KB`** |
| Simulated ASR Variant Corpus WER / CER (108 pairs, raw vs ASCII-folded) | Raw WER `44.97%` / CER `19.11%` · ASCII-folded WER `19.31%` / CER `12.04%` |

---

## 3. Build Artifact Footprint (`MEASURED_HOST`)

| Artifact | Size | Notes |
|---|---|---|
| `build/app/outputs/flutter-apk/app-github-release.apk` | **`89.01 MB`** (`93,337,875 bytes`) | Down from `96.27 MB` (v3.24.1); `0 MB` bundled offline ASR weights (strictly on-demand) |
| `MaterialIcons-Regular.otf` (tree-shaken) | `65,952 bytes` | `96.0%` reduction from `1,645,184 bytes` |

---

## 4. Physical Android & Live Offline ASR Benchmarks (`NOT_MEASURED — DEVICE REQUIRED`)

The following measurements require physical Android ARM64 hardware (`adb devices` = `0`) and installed native ASR binaries; they are explicitly **NOT** fabricated:

| Metric | Status |
|---|---|
| Live Vietnamese microphone WER / CER across Android `SpeechRecognizer` vs `createOnDeviceSpeechRecognizer` vs Vosk `small-vn-0.4` vs Whisper `tiny/base` | `NOT_MEASURED — DEVICE REQUIRED` |
| On-device ARM64 NEON Real-Time Factor (RTF) & time-to-first-partial / time-to-final | `NOT_MEASURED — DEVICE REQUIRED` |
| Physical Android runtime RSS memory, CPU %, thermal throttling, and battery drain | `NOT_MEASURED — DEVICE REQUIRED` |
| 50-session consecutive real-device soak reliability & Bluetooth SCO/BLE handoff jitter | `NOT_MEASURED — DEVICE REQUIRED` |
