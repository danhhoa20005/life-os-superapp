# Architecture Audit — Life OS Offline Financial AI Classification Engine

## 1. Thông tin Môi trường & Nền tảng Hiện tại

- **Ứng dụng:** Life OS Super App (`name: life_os`, phiên bản hiện tại trong workspace: `3.15.0+30`).
- **Flutter / Dart SDK:** `Flutter 3.47.0` (stable) · `Dart 3.13.0` (`sdk: ^3.10.0` trong `pubspec.yaml`).
- **Hệ điều hành build hiện tại:** Windows (`windows`), có sẵn `Python 3.14.7`, **Android SDK + NDK `27.0.12077973` / `28.2.13676358`** và **CMake `3.22.1`**. Không có macOS/Xcode trên máy host hiện tại (do đó mọi bước build/test vật lý iOS sẽ được ghi nhận trung thực là `Not measured on Windows host`).
- **Kiến trúc tổng thể:**
  - **Feature-First Clean Architecture** (`domain` / `data` / `presentation`).
  - **Quản lý trạng thái:** `bloc ^9.0.0`, `flutter_bloc ^9.1.0`, `bloc_concurrency ^0.3.0` — **0% `Cubit`** (được bảo vệ tự động bởi `test/unit/architecture_guard_test.dart`).
  - **Dependency Injection:** `get_it ^9.3.0` (`lib/core/di/dependency_injection.dart`).
  - **Điều hướng:** `go_router ^18.1.4` (`lib/app/app_router.dart`).
  - **Đơn vị tiền tệ:** Số nguyên `int` minor units (`VND` nguyên đồng, không dùng `double` cho số dư hay bút toán kế toán).

---

## 2. Kiểm kê Các Module Hiện có trong `lib/`

| Module / Thành phần | Đường dẫn chính | Hiện trạng chức năng |
| :--- | :--- | :--- |
| **Transactions & Ledger** | `lib/features/transactions/` | Đầy đủ sổ cái thu/chi/chuyển khoản nội bộ (`transfer`)/trả thẻ tín dụng (`creditCardPayment`)/đảo bút toán (`reversal`), tách hóa đơn đa danh mục (`TransactionSplitLine`), kiểm tra idempotency theo `operationId`, tính `FinanceOverviewSummary` không đếm trùng chuyển khoản nội bộ. |
| **Wallets & Accounts** | `lib/features/transactions/` + `lib/features/notifications/` | Quản lý `WalletEntity` (`cash`, `bank`, `creditCard`, `savings`) dưới `/users/{uid}/wallets/{walletId}` và tài khoản nhận VietQR `/users/{uid}/bank_accounts/{accountId}`. Khi đăng ký tài khoản, hệ thống khởi tạo `wallet_cash_default` và ví ngân hàng mặc định. |
| **Categories** | `lib/features/authentication/data/datasources/firebase_auth_remote_datasource.dart` + `TransactionRepository.watchCategories` | Khởi tạo 15 danh mục chuẩn đời sống Việt Nam dưới `/users/{uid}/categories/{categoryId}` (`cat_food`, `cat_housework`, `cat_housing`, `cat_utilities`, `cat_shopping`, `cat_vehicle`, `cat_vehicle_maint`, `cat_health`, `cat_entertainment`, `cat_family_social`, `cat_debt`, `cat_bank_fee`, `cat_other_exp`, `cat_salary`, `cat_other_inc`). |
| **Budgets & Funds** | `lib/features/budgets/` | Quản lý hạn mức chi tiêu theo tháng/danh mục (`/users/{uid}/budgets`) và quỹ tích lũy cá nhân (`/users/{uid}/personal_funds`). |
| **Bank Notifications & Reconciliation** | `lib/core/security/bank_notification_parser.dart` + `lib/features/notifications/` | Đã có `AndroidNotificationBridge` kết nối `NotificationListenerService` (Kotlin), `OtpRedactor` chặn tuyệt đối mã OTP/CVV/PIN, `BankNotificationParser` phân tích 18 ngân hàng/ví VN, chống trùng bằng `source_events` + `crossSourceFingerprint` + `softWindowFingerprint` (±15 phút) và đối soát nâng cấp `provisional` → `verified` với SePay Webhook/API. |
| **Quick Text & Voice Input** | `lib/core/utils/smart_quick_entry_parser.dart`, `lib/core/utils/voice_financial_nlp_engine.dart`, `lib/core/widgets/voice_smart_capture_sheet.dart`, `lib/core/services/native_voice_assistant_bridge.dart` | Đã có MethodChannel/EventChannel nhận transcript giọng nói Android (`NativeVoiceAssistantBridge`) và bộ regex sơ bộ (`SmartQuickEntryParser`, `VoiceFinancialNlpEngine`). |
| **Family Finance** | `lib/features/family/` | Không gian cộng tác (`/families/{familyId}`), chia hóa đơn 4 chế độ (`SplitBillCalculator`), rút gọn nợ (`DebtSimplifier`), phân quyền `owner`/`admin`/`member`. Dữ liệu cá nhân `/users/{uid}/**` tách biệt hoàn toàn với `/families/{familyId}/**`. |
| **Settings & Privacy** | `lib/features/notifications/presentation/pages/activity_and_settings_pages.dart` + `notifications_privacy_page.dart` | Cài đặt giao diện Sáng/Tối, quyền đọc thông báo ngân hàng, liên kết tài khoản và xóa toàn bộ dữ liệu cá nhân (`deleteAccountAndPersonalData`). |

