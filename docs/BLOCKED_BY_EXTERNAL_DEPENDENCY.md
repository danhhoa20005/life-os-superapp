# DANH MỤC PHỤ THUỘC BÊN NGOÀI ĐANG BỊ CHẶN (BLOCKED BY EXTERNAL DEPENDENCY)

> Tài liệu này liệt kê trung thực các tác vụ đòi hỏi xác thực danh tính tương tác của chủ tài khoản hoặc hợp đồng đối tác thương mại bên ngoài mà Agent không được phép giả mạo.

---

## 1. Tạo / Liên kết Project Trực tuyến trên Firebase Google Cloud (`BLOCKED`)
- **Nguyên nhân thực tế:** Khi chạy `firebase projects:list` với tài khoản đã lưu `danhhoa200005@gmail.com`, máy chủ Google OAuth trả về `HTTP 400` tại `https://www.googleapis.com/oauth2/v3/token` và `HTTP 401 Unauthenticated` tại `https://firebase.googleapis.com/v1beta1/projects` (refresh token hết hạn).
- **Trạng thái đã chuẩn bị sẵn trong dự án:** Đã hoàn thiện 100% `firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json`, `lib/firebase_options.dart` và kiểm chứng thành công trên **Firebase Local Emulator Suite (`demo-life-os`)**.
- **Hành động chính xác người dùng cần làm:**
  ```bash
  firebase login --reauth
  firebase projects:create <TEN_PROJECT_SPARK_CUA_BAN>
  dart pub global activate flutterfire_cli
  flutterfire configure --project=<TEN_PROJECT_SPARK_CUA_BAN>
  firebase deploy --only firestore:rules,firestore:indexes --project <TEN_PROJECT_SPARK_CUA_BAN>
  ```
  Sau đó vào **Firebase Console → Authentication → Sign-in method** và bật **Email/Password**.

---

## 2. Kết nối Đối tác Thương mại SePay Bank Hub Live / Sandbox (`BLOCKED`)
- **Nguyên nhân thực tế:** Chưa có hợp đồng đối tác Bank Hub, `client_id`, `client_secret` và `company_xid` từ SePay; đồng thời theo quy tắc bảo mật bắt buộc, **tuyệt đối không được nhúng `client_secret` hay khóa xác thực IPN vào ứng dụng Flutter client**.
- **Trạng thái đã chuẩn bị sẵn trong dự án:**
  - Đã hiện thực đầy đủ ma trận khả năng ngân hàng (`kSupportedVnBanks`), quy tắc chống hiểu nhầm `accumulated=0` thành số dư 0 VND (`safeObservedBalanceFromIpn`), khử trùng lặp liên nguồn (`crossSourceFingerprint` + `softWindowFingerprint`) và luồng nâng cấp `PROVISIONAL` → `VERIFIED` (`ingestVerifiedBankFeedEvent`).
- **Hành động chính xác người dùng cần làm khi lên Production:**
  1. Đăng ký đối tác SePay Bank Hub để nhận thông tin Sandbox (`https://bankhub-api-sandbox.sepay.vn/v1`).
  2. Triển khai một dịch vụ Trusted Backend độc lập giữ `SEPAY_CLIENT_SECRET` trong Secret Manager, nhận Bank Hub IPN, xác thực chữ ký/API key và ghi vào Firestore qua Firebase Admin SDK.

---

## 3. Kết nối Trực tiếp Gmail API Restricted Scope (`OUT OF SCOPE / BLOCKED`)
- **Nguyên nhân thực tế:** Scope `gmail.readonly` thuộc nhóm Restricted của Google, đòi hỏi xác minh ứng dụng OAuth công khai và đánh giá bảo mật CASA hằng năm nếu xử lý qua máy chủ.
- **Giải pháp thay thế an toàn đã hoạt động trong MVP:** Nhập sao kê CSV có khử trùng lặp SHA-256 (`importCsvStatement`) và nhận diện thông báo ngân hàng cục bộ trên Android (`BankNotificationListenerService`).
