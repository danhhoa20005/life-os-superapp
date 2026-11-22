# PHẠM VI MVP & ĐỊNH NGHĨA HOÀN THÀNH (MVP SCOPE)

---

## 1. Phân loại Ưu tiên Tính năng (P0 / P1 / P2 / P3)

| Mã | Nhóm tính năng | Phân loại | Trạng thái Phạm vi |
| --- | --- | :---: | :---: |
| **MVP-01** | Đăng ký, Đăng nhập, Quên mật khẩu, Khôi phục phiên & Onboarding riêng tư | **P0** | **IN SCOPE** |
| **MVP-02** | Dashboard **Hôm nay** (Tổng quan thu chi, việc đến hạn, lịch, cảnh báo xe/hóa đơn, gợi ý duyệt) | **P0** | **IN SCOPE** |
| **MVP-03** | Quản lý Ví, Danh mục, Giao dịch Thu/Chi, Chuyển ví nội bộ, Trả thẻ & Đảo bút toán (`VND`) | **P0** | **IN SCOPE** |
| **MVP-04** | Ngân sách Tháng theo Danh mục & Quỹ Cá nhân / Quỹ Chung Gia đình (Đóng góp, Đề xuất & Duyệt chi) | **P0** | **IN SCOPE** |
| **MVP-05** | Hộ Gia đình: Tạo nhóm, Mã mời, Phân quyền vai trò (`owner`/`admin`/`member`), Rời nhóm & Mua sắm chung | **P0** | **IN SCOPE** |
| **MVP-06** | Lịch Riêng (`PRIVATE_EVENT` cô lập tuyệt đối) / Lịch Chung (`SHARED_EVENT`) & Tùy chọn Bận/Rảnh | **P0** | **IN SCOPE** |
| **MVP-07** | Giao việc Gia đình Đồng thuận (`proposed` → `accepted`/`declined` → `in_progress` → `done` + lặp định kỳ) | **P0** | **IN SCOPE** |
| **MVP-08** | Hồ sơ Phương tiện (Che biển số, Odometer, Bảo dưỡng `min(km, ngày)`) & Hóa đơn Định kỳ (`P1`) | **P0 / P1** | **IN SCOPE** |
| **MVP-09** | Nhận diện Thông báo Ngân hàng Android có Consent, Chặn OTP, Khử trùng lặp, Nâng cấp `PROVISIONAL` & Xuất dữ liệu | **P1** | **IN SCOPE** |
| **MVP-10** | Đồng bộ Đa thiết bị & Hỗ trợ Ngoại tuyến trung thực (`hasPendingWrites` indicator) | **P1** | **IN SCOPE** |
| **OUT-01** | Liên kết thương mại trực tiếp SePay Bank Hub Hosted Link & Webhook Server | **P2** | OUT OF SCOPE / Cần Backend & Hợp đồng đối tác |
| **OUT-02** | Đọc hộp thư Gmail OAuth Restricted Scope & Google Push Pub/Sub | **P2** | OUT OF SCOPE |
| **OUT-03** | Gửi Push Notification từ máy chủ qua FCM Admin Key | **P2** | OUT OF SCOPE (Không nhúng khóa server vào client) |
| **OUT-04** | Thực đơn tủ lạnh, chăm sóc thú cưng, trợ lý AI hội thoại | **P3** | OUT OF SCOPE |

---

## 2. Đặc tả Chi tiết Các Feature Thuộc MVP

### 2.1. `authentication` (`MVP-01` — P0)
- **User story:** Người dùng tạo tài khoản, đăng nhập, khôi phục mật khẩu và thiết lập không gian cá nhân riêng tư mặc định.
- **Input / Output:** `{ email, password, fullName }` → `UserEntity` + khởi tạo ví/danh mục mặc định.
- **Business & Permission rules:** Mật khẩu `>= 8` ký tự; không lưu mật khẩu vào Firestore; chỉ `request.auth.uid == userId` mới đọc/sửa hồ sơ riêng `users/{userId}`.
- **Events & States (`AuthBloc`):**
  - Events: `AuthSubscriptionRequested`, `AuthSignInSubmitted`, `AuthSignUpSubmitted`, `AuthPasswordResetRequested`, `AuthOnboardingCompleted`, `AuthAvailabilitySharingToggled`, `AuthSignOutRequested`.
  - States: `AuthState` (`status`: `unknown`, `authenticated`, `unauthenticated`; `isSubmitting`, `user`, `failure`, `infoMessage`).
