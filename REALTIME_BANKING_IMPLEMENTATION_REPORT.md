# BÁO CÁO TRIỂN KHAI — LIFE OS REAL-TIME BANKING NOTIFICATIONS (`v3.8.0+23`)

## 1. Kiến trúc đã triển khai

Hệ thống nhận diện giao dịch ngân hàng theo thời gian thực và thông báo đẩy của **Life OS** được triển khai đồng bộ từ Backend (`Firebase Cloud Functions Gen 2` TypeScript/Node.js) đến ứng dụng di động (`Flutter` Clean Architecture + `BLoC` thuần sự kiện, **0 `Cubit`**) và tầng gốc Android (`Kotlin`):

```text
[NGUỒN A: SePay Webhook] ──► POST /webhooks/sepay (Cloud Functions Gen 2, asia-southeast1)
                                  │  1. Kiểm tra POST, giới hạn <= 64KB, đọc rawBody nguyên bản
                                  │  2. Xác thực chữ ký HMAC-SHA256 constant-time (X-SePay-Signature)
                                  │     + cửa sổ chống replay ±300s (X-SePay-Timestamp)
                                  │  3. Chặn nội dung chứa OTP/PIN/CVV & loại bỏ userId ngoại lai
                                  ▼
                       sepay_webhook_inbox/{providerEventKey}  (Durable Event Inbox)
                                  │  Chỉ trả HTTP 200 {"success": true} SAU KHI ghi bền vững!
                                  ▼
                       processSePayInboxWorker (onDocumentCreated Queue Worker)
                                  │  - Tra cứu server_bank_connections (đã xác minh sở hữu)
                                  │  - Kiểm tra BankIntegrationCapability (tiền vào vs tiền ra / TKP)
                                  │  - Giao dịch ACID Firestore: Khử trùng & Đối soát chéo 3 nguồn
                                  │  - Bảo toàn tiền: cờ `ledgerApplied` chống cộng/trừ số dư 2 lần
                                  │  - Không ghi đè số dư = 0 khi `accumulated = 0`
                                  ▼
         ┌────────────────────────┴────────────────────────┐
         ▼                                                 ▼
users/{uid}/transactions/{txId}               notification_outbox/{notifId}
users/{uid}/wallets/{walletId}                             │  Atomic CAS claim (PENDING -> DISPATCHING)
users/{uid}/ledger_audits/{auditId}                        ▼
users/{uid}/financial_notifications/{notifId}  dispatchNotificationOutboxWorker (FCM Admin SDK)
                                                           │  - Áp dụng tùy chọn riêng tư màn hình khóa
                                                           │  - Gửi tới users/{uid}/devices (pushEnabled=true)
                                                           │  - Lỗi FCM KHÔNG rollback giao dịch tài chính!
                                                           ▼
[NGUỒN B: SePay REST API] ──► reconcileBankConnectionViaApi (Server-side callable đối soát bù)
[NGUỒN C: Android NotificationListenerService] ──► BankNotificationListenerService.kt (On-device)
```

### Phân biệt mô hình đa người dùng (Multi-User Provisioning)
- **Không dùng chung một webhook cá nhân của chủ ứng dụng cho mọi người dùng** mà không có định danh/ủy quyền hợp lệ.
- Mỗi người dùng xác minh quyền sở hữu tài khoản ngân hàng qua callable `verifyAndLinkBankConnection` trên backend (kiểm tra danh sách `/userapi/bankaccounts/list` của chính token người dùng cung cấp và kiểm tra xung đột trên `server_bank_connections` để ngăn người dùng B chiếm quyền số tài khoản đã xác minh của người dùng A).
- Việc chỉ tự nhập số tài khoản trên ứng dụng chỉ phục vụ tạo mã VietQR / gợi ý định tuyến cục bộ (`Qua Android & QR`), **tuyệt đối không** hiển thị trạng thái `Đã kết nối` của SePay.

---

## 2. Danh sách file được tạo mới và nâng cấp

