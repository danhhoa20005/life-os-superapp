# BÁO CÁO KIỂM THỬ TỰ ĐỘNG & XÁC MINH CHẤT LƯỢNG (TEST REPORT)

> **Ngày thực thi:** 22/11/2026  
> **Môi trường:** Flutter `3.47.0` (stable), Dart `3.13.0`, JDK `21.0.10`, Firebase CLI `15.27.0` (`cloud-firestore-emulator-v1.22.0.jar`)

---

## 1. Tổng hợp Kết quả Chạy Kiểm thử Thực tế

| Hạng mục Kiểm tra | Lệnh thực thi | Kết quả | Chi tiết xác minh |
| --- | --- | :---: | --- |
| **Static Analysis & Lints** | `flutter analyze` | **PASS (`0 issues`)** | Bật `strict-casts: true`, `strict-raw-types: true`, `cancel_subscriptions`, `close_sinks`. |
| **Architecture & BLoC-Only Guard** | `test/unit/architecture_guard_test.dart` | **PASS (`5/5`)** | 0 lớp `Cubit` trong `lib/`, 0 import Flutter/Firebase/BLoC trong `domain/`, 0 import Firebase SDK trong `presentation/`, 0 phụ thuộc chéo giữa các BLoC. |
| **Domain, Personal Analytics, Income Allocator & Bill Splitting** | `test/unit/domain_and_parser_test.dart` | **PASS (`6/6`)** | `VndAmount` nguyên đồng, **Split Transaction** đa danh mục (*Ăn uống* + *Việc nhà*), Tỷ lệ tiết kiệm `%`, **IncomeAllocationEngine** (Cá nhân/Gia đình/Ở ghép không lệch `1 ₫`), **SplitBillCalculator** & **DebtSimplifier** tối giản công nợ kèm mã `SEVQR`, chặn 100% OTP, quy tắc `accumulated=0` (T15), phân biệt mã tham chiếu (T06), bảo dưỡng `min(km, ngày)`, che biển số, quyền nhận việc `assignee`. |
| **BLoC Event → State & Concurrency** | `test/bloc/bloc_concurrency_and_state_test.dart` & `all_feature_blocs_test.dart` | **PASS (`4/4`)** | Kiểm tra `ThemeBloc`, `TransactionActionBloc` (`sequential` + kiểm tra tổng dòng tách khoản `splitLines`), `FamilyBloc` (chia tiền chung + tất toán `SEVQR`), toàn bộ 9 feature BLoCs và Cold Restart Persistence. |
| **Security Rules (Local Dart)** | `test/security/firestore_rules_test.dart` | **PASS (`3/3`)** | Kiểm tra bất biến `firestore.rules` (default deny, không có `if true`, chống xóa cứng giao dịch & `settlements`, bảo vệ `split_bills`, chống tự nâng quyền) và cô lập đường dẫn `users/{uid}`. |
| **Security Rules (Real Firebase Emulator)** | `firebase emulators:exec --only firestore --project demo-life-os "node firebase/rules_tests/run_emulator_rules_tests.mjs"` | **PASS (`3/3`)** | Thực thi trên động cơ Java Cloud Firestore Emulator thật: từ chối `403` khách chưa đăng nhập, chặn chủ gia đình đọc `private_events`/ví riêng, chặn xóa cứng giao dịch & bản ghi tất toán `settlements`, chặn người ngoài đọc `split_bills`, chặn tự nâng quyền `owner` và thu hồi quyền ngay khi rời nhóm. |
| **Vertical Slice Integration** | `test/integration/mvp_vertical_slice_test.dart` | **PASS (`1/1`)** | Luồng tích hợp đầy đủ: Đăng ký → Ví → Chi tiêu (`operationId`) → Chuyển ví → Đảo bút toán → Thông báo ngân hàng → Nâng cấp `PROVISIONAL` → `VERIFIED` → **Split Transaction cập nhật đồng thời 2 Ngân sách danh mục (*Ăn uống* & *Việc nhà*)** → **Gia đình/Ở ghép chia hóa đơn theo `%` & mã mời** → Quỹ chung → Công việc lặp → Xuất JSON & Xóa tài khoản PDPL. |
| **UI, Splash Screen, Nano Banana Assets & Routing Widget Test** | `test/widget/app_widget_test.dart` | **PASS (`2/2`)** | Xác minh toàn bộ 8 tệp hình ảnh Nano Banana trong `assets/images/`, render `SplashPage` (`/splash`), và kiểm thử luồng `LifeOsApp` thật: Auth Guard `/login` → Đăng ký → Onboarding → Shell 5 tab Tammy × Apple → Ghi giao dịch `-85.000 ₫` → Mở tab **Phân tích & Bộ Chia Thu nhập** → Chuyển sang **Gia đình & Hội nhóm**, tạo không gian Ở ghép và ghi nhận **Chia khoản mới (*Ăn tối & Nước lau nhà*)** không tràn khung hình (`0 RenderFlex overflow`). |
| **Production Web Build** | `flutter build web --release` | **PASS** | Sinh thành công `build/web` (tree-shake MaterialIcons giảm 98.9%). |
| **Android Debug APK Build** | `flutter build apk --debug` | **PASS** | Biên dịch thành công cả mã Kotlin `BankNotificationListenerService.kt` + `MainActivity.kt` ra `build/app/outputs/flutter-apk/app-debug.apk` (~160.5 MB). |

