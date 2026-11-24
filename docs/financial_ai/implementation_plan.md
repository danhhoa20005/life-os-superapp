# Implementation Plan — Life OS Offline Financial AI Engine

## Lộ trình Thực thi Khép kín (Phase 1 → Phase 21)

1. **Audit & Thiết kế Kiến trúc (`Phase 1–3, 7`):**
   - Hoàn thiện `architecture_audit.md`, `model_selection.md`, `taxonomy.md`, `implementation_plan.md`.
2. **Xây dựng Pipeline Dữ liệu & Huấn luyện FastText Tiếng Việt (`Phase 8` — `tools/financial_ai/`):**
   - Viết bộ công cụ Python độc lập: `generate_synthetic_data.py` (sinh kho ngữ liệu đa dạng có dấu/không dấu/viết tắt/ASR/ngân hàng ẩn danh với **chia tách theo họ template chống rò rỉ dữ liệu**), `prepare_dataset.py`, `train.py` (huấn luyện FastText subword + word bigram + hiệu chỉnh nhiệt độ $T^*$), `quantize.py` (nén `INT8` `.ftq`), `evaluate.py`, `benchmark.py`, `export_metadata.py`.
   - Sinh artifact thật tại `assets/models/vn_financial_fasttext_v1.ftq` và `assets/models/vn_financial_fasttext_v1_meta.json`, đăng ký trong `pubspec.yaml`.
3. **Native C++17 FFI + Isolate Runtime (`Phase 9, 19`):**
   - Triển khai `android/app/src/main/cpp/lifeos_fasttext_ffi.cpp` + `CMakeLists.txt` tích hợp Android NDK (`dart:ffi`) với C ABI ổn định, kiểm tra magic header & checksum, quản lý bộ nhớ chặt chẽ.
   - Triển khai `FastTextClassifier` chạy trên Worker `Isolate` (không bao giờ chặn UI isolate), kèm `RuleBasedClassifier` fallback và `FakeFinancialClassifier` phục vụ kiểm thử.
4. **Domain Layer Thuần Dart (`Phase 4–7, 10–11, 14, 17` — `lib/features/financial_ai/domain/`):**
   - Xây dựng các immutable entities (`FinancialAnalysisRequest`, `FinancialAnalysisResult`, `TransactionCandidate`, `ExtractedFinancialEntity`, `CategoryPrediction`, `ClassificationConfidence`, `PersonalizationRule`, `FinancialModelMetadata`, `FinancialClock`) và đầy đủ 8 UseCases chuẩn mực.
5. **Data Layer: Normalizer, Extractor, Segmenter, Type Detector, Personalization & Sync (`Phase 4–6, 10, 15`):**
   - Xử lý trọn vẹn tiếng Việt có dấu/không dấu, viết tắt, số tiền phức hợp & mơ hồ, ngày tương đối qua `FinancialClock`, tách đa giao dịch trong 1 câu, phân biệt 10 loại giao dịch + chặn câu số dư/phủ định/hủy lệnh.
   - Lưu trữ quy tắc cá nhân hóa, lịch sử sửa nhãn, nháp chờ duyệt và cài đặt AI dưới `/users/{userId}/**` trong Firestore (hỗ trợ offline cache, cập nhật `firestore.rules` và `deleteAccountAndPersonalData`).
6. **Tích hợp Bank Notification, Voice Commands, BLoC & UI (`Phase 12–14, 16`):**
   - Triển khai `FinancialAiBloc` (`Event` + `State` với `bloc_concurrency`, chống race condition & double-submit).
   - Kết nối vào luồng `NotificationsRemoteDataSource` (thông báo ngân hàng Android), `VoiceSmartCaptureSheet` / `QuickCreateHubSheet`, trang **Trợ lý AI Phân tích Thu Chi (`FinancialAiInputPage` + Multi-Draft Preview)** và **Cài đặt Học Cá nhân hóa AI (`FinancialAiSettingsPage`)**.
7. **Kiểm thử Toàn diện, Benchmark Thực tế & Bàn giao (`Phase 18–21`):**
   - Viết bộ Unit Test + Bộ 22+ câu chuẩn tiếng Việt (bao gồm negative/ambiguous) + Integration/Widget Tests.
   - Chạy `flutter analyze`, `flutter test`, kiểm tra build Android APK với NDK CMake, xuất báo cáo thực đo vào `docs/financial_ai/`.
