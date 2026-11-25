# AI EVALUATION REPORT — LIFEOS LOCAL VIETNAMESE AI (v3.27.0)

- **Date:** `2026-11-25`
- **Status:** `VERIFIED` (Independent, Leak-Free Python & Dart Runtime Evaluation)
- **Full Raw Artifact:** `tools/financial_ai/artifacts/v327_full_ai_eval_report.json`

---

## 1. Data Leakage Verification (Programmatically Verified)

Every train/validation/test split and every in-domain vs out-of-domain (OOD) corpus was verified by `evaluate_all_models.py` (`verify_zero_leakage()`):
- **Financial AI:** ID overlap = **`0.0%`**, OOD split overlap = **`0.0%`**, OOD vs ID overlap = **`0.0%`**.
- **Money Split AI:** ID overlap = **`0.0%`**, OOD split overlap = **`0.0%`**, OOD vs ID overlap = **`0.0%`**.
- **Dart Runtime 64-Sample Unseen OOD Stress Sets:** Cross-checked against both `train` and `val` OOD files -> **`0` overlapping prompts**.

---

## 2. Model Architecture Upgrade (Compatible with `LFTQ v1` Binary ABI & C++17 FFI)

To resolve the baseline `60.0%` Financial AI OOD failure and leaked 10-sample Money Split AI OOD evaluation (`AUD-014`), both quantized `INT8` FastText models were retrained with:
1. **Explicit `(K+1)`-th `__ood__` Rejection Class + Learned Positive Bias (`biasB[__ood__] > 0`):** Ensures sparse/unseen zero-vector or colliding-subword inputs default cleanly into `__ood__` instead of spiking onto a random category.
2. **Strictly Disjoint Multi-Stratum OOD Training & Calibration:** Built 5-stratum Vietnamese accented + unaccented OOD corpora (chatter/homonyms, non-financial LifeOS commands, English/gibberish/code fragments, negated/hypothetical/balance/OTP utterances, plus hard near-OOD single-person transactions for Money Split AI).
3. **Leak-Free Temperature Calibration (`T* >= 0.85`):** Calibrated strictly on held-out `val + ood_val`, eliminating the previous `T* = 0.56` logit over-sharpening bug.
4. **Unified Runtime Policy (`FastTextClassifier` + `ConfidencePolicyEngine`):** `__ood__` is strictly rejected as `ConfidenceTier.unknown` (never mapped to `'other'` or auto-assigned), matching `meta.json` and `evaluate_all_models.py` thresholds identically.

---

## 3. Empirical Results (Before vs After)

### A. Financial AI (`assets/models/vn_financial_fasttext_v1.ftq` — `v3.0.0`, 30 categories + `__ood__`)

| Metric | Baseline (`v3.26.0`) | Upgraded (`v3.27.0`) | Target | Status |
|---|---:|---:|---:|---|
| Model Size (`INT8 LFTQ v1`) | `956.12 KB` | **`984.37 KB`** (`1,007,991 B`) | `< 1.2 MB` | `PASS` |
| SHA-256 | Legacy | `602462570be9b70c138835ebf525ecf10e0e51e4d147c2fbd902349e7342a65e` | Verified | `PASS` |
| Calibration Temp `T*` / `b[__ood__]` | `0.56` / `0.0` | **`0.95`** / **`+1.018`** | `T* >= 0.85` | `PASS` |
| Held-out ID Test Accuracy (`1,297` samples) | `99.31%` | **`96.45%`** | `>= 95%` | `PASS` |
| Held-out ID **Macro F1** | `99.43%` | **`97.72%`** | `>= 95%` | `PASS` |
| **Unseen Multi-Stratum OOD Rejection** | `60.0%` (20) / `53.3%` unseen | **`97.94%`** (**`332/339`** unseen!) | `>= 95%` | `PASS` |
| OOD AUROC | Not measured | **`0.9947`** | `>= 0.95` | `PASS` |
| Expected Calibration Error (ECE) | `0.0246` (ID only) | **`0.0491`** (`0.0389` ID-only) | `< 0.05` | `PASS` |
| False Auto-Assignment Rate (`high=0.87`) | `0.0%` (20 OOD) | **`0.18%`** (`0` ID errors; `3/1,636` total) | Low & audited | `PASS` |
| Dart Worker Isolate Latency (P50 / P95) | `~0.4 ms` | **`0.407 ms` / `0.761 ms`** (`23.2 ms` cold) | `< 10 ms` | `PASS` |

