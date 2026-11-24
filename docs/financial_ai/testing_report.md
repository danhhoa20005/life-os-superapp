# Báo cáo Kiểm thử Toàn diện — Offline Financial AI (`testing_report.md`)

## 1. Tổng quan Kết quả Thực thi Kiểm thử

Toàn bộ lệnh kiểm định đã được chạy trực tiếp trên mã nguồn hiện tại và vượt qua **100% không bỏ sót bất kỳ test nào**:

| Hạng mục kiểm định | Lệnh thực thi | Kết quả | Thời gian |
| :--- | :--- | :---: | :---: |
| **Phân tích tĩnh toàn dự án** | `flutter analyze` | **`0 issues found!`** (`0` error, `0` warning, `0` info) | `16.2s` |
| **Toàn bộ Unit, BLoC, Widget & Integration Tests** | `flutter test` | **`98 / 98 PASS` (`100%`)** | `28.0s` |
| **Đánh giá mô hình độc lập (Python Held-out Test)** | `python tools/financial_ai/evaluate.py` | **Accuracy `90.75%` · Macro F1 `0.9164` · OOD Reject `100%`** | `< 2.0s` |
| **Biên dịch Android APK + Native C++17 NDK FFI** | `flutter build apk --debug` | **`app-debug.apk` + `liblifeos_fasttext.so` (`arm64-v8a`, `armeabi-v7a`, `x86_64`)** | `251.1s` |

---

## 2. Chi tiết Các Nhóm Kiểm thử Đã Triển khai (Phase 18)

### 2.1. Unit Tests & 22 Câu Tiếng Việt Bắt buộc ([`test/unit/financial_ai_engine_test.dart`](file:///g:/superapp/test/unit/financial_ai_engine_test.dart))

1. **`FinancialTextNormalizer`:**
   - Tiếng Việt có dấu (`"Ăn sáng hết 35 nghìn"`), không dấu (`"an sang het 35 nghin"`), viết tắt (`cf`, `ck`, `xang`, `tgdd`).
   - Toàn bộ `16` định dạng số tiền bằng số nguyên minor units (`50k`, `50K`, `50 nghìn`, `50 ngàn`, `50.000`, `50,000đ`, `1tr`, `1 triệu`, `1tr5`, `1.5 triệu`, `1,5 triệu`, `2 triệu 300 nghìn`, `125000 VND`, `"mười hai triệu"`, `\$12.50` -> `1250` minor units USD).
   - Phát hiện dấu phân cách mơ hồ `"mua bánh 1.500"` (`isAmbiguous == true`).
   - Giải mã ngày tương đối (`hôm nay`, `hôm qua`, `hôm kia`, `sáng nay`, `tối qua`, `ngày 15`, `thứ hai tuần trước`, `tháng trước`) qua `FixedFinancialClock`.
2. **Đầy đủ 22 mẫu câu tiếng Việt bắt buộc (Phase 18.2) + Chuyển tiền ngoài + Chặn OTP:**
   - `an sang 35k`, `ăn sáng 35 nghìn`, `cafe 25k`, `cf 30k`, `do xang 70k`, `đổ xăng 70 nghìn`, `mua thuốc 120k`, `nhận lương 12tr`, `thưởng 500k`, `mua sắm 1tr5`, `đi taxi 85k`, `hôm qua mua đồ 300k`, `chi 50k ăn trưa`, `nhận 200k từ bạn`.
   - Nghiệp vụ kế toán đặc thù: `"chuyển 2tr từ MB sang VCB của tôi"` -> `internalTransfer` (`w_mb -> w_vcb`), `"rút ATM 500k"` -> `internalTransfer` (`BANK -> w_cash`), `"shop hoàn tiền 120k"` -> `refund`, `"Chuyển 500k cho mẹ"` -> `externalTransfer`.
   - Tách câu đa khoản thu chi: `"mua sách 150k và uống nước 25k"` -> `2` bản nháp độc lập; `"chiều nay ăn 45k đổ xăng 70k"` -> `2` bản nháp độc lập.
   - **Chốt chặn câu phi giao dịch (`0` bản nháp sinh ra):** `"còn 2 triệu trong tài khoản"`, `"tôi không mua gì hôm nay"`, `"hủy giao dịch 100k vừa nhập"`, `"Mã OTP xác thực giao dịch 500k của bạn là 482910"`.
