# AI LOCAL & HYBRID INTELLIGENCE AUDIT — LIFE OS

## 1. Baseline Models in `assets/models/`
1. **`vn_financial_fasttext_v1.ftq` (`v2.0.0`, `956.1 KB`, 30 labels):**
   - Held-out Test Accuracy: `99.31%`, Macro F1: `99.43%`, ECE: `0.0246`, False Auto-Assign: `0.00%`, OOD Reject: `60.0%`.
   - Dart Worker Isolate Warm P50: `0.55 ms`, P95: `2.23 ms`.
   - Note: `offline_fasttext_v2_model_test.dart` locks 14 bit-exact golden vectors on `v2.0.0`. Any retrained candidate is benchmarked side-by-side and only promoted if it strictly improves held-out metrics while updating golden vectors & `docs/financial_ai/*.md` transparently.
2. **`vn_money_split_fasttext_v1.ftq` (`v1.0.0`, `384.9 KB`, 12 labels):**
   - Held-out Test Accuracy: `98.63%`, Macro F1: `98.66%`, False Auto-Assign: `0.00%`, OOD Reject: `100.0%`, ECE: `0.1001` (due to `T* = 1.20`).
   - Action: Export persistent leak-free JSONL splits (`money_split_train/val/test.jsonl`), expand regional/ASR/negation/multi-intent evaluation corpus, and calibrate temperature to bring ECE `< 0.05` while maintaining `Accuracy >= 97%` and `OOD Rejection >= 95%`.

## 2. NLU & Domain Safety Gaps Being Addressed
- **Negation & Hypothetical Guard:** Prevent `"Tôi định mua xe 30 triệu"`, `"Đừng ghi khoản ăn trưa 50k"`, and `"Có nên mua điện thoại 15tr không?"` from creating ledger transactions.
- **Mixed Multi-Intent Segmentation:** Segment `"Trưa nay ăn cơm 45k, đổ xăng 70k, tối 8 giờ nhắc tôi gọi mẹ và ngày mai có lịch họp lúc 9 giờ"` into 4 independent editable/removable action drafts.
- **Rich Entity Extraction:** Extract `amount`, `currency`, `merchant`, `category`, `wallet`, `transactionType`, `participant`, `payer`, `percentage`, `shareWeight`, `date`, `time`, `duration`, `location`, `vehicle`, `odometerKm`, `taskTitle`, `reminderType`, and `negation`.
- **Explainable Personalization:** Unify merchant/category/wallet/nickname learning with full user inspect/edit/delete/reset controls.