### Backend (`Firebase Cloud Functions Gen 2` — TypeScript)
- `functions/package.json` & `functions/tsconfig.json` — Cấu hình Node 22, TypeScript strict, script `lint`, `typecheck`, `build`, `test`.
- `functions/src/capabilities.ts` — Danh mục `BankIntegrationCapability` chuẩn hóa theo tài liệu SePay thực tế (tách biệt chiều tiền vào `in` và chiều tiền ra `out`, điều kiện `TKP` cho `STB`, `TPB`, `CTG`).
- `functions/src/security.ts` — Xác thực chữ ký `HMAC-SHA256` bằng `crypto.timingSafeEqual`, kiểm tra cửa sổ thời gian `±300s`, lọc chặn `OTP/SmartOTP/PIN/CVV` và che số tài khoản (`•••• 1234`).
- `functions/src/schema.ts` — Kiểm tra chặt chẽ schema JSON, ép kiểu số nguyên VNĐ dương (`Number.isSafeInteger`), loại bỏ `accumulated <= 0` khỏi số dư quan sát, bộ phân loại danh mục giải thích được.
- `functions/src/bankingEngine.ts` — Bộ điều phối trung tâm: `handleSePayWebhookHttp`, `processInboxEvent` (ACID idempotency + cross-source reconciliation), `dispatchNotificationOutbox` (atomic CAS claim + FCM retry), `verifyAndConnectBankAccount`.
- `functions/src/firestoreStore.ts` — Triển khai `BankingBackendStore` và `FirebaseAdminFcmSender` trên `firebase-admin/firestore` & `firebase-admin/messaging`.
- `functions/src/memoryStore.ts` — Bộ lưu trữ giao dịch tuần tự phục vụ kiểm thử race condition (`Promise.all`) và tiêm lỗi (fault injection).
- `functions/src/index.ts` — Xuất các Cloud Functions Gen 2 (`sepayWebhook`, `processSePayInboxWorker`, `dispatchNotificationOutboxWorker`, `verifyAndLinkBankConnection`, `disconnectBankConnection`, `migrateLegacySePayToken`, `reconcileBankConnectionViaApi`).
- `functions/src/test/realtime_banking.test.ts` & `functions/src/test/firestore_emulator.test.ts` — Bộ kiểm thử tự động bao phủ kịch bản `T01`–`T24` và kiểm thử trực tiếp trên Cloud Firestore Emulator.

### Cấu hình Firebase & Bảo mật
- `firebase.json` — Khai báo codebase `functions`, rewrite `/webhooks/sepay` → `sepayWebhook` (`asia-southeast1`), cấu hình Functions Emulator (`5001`).
- `firestore.rules` — Khóa hoàn toàn 4 collection server-only (`server_bank_connections`, `sepay_webhook_inbox`, `notification_outbox`, `bank_reconciliation_jobs` với `allow read, write: if false;`), cô lập `devices`, `bank_connections`, `financial_notifications`, `notification_preferences`, `merchant_rules` theo `isOwner(userId)` và cấm client tự giả mạo `status == 'connected'` cho `sepay`.
- `firestore.indexes.json` — Bổ sung composite indexes cho `transactions`, `financial_notifications`, `server_bank_connections`, `notification_outbox`.
- `firebase/rules_tests/run_emulator_rules_tests.mjs` — Mở rộng kiểm thử bảo mật trực tiếp trên Firestore Emulator cho `T20` & `T23`.