---

## 3. Trả lời 5 Câu hỏi Kiến trúc Trọng tâm

### 3.1. Những tính năng nào đã tồn tại?
1. Sổ cái kế toán nguyên tử (`runTransaction`) lưu số nguyên `amountMinor`, hỗ trợ `expense`, `income`, `transfer`, `creditCardPayment`, `reversal` và `splitLines`.
2. Nhận thông báo ngân hàng Android có kiểm duyệt quyền truy cập (`consents/android_notification`), lọc OTP (`OtpRedactor`), khử trùng lặp đa nguồn (`source_events`, `crossSourceFingerprint`, `softWindowFingerprint`).
3. Cầu nối nhận diện giọng nói Android (`NativeVoiceAssistantBridge` — lưu ý: STT dựa trên SpeechRecognizer hệ thống Android, không tự mặc định offline nếu người dùng chưa tải gói ngôn ngữ hệ thống).
4. Quy tắc bảo mật `firestore.rules` cô lập tuyệt đối dữ liệu `/users/{userId}/**` theo `isOwner(userId)` và cấm xóa cứng giao dịch lịch sử (`allow delete: if isAccountDeletionActive(userId)`).
5. Bộ 84 bài kiểm thử tự động (`flutter test`) bao gồm `architecture_guard_test.dart` (cấm `Cubit`, cấm Domain import Flutter/Firebase/BLoC, cấm Presentation import Firebase SDK trực tiếp) và kiểm tra `0` `TextOverflow` / `0` `showSnackBar`.

### 3.2. Những tính năng nào còn thiếu (Cần xây dựng trong đợt triển khai này)?
1. **Mô hình AI phân loại danh mục tiếng Việt thực thụ chạy Offline (`FastTextClassifier`)** cùng pipeline huấn luyện, đánh giá, hiệu chỉnh xác suất (temperature calibration), lượng tử hóa (`INT8`) và kiểm định chống rò rỉ template (`tools/financial_ai/`).
2. **Runtime C++ Native FFI (`dart:ffi` + Android NDK CMake `liblifeos_fasttext.so`) & Background `Isolate` Inference** đọc trực tiếp tệp trọng số nhị phân `.ftq`, kèm fallback an toàn sang `RuleBasedClassifier`.
3. **Bộ chuẩn hóa văn bản tài chính toàn diện (`FinancialTextNormalizer`)** có `FinancialClock` abstraction cho phép kiểm thử thời gian tương đối (*hôm qua, hôm kia, sáng nay, tối qua, thứ hai tuần trước, ngày 15, tháng trước*), xử lý tiếng Việt không dấu/có dấu, từ viết tắt ngân hàng, định dạng số tiền phức hợp (*2 triệu 300 nghìn*, *1,5 triệu*) và **cờ mơ hồ (`ambiguityFlags`)** thay vì đoán mò.
4. **Bộ nhận diện đầy đủ 10 loại giao dịch chuẩn (`FinancialTransactionType`)** và bộ chặn câu phi giao dịch / phủ định / số dư (*"còn 2 triệu trong tài khoản"*, *"tôi không mua gì hôm nay"*, *"hủy giao dịch 100k vừa nhập"*) — hiện tại `SmartQuickEntryParser` cũ sẽ nhận nhầm các câu này thành khoản chi tiêu nếu có con số!
5. **Hệ thống học cá nhân hóa có ngữ cảnh (`PersonalizationEngine`)** lưu theo từng `userId`, `merchantCanonicalKey`, điều kiện hướng tiền/nguồn, đếm số lần xác nhận, tự động vô hiệu hóa khi danh mục bị xóa, và tuyệt đối không rò rỉ sang thành viên gia đình khác.
6. **Chính sách Độ tin cậy đa chiều (`ConfidencePolicyEngine`)** tách riêng `amountConfidence`, `typeConfidence`, `categoryConfidence`, `merchantConfidence`, `sourceConfidence` thành `highConfidence`, `mediumConfidence`, `lowConfidence`, `unknown`.
7. **Module Clean Architecture `lib/features/financial_ai/`** với `FinancialAiBloc` (`Event`/`State`), lưu nháp chờ duyệt, màn hình **AI Phân tích & Xác nhận Giao dịch (Multi-Draft Preview)** và màn hình **Cài đặt AI & Quy tắc Cá nhân hóa (`AiLearningSettingsPage`)**.

