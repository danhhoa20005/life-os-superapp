# Life OS — Vietnamese Financial AI Training & Quantization Toolkit (`v2.0.0`)

Bộ công cụ huấn luyện mô hình phân loại tài chính tiếng Việt chạy hoàn toàn Offline trên thiết bị cho **Life OS Super App** (`vn_financial_fasttext_v1` — `modelVersion: "2.0.0"`), đồng bộ bit-for-bit giữa Python 3.14, Dart Background Worker `Isolate` và Android C++17 NDK `dart:ffi` (`liblifeos_fasttext.so`).

## Kiến trúc & Điểm nhấn Kỹ thuật (`v2.0.0`)

- **30 nhãn ngữ nghĩa tài chính (`23` Chi tiêu + `7` Thu nhập)** chuẩn hóa theo hệ thống danh mục thực tế của người Việt.
- **Đồng nhất chuẩn hóa & băm đặc trưng 100% (`Train-Serve Parity`):**
  - Mở rộng 56 từ viết tắt ngân hàng, ví điện tử, chuỗi bán lẻ, thương mại điện tử và tiếng lóng tiền tệ (`cành`, `xị`, `củ rưỡi`, `trăm rưỡi`, `chục`).
  - Loại bỏ cụm từ đệm thời gian/ngân hàng đa âm tiết (`sáng nay`, `vừa thanh toán`, `cho khoản`, `hết/mất/tốn <số tiền>`) mà **không xóa nhầm âm tiết mang nghĩa theo dấu thanh** (`quà`, `thẻ`, `mắt`, `sổ`, `ăn sáng`, `ăn trưa`).
  - Kết hợp Word Unigram có dấu (`2x`) + bỏ dấu ASCII (`1x`), Word Bigram có dấu (`2x`) + bỏ dấu (`1x`), và Character Subwords `4..5` ký tự trên từ `>= 4` ký tự qua hàm băm `FNV-1a 32-bit` (`28.672` buckets).
- **Chống rò rỉ dữ liệu nghiêm ngặt (`0%` Leakage):** `train` (`3.910` mẫu), `val` (`657` mẫu) và `test` (`1.297` mẫu) sử dụng tập mẫu câu gốc và họ khung câu (`Wrappers`) hoàn toàn tách rời.
- **Huấn luyện QAT + Outlier Exposure + Post-Quantization Calibration:**
  - Giai đoạn 1: Coordinate-Wise AdaGrad lồi toàn cục với Cosine LR Decay.
  - Giai đoạn 2: **Outlier Exposure** đưa câu giao tiếp/lịch hẹn ngoài miền tài chính về phân phối đều `1/30` kết hợp **Straight-Through INT8 Quantization-Aware Fine-Tuning (`[-127, 127]`)**.
  - Giai đoạn 3: Hiệu chuẩn nhiệt độ $T^* = 0.56$ trực tiếp trên logits `INT8` sau lượng tử hóa.

## Chỉ số Thực đo (`v2.0.0` vs `v1.0.0`)

| Chỉ số kiểm định độc lập (`Held-Out Test`) | `v1.0.0` | `v2.0.0` |
|---|---|---|
| Số mẫu `test` độc lập (`0%` rò rỉ) | `436` | **`1.297`** |
| **Test Accuracy** | `90,75%` | **`99,31%`** |
| **Test Macro F1 (30 nhãn)** | `91,64%` | **`99,43%`** |
| **Expected Calibration Error (ECE)** | `0,0481` | **`0,0246`** |
| **False Auto-Assignment Rate (`>= 0.78`)** | `2,06%` | **`0,00%`** |
| Số nhóm đạt `F1 = 100%` trên `test` | `11 / 30` | **`24 / 30`** |
| Kích thước nhị phân `.ftq` (`LFTQ v1 INT8`) | `550,2 KB` | **`956,1 KB`** (`< 1 MB`) |
| Độ trễ suy luận ấm (`Warm p50 / p95`) | `0,42 ms / 0,95 ms` | **`0,40 ms / 0,76 ms`** |

## Cách chạy toàn bộ Pipeline

```powershell
python -u tools/financial_ai/generate_synthetic_data.py
python -u tools/financial_ai/prepare_dataset.py
python -u tools/financial_ai/train.py
python -u tools/financial_ai/quantize.py
python -u tools/financial_ai/evaluate.py
python -u tools/financial_ai/export_metadata.py
python -u tools/financial_ai/benchmark.py
```
