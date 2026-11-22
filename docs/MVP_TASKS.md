# KẾ HOẠCH TRIỂN KHAI TỔNG THỂ 15 GIAI ĐOẠN (MASTER TASK LIST)

> **Cập nhật cuối:** 22/11/2026 — Hoàn tất triển khai, kiểm thử tự động, kiểm thử Emulator Security Rules và biên dịch Web + Android APK.

| Task ID | Giai đoạn / Feature | Ưu tiên | Phụ thuộc | Trạng thái | Bằng chứng Hoàn thành Thực tế |
| --- | --- | :---: | --- | :---: | --- |
| **T-01** | PHASE 1–3: Audit, MVP Spec & Clean Architecture Design | `P0` | — | `DONE` | Đầy đủ tài liệu tại `docs/PROJECT_AUDIT.md`, `PRODUCT_REQUIREMENTS.md`, `USER_FLOWS.md`, `MVP_SCOPE.md`, `ARCHITECTURE.md`, `DECISIONS.md` |
| **T-02** | PHASE 4: Flutter Foundation, Design System Tammy × Apple & Core | `P0` | `T-01` | `DONE` | `lib/core/`, `lib/app/theme/` (`TammySemanticColors`, `ThemeBloc`), `domain_and_parser_test.dart` PASS |
| **T-03** | PHASE 5: Dependency Injection (`get_it`) & Routing (`go_router`) | `P0` | `T-02` | `DONE` | `lib/core/di/dependency_injection.dart`, `lib/app/app_router.dart`, `app_widget_test.dart` PASS |
| **T-04** | PHASE 6: Firebase Cloud Provisioning & FlutterFire Config | `P0` | `T-02` | `BLOCKED` *(Chỉ phần gọi API tạo project Google Cloud)* | `firebase.json`, `.firebaserc`, `lib/firebase_options.dart`, `lib/app/config/firebase_config.dart` đã hoàn tất. Lệnh `firebase projects:list` trả `HTTP 401` do OAuth token CLI của `danhhoa200005@gmail.com` hết hạn, cần người dùng chạy `firebase login --reauth` |
| **T-05** | PHASE 7: Firestore Schema & Security Rules | `P0` | `T-04` | `DONE` | `firestore.rules`, `firestore.indexes.json`, `docs/FIRESTORE_SCHEMA.md`, vượt qua `3/3` bài test trên Cloud Firestore Emulator thật (`task-377`) |
| **T-06** | PHASE 8: Feature `authentication` (Domain + Data + `AuthBloc` + UI) | `P0` | `T-03`, `T-05` | `DONE` | `lib/features/authentication/**`, `all_feature_blocs_test.dart` & `app_widget_test.dart` PASS |
| **T-07** | PHASE 9A: Feature `transactions` (Ví, Danh mục, Sổ cái, Chuyển ví, Đảo bút toán) | `P0` | `T-06` | `DONE` | `lib/features/transactions/**`, `bloc_concurrency_and_state_test.dart` & `mvp_vertical_slice_test.dart` PASS |
| **T-08** | PHASE 9B: Feature `budgets` (Ngân sách Tháng & Quỹ Riêng/Chung) | `P0` | `T-07` | `DONE` | `lib/features/budgets/**`, `mvp_vertical_slice_test.dart` & `all_feature_blocs_test.dart` PASS |
| **T-09** | PHASE 9C: Feature `family` (Nhóm Gia đình, Mã mời, Vai trò, Mua sắm & Rời nhóm) | `P0`/`P1` | `T-06` | `DONE` | `lib/features/family/**`, kiểm chứng cô lập & thu hồi quyền trên Firestore Emulator PASS |
| **T-10** | PHASE 9D: Features `calendar` & `tasks` (Lịch Riêng/Chung & Giao việc Đồng thuận) | `P0` | `T-09` | `DONE` | `lib/features/calendar/**`, `lib/features/tasks/**`, `mvp_vertical_slice_test.dart` PASS |
| **T-11** | PHASE 9E: Feature `vehicles` (Phương tiện, Odometer, Bảo dưỡng & Hóa đơn Định kỳ) | `P0`/`P1` | `T-07` | `DONE` | `lib/features/vehicles/**`, `domain_and_parser_test.dart` & `all_feature_blocs_test.dart` PASS |
| **T-12** | PHASE 9F & 10: Features `notifications` + `dashboard` + Android Native Listener | `P0`/`P1` | `T-07`..`T-11` | `DONE` | `lib/features/notifications/**`, `lib/features/dashboard/**`, `BankNotificationListenerService.kt`, `MainActivity.kt` biên dịch thành công vào APK |
| **T-13** | PHASE 11–13: Offline Indicator, Architecture Guard, Security, BLoC, Widget & Integration Tests | `P0` | `T-12` | `DONE` | `flutter test` (`17/17 PASS`), `architecture_guard_test.dart` (`0 Cubit`), Emulator Rules (`3/3 PASS`) |
| **T-14** | PHASE 14–15: Tối ưu Hiệu năng, Build (`web` & `apk`), Final Audit & Báo cáo | `P0` | `T-13` | `DONE` | `flutter analyze` (`No issues found`), `build/web` thành công, `build/app/outputs/flutter-apk/app-debug.apk` thành công, xuất bản `TEST_REPORT.md` & `MVP_FINAL_REPORT.md` |