3. **Khả năng chịu lỗi Runtime (Fault Tolerance — Phase 9.6):**
   - Mô phỏng thiếu tệp model (`StateError`) và tệp model hỏng byte (`[0x01..0x05]`) -> tự động chuyển sang `RuleBasedClassifier` (`usingRuleFallback == true`), không văng ngoại lệ.
   - Kiểm tra không bao giờ tự bịa `categoryId` khi danh mục dự đoán chưa tồn tại trong danh sách của người dùng (`resolved.categoryId == null`).

### 2.2. End-to-End Integration & Responsive UI Tests ([`test/integration/financial_ai_integration_test.dart`](file:///g:/superapp/test/integration/financial_ai_integration_test.dart))

1. **Học cá nhân hóa & Cô lập gia đình (Phase 10 & 17):**
   - Alice sửa `"Circle K"` sang `"Ăn uống"` -> lần tiếp theo `"Circle K 32k"` tự nhận `"Ăn uống"` qua `personalizationRule`.
   - Thành viên gia đình Bob (`shared_family_01`) nhập `"Circle K 32k"` **không** bị áp quy tắc riêng của Alice.
   - Khi Alice xóa danh mục `"cat_alice_food"`, quy tắc cũ tự động được bỏ qua an toàn, không gán khóa ngoại đã xóa.
2. **Toàn vẹn kế toán chuyển nội bộ & chống ghi đúp (`operationId` Idempotency):**
   - Xác nhận `"Chuyển 2 triệu từ MB sang Vietcombank của tôi"` cập nhật đúng `MBBank: 10tr -> 8tr` và `Vietcombank: 5tr -> 7tr` (tổng tài sản `15tr` giữ nguyên, không thổi phồng thu/chi), gọi lặp cùng `operationId` chỉ tạo duy nhất `1` giao dịch.
3. **Tích hợp Thông báo Ngân hàng Android & Chống trùng lặp (Phase 12 & 15):**
   - Chặn tuyệt đối thông báo `VCB SmartOTP`.
   - Phân tích thông báo biến động `VCB Digibank -55,000VND ... ND: THANH TOAN HIGHLANDS COFFEE`, áp dụng quy tắc cá nhân hóa `"Ăn uống"` và chặn thông báo lặp đến sau `10` giây (`IngestionOutcomeKind.duplicateIgnored`).
4. **Kiểm thử Giao diện ở màn hình hẹp `360×800` + cỡ chữ lớn `112%`:**
   - Cả [`FinancialAiAssistantPage`](file:///g:/superapp/lib/features/financial_ai/presentation/pages/financial_ai_assistant_page.dart) và [`FinancialAiSettingsPage`](file:///g:/superapp/lib/features/financial_ai/presentation/pages/financial_ai_settings_page.dart) vượt qua bộ quét `_assertZeroVisualOverflow` (`0` `RenderParagraph.didExceedMaxLines`), điều hướng mượt từ tab Tài chính (`/financial-ai`).

---

## 3. Các Lỗi Thực tế Đã Phát hiện và Sửa Triệt để Nhờ Kiểm thử

1. **Lỗi khớp chuỗi con `'MB'` bên trong `'VIETCOMBANK'` (`_resolveWalletHint`):** Khi tìm ví cho mã `'MB'`, kiểm tra `name.contains('MB')` ban đầu khớp nhầm cả `'VIETCOMBANK'` (`VIETCO[MB]ANK`). Đã sửa bằng cách ưu tiên khớp chính xác `bankCode == 'MB'` trước rồi mới kiểm tra biên từ trên tên ví.
2. **Lỗi bóc tách `ND:` bị ăn vào chữ `VND ` trong `BankNotificationParser`:** Chuỗi `-55,000VND luc ... ND: THANH TOAN ...` ban đầu thiếu biên từ `\b` trước `ND`, làm khớp nhầm `ND ` cuối chữ `VND`. Đã thêm `\b` tại [`bank_notification_parser.dart`](file:///g:/superapp/lib/core/security/bank_notification_parser.dart#L526).
3. **Lỗi biên từ regex `nhan\s+\d\b` với hậu tố đơn vị tiền (`200k`):** Đã mở rộng thành `nhan\s+\d[a-z0-9.,]*` để nhận diện chính xác `"nhận 200k từ bạn"`, `"nhận 1tr5"`.
4. **Lỗi định kiểu động `StreamTransformer.fromHandlers`:** Đã khai báo tường minh kiểu tĩnh `StreamTransformer<Result<T>, Result<T>>.fromHandlers` trong `FinancialAiRepositoryImpl`.