### 3.3. Dữ liệu giao dịch đang được lưu ở đâu?
- **Local + Cloud đồng bộ tự động:** Cloud Firestore SDK (`cloud_firestore ^7.2.0`) với bộ nhớ đệm offline bền vững trên thiết bị (SQLite trên Android/iOS, IndexedDB trên Web), hỗ trợ ghi khi mất mạng (`hasPendingWrites: true`) và tự đồng bộ khi có mạng lại.
- **Đường dẫn lưu trữ chính:**
  - Giao dịch cá nhân: `/users/{userId}/transactions/{txId}` (kèm nhật ký kiểm toán bất biến `/users/{userId}/ledger_audits/{auditId}`).
  - Ví cá nhân: `/users/{userId}/wallets/{walletId}`.
  - Danh mục người dùng: `/users/{userId}/categories/{categoryId}`.
  - Sự kiện nguồn chống trùng: `/users/{userId}/source_events/{eventKey}`.
  - Quy tắc cửa hàng & cấu hình AI cá nhân (mở rộng trên cùng cơ sở dữ liệu Firestore, không tạo DB thứ hai):
    - `/users/{userId}/ai_personalization_rules/{ruleId}`
    - `/users/{userId}/ai_category_corrections/{correctionId}`
    - `/users/{userId}/ai_pending_drafts/{draftId}`
    - `/users/{userId}/ai_preferences/settings`

### 3.4. Những phần nào có thể tái sử dụng trực tiếp?
- `TransactionRepository.createTransaction`, `watchWallets`, `watchCategories` và `CreateTransactionUseCase` (đảm bảo mọi giao dịch AI sau khi người dùng xác nhận đều đi qua đúng quy tắc kế toán và idempotency `operationId` hiện có).
- `OtpRedactor` và `BankNotificationParser.computeCrossSourceFingerprint` / `computeOverlappingSoftWindowFingerprints` (`lib/core/security/bank_notification_parser.dart`).
- `NativeVoiceAssistantBridge` (`lib/core/services/native_voice_assistant_bridge.dart`) cho tín hiệu micro/transcript.
- Hệ thống UI `LiquidGlassSurface`, `LiquidGlassSheetFrame`, `LifeOsMintWaveCanvas`, `LifeOsTopBrandHeader`, `LifeOsTopToast` và `ProCategoryStyle`.

### 3.5. Những thay đổi nào có nguy cơ phá vỡ tương thích và biện pháp phòng vệ?
1. **Ràng buộc Clean Architecture Guard (`test/unit/architecture_guard_test.dart`):**
   - Mọi file trong `lib/features/financial_ai/domain/**` tuyệt đối không được import `package:flutter/...`, `package:bloc/...`, hay `package:cloud_firestore/...`.
   - `FinancialAiBloc` và các trang UI không được import `cloud_firestore` hay BLoC của feature khác trong file `*_bloc.dart`.
2. **Ràng buộc UI Guard (`test/widget/top_toast_and_pro_max_redesign_test.dart`):**
   - Tuyệt đối **không dùng `TextOverflow`** ở bất kỳ đâu trong `lib/` (kể cả trong chú thích) và **không dùng `.showSnackBar(`** (chỉ dùng `LifeOsTopToast`).
3. **Ràng buộc Quyền Xóa Dữ liệu (`test/unit/audit_remediation_v3_test.dart`):**
   - Mọi subcollection mới thêm vào `/users/{userId}` trong `firestore.rules` phải được bổ sung vào danh sách xóa của `deleteAccountAndPersonalData` để đảm bảo quyền xóa sạch 100% dữ liệu cá nhân.
4. **Tương thích ngược với `SmartQuickEntryParser` & `BankNotificationParser`:**
   - Giữ nguyên API công khai của các hàm hiện có để toàn bộ 84 bài test hiện hành tiếp tục chạy xanh, đồng thời nâng cấp luồng Quick Create Hub, Voice Sheet và Bank Notification Ingestion kết nối với `FinancialAiEngine`.