- **Use Cases & Repo:** `AuthRepository` (`SignUpUseCase`, `SignInUseCase`, `SignOutUseCase`, `SendPasswordResetUseCase`, `CompleteOnboardingUseCase`, `WatchAuthUserUseCase`).
- **Firestore Collections:** `users/{uid}`, `users/{uid}/wallets/{id}`, `users/{uid}/categories/{id}`, `users/{uid}/consents/{source}`.

### 2.2. `transactions` (`MVP-03` — P0)
- **User story:** Người dùng ghi chép thu nhập, chi tiêu, chuyển tiền giữa các ví cá nhân, trả dư nợ thẻ tín dụng và đảo bút toán khi hoàn tiền mà không bị tính đúp chi tiêu.
- **Input / Output:** `{ walletId, targetWalletId?, kind, amountMinor, categoryId?, merchant, note, occurredAt, operationId }` → `TransactionEntity` + cập nhật số dư ví nguyên tử.
- **Business rules:** `amountMinor > 0` nguyên đồng VND; `transfer` và `creditCardPayment` không tính vào tổng chi tiêu; `operationId` chống gửi trùng; không sửa/xóa âm thầm giao dịch đã xác nhận mà hỗ trợ đảo bút toán (`reversal`).
- **Events & States:**
  - `TransactionListBloc`: `TransactionsSubscriptionRequested` (`restartable`), `TransactionsMonthChanged` (`restartable`), `TransactionsSearchQueryChanged` (`restartable`), `TransactionsKindFilterChanged` (`restartable`).
  - `TransactionActionBloc`: `TransactionCreateSubmitted` (`sequential`), `WalletCreateSubmitted` (`sequential`), `TransactionReversalRequested` (`sequential`), `ProvisionalDecisionSubmitted` (`sequential`).
- **Firestore Collections:** `users/{uid}/wallets/{walletId}`, `users/{uid}/categories/{categoryId}`, `users/{uid}/transactions/{txId}`.

### 2.3. `budgets` (`MVP-04` — P0)
- **User story:** Người dùng đặt hạn mức ngân sách tháng cho từng danh mục và quản lý quỹ tiết kiệm riêng hoặc quỹ chung gia đình (ghi nhận góp quỹ, đề xuất & phê duyệt chi quỹ).
- **Business rules:** Cảnh báo khi chi tiêu đạt `>= 80%` và vượt `100%` ngân sách; quỹ chung chỉ hiển thị các khoản góp/chi của quỹ, không làm lộ số dư ngân hàng cá nhân của người góp; không duyệt chi vượt số dư sổ sách của quỹ.
- **Events & States (`BudgetBloc`):** `BudgetsStarted` (`restartable`), `BudgetSaved` (`sequential`), `FundCreated` (`sequential`), `FundContributionAdded` (`sequential`), `FundExpenseProposed` (`sequential`), `FundExpenseDecided` (`sequential`).
- **Firestore Collections:** `users/{uid}/budgets/{budgetId}`, `users/{uid}/personal_funds/{fundId}`, `families/{familyId}/funds/{fundId}`, `.../contributions/{id}`, `.../expenses/{id}`.

### 2.4. `family` (`MVP-05` — P0 & P1)
- **User story:** Người dùng tạo nhóm gia đình, tạo mã mời để người thân tham gia, phân công danh sách mua sắm chung và có thể rời gia đình bất cứ lúc nào (thu hồi quyền đọc dữ liệu chung ngay lập tức).
- **Business rules:** Không thành viên nào tự sửa `memberRoles` để tự nâng quyền lên `owner`/`admin`; rời gia đình loại bỏ `uid` khỏi `memberIds`.
- **Events & States (`FamilyBloc`):** `FamilyWatchStarted` (`restartable`), `FamilyActiveChanged` (`restartable`), `FamilyCreateSubmitted` (`sequential`), `FamilyInviteGenerated` (`droppable`), `FamilyJoinByCodeSubmitted` (`sequential`), `FamilyLeaveConfirmed` (`sequential`), `ShoppingItemCreated` (`sequential`), `ShoppingItemStatusToggled` (`sequential`).
- **Firestore Collections:** `families/{familyId}`, `family_invites/{inviteCode}`, `families/{familyId}/shopping_items/{itemId}`.

