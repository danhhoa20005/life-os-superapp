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
4. **Chia hóa đơn nhiều người & Phân giải thành viên (`FIX-004`, `FIX-005`):**
   - `SmartMoneySplitAiEngine` và `VoiceFinancialNlpEngine` thực hiện bóc tách và kiểm tra hợp lệ toàn bộ các chế độ chia tiền (`equal`, `percentage`, `shares`, `itemizedRemainder`, `exactAmounts`), áp dụng phép chia số nguyên `BigInt` (`apportionExactVnd`) đảm bảo tổng phần chia luôn khớp tuyệt đối `100%` tới từng đồng VND và **không bao giờ tự rơi ngầm về `SplitMethod.equal`** khi dữ liệu mâu thuẫn (`SplitValidationStatus != valid`).
   - Giới hạn cố ý: khi có từ 2 thành viên trùng tên ngắn (ví dụ `"Lê Hà"` và `"Phạm Hà"` cùng gọi `"Hà"`), `ParticipantResolutionEngine` sẽ **từ chối đoán tự động**, gắn `ambiguousParticipant` và yêu cầu người dùng chọn rõ qua `ChoiceChip` trên `VoiceSmartCaptureSheet`.
   - Khi giọng nói đọc khoản riêng lẻ có phần trùng lặp/lệch tổng ở biên lai đa danh mục (`sumLines > headTotal`), hệ thống yêu cầu người dùng tick xác nhận rõ trước khi khóa nút lưu.
5. **Chặn mệnh đề phủ định / giả định & Ranh giới Hybrid Cloud (`Section 13`, `Section 16`):**
   - `ClauseSafetyScreener` chủ động chặn các mệnh đề giả định/hủy (`"định mua..."`, `"dự định..."`, `"có nên... không"`, `"đừng ghi..."`, `"không lưu..."`); trong trường hợp câu quá phức tạp hoặc mang tính tư vấn mở, `SmartHybridGate` chỉ chuyển tiếp qua `GeminiPrivacySanitizer` + `OtpRedactor.redact` khi người dùng đã chủ động bật Gemini + có khóa API hợp lệ.
6. **Phân tích biến động số dư Ngân hàng Android (`Section 27`):**
   - `BankNotificationListenerService` chủ động bỏ qua thông báo tóm tắt nhóm (`FLAG_GROUP_SUMMARY`) và chỉ chặn mã OTP/PIN thực sự (`m[aã]\s*pin|pin\s*code`), tránh chặn nhầm tên ngân hàng hoặc mã tham chiếu hợp lệ; `BankNotificationParser` loại bỏ tin quảng cáo/mời bạn (`referral`, `voucher`, `hoàn tiền đến...`). Tuy nhiên các định dạng SMS/thông báo ngân hàng mới phát hành sau bản cập nhật vẫn có thể cần bổ sung regex nếu cấu trúc thay đổi hoàn toàn.

---

## 3. Giới hạn Môi trường Đo kiểm Hiện tại

- Máy trạm phát triển và kiểm thử hiện tại chạy **Windows x64** (có đầy đủ Flutter SDK, Python 3.14, Android SDK, Android NDK & CMake để biên dịch thật `liblifeos_fasttext.so` cho các kiến trúc ARM64/ARMv7/x86_64).
- Máy trạm hiện **không có macOS / Xcode** và **không gắn thiết bị vật lý iPhone/Android qua USB**, do đó:
  - Chưa đo trực tiếp độ trễ FFI C++ trên chip ARM vật lý và chưa chạy `flutter build ios` (được ghi nhận trung thực là `"Not measured"` trong `benchmark_report.md`).
  - Đối với iOS khi build trên macOS sau này, chỉ cần liên kết cùng tệp nguồn [`android/app/src/main/cpp/lifeos_fasttext_ffi.cpp`](file:///g:/superapp/android/app/src/main/cpp/lifeos_fasttext_ffi.cpp) vào Podspec/Xcode target (hoặc chạy trực tiếp nhân `FastTextBinaryModel` trong Worker `Isolate` vốn đã hoạt động 100% đa nền tảng mà không cần cấu hình thêm).
