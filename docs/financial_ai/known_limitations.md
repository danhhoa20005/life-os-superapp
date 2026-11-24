# Giới hạn Kỹ thuật Đã biết & Hướng Phát triển Tiếp theo (`known_limitations.md`)

Tài liệu này ghi nhận trung thực các giới hạn kỹ thuật hiện tại của hệ thống Offline Financial AI trong Life OS Super App và lộ trình nâng cấp khả thi.

---

## 1. Giới hạn Theo Hệ điều hành (OS Platform Restrictions)

1. **iOS không cho phép đọc thông báo đẩy của ứng dụng Ngân hàng bên thứ ba:**
   - Trên Android, `BankNotificationListenerService` hoạt động hợp lệ thông qua quyền `BIND_NOTIFICATION_LISTENER_SERVICE` do người dùng cấp.
   - Trên iOS, cơ chế sandbox của Apple không cho phép ứng dụng bên thứ ba đọc thông báo của Vietcombank, Techcombank, MBBank... Vì vậy trên iOS, luồng AI phân loại hoạt động qua:
     - Nhập câu tự nhiên / dán nội dung tin nhắn từ Clipboard (hoặc iOS Shortcuts chuyển văn bản vào ứng dụng).
     - Nhập bằng giọng nói tiếng Việt.
2. **Nhận diện giọng nói phụ thuộc gói ngôn ngữ Offline của hệ điều hành:**
   - Bộ phân loại tài chính AI (`FastTextClassifier` + `FinancialEntityExtractor`) chạy **100% offline** bên trong ứng dụng.
   - Tuy nhiên, khâu chuyển âm thanh micro thành văn bản (`NativeVoiceAssistantBridge` gọi `SpeechRecognizer` của Android / `SFSpeechRecognizer` của iOS) chỉ hoạt động hoàn toàn không cần mạng khi người dùng đã tải gói ngôn ngữ **Tiếng Việt (`vi-VN`) offline** trong phần Cài đặt giọng nói của điện thoại.

---

## 2. Giới hạn Ngôn ngữ học & Mô hình Phân loại

1. **Tên người nhận cá nhân hoặc mã chuyển khoản nội bộ không mang ngữ nghĩa danh mục:**
   - Ví dụ thông báo ngân hàng chỉ ghi `"ND: NGUYEN VAN A CHUYEN TIEN"` hoặc `"MBVCB.72819281.CT TU 0123456789"`.
   - Khi không có từ khóa hàng hóa/dịch vụ, model FastText sẽ trả xác suất thấp và `ConfidencePolicyEngine` tự động gắn cờ `lowCategoryConfidence` + `requiresConfirmation = true` thay vì đoán bừa. Khi người dùng chọn danh mục cho đối tác/merchant quen thuộc 1 lần, `PersonalizationEngine` sẽ ghi nhớ cho những lần sau.
2. **Nhầm lẫn nhẹ giữa `family` và `gifts` / `food.meals` khi câu thiếu chủ thể rõ ràng:**
   - Trên tập kiểm thử độc lập (`eval_report.json`), hai lớp có độ chồng lấn ngữ nghĩa tự nhiên cao nhất là `family` (chi cho gia đình/con cái) và `income.gift` (nhận tiền mừng/biếu tặng). Hệ thống giảm thiểu rủi ro bằng cách lọc chặt theo chiều giao dịch (`debit` vs `credit`) và hiển thị Top-3 danh mục gợi ý trên thẻ duyệt nháp để người dùng đổi bằng 1 chạm.
3. **Số tiền mập mờ không kèm đơn vị (`"mua bánh 1.500"`):**
   - Theo đúng thiết kế an toàn tài chính Phase 4.4, các con số dạng `d.ddd` dưới `10.000` không kèm chữ `đ`/`VND`/`k` được đánh dấu `AmbiguityFlag.ambiguousAmountSeparator` và **luôn bắt buộc người dùng xác nhận** thay vì tự suy diễn giữa `1.500 ₫` và `1.500.000 ₫`.
4. **Chia hóa đơn nhiều người nâng cao:**
   - Pipeline `FinancialAiRepository` tập trung vào tách câu đa giao dịch độc lập (`"đổ xăng 70k và mua nước 15k"`), chuyển khoản nội bộ/ngoài, hoàn tiền và phân loại danh mục cá nhân hóa. Các câu chia tiền nhóm phức tạp theo tỷ lệ từng thành viên gia đình (`"Ăn lẩu 450k chia đều 3 người"`) vẫn được phục vụ song song bởi `VoiceSmartCaptureSheet` hiện hữu của ứng dụng.

---

## 3. Giới hạn Môi trường Đo kiểm Hiện tại

- Máy trạm phát triển và kiểm thử hiện tại chạy **Windows x64** (có đầy đủ Flutter SDK, Python 3.14, Android SDK, Android NDK & CMake để biên dịch thật `liblifeos_fasttext.so` cho các kiến trúc ARM64/ARMv7/x86_64).
- Máy trạm hiện **không có macOS / Xcode** và **không gắn thiết bị vật lý iPhone/Android qua USB**, do đó:
  - Chưa đo trực tiếp độ trễ FFI C++ trên chip ARM vật lý và chưa chạy `flutter build ios` (được ghi nhận trung thực là `"Not measured"` trong `benchmark_report.md`).
  - Đối với iOS khi build trên macOS sau này, chỉ cần liên kết cùng tệp nguồn [`android/app/src/main/cpp/lifeos_fasttext_ffi.cpp`](file:///g:/superapp/android/app/src/main/cpp/lifeos_fasttext_ffi.cpp) vào Podspec/Xcode target (hoặc chạy trực tiếp nhân `FastTextBinaryModel` trong Worker `Isolate` vốn đã hoạt động 100% đa nền tảng mà không cần cấu hình thêm).