### 2.5. `calendar` (`MVP-06` — P0)
- **User story:** Người dùng quản lý lịch riêng tư và lịch sự kiện gia đình với cam kết chủ gia đình không bao giờ đọc được sự kiện riêng của thành viên.
- **Business rules:** `PRIVATE_EVENT` lưu tại `users/{uid}/private_events/{id}`; `SHARED_EVENT` lưu tại `families/{familyId}/shared_events/{id}`; `endsAt >= startsAt`.
- **Events & States (`CalendarBloc`):** `CalendarWatchStarted` (`restartable`), `CalendarFilterUpdated` (`restartable`), `CalendarEventCreated` (`sequential`), `CalendarEventDeleted` (`sequential`).

### 2.6. `tasks` (`MVP-07` — P0)
- **User story:** Thành viên giao việc cho người khác trong gia đình; người nhận có quyền Chấp nhận hoặc Từ chối (tránh áp đặt), cập nhật tiến độ và tự động sinh công việc kỳ tiếp theo nếu có lặp định kỳ.
- **Business rules:** Trạng thái `proposed` → `accepted` / `declined` → `in_progress` → `done`; chỉ `assigneeId` được chấp nhận/từ chối lời mời việc.
- **Events & States (`TaskBloc`):** `TasksWatchStarted` (`restartable`), `TaskFilterSelected` (`restartable`), `TaskCreated` (`sequential`), `TaskResponseSubmitted` (`sequential`), `TaskStatusChanged` (`sequential`).
- **Firestore Collections:** `users/{uid}/personal_tasks/{id}`, `families/{familyId}/tasks/{id}`.

### 2.7. `vehicles` (`MVP-08` — P0 & P1)
- **User story:** Người dùng theo dõi hồ sơ phương tiện (xe máy/ô tô), cập nhật số Odometer, lưu lịch sử bảo dưỡng để ứng dụng nhắc hạn theo `min(km đến hạn, ngày đến hạn)` và quản lý hóa đơn định kỳ (điện, nước, internet, gói đăng ký).
- **Business rules:** Odometer mới `>=` Odometer hiện tại; che biển số xe khi chia sẻ gia đình nếu bật `maskPlate`; cảnh báo khi hóa đơn thanh toán tăng `>= 25%` so với trung bình trước đó.
- **Events & States (`VehicleBloc`):** `VehiclesAndBillsStarted` (`restartable`), `VehicleCreated` (`sequential`), `VehicleOdometerLogged` (`sequential`), `MaintenanceLogged` (`sequential`), `RecurringBillAdded` (`sequential`), `RecurringBillPaid` (`sequential`).
- **Firestore Collections:** `users/{uid}/vehicles/{id}`, `families/{familyId}/vehicles/{id}`, `.../maintenances/{id}`, `users/{uid}/bills/{id}`, `families/{familyId}/bills/{id}`.

### 2.8. `notifications` & `dashboard` (`MVP-02`, `MVP-09`, `MVP-10` — P0 & P1)
- **User story:** Người dùng xem bức tranh tổng thể trong tab **Hôm nay**, chủ động cấp/thu hồi quyền đọc thông báo ngân hàng trên Android (lọc OTP, chống trùng lặp, nâng cấp `provisional` → `verified` khi khớp nguồn) và xuất dữ liệu cá nhân.
- **Events & States:** `DashboardBloc` (`DashboardWatchStarted`, `DashboardRefreshed`); `NotificationIngestionBloc` (`NotificationsStarted`, `ConsentToggled`, `BankAlertSimulatedOrReceived`, `PersonalDataExported`).

---

## 3. Definition of Done (Tiêu chí Hoàn thành MVP)
1. 100% mã nguồn tuân thủ **Feature-First Clean Architecture**; `Domain` không import Flutter/Firebase/BLoC; **0 lớp `Cubit`** trong `lib/` (được kiểm tra tự động bằng bài test kiến trúc).
2. Toàn bộ BLoC áp dụng đúng chiến lược `bloc_concurrency` (`sequential` cho thao tác ghi, `restartable` cho stream/filter/search, `droppable` cho thao tác chống nhấn lặp an toàn).
3. `firestore.rules` mặc định `deny all`, bảo vệ chặt dữ liệu riêng tư và phân quyền gia đình, vượt qua toàn bộ bài kiểm thử Security Rules.
4. Toàn bộ Unit Tests, Data/Repository Tests, BLoC Tests, Security Rules Tests, Widget Tests và Integration Tests chạy `PASS` 100%; `flutter analyze` đạt 0 lỗi.