**Financial AI Per-Stratum Unseen OOD Breakdown (`339` samples):**
- Chatter & Homonyms (`Lê Văn Lương`, `giải lao`, `uống nước lọc`): **`105 / 106` (`99.06%`)**
- Non-Financial LifeOS Commands (calendar, alarms, meds, water, ODO): **`90 / 90` (`100.0%`)**
- English / Gibberish / Code / Short Fragments: **`48 / 53` (`90.57%`)**
- Negated / Hypothetical / Balance Inquiry / OTP: **`89 / 90` (`98.89%`)**

### B. Money Split AI (`assets/models/vn_money_split_fasttext_v1.ftq` — `v2.0.0`, 12 intents + `__ood__`)

| Metric | Baseline (`v3.26.0`) | Upgraded (`v3.27.0`) | Target | Status |
|---|---:|---:|---:|---|
| Model Size (`INT8 LFTQ v1`) | `384.89 KB` | **`409.00 KB`** (`418,817 B`) | `< 450 KB` | `PASS` |
| SHA-256 | Legacy | `6f0daa594f6f5766edc193361c25aaaf6483f0ced023423fa5d1b2b6bb6dc4b6` | Verified | `PASS` |
| Calibration Temp `T*` / `b[__ood__]` | `0.76` / `0.0` | **`0.88`** / **`+0.565`** | `T* >= 0.85` | `PASS` |
| Held-out ID Test Accuracy (`232` samples) | `99.57%` (leaked OOD) | **`97.84%`** | `>= 95%` | `PASS` |
| Held-out ID **Macro F1** | `99.58%` | **`96.80%`** | `>= 95%` | `PASS` |
| **Unseen Multi-Stratum OOD Rejection** | `55%–75%` unseen | **`97.73%`** (**`431/441`** unseen!) | `>= 95%` | `PASS` |
| OOD AUROC | Not measured | **`0.9931`** | `>= 0.95` | `PASS` |
| Expected Calibration Error (ECE) | `0.0405` | **`0.0439`** | `< 0.05` | `PASS` |
| False Auto-Assignment Rate (`high=0.87`) | Leaked | **`1.04%`** (`0` ID errors; `7/673` high-overlap near-OOD) | Audited | `PASS` |
| Python Inference Latency (P50 / P95) | `~0.38 ms` | **`0.379 ms` / `0.677 ms`** (`5.23 ms` cold) | `< 10 ms` | `PASS` |

**Money Split AI Per-Stratum Unseen OOD Breakdown (`441` samples):**
- Chatter & Homonyms: **`100 / 101` (`99.01%`)**
- Non-Financial LifeOS Commands: **`89 / 89` (`100.0%`)**
- English / Gibberish / Fragments: **`52 / 53` (`98.11%`)**
- Negated / Hypothetical / Balance / OTP: **`88 / 88` (`100.0%`)**
- Hard Near-OOD Single-Person Transactions (e.g., `"chuyển khoản 2 triệu cho mẹ"`, `"nhận lương 20 triệu"`): **`102 / 110` (`92.73%`)**

---

## 4. Dart Runtime & Multi-Intent Verification (`test/unit/v327_ai_ood_and_nlu_test.dart`)
- Verified Vietnamese colloquial amount parsing (`65k`, `1tr2`, `18 triệu rưỡi`, `2 củ`, `500 nghìn`) with `100%` exact integer VND accuracy.
- Verified multi-intent compound parsing (`"Hôm nay nhận lương 15 triệu, đổ xăng 70k, tối ăn lẩu 600k chia bốn người và Chủ nhật nhắc bảo dưỡng xe"`) decomposes cleanly into distinct draft actions requiring explicit user confirmation before committing.
- Verified both `.ftq` models load bit-identically in Dart runtime with `>= 95%` OOD rejection on 64 unseen prompts each.
