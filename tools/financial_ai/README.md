# Life OS — Vietnamese Financial AI Training & Quantization Toolkit

Bộ công cụ huấn luyện, kiểm định chống rò rỉ dữ liệu, hiệu chỉnh xác suất (Temperature Scaling), lượng tử hóa `INT8` (`.ftq`) và đo hiệu năng cho bộ phân loại danh mục tài chính tiếng Việt chạy offline của Life OS.

## Cấu trúc Thư mục

- `feature_spec.py` — Chuẩn hóa tiếng Việt (bảo toàn từ có dấu + sinh đồng thời từ bỏ dấu ASCII + tách word n-gram + subword UTF-8 + hàm băm `fnv1a32` đồng nhất bit-for-bit với C++17 NDK FFI và Dart Isolate).
- `generate_synthetic_data.py` — Sinh kho ngữ liệu tiếng Việt 28 nhãn ngữ nghĩa chia tách nghiêm ngặt theo **họ mẫu câu (Template Families A / B / C)** để ngăn chặn hoàn toàn rò rỉ template giữa `train` / `val` / `test`.
- `prepare_dataset.py` — Kiểm tra tính hợp lệ của nhãn, khử trùng lặp, kiểm tra `0%` chồng lấp câu & mẫu câu, xuất định dạng `.jsonl` và chuẩn Meta FastText `__label__<key>`.
- `train.py` — Huấn luyện mô hình Supervised FastText (Subword + Word Bigram Embedding + Mini-batch AdaGrad + tìm kiếm siêu tham số trên `val` + tối ưu Temperature Calibration $T^*$).
- `quantize.py` — Nén ma trận trọng số sang **Per-Row Symmetric INT8 (`.ftq`)** kèm kiểm tra độ lệch F1 sau nén `< 0.5%`.
- `evaluate.py` — Tính toán Accuracy, Macro F1, Precision/Recall từng nhãn, Confusion Matrix, Expected Calibration Error (ECE), Unknown Rejection và False Auto-Assignment Rate.
- `export_metadata.py` — Xuất `assets/models/vn_financial_fasttext_v1.ftq` và `assets/models/vn_financial_fasttext_v1_meta.json` kèm mã băm toàn vẹn `SHA-256`.
- `benchmark.py` — Đo thời gian Cold-start, Warm Inference Latency `p50`/`p95`, Peak RAM và xuất báo cáo thực đo.

## Cách chạy toàn bộ Pipeline

```bash
python tools/financial_ai/generate_synthetic_data.py
python tools/financial_ai/prepare_dataset.py
python tools/financial_ai/train.py
python tools/financial_ai/quantize.py
python tools/financial_ai/evaluate.py
python tools/financial_ai/export_metadata.py
python tools/financial_ai/benchmark.py
```
