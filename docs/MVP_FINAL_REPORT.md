# BÁO CÁO BÀN GIAO SẢN PHẨM MVP (MVP FINAL REPORT)

> **Dự án:** **Life OS** — Super App Quản lý Cuộc sống & Gia đình  
> **Trạng thái Bàn giao:** **PARTIALLY COMPLETE** *(100% Mã nguồn Flutter Clean Architecture + BLoC + UI Tammy × Apple + Firestore Security Rules + Emulator/Unit/BLoC/Widget/Integration Tests + Web & Android APK Builds đã hoàn thành và kiểm chứng; duy nhất bước tạo Project trực tuyến trên Google Cloud đang `BLOCKED` chờ người dùng xác thực lại `firebase login --reauth`)*.

---

## 1. Tổng quan Sản phẩm
**Life OS** là ứng dụng quản lý cuộc sống hằng ngày dành cho cá nhân và hộ gia đình tại Việt Nam, hợp nhất **5 trụ cột**: tổng quan Hôm nay, tài chính cá nhân & sổ cái `VND` nguyên đồng, quỹ riêng/quỹ chung gia đình, lịch riêng tư & giao việc đồng thuận, phương tiện/bảo dưỡng & hóa đơn định kỳ, kết hợp nhận diện biến động ngân hàng có kiểm duyệt trên Android theo triết lý **Privacy by Default**.

## 2. Phạm vi MVP & Nâng cấp Chuyên sâu Đã Triển khai (`P0` & `P1`)
- **Hoàn thành trong MVP (`MVP-01` → `MVP-12`):**
  1. Đăng ký/đăng nhập/quên mật khẩu/khôi phục phiên, Onboarding riêng tư, Dashboard Hôm nay & gợi ý thông minh.
  2. **Quản lý Tài chính Cá nhân Chuyên sâu chuẩn SePay Blueprint:** Ví tiền mặt/ngân hàng/thẻ tín dụng, 15 nhóm danh mục đời sống VN (bao gồm *Ăn uống*, *Việc nhà & Gia dụng*, *Nhà cửa & Thuê nhà*, *Điện/Nước/Internet*, *Bảo dưỡng xe*, *Trả nợ*, *Phí ngân hàng*), Sổ giao dịch bất biến (`expense`, `income`, `transfer`, `creditCardPayment`, `reversal`), **Tách hóa đơn đa danh mục (`Split Transaction`)**, **Phân tích Sức khỏe Tài chính** (Dòng tiền ròng, Tỷ lệ tiết kiệm `%`, Chi trung bình/ngày, Độ tin cậy nguồn `VERIFIED`/`USER_CONFIRMED`/`PROVISIONAL`), và **Bộ Phân bổ Thu nhập Thông minh (`IncomeAllocationEngine`)** áp dụng 1 chạm vào Ngân sách tháng.
  3. **3 Mô hình Cộng tác Thực tế (Gia đình · Ở ghép · Hội nhóm) & Bộ Chia Tiền Tối giản Công nợ:** Lựa chọn loại không gian (`family`, `roommates`, `group`), **Chia tiền khoản chung (`SplitBillCalculator`)** cho ăn uống/việc nhà/điện nước/du lịch theo 4 chế độ (*Chia đều* xử lý số lẻ `1 ₫`, *Theo `%`*, *Theo phần `Shares`*, *Số tiền cụ thể `Exact`*), **Thuật toán Tối giản Đồ thị Nợ (`DebtSimplifier`)** rút gọn về tối đa `N - 1` giao dịch kèm mã chuyển khoản chuẩn `SEVQR LIFEOS ...`, và ghi nhận tất toán bất biến (`settlements`).
  4. Quỹ cá nhân & Quỹ chung gia đình, Lịch `PRIVATE_EVENT` / `SHARED_EVENT` & Bận/Rảnh opt-in, Giao việc đồng thuận & lặp định kỳ, Phương tiện (`min(km, ngày)`), Hóa đơn định kỳ (cảnh báo tăng đột biến `>= 25%`), Nhận diện thông báo ngân hàng VN (chặn OTP, nâng cấp `PROVISIONAL` → `VERIFIED`), Nhập CSV khử trùng lặp, Xuất dữ liệu JSON & Tự xóa tài khoản (PDPL 91/2025).
- **Ngoài phạm vi MVP (`P2`/`P3`):** Kết nối đối tác thương mại SePay Bank Hub Hosted Link cần `client_secret` phía server, đọc hộp thư Gmail Restricted Scope, gửi FCM Push từ backend Admin SDK, thực đơn tủ lạnh và trợ lý AI đàm thoại.