### Flutter Client & Native Android (`Clean Architecture + BLoC`)
- `lib/features/notifications/domain/entities/bank_capability_and_connection_entities.dart` — Pure Dart entities: `BankIntegrationCapability`, `BankConnectionEntity`, `BankingNotificationPreferencesEntity`, `FinancialNotificationEntity`, `MerchantCategoryRuleEntity`, `ExplainableBankingRuleEngine`.
- `lib/features/transactions/domain/entities/transaction_entities.dart` & `lib/features/transactions/data/models/transaction_models.dart` — Bổ sung `TransactionVerification.needsReview`, `TransactionSourceKind.bankWebhook`, `TransactionBalanceType` (`observedBankBalance`, `estimatedWalletBalance`, `unknownBalance`), cờ bảo toàn số dư `ledgerApplied` và các trường đối soát.
- `lib/features/transactions/data/datasources/transaction_remote_datasource.dart` — Sửa `decideProvisionalTransaction` kiểm tra `!current.ledgerApplied` trước khi cộng/trừ ví.
- `lib/features/notifications/data/repositories/notifications_repository_impl.dart` — Sửa triệt để lỗi cộng/trừ số dư hai lần khi đối soát chéo giữa `androidNotification` (`provisional` / `userConfirmed`) và nguồn xác minh (`bankApi` / `bankWebhook`); bổ sung di trú xóa token cũ `consents/sepay_api`, cài đặt riêng tư, thông báo kiểm thử an toàn và quy tắc phân loại của người dùng.
- `lib/core/services/fcm_banking_messaging_service.dart` — Dịch vụ quản lý vòng đời token FCM theo từng tài khoản, khử trùng thông báo foreground, xử lý chạm thông báo từ background (`onMessageOpenedApp`) & trạng thái đóng hoàn toàn (`getInitialMessage`), vô hiệu hóa token ngay khi đăng xuất (`T16`).
- `lib/features/notifications/presentation/bloc/notification_ingestion_bloc.dart` — Mở rộng `Event`/`State` quản lý kết nối SePay, đối soát bù, cài đặt riêng tư màn hình khóa, thông báo kiểm thử và dọn phiên khi logout.
- `lib/features/notifications/presentation/pages/notifications_privacy_page.dart` & `activity_and_settings_pages.dart` — Màn **Ngân hàng & Đồng bộ giao dịch** và **Thông báo & Biến động** (`Tất cả | Tiền vào | Tiền ra`), hiển thị trung thực giới hạn từng ngân hàng, che số tài khoản, công tắc riêng tư màn hình khóa (mặc định bật) và nút kiểm tra thông báo không tạo giao dịch thật.
- `lib/features/transactions/presentation/pages/auto_tx_and_report_pages.dart` — Gợi ý gắn giao dịch với **Lịch sử bảo dưỡng xe** (`[Ghi vào lịch sử bảo dưỡng] | [Bỏ qua]`), gợi ý **Khoản chi định kỳ**, và tự học quy tắc phân loại khi người dùng đổi danh mục.
- `lib/app/app_router.dart` & `lib/bootstrap.dart` & `lib/core/di/dependency_injection.dart` — Đăng ký background handler FCM và điều hướng sâu `/auto-tx-review?txId=...`.
- `android/app/src/main/AndroidManifest.xml` & `MainActivity.kt` — Kênh thông báo Android `lifeos_banking_realtime` (`VISIBILITY_PRIVATE`), kiểm tra quyền `POST_NOTIFICATIONS` (Android 13+) và kiểm tra tối ưu pin không gây phiền.
- `test/unit/realtime_banking_fcm_and_reconciliation_test.dart` & `test/security/firestore_rules_test.dart` — Bộ kiểm thử tự động phía Flutter & Firestore Rules.

---

## 3. Các tính năng đã hoạt động và xác minh

1. **Nhận webhook SePay (`POST /webhooks/sepay`)**: Xác thực chữ ký `HMAC-SHA256` constant-time trên raw body, chống replay `±300s`, ghi `sepay_webhook_inbox` bền vững trước khi phản hồi `HTTP 200 {"success": true}` (trả `503` nếu lỗi lưu trữ để SePay tự retry).
2. **Bảo toàn tiền tuyệt đối & Chống trùng 3 nguồn**:
   - Đã phát hiện và vá lỗi cộng/trừ ví hai lần khi giao dịch Android đã được xác nhận (`userConfirmed` / `autoConfirm`) trước khi sự kiện xác minh từ SePay đến sau (`T05`, `T24`).
   - Giữ tách biệt hai giao dịch cùng số tiền trong vòng 15 phút nếu khác `referenceCode` (`T06`), và chuyển sang `NEEDS_REVIEW` khi có nhiều giao dịch tạm thời mơ hồ trùng khớp.
   - Không bao giờ đặt số dư ngân hàng về `0` khi `accumulated = 0` (`T15`).
3. **Thông báo đẩy FCM & Điều hướng sâu**: Hỗ trợ đầy đủ 3 trạng thái `Foreground` (hiển thị 1 toast duy nhất không lặp), `Background` (`onMessageOpenedApp`) và `Terminated` (`getInitialMessage`) mở thẳng chi tiết giao dịch `/auto-tx-review?txId=...`.
4. **Bảo vệ riêng tư & Bảo mật token**:
   - Mặc định bật **Ẩn số tiền trên màn hình khóa** (`hideAmountOnLockscreen = true`).
   - Tự động di trú và xóa tài liệu cũ `users/{uid}/consents/sepay_api` để không còn bất kỳ `apiToken` dạng rõ nào trong vùng Firestore client đọc được.
   - Chặn tuyệt đối mọi thông báo chứa mã `OTP`, `SmartOTP`, `PIN`, `CVV` ngay từ cổng vào cả trên thiết bị Android và trên Cloud Functions.
5. **Trải nghiệm thông minh có giải thích**: Tự động phân loại theo quy tắc rõ ràng (hỗ trợ người dùng sửa và lưu quy tắc riêng), đề xuất hóa đơn định kỳ và đề xuất gắn khoản chi sửa xe vào hồ sơ bảo dưỡng phương tiện.

