# TRẠNG THÁI TRIỂN KHAI CHI TIẾT (IMPLEMENTATION STATUS)

> **Cập nhật:** 22/11/2026

## 1. Tổng quan Module Đã Triển khai
- **Nền tảng ứng dụng:** Flutter `3.47.0` / Dart `3.13.0` (`vn.lifeos.app`).
- **Kiến trúc:** Feature-First Clean Architecture (`domain` / `data` / `presentation`), `get_it`, `go_router`, `flutter_bloc` + `bloc_concurrency` (**0% Cubit**).
- **Cơ sở dữ liệu & Bảo mật:** Cloud Firestore + Firebase Auth + `firestore.rules` (đã kiểm thử trên động cơ Cloud Firestore Emulator thật).
- **Thiết kế giao diện:** Hệ thống semantic token “Tammy × Apple” (Light, Dark, High-Contrast WCAG 2.2 AA, Liquid Glass Navigation).
- **Cầu nối Android Native:** `BankNotificationListenerService.kt` + `MainActivity.kt` (chặn OTP ngay trên thiết bị, chỉ lọc ngân hàng trong allowlist).

## 2. Kết quả Kiểm thử & Build
- `flutter analyze`: **0 lỗi, 0 cảnh báo**.
- `flutter test --reporter expanded`: **100% PASS**.
- `firebase emulators:exec --only firestore`: **3/3 kịch bản bảo mật PASS**.
- `flutter build web --release`: **Thành công (`build/web`)**.
- `flutter build apk --debug`: **Thành công (`build/app/outputs/flutter-apk/app-debug.apk`)**.

## 3. Giới hạn Đã Ghi nhận (Known Limitations)
- Việc kết nối vào project Firebase Cloud trực tuyến cần người dùng chạy `firebase login --reauth` để làm mới phiên OAuth CLI đã hết hạn (chi tiết tại `docs/BLOCKED_BY_EXTERNAL_DEPENDENCY.md`).
- Đọc thông báo ngân hàng tự động từ ứng dụng khác chỉ khả dụng trên Android thông qua `NotificationListenerService`; trên iOS hệ điều hành không cung cấp API tương đương nên người dùng sử dụng nhập thủ công hoặc nhập sao kê CSV.