## 3. Kiến trúc Đã Triển khai
Áp dụng nghiêm ngặt **Feature-First Clean Architecture**:
- Luồng phụ thuộc một chiều: `Presentation (Widgets + GoRouter + BLoC) → Domain (Pure Dart Entities + UseCases + Repository Interfaces) ← Data (RepositoryImpl + Models + RemoteDataSources) → Firebase / Android Kotlin Platform`.
- Được bảo vệ tự động bởi bài kiểm thử kiến trúc `test/unit/architecture_guard_test.dart`.

## 4. Cấu trúc Thư mục Thực tế
- `lib/main.dart`, `lib/bootstrap.dart`, `lib/firebase_options.dart`
- `lib/app/` (`app.dart`, `app_router.dart`, `app_bloc_observer.dart`, `config/firebase_config.dart`, `theme/*`)
- `lib/core/` (`di/dependency_injection.dart`, `error/*`, `security/bank_notification_parser.dart`, `services/android_notification_bridge.dart`, `usecases/usecase.dart`, `utils/*`, `widgets/status_widgets.dart`)
- `lib/features/` (`authentication`, `dashboard`, `transactions`, `budgets`, `family`, `calendar`, `tasks`, `vehicles`, `notifications`)
- `android/app/src/main/kotlin/vn/lifeos/app/life_os/` (`MainActivity.kt`, `BankNotificationListenerService.kt`)
- `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `.firebaserc`, `firebase/rules_tests/`
- `test/` (`unit/`, `bloc/`, `security/`, `integration/`, `widget/`) & `integration_test/`

## 5. Danh sách 9 Feature Modules
1. `authentication` — Định danh, phiên đăng nhập, khôi phục mật khẩu, khởi tạo không gian riêng & Onboarding.
2. `dashboard` — Trung tâm điều hành Hôm nay & gợi ý tự động hóa liên module.
3. `transactions` — Ví tiền mặt/ngân hàng/thẻ tín dụng, sổ cái `VND`, chuyển ví nội bộ, đảo bút toán & duyệt giao dịch `PROVISIONAL`.
4. `budgets` — Ngân sách tháng theo danh mục & Quỹ tiết kiệm riêng / Quỹ chung gia đình.
5. `family` — Quản trị hộ gia đình, mã mời, phân quyền vai trò, rời gia đình & danh sách mua sắm chung.
6. `calendar` — Lịch cá nhân `PRIVATE_EVENT` cô lập tuyệt đối, lịch chung `SHARED_EVENT` & khung giờ bận opt-in.
7. `tasks` — Giao việc gia đình đồng thuận & tự động sinh kỳ lặp lại.
8. `vehicles` — Hồ sơ xe máy/ô tô, Odometer, lịch bảo dưỡng kép `min(km, ngày)` & hóa đơn định kỳ.
9. `notifications` — Quản lý Consent, cầu nối Android Notification Listener, lọc chặn OTP, nâng cấp `PROVISIONAL` → `VERIFIED` qua cửa sổ trượt chồng lấp, nhập sao kê CSV khử trùng lặp SHA-256, xuất dữ liệu cá nhân JSON & tự xóa tài khoản (PDPL 91/2025).

## 6. Domain Layer
- 100% Pure Dart (0 import `flutter`, `cloud_firestore`, `firebase_auth`, `bloc`).
- Sử dụng Value Object `VndAmount` (số nguyên 64-bit `int` cho đơn vị đồng nguyên `VND`), các Entity bất biến (`Equatable`) và hệ thống UseCase kiểm tra quy tắc nghiệp vụ độc lập hạ tầng.

## 7. Data Layer
- Tách biệt `RemoteDataSource` và `RepositoryImpl` cho từng feature, chuyển đổi `Timestamp` ↔ `DateTime`, theo dõi `doc.metadata.hasPendingWrites` để phản ánh trung thực trạng thái lưu ngoại tuyến, và ánh xạ ngoại lệ qua `ErrorMapper` thành `Failure` có ngữ nghĩa rõ ràng.

## 8. BLoC Implementation (`0% Cubit`)
- Mọi trạng thái nghiệp vụ và giao diện sử dụng `Bloc<Event, State>` (`ThemeBloc`, `AuthBloc`, `DashboardBloc`, `TransactionListBloc`, `TransactionActionBloc`, `BudgetBloc`, `FamilyBloc`, `CalendarBloc`, `TaskBloc`, `VehicleBloc`, `NotificationIngestionBloc`).
- Áp dụng `bloc_concurrency`: `restartable()` cho các luồng lắng nghe realtime/tìm kiếm, `sequential()` kết hợp khóa lũy đẳng `operationId` cho mọi giao dịch tài chính và thay đổi dữ liệu, `droppable()` chống gửi lặp yêu cầu đăng nhập/xuất dữ liệu.

## 9. Firebase Project ID & Trạng thái Kết nối
- **Cấu hình Emulator mặc định sẵn sàng chạy ngay:** `demo-life-os` (`Auth: 127.0.0.1:9199`, `Firestore: 127.0.0.1:8188`).
- **Cấu hình Cloud thật:** Đọc linh hoạt qua `--dart-define=FIREBASE_PROJECT_ID=...` hoặc tệp sinh từ `flutterfire configure`.

## 10. Firestore Collections
- Không gian riêng `/users/{userId}`: `wallets`, `categories`, `transactions`, `budgets`, `personal_funds` (`contributions`, `expenses`), `private_events`, `personal_tasks`, `vehicles` (`maintenances`), `bills`, `consents`, `source_events`.
- Không gian chung `/families/{familyId}` (`spaceType`: `family` | `roommates` | `group`) & `/family_invites/{inviteCode}`: `funds` (`contributions`, `expenses`), `split_bills`, `settlements`, `shared_events`, `availability`, `tasks`, `vehicles` (`maintenances`), `bills`, `shopping_items`.

## 11. Security Rules (`firestore.rules`)
- Mặc định từ chối toàn bộ (`allow read, write: if false;`), không tồn tại quy tắc `if true`.
- Ngăn chặn tuyệt đối đọc chéo tài khoản và ngăn chủ gia đình xem `private_events` hoặc ví riêng của thành viên; cấm xóa cứng giao dịch (`allow delete: if false`); chống tự nâng quyền lên `owner`/`admin` khi tham gia bằng mã mời; thu hồi quyền đọc ngay khi rời gia đình.

## 12. Authentication
- Tích hợp `FirebaseAuth` (Email/Password Sign-up, Sign-in, Password Reset, Sign-out, khôi phục phiên tức thì qua `watchUser()`), điều phối tập trung bởi `AuthBloc` và bảo vệ điều hướng bằng `GoRouter` redirect guard.

## 13. UI/UX (“Tammy × Apple” Design System) & Bộ Nhận diện Hình ảnh Nano Banana
- Áp dụng đầy đủ token màu semantic Light (`#0B7A2A` / `#F2F2F7` / `#FFFFFF`) & Dark (`#19C23E` / `#000000` / `#1C1C1E`) + chế độ High Contrast WCAG 2.2 AA từ `a.docx`.
- **Splash Screen Đa tầng & Bộ 19 Tài nguyên Hình ảnh/Icon từ Nano Banana (`assets/images/`, Android `mipmap-*`, Web PWA Icons):**
  - Màn hình khởi động Flutter `SplashPage` (`/splash`), Native Android Launch Splash (`@drawable/launch_logo`) và Native Web CSS Splash (`web/index.html` tự mờ dần khi nhận `flutter-first-frame`).
  - Tích hợp đồng bộ `logo_life_os.png`, `splash_hero.png`, `auth_hero.png`, `onboarding_privacy.png`, `dashboard_banner.png`, `finance_illustration.png`, `family_split_illustration.png` và `planning_assets_illustration.png` xuyên suốt toàn bộ 5 phân hệ và các trạng thái trống (`EmptyStateView`).
