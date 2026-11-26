# Hướng dẫn Chuyển đổi Chữ ký Release & Xoay vòng Khóa (Android Signing Migration)

**Tài liệu liên quan:** `android/app/build.gradle.kts`, `android/signing/expected_certs.json`, `scripts/verify_apk_signature.ps1`, `scripts/verify_apk_signature.sh`, `.github/workflows/ci.yml`  
**Tài liệu chính thức Android:** https://developer.android.com/studio/publish/app-signing

---

## 1. Bối cảnh & Nguyên nhân gốc rễ

Các bản APK phát hành công khai trước đây (`v3.26.0` và `v3.27.0`) bị ký bằng chứng chỉ **Android Debug** mặc định trên máy phát triển:
- **Subject DN:** `C=US, O=Android, CN=Android Debug`
- **Certificate SHA-256:** `3c1738043f4ed47e6f5f5724ab3e9fd0b24e89fde667af43670cb630e4d5176b`
- **Certificate SHA-1:** `4340453021a1432c986f35eb68790e6f13cb3d44`

Vì Android `PackageManager` khóa danh tính ứng dụng (`vn.lifeos.app.life_os`) theo chứng chỉ ký số, một thiết bị đang cài đặt `v3.26.0` hoặc `v3.27.0` (ký bằng debug key) **không thể cập nhật đè tại chỗ (in-place update)** lên bản APK ký bằng khóa Release mới (sẽ gặp lỗi `INSTALL_FAILED_UPDATE_INCOMPATIBLE`), **trừ khi** sử dụng cơ chế xoay vòng khóa **APK Signature Scheme v3** (`apksigner rotate` tạo `SigningCertificateLineage` từ chứng chỉ debug cũ sang chứng chỉ release mới).

> **CẢNH BÁO BẢO MẬT QUAN TRỌNG — TUYỆT ĐỐI KHÔNG TÁI SỬ DỤNG DEBUG KEY:**
> Không bao giờ dùng `~/.android/debug.keystore` hoặc khóa `CN=Android Debug` làm khóa phát hành sản phẩm (GitHub OTA hay Google Play). Debug key có mật khẩu chuẩn công khai (`android`), không có cơ chế bảo quản khóa sản xuất, và Google Play Console / script kiểm duyệt phát hành của LifeOS (`verify_apk_signature.*`, `expected_certs.json`) từ chối vĩnh viễn mọi gói APK mang `CN=Android Debug`.

---

## 2. Giới hạn Hệ điều hành: API 28+ (Android 9+) so với API 24–27 (Android 7.0–8.1)

| Nhóm thiết bị | Khả năng nâng cấp từ `v3.26.0` / `v3.27.0` | Hành động bắt buộc |
|---|---|---|
| **Android 9 trở lên (API 28+)** | Hỗ trợ **APK Signature Scheme v3** và `SigningCertificateLineage` (`apksigner rotate`). Có thể nâng cấp tại chỗ **nếu và chỉ nếu** APK mới mang `lineage` hợp lệ nối từ chứng chỉ cũ sang chứng chỉ Release mới. | Nếu triển khai v3 lineage cho kênh GitHub OTA: giữ nguyên dữ liệu cục bộ khi nâng cấp đè. Nếu phát hành không kèm lineage (hoặc cài từ Google Play App Signing): phải sao lưu trước rồi gỡ cài đặt bản cũ. |
| **Android 7.0 – 8.1 (API 24–27)** | **KHÔNG hỗ trợ** APK Signature Scheme v3 key rotation (chỉ kiểm tra v1/v2 signer). Nâng cấp đè bằng khóa mới chắc chắn thất bại với `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. | **Bắt buộc gỡ cài đặt bản cũ và cài mới**. Người dùng **PHẢI xuất bản sao lưu đã xác minh** và đồng bộ dữ liệu đám mây trước khi gỡ ứng dụng! |

---

## 3. Khởi tạo Khóa Release Mới & Cấu hình Môi trường / CI

### 3.1. Tạo Upload/Release Keystore sản xuất mới
Chạy trên máy bảo mật (không commit file `.jks`/`.keystore` hay `key.properties` vào Git):

```bash
keytool -genkeypair -v \
  -keystore lifeos-release.jks \
  -alias lifeos-release \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -dname "CN=LifeOS Release, O=LifeOS, C=VN"