---

## 4. Các giới hạn thực tế của nhà cung cấp (Provider Limitations)

Theo tài liệu chính thức của SePay (`developer.sepay.vn`) tại thời điểm triển khai:
- **Chiều tiền vào (`transferType: "in"`)**: Được hỗ trợ qua SePay Webhook cho các ngân hàng liên kết hợp lệ (`Vietcombank`, `MB Bank`, `BIDV`, `VietinBank`, `TPBank`, `Sacombank`, `ACB`, `VPBank`, `MSB`, `OCB`, ...).
- **Chiều tiền ra (`transferType: "out"`)**: Trên SePay Webhook bị giới hạn nghiêm ngặt — chỉ hỗ trợ cho **Sacombank (`STB`), TPBank (`TPB`) và VietinBank (`CTG`)** kèm điều kiện **bắt buộc cấu hình qua `TKP` (Tài khoản phụ / VA nội dung)**, **không áp dụng cho VA chính thức** của ngân hàng.
- Với các ngân hàng chỉ hỗ trợ tiền vào trên SePay (như `VCB`, `MB`, `BIDV`, `ACB`, `VPB`, ...) hoặc ngân hàng chưa hỗ trợ SePay Webhook trực tiếp (`TCB`), giao diện `Ngân hàng & Đồng bộ giao dịch` giải thích minh bạch giới hạn này và đề xuất người dùng bật bổ sung **Thông báo Android (`NotificationListenerService`)** trên điện thoại Android để nhận diện chiều tiền ra.
- Về FCM: Hệ điều hành có thể trì hoãn hoặc chặn thông báo nếu người dùng tắt quyền thông báo hệ thống, thiết bị mất mạng hoặc ứng dụng bị `Force Stop` bởi OEM tiết kiệm pin cực đoan — dữ liệu giao dịch vẫn luôn được lưu an toàn trên server độc lập với FCM.

---

## 5. Những API và Dịch vụ cần cấu hình khi chạy Production

1. **Firebase Cloud Functions Gen 2 (`asia-southeast1`)** & **Cloud Build / Artifact Registry** (yêu cầu nâng cấp dự án Firebase lên gói **Blaze** — xem Mục 8 & 13).
2. **Google Cloud Secret Manager API** (lưu khóa bí mật `SEPAY_WEBHOOK_SECRET`).
3. **Firebase Cloud Messaging API (V1)** (được bật mặc định khi cấu hình Firebase Android/iOS).
4. **SePay User API & Webhooks** trên tài khoản SePay của người dùng (`https://my.sepay.vn`).

---

## 6. Những quyền trên thiết bị người dùng

| Quyền | Mục đích | Cơ chế xin quyền |
|---|---|---|
| `android.permission.POST_NOTIFICATIONS` | Hiển thị thông báo đẩy FCM trên Android 13+ | Xin khi người dùng đăng nhập / bấm nút cấp quyền trong Cài đặt thông báo |
| `BIND_NOTIFICATION_LISTENER_SERVICE` | Nguồn bổ sung đọc thông báo biến động ngân hàng ngay trên máy (tùy chọn) | Tắt mặc định; chỉ hoạt động khi người dùng chủ động bật và chọn từng ngân hàng |
| Tối ưu pin (`isIgnoringBatteryOptimizations`) | Giữ dịch vụ lắng nghe ổn định trên Android OEM | Chỉ kiểm tra trạng thái nhẹ nhàng, không ép buộc gây phiền |

---

## 7. Những Secret cần thiết

- **`SEPAY_WEBHOOK_SECRET`**: Chuỗi bí mật tối thiểu 32 ký tự dùng để ký và xác minh `HMAC-SHA256` giữa SePay và Cloud Functions Gen 2.
  - Thiết lập an toàn qua Firebase CLI (lưu thẳng vào Google Secret Manager, không bao giờ nằm trong git hay APK):
    ```bash
    firebase functions:secrets:set SEPAY_WEBHOOK_SECRET
    ```

---

## 8. Hướng dẫn triển khai Firebase (Deploy Guide)

