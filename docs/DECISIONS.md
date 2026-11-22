# NHẬT KÝ QUYẾT ĐỊNH KỸ THUẬT (DECISIONS LOG — ADR)

## ADR-001: Feature-First Clean Architecture + Pure BLoC (`Bloc<Event, State>`) — Nghiêm cấm `Cubit`
- **Quyết định:** Toàn bộ ứng dụng Flutter được chia thành 9 feature độc lập dưới `lib/features/`, mỗi feature tách bạch 3 tầng `domain` / `data` / `presentation`. Mọi quản lý trạng thái nghiệp vụ và cấu hình ứng dụng sử dụng `Bloc<Event, State>` kết hợp `bloc_concurrency`, tuyệt đối không sử dụng `Cubit`.
- **Kiểm chứng:** Bài test tự động `test/unit/architecture_guard_test.dart` quét toàn bộ cây thư mục `lib/` để chặn đứng mọi từ khóa `extends Cubit`, import sai tầng hoặc phụ thuộc chéo giữa các BLoC.

## ADR-002: Xử lý Kết nối Firebase Cloud vs Local Emulator khi Google OAuth CLI Hết hạn
- **Bối cảnh:** Kiểm tra thực tế `firebase-tools 15.27.0` cho thấy tài khoản `danhhoa200005@gmail.com` đã hết hạn phiên OAuth (`HTTP 401 Unauthenticated` khi gọi `firebase projects:list`), cần thao tác đăng nhập trình duyệt tương tác của người dùng (`firebase login --reauth`) mới tạo được project trên Google Cloud.
- **Quyết định:**
  1. Không điền bừa cấu hình giả mạo cho môi trường Cloud thật; đánh dấu bước tạo project trên Google Cloud Console là `BLOCKED` chờ người dùng xác thực lại `firebase login --reauth`.
  2. Xây dựng `lib/app/config/firebase_config.dart` và `lib/firebase_options.dart` đọc cấu hình chuẩn qua `--dart-define` (sẵn sàng nhận kết quả từ `flutterfire configure`), đồng thời hỗ trợ đầy đủ **Firebase Local Emulator Suite (`demo-life-os`)** kèm `firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json`.
  3. Kiểm thử toàn diện Data Layer + Security Rules bằng `fake_cloud_firestore` (có tích hợp bộ thực thi `FakeFirebaseSecurityRules` đọc trực tiếp tệp `firestore.rules` thật của dự án!) và `firebase_auth_mocks`.

## ADR-003: Phân tách Vật lý Dữ liệu Cá nhân (`users/{uid}`) và Dữ liệu Gia đình (`families/{familyId}`) trên Firestore
- **Lý do:** Firestore Security Rules không lọc kết quả truy vấn (rules are not filters). Nếu trộn chung sự kiện lịch riêng (`PRIVATE_EVENT`) và lịch gia đình (`SHARED_EVENT`) trong cùng một collection, truy vấn của thành viên gia đình hoặc sẽ bị từ chối toàn bộ hoặc có nguy cơ cấu hình sai làm lộ dữ liệu riêng. Việc tách `users/{uid}/private_events` và `families/{familyId}/shared_events` giúp bảo mật cấp đường dẫn tuyệt đối, nhanh và tiết kiệm lượt đọc trong hạn mức Firebase Spark miễn phí.

## ADR-004: Đơn vị Tiền tệ Nguyên đồng (`int` Minor Units cho VND) & Quy tắc Bất biến Sổ cái
- **Quyết định:** Dùng `int` 64-bit của Dart cho số tiền nguyên đồng `VND` (`amountMinor`), loại bỏ hoàn toàn sai số dấu phẩy động. Chuyển tiền giữa hai ví (`transfer`) và trả dư nợ thẻ tín dụng (`creditCardPayment`) được thực hiện trong một giao dịch nguyên tử cập nhật hai ví đối ứng và loại khỏi phép cộng chi tiêu tiêu dùng. Giao dịch `provisional` từ thông báo ngân hàng được nâng cấp lên `verified`/`userConfirmed` qua khóa `crossSourceFingerprint` mà không tạo bản ghi chi tiêu trùng lặp.

## ADR-005: Tích hợp Hệ thống Thiết kế “Tammy × Apple” trên Flutter Material 3
- **Quyết định:** Chuyển hóa toàn bộ bảng mã màu semantic, thang chữ, khoảng cách 4pt, bo góc `8/12/16/24` và nguyên tắc Liquid Glass tiết chế từ `a.docx` thành `AppColors`, `AppTypography`, `AppSpacing` và `AppTheme` (Light & Dark), đảm bảo tỷ lệ tương phản WCAG 2.2 AA và vùng chạm tối thiểu `44 × 44 pt`.
