# HƯỚNG DẪN THIẾT LẬP & KẾT NỐI FIREBASE CLOUD / EMULATOR (FIREBASE SETUP)

**Phiên bản:** 1.0 | **Cập nhật:** 22/11/2026 | **Chi phí cam kết:** **0 ₫ (Firebase Spark Plan)**

---

## 1. Hiện trạng Công cụ Chính thức trên Môi trường Phát triển

Đã kiểm tra và kích hoạt đầy đủ toàn bộ bộ công cụ chính thức trên Windows 11 (`g:\superapp`):

| Công cụ / SDK | Phiên bản Thực tế | Đường dẫn / Cấu hình | Trạng thái |
| --- | --- | --- | :---: |
| **Flutter SDK / Dart SDK** | Flutter `3.47.0` / Dart `3.13.0` | `C:\src\flutter\bin\flutter.bat` | **HOẠT ĐỘNG** |
| **Node.js / npm** | Node `v24.11.1` / npm `11.6.2` | `C:\Program Files\nodejs\node.exe` | **HOẠT ĐỘNG** |
| **Firebase CLI (`firebase-tools`)** | `15.27.0` | `firebase` (toàn cục) | **HOẠT ĐỘNG** |
| **FlutterFire CLI (`flutterfire_cli`)** | `1.5.0` | `C:\Users\ADMIN\AppData\Local\Pub\Cache\bin\flutterfire.bat` | **ĐÃ CÀI & KÍCH HOẠT** |
| **JDK / Android SDK** | JDK `21.0.10` / Android SDK `36.1.0` | Package ID: `vn.lifeos.app.life_os` | **HOẠT ĐỘNG** |
| **iOS Bundle ID** | `vn.lifeos.app` | `ios/Runner` | **ĐÃ KHAI BÁO** |
| **Firebase Packages (`pubspec.yaml`)** | `firebase_core ^5.2.0`, `firebase_auth ^7.1.0`, `cloud_firestore ^7.2.0`, `google_sign_in ^7.2.0` | Xác thực Email + Google OAuth 2.0 trọn bộ, 0 SDK trả phí | **ĐÃ TÍCH HỢP** |
| **Firebase Local Emulator Suite** | Auth (`9199`), Firestore (`8188`), UI (`4100`) | `firebase.json` + `.firebaserc` | **ĐÃ XÁC MINH 100%** |

---

## 2. Chế độ 1: Chạy Ngay Lập tức với Firebase Local Emulator Suite (Offline / 0 ₫)

1. Mở Terminal 1 tại `g:\superapp`:
   ```powershell
   firebase emulators:start --only auth,firestore --project demo-life-os
   ```
   - Giao diện quản trị Emulator UI tự mở tại: `http://127.0.0.1:4100`
2. Mở Terminal 2 khởi chạy ứng dụng Flutter:
   ```powershell
   flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
   ```

---

## 3. Chế độ 2: Kết nối & Triển khai Lên Firebase Cloud Thật (Gói Spark Miễn phí)

Hiện tại tài khoản `danhhoa200005@gmail.com` trong Firebase CLI có refresh token Google OAuth đã hết hạn (`POST oauth2/v3/token` trả `400`, `firebase projects:list` trả `401`). Ngay khi làm mới đăng nhập trên trình duyệt, bạn có thể chạy **kịch bản tự động hóa trọn gói 1 lệnh** đã được viết sẵn:

### Cách A — Chạy Script Tự động Hóa 1 Lệnh (Khuyến nghị)
```powershell
powershell -ExecutionPolicy Bypass -File firebase/provision_and_deploy_cloud.ps1
```
Script này tự động thực hiện tuần tự **9 bước khép kín**:
1. Gọi `firebase login --reauth` (nếu phiên hết hạn) để bạn bấm xác nhận Google chính thức trên trình duyệt.
2. Tạo mới Firebase Project gói **Spark 0 ₫** (`life-os-vn-xxxx`, không gắn thẻ/billing) nếu chưa có project `life-os*`.
3. Gắn `.firebaserc` (`firebase use <PROJECT_ID>`).
4. Khởi tạo **Cloud Firestore Standard `(default)`** tại vùng **`asia-southeast1` (Singapore)**.
5. Chạy `flutterfire configure --project=<PROJECT_ID> --platforms=android,ios,web --android-package-name=vn.lifeos.app.life_os --ios-bundle-id=vn.lifeos.app --out=lib/firebase_options.dart --yes`.
6. Tự động trích xuất và đăng ký chứng chỉ ký số Android **`SHA-1` (`43:40:45:30:21:A1:43:2C:98:6F:35:EB:68:79:0E:6F:13:CB:3D:44`)** & **`SHA-256`** lên Firebase Android App, sau đó tải lại `android/app/google-services.json` chứa đầy đủ `oauth_client` cho **Google Sign-In**.
7. Tự động kích hoạt **Identity Toolkit API (`Email/Password`)** qua REST API.
8. Deploy bảo mật: `firebase deploy --only firestore --project <PROJECT_ID>` (chỉ đẩy `firestore.rules` và `firestore.indexes.json`, không đẩy Functions/Storage).
9. Build bản **`app-release.apk` (`arm64-v8a`) kết nối Cloud thật 100%** (không qua Emulator) và tự động cài + mở ngay trên điện thoại **OPPO (`AATSFI85TK79W8DM`)**!

### Cách B — Bật Google Sign-In Provider & Chạy Kiểm thử Cloud Thật
1. Mở trang cấu hình Authentication chính thức của Project vừa tạo:
   `https://console.firebase.google.com/project/<PROJECT_ID>/authentication/providers` → Bật **Email/Password** và **Google** (chọn email hỗ trợ dự án) → **Save**.
2. Chạy bài kiểm thử CRUD & phân quyền trực tiếp trên Firebase Cloud thật:
   ```powershell
   node firebase/verify_live_cloud_crud.mjs
   ```
3. Khởi chạy ứng dụng Flutter kết nối thẳng Cloud thật (`FirebaseConfig.shouldUseEmulator` tự chuyển sang `false` ngay khi `lib/firebase_options.dart` mang `projectId` thật!):
   ```powershell
   flutter run -d chrome
   ```

---

## 4. Khôi phục Môi trường Phát triển trên Máy Mới
```powershell
git clone <repo_url> superapp
cd superapp
flutter pub get
dart pub global activate flutterfire_cli
npm install -g firebase-tools
flutter analyze
flutter test --reporter expanded
firebase emulators:exec --only auth,firestore --project demo-life-os "node firebase/rules_tests/run_full_emulator_e2e.mjs"
```
