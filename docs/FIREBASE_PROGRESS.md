# NHẬT KÝ TIẾN ĐỘ TÍCH HỢP FIREBASE & TRIỂN KHAI THIẾT BỊ (FIREBASE PROGRESS)

**Cập nhật gần nhất:** 22/11/2026 18:54 GMT+07:00

## 1. Các Hạng mục Đã Hoàn thành & Xác minh (`DONE`)
- [x] **Công cụ chính thức:** Xác minh Flutter `3.47.0`, Dart `3.13.0`, Node `v24.11.1`, Firebase CLI `15.27.0`; cài đặt mới và kích hoạt thành công `flutterfire_cli 1.5.0`.
- [x] **Kiến trúc & Bảo mật Spark 0 ₫:**
  - Hoàn thiện `FirebaseConfig` khởi tạo an toàn, bật lưu trữ ngoại tuyến (`persistenceEnabled: true`).
  - Bổ sung abstraction `FileStorageService` + `SparkSafeFileStorageService` (`PHẦN 11`), cam kết không tự nâng cấp gói Blaze và không lưu nhị phân lớn vào Firestore.
  - Hoàn thiện `firestore.rules` (mặc định từ chối, cô lập `/users/{uid}`, bất biến `transactions` & `settlements`, chống tự nâng quyền `owner`/`admin` khi vào nhóm) và `firestore.indexes.json`.
- [x] **Kiểm thử Tự động Toàn diện (`100% PASS`):**
  - `run_full_emulator_e2e.mjs` trên **Firebase Auth Emulator (`9199`) + Cloud Firestore Emulator (`8188`)**: Đạt tuyệt đối **15/15 kịch bản** (`3/3 suites PASS`).
  - `flutter test --reporter expanded`: Đạt **`21/21` bài kiểm thử**.
  - Build thành công cả **Web Release (`build/web`)** và **Android APK (`app-debug.apk`)**.
- [x] **Kịch bản tự động hóa Cloud:** Đã đóng gói sẵn `firebase/provision_and_deploy_cloud.ps1` và `firebase/verify_live_cloud_crud.mjs`.

## 2. Đã Hoàn tất Cài đặt Thực tế Trên Máy OPPO & Trạng thái Cloud
- [x] **[DONE] Cài đặt & mở trực tiếp trên máy OPPO `CPH2001` (`AATSFI85TK79W8DM`):**
  - Biên dịch bản `app-release.apk` (`25.1 MB`, tối ưu riêng chip `arm64-v8a` mượt 60 FPS, tích hợp đầy đủ Logo, Launcher Icon, Native Splash & 8 minh họa Nano Banana).
  - Cài đặt thành công (`Performing Streamed Install -> Success`), khởi chạy `vn.lifeos.app.life_os/.MainActivity` ngay trên màn hình máy OPPO.
  - Duy trì song song 2 dịch vụ nền: **Firebase Auth + Firestore Server (`9199` / `8188`, lưu bền vào `./firebase/emulator_data`)** và **ADB USB Reverse Tunnel** để mọi tài khoản, giao dịch, tách khoản và chia tiền tạo trên máy OPPO đều được lưu bền vững.
- [ ] **[BLOCKED — Chờ xác thực trình duyệt Google 1 bước] Tạo Project trên Firebase Cloud trực tuyến:**
  - Refresh token của `danhhoa200005@gmail.com` đã hết hạn (`HTTP 401 Unauthenticated`). Khi muốn chuyển từ máy chủ cục bộ lên Google Cloud thật (gói Spark 0 ₫, vùng Singapore `asia-southeast1`), chỉ cần chạy `powershell -ExecutionPolicy Bypass -File firebase/provision_and_deploy_cloud.ps1`.