> **Lưu ý quan trọng về gói cước & trạng thái triển khai:**
> - Bộ **`firestore:rules`** và **`firestore:indexes`** mới nhất của `v3.8.0+23` **đã được triển khai trực tiếp thành công** lên dự án `life-os-vn-2026` (miễn phí trên gói Spark `\$0/tháng`).
> - Riêng **`functions` (`Cloud Functions Gen 2`)** và **`Secret Manager`** yêu cầu nâng cấp dự án lên gói **Blaze**. Theo nguyên tắc an toàn chi phí, mình **không tự ý nâng cấp gói trả phí** khi chưa có phê duyệt của bạn; toàn bộ mã nguồn TypeScript tại `functions/` đã biên dịch và vượt qua 100% kiểm thử để sẵn sàng chạy ngay bằng 3 lệnh bên dưới:

Khi bạn sẵn sàng bật gói Blaze để chạy webhook thật trên Cloud:

```bash
# 1. Cài đặt gói phụ thuộc & biên dịch kiểm tra Backend
cd functions
npm ci
npm run lint && npm test
cd ..

# 2. Khai báo khóa bí mật HMAC trên Google Secret Manager
firebase functions:secrets:set SEPAY_WEBHOOK_SECRET --project life-os-vn-2026

# 3. Triển khai Firestore Rules, Indexes và Cloud Functions Gen 2
firebase deploy --only firestore:rules,firestore:indexes,functions --project life-os-vn-2026
```

Sau khi lệnh hoàn tất, Firebase CLI sẽ in ra URL HTTPS của hàm `sepayWebhook` dạng:
`https://asia-southeast1-life-os-vn-2026.cloudfunctions.net/sepayWebhook` (hoặc qua Firebase Hosting: `https://life-os-vn-2026.web.app/webhooks/sepay`).

---

## 9. Hướng dẫn tạo Webhook trên SePay Dashboard

1. Đăng nhập vào `https://my.sepay.vn` → chọn mục **Webhooks** → **Thêm Webhook**.
2. **Tài khoản ngân hàng**: Chọn tài khoản ngân hàng (hoặc `TKP` nếu dùng Sacombank/TPBank/VietinBank cần cả tiền ra).
3. **Sự kiện kích hoạt**: Chọn `Có tiền vào` (hoặc `Cả hai` nếu tài khoản thuộc nhóm hỗ trợ `TKP` tiền ra).
4. **URL nhận Webhook**: Dán URL `https://life-os-vn-2026.web.app/webhooks/sepay` (hoặc URL trực tiếp của hàm `sepayWebhook`).
5. **Phương thức xác thực**: Chọn **HMAC-SHA256**, nhập cùng chuỗi bí mật đã cấu hình trong `SEPAY_WEBHOOK_SECRET` (gửi kèm header `X-SePay-Signature` & `X-SePay-Timestamp`).
6. **Kiểu dữ liệu (Content-Type)**: `application/json`. Lưu cấu hình.

---

## 10. Kết quả từng nhóm kiểm thử đã chạy xác minh

| Nhóm kiểm thử | Lệnh thực thi | Kết quả | Chi tiết bao phủ |
|---|---|---|---|
| **Backend Lint & Typecheck** | `cd functions && npm run lint && npm run typecheck` | **PASS (`0` lỗi)** | TypeScript strict mode trên toàn bộ `functions/src/`. |
| **Backend Unit & Concurrency (`T01`–`T24`)** | `cd functions && npm test` | **PASS (`8/8` suites/tests)** | Tiền vào (`T01`), Tiền ra TPBank TKP (`T02`), Retry 10 lần (`T03`), Race `Promise.all` đồng thời (`T04`), Đối soát chéo không nhân đôi số dư (`T05`, `T24`), Khác mã tham chiếu trong 2 phút (`T06`), Sai HMAC (`T07`), Replay >300s (`T08`), Tài khoản chưa liên kết & chèn `userId` giả (`T09`), Nhiều ví (`T10`), Lỗi FCM vẫn giữ giao dịch (`T14`), `accumulated=0` (`T15`), Khử trùng FCM (`T18`), Chặn OTP (`T19`), Đồng bộ ngược (`T21`), Giới hạn ngân hàng (`T22`), Chống chiếm quyền tài khoản user khác (`T23`), Lỗi ghi inbox trả `503`. |
| **Live Cloud Firestore Emulator Integration** | `functions/src/test/firestore_emulator.test.ts` | **PASS** | Chạy giao dịch ACID thật trên Firestore Emulator (`127.0.0.1:8188`) từ Webhook → Inbox → Ledger → Outbox. |
| **Firestore Security Rules Emulator (`T20`)** | `node --test firebase/rules_tests/run_emulator_rules_tests.mjs` | **PASS (`4/4`)** | Cô lập `devices`, `bank_connections`, `financial_notifications`, chặn giả mạo `connected` và khóa chặt 4 collection server-only (`403`). |
| **Flutter Format & Static Analysis** | `dart format lib test && flutter analyze` | **PASS (`0` issues)** | Kiến trúc Clean Architecture, 0 `Cubit`, 0 gọi trực tiếp `my.sepay.vn` từ `lib/`. |
| **Flutter Unit, BLoC, Integration & Widget Tests** | `flutter test` | **PASS (`100%`)** | Toàn bộ test hiện hữu + bộ test mới `realtime_banking_fcm_and_reconciliation_test.dart` (`T05`, `T06`, `T11`–`T13`, `T15`–`T19`, `T22`–`T24`, Migration token cũ, Test notification an toàn, Rule phân loại). |
| **Android Release Build** | `flutter build apk --release` | **PASS** | Đóng gói thành công APK Android kèm kênh thông báo `lifeos_banking_realtime` và `firebase_messaging`. |