```

Xuất fingerprint SHA-1 & SHA-256 của khóa mới:

```bash
keytool -list -v -keystore lifeos-release.jks -alias lifeos-release
```

### 3.2. Cập nhật cấu hình & Firebase / GitHub
1. **Firebase Console (`life-os-vn-2026`):** Thêm **SHA-1** và **SHA-256** của chứng chỉ Release mới (và Play App Signing key trên Google Play Console) để Google Sign-In hoạt động.
2. **`android/signing/expected_certs.json`:** Thay thế các chuỗi `REPLACE_WITH_*` bằng mã SHA-256 chữ thường 64 ký tự hex (không có dấu `:`) tương ứng cho kênh `github` và `play`.
3. **GitHub Repository Secrets / Variables (bắt buộc cho workflow CI `publish-android-ota-release`):**
   - `secrets.LIFEOS_RELEASE_KEYSTORE_BASE64`: nội dung base64 của file `lifeos-release.jks`
   - `secrets.LIFEOS_RELEASE_STORE_PASSWORD`
   - `secrets.LIFEOS_RELEASE_KEY_ALIAS`
   - `secrets.LIFEOS_RELEASE_KEY_PASSWORD`
   - `vars.LIFEOS_GITHUB_RELEASE_CERT_SHA256` hoặc `secrets.LIFEOS_GITHUB_RELEASE_CERT_SHA256` (khớp với `expected_certs.json`)
4. **Build local có Release Key:** sao chép `android/key.properties.example` thành `android/key.properties` (git-ignored) hoặc xuất 4 biến môi trường `LIFEOS_RELEASE_STORE_FILE`, `LIFEOS_RELEASE_STORE_PASSWORD`, `LIFEOS_RELEASE_KEY_ALIAS`, `LIFEOS_RELEASE_KEY_PASSWORD`.
5. **Chính sách Fail-Closed trong `android/app/build.gradle.kts`:**
   - Khi thiếu release keystore, `flutter build apk --release` **từ chối build và báo lỗi GradleException**.
   - Nếu chỉ cần thử nghiệm cục bộ không phân phối, phải bật tường minh `LIFEOS_ALLOW_DEBUG_SIGNED_RELEASE=true` (tự động gắn `versionNameSuffix = "-debugsigned"`). Cờ này bị vô hiệu hóa khi `CI=true`, `LIFEOS_REQUIRE_RELEASE_SIGNING=true`, hoặc tag `refs/tags/v*`.

---

## 4. Quy trình Di trú (Migration Paths)

### Phương án A — Khuyến nghị cho mọi thiết bị (đặc biệt API 24–27 & chuyển sang khóa sạch hoàn toàn)
Áp dụng bắt buộc cho **Android 7.0–8.1 (API 24–27)** và khuyến nghị nếu muốn chuỗi tin cậy hoàn toàn sạch không gắn debug ancestor:
1. Mở LifeOS (`v3.26.0` hoặc `v3.27.0`) → **Hồ sơ → Sao lưu & Khôi phục (Backup & Restore Studio)** → Tạo bản sao lưu đầy đủ và lưu ra bộ nhớ ngoài / tệp an toàn; kiểm tra đồng bộ Cloud (nếu đăng nhập).
2. Gỡ cài đặt bản `v3.26.0` / `v3.27.0` cũ trên thiết bị (`adb uninstall vn.lifeos.app.life_os` hoặc thao tác tay).
3. Cài đặt gói APK Release mới (`life-os-v3.28.0-github-arm64-v8a.apk` đã vượt qua `verify_apk_signature`).
4. Đăng nhập lại và khôi phục dữ liệu từ bản sao lưu đã xác minh.

### Phương án B — Xoay vòng khóa APK Signature Scheme v3 cho cập nhật tại chỗ trên API 28+ (Android 9+)
Chỉ dùng khi cần người dùng **API 28+** trên kênh GitHub OTA cập nhật đè từ `v3.26.0`/`v3.27.0` mà không mất dữ liệu cục bộ. *Lưu ý: Google Play App Signing sử dụng khóa riêng do Play quản lý; không dùng lineage dính debug key cho Google Play.*

1. **Tạo `SigningCertificateLineage` từ chứng chỉ debug cũ sang keystore release mới:**
   ```bash
   apksigner rotate \
     --out lineage-debug-to-release.bin \
     --old-signer \
       --ks "$HOME/.android/debug.keystore" \
       --ks-key-alias androiddebugkey \
       --ks-pass pass:android \
     --new-signer \
       --ks lifeos-release.jks \
       --ks-key-alias lifeos-release \
       --ks-pass env:LIFEOS_RELEASE_STORE_PASSWORD
   ```
   *(Khuyến nghị kiểm tra lại bằng `apksigner verify --verbose --print-certs` sau khi ký; lưu ý khóa cũ trong debug keystore không được tiếp tục dùng để ký các bản mới độc lập.)*

2. **Ký APK bằng v3 lineage (chỉ định `--rotation-min-sdk-version 28` và hai signer khi cần hỗ trợ cả v2 trên máy cũ nếu giữ compatibility, hoặc `--v3-signing-enabled true` cho API 28+):**
   ```bash
   # Build unsigned / release APK hoặc re-sign với apksigner:
   apksigner sign \
     --v1-signing-enabled false \
     --v2-signing-enabled true \
     --v3-signing-enabled true \
     --rotation-min-sdk-version 28 \
     --lineage lineage-debug-to-release.bin \
     --ks "$HOME/.android/debug.keystore" \
     --ks-key-alias androiddebugkey \
     --ks-pass pass:android \
     --next-signer \
     --ks lifeos-release.jks \
     --ks-key-alias lifeos-release \
     --ks-pass env:LIFEOS_RELEASE_STORE_PASSWORD \
     --out lifeos-release-rotated.apk \
     app-arm64-v8a-github-release.apk
   ```
   > **Cảnh báo:** Nếu gắn `--ks debug.keystore` ở `--v2-signing-enabled true` cho API 24–27, chữ ký v2 vẫn chứa debug cert cho máy API < 28 (nên script `verify_apk_signature.*` sẽ từ chối nếu phát hiện `CN=Android Debug` còn tồn tại trong chuỗi signer). Sau một chu kỳ chuyển tiếp có kiểm soát (hoặc chọn Phương án A), hãy phát hành APK thuần release key (`--v2-signing-enabled true --v3-signing-enabled true` chỉ với `lifeos-release.jks`, không còn debug signer).

3. **Xác minh chữ ký APK trước khi phát hành:**
   ```bash
   apksigner verify --verbose --print-certs lifeos-release-verified.apk
   bash scripts/verify_apk_signature.sh --apk lifeos-release-verified.apk --channel github
   ```
   Hoặc trên Windows PowerShell:
   ```powershell
   .\scripts\verify_apk_signature.ps1 -ApkPath .\lifeos-release-verified.apk -Channel github
   ```

4. **Kiểm tra khả năng xác minh OTA trong ứng dụng:**
   `LifeOsApkSignatureVerifier.kt` hỗ trợ kiểm tra chứng chỉ trùng khớp và chuỗi xoay vòng `SigningInfo.signingCertificateHistory` trên API 28+, trả về trạng thái `MATCH` / `MISMATCH` / `UNREADABLE` (chặn cài đặt nếu `MISMATCH` hoặc `UNREADABLE`).

---

## 5. Kế hoạch Kiểm thử Di trú (Test Plan) với Dữ liệu mẫu

Chuẩn bị dữ liệu mẫu trên các bản đang phát hành (`v3.26.0` và `v3.27.0`):
- **Tài khoản & Dữ liệu mẫu:**
  - Ví tiền mặt (`3.500.000 ₫`) + Ví ngân hàng VCB (`12.400.000 ₫`).
  - 5 giao dịch thu/chi mẫu + 1 hóa đơn chia tiền nhóm 3 người.
  - 1 tài liệu lưu cục bộ trong `LifeOsSecureVault` + cài đặt chế độ giọng nói `Chỉ Offline` (`offline_strict`).
  - 1 thông báo ngân hàng giả lập trong hàng đợi nền.

| Kịch bản kiểm thử | Thiết bị mục tiêu | Thao tác | Kết quả đạt yêu cầu |
|---|---|---|---|
| **T1 — Clean Install Rejection of Debug APK** | Máy tính build / CI | Chạy `verify_apk_signature.ps1` / `.sh` lên `v3.26.0` hoặc `v3.27.0` (`CN=Android Debug`) | Exit code `!= 0`, thông báo `REJECTED: ... CN=Android Debug`. |
| **T2 — Fail-Closed Local Build** | Máy tính build | Chạy `flutter build apk --release --flavor github` không có `key.properties` / biến môi trường | Exit code `!= 0`, Gradle dừng ngay với thông báo `APP-02 Security Gate (FAIL-CLOSED)`. |
| **T3 — Upgrade API 24–27 (Backup → Uninstall → Reinstall)** | Emulator / Thiết bị Android 7.0–8.1 (API 24–27) | Cài `v3.26.0` & `v3.27.0` với dữ liệu mẫu → Xuất sao lưu → Gỡ cài đặt → Cài APK Release mới → Khôi phục sao lưu | Cài đặt thành công, khôi phục đủ 5 giao dịch, số dư ví khớp `100%`, không crash `LifeOsSecureVault`. |
| **T4 — Upgrade API 28+ (`v3.26.0` → New Build & `v3.27.0` → New Build)** | Thiết bị / Emulator Android 9–15 (API 28–35) | Cài `v3.26.0` / `v3.27.0` với dữ liệu mẫu → Cài đè APK Release mới (với v3 lineage nếu áp dụng Phương án B, hoặc OTA trong app) | Không lỗi `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, dữ liệu ví/giao dịch/cài đặt `offline_strict` được bảo toàn; OTA kiểm tra chữ ký trả `MATCH`. |
| **T5 — OTA Chặn APK Sai Khóa / Thiếu Chữ ký** | Thiết bị Android | Tải OTA APK giả mạo ký bằng khóa khác hoặc APK lỗi không đọc được cert | `LifeOsApkSignatureVerifier` trả `MISMATCH` hoặc `UNREADABLE`, xóa tệp tạm, **không** mở PackageInstaller, hiển thị lý do tiếng Việt trên UI. |
| **T6 — Google Sign-In với Khóa Mới** | Thiết bị Android có Play Services | Đăng nhập Google trên APK Release mới | Đăng nhập thành công sau khi đăng ký SHA-1/SHA-256 mới trên Firebase Console. |

---

## 6. Tài liệu tham khảo
- Android Developers — *Sign your app* & *APK Signature Scheme v3 / Key Rotation*: https://developer.android.com/studio/publish/app-signing