- Hiệu ứng Liquid Glass (`BackdropFilter`) đặt chuẩn xác ở thanh điều hướng và Bottom Bar; thẻ nội dung dùng nền đặc, vùng chạm `>= 44 pt`, luôn kèm biểu tượng + văn bản cho mọi nhãn trạng thái, hỗ trợ Adaptive Layout (`NavigationBar` trên điện thoại & `NavigationRail` có gắn `BrandLogoMark` trên màn hình rộng).

## 14. Kết quả Kiểm thử (`docs/TEST_REPORT.md`)
- `flutter analyze`: **`No issues found!`**
- `flutter test --reporter expanded`: **`21/21 All tests passed!`** (Unit, Architecture Guard, BLoC Concurrency, Split Transactions, Personal Analytics & Income Allocation, 3-Mode Family/Roommates/Group Bill Splitting & Debt Simplification, Security, Vertical Slice Integration, Nano Banana Splash & Full Widget Flow).
- Cloud Firestore Emulator Security Rules (`run_emulator_rules_tests.mjs`): **`3/3 suites PASS`**.

## 15. Kết quả Build Thực tế
- **Web Production Release (`flutter build web --release`):** Thành công (`build/web`).
- **Android Debug APK (`flutter build apk --debug`):** Thành công (`build/app/outputs/flutter-apk/app-debug.apk`, ~160.5 MB, biên dịch trọn vẹn cả Kotlin `BankNotificationListenerService`).

