# Model Research & Selection — Offline Vietnamese Financial AI

## 1. Đánh giá Các Phương án Công nghệ (Phase 2)

| Tiêu chí | **FastText Supervised (C++17 FFI + Isolate INT8 `.ftq`) — ĐƯỢC CHỌN** | **TensorFlow Lite (`tflite_flutter ^0.12.1` / LiteRT)** | **Local LLM (`llamadart` / `llama.cpp` GGUF)** | **Deterministic Rule Engine Only** |
| :--- | :--- | :--- | :--- | :--- |
| **Giấy phép (License)** | **MIT License** (Meta AI `fastText` & mã nguồn C++/Dart nội bộ Life OS) | Apache-2.0 (`tflite_flutter` / Google LiteRT) | MIT (`llamadart` / `llama.cpp`); giấy phép model phụ thuộc GGUF | Nội bộ dự án (Proprietary/MIT) |
| **Dung lượng Model** | **`548.12 KB`** (`561,270` bytes — `INT8` quantized subword + word n-gram binary `.ftq`) | `1.5 MB – 8 MB` (Embedding + Conv1D/BiGRU `.tflite`) | `700 MB – 2.2 GB` (1B–3B Q4_K_M GGUF) | `0 MB` |
| **Dung lượng Native Binary** | **`152.21 KB – 259.77 KB`** (stripped `liblifeos_fasttext.so` mỗi ABI trên Android) | `~4.5 – 9 MB` (`libtensorflowlite_jni.so`) | `~15 – 40 MB` (`libllama.so` + Vulkan/Metal) | `0 KB` |
| **RAM sử dụng lúc chạy** | **< 4 MB** (ma trận trọng số nén `INT8` đọc một lần trong Worker Isolate) | `18 – 45 MB` (Interpreter arena + tensors) | `1.5 GB – 3.5 GB` (nguy cơ OOM cao trên máy Android tầm trung) | `< 1 MB` |
| **Độ trễ Warm Inference** | **< 2 ms** (mục tiêu `< 100 ms`, đo thực tế trong `benchmark_report.md`) | `3 – 15 ms` | `400 – 3.500 ms` / câu | `< 0.5 ms` |
| **Chạy Offline 100%** | **Có (100% Offline)** | Có (100% Offline) | Có (nhưng cần tải model hàng GB) | Có |
| **Phân loại Tiếng Việt (có dấu, không dấu, viết tắt, lỗi ASR)** | **Xuất sắc:** Kết hợp word bigrams (`an_sang`, `do_xang`) + character subwords `3..5` ký tự xử lý cực tốt từ viết tắt, mất dấu và lỗi chính tả giọng nói. | Tốt nhưng phải đóng gói bộ từ điển WordPiece/Subword đồng bộ giữa Python và Dart. | Hiểu ngữ cảnh rộng nhưng quá nặng, dễ sinh ảo giác số tiền nếu không khoanh vùng chặt. | Chính xác cao trên mẫu cố định nhưng kém khái quát với cách diễn đạt mới. |
| **Độ phức tạp tích hợp Flutter** | Rất gọn: CMake có sẵn trong Android NDK (`dart:ffi`), kèm bộ đọc nhị phân tương đồng bit-for-bit trên Dart Isolate cho môi trường test/desktop/web. | Phụ thuộc plugin native bên thứ 3 (`minSdk >= 26`, cấu hình CocoaPods/SPM riêng). | Rất phức tạp để đóng gói & quản lý tải model lớn, không phù hợp MVP mặc định. | Đơn giản nhất (làm tầng tiền kiểm & fallback). |

---

## 2. Quyết định Kiến trúc Model (Hybrid 4-Layer Architecture)

Theo đúng định hướng **Rule Engine + Personalization + FastText Supervised Classifier** (không nhúng LLM nặng vào pipeline mặc định):

1. **Tầng 1 — Deterministic Guard & Structural Extractor:**
   - Lọc OTP/bảo mật (`OtpRedactor`), nhận diện câu phủ định (*"không mua gì"*), câu hủy (*"hủy giao dịch"*), câu thông báo số dư (*"còn 2 triệu trong tài khoản"*).
   - Chuẩn hóa văn bản (`FinancialTextNormalizer`), tách đa giao dịch trong một câu, bóc tách số tiền nguyên đồng (`int`), ngày tương đối (`FinancialClock`) và loại nghiệp vụ (`FinancialTransactionType`).
2. **Tầng 2 — User Personalization Engine:**
   - Tra cứu bộ nhớ quy tắc cá nhân của đúng `userId` theo khóa chuẩn hóa cửa hàng (`merchantCanonicalKey`) + ngữ cảnh hướng giao dịch (`debit`/`credit`) + kiểm tra tính hợp lệ của `categoryId` hiện tại.
3. **Tầng 3 — Offline Vietnamese FastText Supervised Classifier (`FastTextClassifier`):**
   - Huấn luyện riêng trên tập dữ liệu tài chính tiếng Việt (có dấu + không dấu + ASR + mô tả ngân hàng ẩn danh) theo định dạng chuẩn `__label__<semantic_key> <normalized_tokens>`.
   - Sử dụng đặc trưng **Unigrams + Word Bigrams (`wordNgrams = 2`) + Character Subword N-grams (`minn = 3, maxn = 5`)** băm bằng hàm **32-bit UTF-8 FNV-1a** bất biến trên mọi nền tảng (Python, C++17 Android NDK FFI, và Dart Isolate).
   - Hậu kiểm hiệu chỉnh xác suất bằng **Temperature Scaling ($T^*$)** tối ưu trên tập Validation để xác suất đầu ra phản ánh trung thực độ tin cậy thực tế (Expected Calibration Error thấp).
   - Lượng tử hóa đối xứng theo hàng (**Per-Row Symmetric INT8 Quantization**) đóng gói vào tệp nhị phân gọn nhẹ `assets/models/vn_financial_fasttext_v1.ftq` kèm chữ ký `SHA-256` trong `assets/models/vn_financial_fasttext_v1_meta.json`.
4. **Tầng 4 — Rule-Based Fallback & Multi-Dimensional Confidence Policy:**
   - Nếu tệp model bị thiếu/hỏng chữ ký hoặc môi trường không cho phép khởi tạo model, hệ thống tự động chuyển sang `RuleBasedClassifier` mà không làm gián đoạn người dùng hay đóng băng UI.
   - `ConfidencePolicyEngine` kết hợp `amountConfidence`, `typeConfidence`, `categoryConfidence`, `merchantConfidence`, `sourceConfidence` theo nguyên tắc **bottleneck an toàn** (`min` có trọng số kiểm soát + cờ mơ hồ) để quyết định `highConfidence` / `mediumConfidence` / `lowConfidence` / `unknown`.

---

## 3. Khung Bảng Benchmark (Số liệu thực tế cập nhật sau khi chạy `benchmark.py` & `flutter test`)

> Số liệu chi tiết sau khi huấn luyện và đo đạc thực tế trên máy được xuất tự động sang `docs/financial_ai/benchmark_report.md`. Các nền tảng không hiện diện trên máy Windows hiện tại (như thiết bị iOS vật lý) được ghi nhận trung thực là `Not measured`.
