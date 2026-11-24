# Báo cáo Benchmark Hiệu năng & Độ chính xác Thực tế (`benchmark_report.md`)

> **Nguyên tắc trung thực số liệu (Phase 2.3 & Phase 19):** Mọi con số dưới đây được đo thực tế bằng script tự động [`tools/financial_ai/benchmark.py`](file:///g:/superapp/tools/financial_ai/benchmark.py), [`tools/financial_ai/evaluate.py`](file:///g:/superapp/tools/financial_ai/evaluate.py), [`test/unit/financial_ai_engine_test.dart`](file:///g:/superapp/test/unit/financial_ai_engine_test.dart) và bản build Android NDK `flutter build apk --debug`. Các chỉ số đòi hỏi máy macOS/Xcode hoặc thiết bị vật lý cắm cáp chưa có trên máy trạm Windows hiện tại được ghi rõ là **`Not measured`**.

---

## 1. Bảng Benchmark Chuẩn Mô hình `vn_financial_fasttext_v1` (Phase 2.3)

| Chỉ số | Kết quả đo thực tế | Nguồn đo kiểm |
| :--- | :--- | :--- |
| **Model name** | `vn_financial_fasttext_v1` (`v1.0.0`, `LFTQ` v1 `INT8`) | [`vn_financial_fasttext_v1_meta.json`](file:///g:/superapp/assets/models/vn_financial_fasttext_v1_meta.json) |
| **Model size** | **`561,270 bytes` (`548.12 KB` / `0.535 MB`)** | `assets/models/vn_financial_fasttext_v1.ftq` |
| **Native library size (`arm64-v8a`, stripped)** | **`266,000 bytes` (`259.77 KB`)** | `build/.../stripped_native_libs/.../arm64-v8a/liblifeos_fasttext.so` |
| **Native library size (`armeabi-v7a`, stripped)** | **`155,864 bytes` (`152.21 KB`)** | `build/.../stripped_native_libs/.../armeabi-v7a/liblifeos_fasttext.so` |
| **Native library size (`x86_64`, stripped)** | **`263,184 bytes` (`257.02 KB`)** | `build/.../stripped_native_libs/.../x86_64/liblifeos_fasttext.so` |
| **Cold-start time (Dart Worker Isolate)** | **`15.932 ms`** (khởi tạo Isolate + kiểm tra SHA-256 + nạp INT8) | [`dart_runtime_benchmark.json`](file:///g:/superapp/tools/financial_ai/artifacts/dart_runtime_benchmark.json) |
| **Cold-start time (Python Reference Runtime)** | **`173.544 ms`** | [`python_benchmark.json`](file:///g:/superapp/tools/financial_ai/artifacts/python_benchmark.json) |
| **Warm inference latency `p50` / `p95` (Dart Worker Isolate IPC)** | **`0.4220 ms` / `1.2770 ms`** (`100` lượt bao gồm gửi/nhận Isolate) | [`dart_runtime_benchmark.json`](file:///g:/superapp/tools/financial_ai/artifacts/dart_runtime_benchmark.json) |
| **Warm inference latency `p50` / `p95` (Python Host)** | **`0.4712 ms` / `1.0961 ms`** (`1,000` lượt) | [`python_benchmark.json`](file:///g:/superapp/tools/financial_ai/artifacts/python_benchmark.json) |
| **Warm inference latency trên thiết bị ARM vật lý** | `Not measured` (máy trạm Windows chưa kết nối điện thoại vật lý) | — |
| **Peak RAM (Python Heap khi nạp & suy luận)** | **`8,081.84 KB` (`~7.89 MB`)** | [`python_benchmark.json`](file:///g:/superapp/tools/financial_ai/artifacts/python_benchmark.json) |
| **Peak RAM riêng trên thiết bị Android/iOS vật lý** | `Not measured` (ước tính cấu trúc mảng tĩnh INT8 + scales `< 2 MB`) | — |
| **Classification Accuracy (Held-out Test `681` mẫu)** | **`90.75%`** (`0.9075`) | [`eval_report.json`](file:///g:/superapp/tools/financial_ai/artifacts/eval_report.json) |
| **Macro F1 (Held-out Test `30` danh mục)** | **`0.9164`** | [`eval_report.json`](file:///g:/superapp/tools/financial_ai/artifacts/eval_report.json) |
| **Expected Calibration Error (ECE, $T^* = 0.75$)** | **`0.0481`** | [`eval_report.json`](file:///g:/superapp/tools/financial_ai/artifacts/eval_report.json) |
| **False Auto-Assignment Rate (`threshold >= 0.78`)** | **`2.06%`** (`0.0206`) | [`eval_report.json`](file:///g:/superapp/tools/financial_ai/artifacts/eval_report.json) |
| **Android compatibility** | **Verified (`flutter build apk --debug` PASS, NDK CMake 16KB page-aligned)** | Gradle `assembleDebug` (`app-debug.apk`) |
| **iOS compatibility** | `Not measured` (cần macOS + Xcode để biên dịch target iOS; Worker Isolate Dart tương thích đa nền tảng) | — |
| **Offline capability** | **100% Offline** (`0` HTTP call, chạy hoàn toàn khi bật Airplane Mode) | Kiến trúc nội bộ + Unit/Integration Test |

---

## 2. So sánh Thực nghiệm Các Tầng Phân loại (Ablation Comparison)

Đo trực tiếp trên bộ câu khẩu ngữ & tên thương hiệu thực tế tiếng Việt (`20` mẫu đa danh mục trong `test/unit/financial_ai_engine_test.dart`):

| Cấu hình Pipeline | Độ chính xác trên tập câu khẩu ngữ/merchant | Khả năng học thói quen cửa hàng riêng (VD: `Circle K -> Ăn uống`) | Ghi chú kỹ thuật |
| :--- | :---: | :---: | :--- |
| **1. Rule-only (`RuleBasedClassifier`)** | `75.00%` (`15/20`) | Không | Nhanh, ổn định làm tầng dự phòng khi thiếu tệp model, nhưng bỏ sót các cách diễn đạt tự nhiên chưa khai báo từ khóa cứng. |
| **2. Rule + Offline FastText (`FastTextClassifier`)** | **`95.00%`** (`19/20`) | Chưa cá nhân hóa | Tăng **+20 điểm phần trăm** nhờ biểu diễn word bigrams + subword n-grams (`3..5` ký tự) tiếng Việt có dấu & không dấu. |
| **3. Rule + Personalization + Offline FastText (Full Hybrid)** | **`95.00%+`** (đạt **`100%`** với các merchant người dùng đã xác nhận 1 lần) | **Có (cô lập theo từng `userId`)** | Xử lý triệt để các cửa hàng đa ngành (`Circle K`, `GS25`, `Shopee`) theo đúng thói quen chi tiêu riêng của từng cá nhân. |

---

## 3. Đánh giá So với Tiêu chí Hiệu năng Thiết kế (Phase 19)

1. **Khởi tạo lười duy nhất 1 lần (Lazy Single-Load):** `FastTextClassifier` chỉ nạp tệp `.ftq` khi người dùng mở tính năng AI hoặc nhận thông báo ngân hàng đầu tiên (`coldStartMs = 15.932 ms`).
2. **Không bao giờ chặn luồng giao diện (Zero UI Jank):** Toàn bộ giải mã nhị phân, kiểm tra SHA-256 và nhân ma trận thực thi bên trong `Isolate` riêng (`LifeOS_FastText_AI_Worker`). Độ trễ khứ hồi ấm `p95 = 1.277 ms` nhỏ hơn **78 lần** so với trần thiết kế `100 ms` cho tác vụ nền!
3. **Bộ nhớ đệm chuẩn hóa có giới hạn (`_maxCacheEntries = 256`):** Tránh cấp phát chuỗi lặp lại khi người dùng gõ hoặc nhận thông báo liên tiếp mà không gây rò rỉ bộ nhớ.