---

## 2. Các Lỗi Đã Phát hiện và Khắc phục Trong Quá trình QA
1. **Khôi phục phiên đăng nhập tức thì khi khởi động lại (`FirebaseAuthRemoteDataSource.watchUser`):** Phát hiện qua bài test Cold Restart rằng stream cần phát giá trị đồng bộ `_firebaseAuth.currentUser` ngay thời điểm đăng ký lắng nghe trước khi nối tiếp `authStateChanges()`. Đã sửa bằng `Stream.multi` và kiểm thử đạt 100%.
2. **Tràn ngang giao diện (`RenderFlex overflow`) trên màn hình hẹp / phông chữ lớn:** Phát hiện qua `app_widget_test.dart` trên `DropdownButtonFormField` và hàng tiêu đề thẻ. Đã bổ sung `isExpanded: true` cho toàn bộ dropdown và chuyển sang `Wrap` thích ứng, loại bỏ 100% lỗi tràn khung hình.
3. **Xung đột ổ đĩa Windows khi biên dịch Kotlin Gradle (`C:\` Pub Cache vs `G:\` Project):** Phát hiện khi chạy `flutter build apk --debug` (`IllegalArgumentException: this and base files have different roots`). Đã khắc phục triệt để bằng `kotlin.incremental=false` trong `android/gradle.properties`.
4. **Xung đột cổng `8080` trên máy phát triển:** Phát hiện cổng `8080` đang bận khi khởi chạy Firestore Emulator; đã chuyển cấu hình Emulator sang bộ cổng sạch (`firestore: 8188`, `auth: 9199`, `ui: 4100`) đồng bộ giữa `firebase.json` và `firebase_config.dart`.
5. **Khử trùng lặp xuyên qua ranh giới khung giờ `:00/:15/:30/:45` (`computeOverlappingSoftWindowFingerprints`):** Phát hiện khi thông báo Android đến lúc `17:29:45` và sự kiện đối soát đến lúc `17:30:45` (cách nhau 60 giây nhưng vắt qua mốc `:30`). Đã nâng cấp lên thuật toán cửa sổ trượt chồng lấp 3 bucket liền kề kèm kiểm tra khoảng cách thời gian tuyệt đối `<= 15 phút`, đảm bảo nâng cấp `PROVISIONAL` → `VERIFIED` chính xác 100% ở mọi thời điểm.