---

## 11. Những phần cần Thiết bị thật / Tài khoản SePay thật / Gói Blaze để kiểm chứng thực địa

Để trung thực tuyệt đối giữa kiểm thử mô phỏng/emulator và môi trường thực tế:
- **Đã xác minh tự động trên máy cục bộ & Firebase Emulator**: Toàn bộ thuật toán HMAC-SHA256, chống replay, ACID idempotency, đối soát chéo 3 nguồn, bảo toàn số dư một lần, Firestore Security Rules, BLoC/UI Flutter và build APK release.
- **Cần bạn cấu hình thêm để nghiệm thu thực địa Production**:
  1. Nâng cấp dự án Firebase `life-os-vn-2026` lên gói **Blaze** và chạy `firebase deploy --only functions,firestore` để mở cổng HTTPS công khai nhận request từ máy chủ SePay.
  2. Cấu hình `SEPAY_WEBHOOK_SECRET` và gắn URL webhook trên tài khoản SePay thật của bạn.
  3. Kiểm thử chạm thông báo FCM khi ứng dụng bị đóng (`Terminated`) trên điện thoại Android thật đã đăng nhập Google Play Services và thực hiện 1 giao dịch chuyển khoản thật.

---

## 12. Rủi ro còn tồn tại & Biện pháp giảm thiểu

1. **Độ trễ thông báo do chế độ tiết kiệm pin OEM (Xiaomi/OPPO/Vivo)**:
   - *Giảm thiểu*: Kết hợp cả FCM ưu tiên cao (`priority: "high"`, kênh `IMPORTANCE_HIGH`) từ server lẫn hàng đợi ngoại tuyến cục bộ trong `BankNotificationListenerService.kt` để đồng bộ bù ngay khi mở lại app.
2. **Hai giao dịch tiền mặt/chuyển khoản cùng số tiền trong 15 phút nhưng thông báo Android bị ngân hàng cắt mất mã tham chiếu**:
   - *Giảm thiểu*: Hệ thống không gộp mù quáng khi có từ 2 ứng viên mơ hồ trở lên mà chuyển trạng thái sang `NEEDS_REVIEW` (`Cần kiểm tra đối soát`) và giữ nguyên số dư cho tới khi người dùng xác nhận.

---

## 13. Chi phí dự kiến và phụ thuộc gói Firebase / SePay

- **Firebase**:
  - **Firestore & FCM**: Firebase Cloud Messaging hoàn toàn **miễn phí (`$0`)**. Với quy mô cá nhân/gia đình (vài chục đến vài trăm giao dịch/tháng), mức đọc/ghi Firestore và số lần gọi Cloud Functions Gen 2 (miễn phí 2 triệu lượt gọi/tháng trong hạn mức free tier của gói Blaze) có chi phí thực tế xấp xỉ **`$0.00 – $0.05 / tháng`**, nhưng Google Cloud bắt buộc gắn thẻ thanh toán (gói Blaze) để bật Cloud Functions Gen 2 và Secret Manager.
- **SePay**:
  - Phụ thuộc hạn mức gói dịch vụ trên `sepay.vn` của từng người dùng (SePay có gói miễn phí giới hạn số giao dịch/tháng cho cá nhân thử nghiệm và các gói trả phí theo sản lượng giao dịch). Nếu không dùng SePay, người dùng vẫn sử dụng miễn phí 100% chế độ **Thông báo Android (`NotificationListenerService`) + Mã VietQR nội bộ** ngay trên thiết bị.
