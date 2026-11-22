# NGỮ CẢNH KHÔI PHỤC TỰ ĐỘNG (AI CONTEXT PERSISTENCE)

## 1. Trạng thái Hiện tại
- **Trạng thái tổng thể:** Hoàn tất toàn bộ mã nguồn, kiểm thử tự động, kiểm thử Firestore Emulator Security Rules, build Web Release và build Android Debug APK (`PARTIALLY COMPLETE` duy nhất ở bước tạo project trực tuyến trên Google Cloud do cần người dùng xác thực lại `firebase login --reauth`).
- **Kiểm chứng mới nhất:**
  - `flutter analyze` → `No issues found!`
  - `flutter test --reporter expanded` → `17/17 All tests passed!`
  - `firebase emulators:exec --only firestore --project demo-life-os "node firebase/rules_tests/run_emulator_rules_tests.mjs"` → `3/3 PASS`
  - `flutter build web --release` → `build/web` OK
  - `flutter build apk --debug` → `build/app/outputs/flutter-apk/app-debug.apk` OK

## 2. Lưu ý Cấu hình Quan trọng
- Cổng Firebase Local Emulator trong `firebase.json` và `lib/app/config/firebase_config.dart`: Auth `9199`, Firestore `8188`, UI `4100` (tránh xung đột cổng `8080` trên máy Windows hiện tại).
- `android/gradle.properties` đã bật `kotlin.incremental=false` để biên dịch ổn định khi Pub Cache ở ổ `C:\` và dự án ở ổ `G:\`.

## 3. Bước Tiếp theo Khi Người dùng Đăng nhập Lại Firebase CLI
Chạy `firebase login --reauth`, tạo/chọn project Spark miễn phí, chạy `flutterfire configure --project=<PROJECT_ID>` và `firebase deploy --only firestore:rules,firestore:indexes`.