## 16. Các Lỗi Đã Phát hiện & Sửa chữa
1. Sửa `FirebaseAuthRemoteDataSource.watchUser()` phát giá trị `_firebaseAuth.currentUser` đồng bộ ngay khi lắng nghe để khôi phục phiên tức thì sau khi khởi động lại app.
2. Bổ sung `isExpanded: true` cho mọi `DropdownButtonFormField` và dùng `Wrap` thích ứng trên thẻ tổng quan/đăng nhập, xử lý triệt để lỗi tràn ngang `RenderFlex`.
3. Thêm `kotlin.incremental=false` vào `android/gradle.properties` để khắc phục lỗi biên dịch Kotlin đa ổ đĩa trên Windows (`C:\` Pub Cache và `G:\` Workspace).
4. Đổi cổng Firestore Emulator sang `8188` (thay vì `8080` đang bận trên máy host).
5. Nâng cấp thuật toán khử trùng lặp liên nguồn lên cửa sổ trượt chồng lấp (`computeOverlappingSoftWindowFingerprints`) xử lý chính xác các giao dịch vắt qua mốc phút `:00/:15/:30/:45`.

## 17. Các Blocker Bên ngoài Còn Tồn tại
1. **Tạo/liên kết Firebase Cloud Project trực tuyến (`BLOCKED` bởi phiên Google OAuth hết hạn):** Lệnh `firebase projects:list` trên tài khoản `danhhoa200005@gmail.com` trả về `HTTP 401 Unauthenticated` (`oauth2/v3/token` trả `400`). Người dùng chỉ cần chạy `firebase login --reauth` trên trình duyệt rồi chạy `flutterfire configure` để nối thẳng vào Cloud thật.
2. **Kết nối thương mại trực tiếp SePay Bank Hub / Gmail Restricted Scope:** Thuộc nhóm tích hợp đối tác bên ngoài cần hợp đồng merchant, `client_secret` lưu trên backend riêng và xác minh OAuth của Google.

## 18. Giới hạn của Gói Firebase Spark (Miễn phí)
- Hạn mức đọc/ghi hằng ngày của Cloud Firestore Spark (50.000 lượt đọc, 20.000 lượt ghi/ngày): ứng dụng đã tối ưu bằng truy vấn theo tháng (`monthKey`), giới hạn `limit(100)` và hủy toàn bộ listener ngay khi đóng BLoC.
- Gói Spark không bao gồm Cloud Functions có kết nối mạng ra ngoài (cần gói Blaze nếu sau này triển khai webhook nhận IPN trực tiếp từ SePay trên hạ tầng Firebase).

## 19. Hướng dẫn Chạy Ứng dụng
- **Chạy ngay tại máy cục bộ với Firebase Emulator:**
  1. Terminal 1: `firebase emulators:start --only auth,firestore --project demo-life-os`
  2. Terminal 2: `flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true`
- **Chạy với Firebase Cloud thật sau khi đăng nhập lại CLI:**
  1. `firebase login --reauth`
  2. `flutterfire configure --project=<YOUR_PROJECT_ID>`
  3. `firebase deploy --only firestore:rules,firestore:indexes --project <YOUR_PROJECT_ID>`
  4. Bật Email/Password trên Firebase Console → `flutter run`

## 20. Lộ trình Phát triển Tiếp theo (Post-MVP)
1. Hoàn tất đăng nhập `firebase login --reauth` để gắn project Firebase Spark thật cho môi trường dev/staging.
2. Bổ sung dịch vụ Trusted Backend nhỏ (khi có hợp đồng đối tác SePay) để nhận Bank Hub IPN và đẩy vào Firestore qua Admin SDK.
3. Mở rộng nhập sao kê CSV có giao diện ánh xạ cột trực quan, đồng bộ lịch Google Calendar OAuth phạm vi tối thiểu và thông báo nhắc hạn cục bộ (`flutter_local_notifications`).
