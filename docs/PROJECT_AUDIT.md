# BÁO CÁO KHẢO SÁT TOÀN BỘ WORKSPACE (PROJECT AUDIT)

> **Ngày khảo sát:** 22/11/2026  
> **Workspace:** `g:\superapp`  
> **Kiến trúc mục tiêu bắt buộc:** Flutter + Feature-First Clean Architecture + BLoC Event-Driven (`bloc` + `flutter_bloc` + `bloc_concurrency`, **TUYỆT ĐỐI KHÔNG DÙNG CUBIT**) + `get_it` + `go_router` + Firebase Authentication + Cloud Firestore + Firestore Security Rules.

---

## 1. Kiểm kê Toàn bộ Tài liệu & Hiện trạng Repository

Toàn bộ các tệp gốc của người dùng trong `g:\superapp` đã được đọc và đối chiếu 100% nội dung (bao gồm văn bản XML trong `.docx`, bảng biểu, chú thích và hình ảnh tham chiếu UI):

| Tệp tài liệu trong Workspace | Loại | Nội dung chính đã phân tích |
| --- | --- | --- |
| `Bao_cao_nghien_cuu_Super_App_LifeOS_2026.docx` | DOCX (72 KB) | Đề án sản phẩm & kiến trúc **Super App Quản lý Cuộc sống & Gia đình (Life OS)**: 5 trụ cột (Hôm nay, Tài chính, Lịch & Việc, Gia đình, Tài sản/Xe), sổ cái VND nguyên đồng, quyền riêng tư mặc định, Notification Listener Android, tiêu chí nghiệm thu 13 kịch bản. |
| `a.docx` (+ ảnh nhúng `word/media/rId12.png`) | DOCX (720 KB) | Đặc tả **Design System UI/UX “Tammy × Apple”**: cấu trúc Apple HIG + điểm nhấn xanh lá Tammy (`#0B7A2A` Light / `#19C23E` Dark), Liquid Glass tiết chế cho thanh điều hướng/tab bar, typography SF Pro/Inter, grid 4pt, vùng chạm `>= 44×44`, chuẩn tương phản WCAG 2.2 AA. |
| `SePay_LifeOS_Blueprint_2026.md` & `.docx` | MD / DOCX | Đặc tả kết nối tài chính cho Life OS: mô hình `CanonicalTransaction`, phân tách độ tin cậy `PROVISIONAL` vs `USER_CONFIRMED` vs `VERIFIED`, ma trận khả năng ngân hàng, quy tắc không hiểu nhầm `accumulated=0` thành số dư 0đ, chống nhân đôi giao dịch đa nguồn, nâng cấp `provisional` → `verified`, kịch bản kiểm thử T01–T24. |
| `Prompt_Implement_LifeOS_SePay.md` | Markdown | 10 luật bất biến về bảo mật tài chính: không thu thập mật khẩu/OTP ngân hàng, không đặt secret đối tác trong Flutter client, chuyển tiền nội bộ không tính vào chi tiêu, quản trị gia đình không được xem dữ liệu `PRIVATE`. |

### 1.1. Kiểm tra Môi trường Công cụ & Firebase Cloud
| Thành phần | Kết quả kiểm tra thực tế | Ý nghĩa triển khai |
| --- | --- | --- |
| Flutter SDK | `Flutter 3.47.0` (channel `stable`) | Đã tạo nền tảng `android/`, `ios/`, `web/` cho package `vn.lifeos.app` (`life_os`). |
| Dart SDK | `Dart 3.13.0` (`windows_x64`) | Hỗ trợ đầy đủ `sealed class`, pattern matching, strict null-safety. |
| Bộ thư viện Pub | `flutter_bloc 9.1.1`, `bloc 9.2.1`, `bloc_concurrency 0.3.0`, `get_it 9.3.0`, `go_router 18.1.4`, `firebase_core 5.2.0`, `firebase_auth 7.1.0`, `cloud_firestore 7.2.0`, `equatable 2.1.0`, `intl 0.20.3`, `bloc_test 10.0.0`, `mocktail 1.0.5`, `fake_cloud_firestore 4.5.0`, `firebase_auth_mocks 0.16.0` | Đã tải và giải quyết thành công 100% từ nguồn chính thức `pub.dev`. |
| Java Runtime | `Eclipse Adoptium JDK 21.0.10` | Đủ điều kiện chạy Firebase Emulator và công cụ kiểm thử. |
| Firebase CLI | `firebase-tools 15.27.0` | Đã cài đặt toàn cục. `firebase login:list` ghi nhận tài khoản `danhhoa200005@gmail.com`, **nhưng** lệnh `firebase projects:list` trả về `HTTP 401 Unauthenticated` (refresh token Google OAuth đã hết hạn, trả `400` tại `oauth2/v3/token`). |

> **Ghi nhận Blocker Hạ tầng Bên ngoài (Tuân thủ Mục 1 & Mục 15):**  
> Việc tự động gọi Google Cloud API để tạo mới project Firebase Cloud thật (`firebase projects:create`) và chạy `flutterfire configure` trực tuyến đang **BLOCKED bởi phiên đăng nhập Google OAuth hết hạn** của Firebase CLI (cần người dùng tự xác thực tương tác trình duyệt qua `firebase login --reauth`).  
> **Giải pháp kỹ thuật an toàn đã triển khai:** Không điền giả Firebase App ID hay API key bịa đặt. Hệ thống được thiết kế hỗ trợ song song:
> 1. **Chế độ Cloud thật (`--dart-define` / `flutterfire configure`)** ngay khi người dùng chạy `firebase login --reauth` & `flutterfire configure`.
> 2. **Chế độ Firebase Local Emulator (`demo-life-os`)** cấu hình đầy đủ `firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json` để kiểm thử xác thực, dữ liệu thực và quy tắc bảo mật ngay tại máy cục bộ mà không tốn chi phí hay lộ khóa.

---

## 2. Xác định 13 Khía cạnh Cốt lõi của Hệ thống

1. **Ứng dụng dùng để làm gì:** Quản lý toàn diện cuộc sống hằng ngày cho cá nhân và gia đình Việt Nam: thu chi cá nhân chính xác đến từng đồng (`VND`), ngân sách, quỹ riêng/quỹ chung gia đình, lịch riêng tư & lịch chung, giao việc đồng thuận, phương tiện & nhắc hạn bảo dưỡng, hóa đơn định kỳ và nhận diện thông báo ngân hàng có kiểm duyệt.
2. **Người dùng mục tiêu:** Cá nhân trẻ tự lập, cặp đôi/vợ chồng, hộ gia đình có con, nhóm ở ghép, gia đình sở hữu xe máy/ô tô.
3. **Các nhóm chức năng:** `authentication`, `dashboard`, `transactions` (ví, danh mục, sổ thu chi, chuyển ví, đảo bút toán), `budgets` (ngân sách tháng & quỹ riêng/chung), `family` (nhóm gia đình, mã mời, vai trò, mua sắm chung), `calendar` (lịch riêng/chung & rảnh/bận opt-in), `tasks` (giao việc đồng thuận & lặp), `vehicles` (xe, odo, bảo dưỡng `min(km, ngày)`, hóa đơn định kỳ), `notifications` (consent, parser thông báo ngân hàng VN, chống OTP, khử trùng lặp, xuất dữ liệu).
4. **User flows:** Đăng ký/đăng nhập → Onboarding quyền riêng tư → Dashboard Hôm nay → Ghi/duyệt giao dịch & chuyển ví → Lập ngân sách & góp/chi quỹ gia đình → Tạo lịch riêng/chung & giao/nhận việc → Cập nhật Odometer & bảo dưỡng xe → Cấp/thu hồi quyền nhận diện thông báo ngân hàng.
5. **Business rules:** Tiền tệ `VND` lưu số nguyên (`amountMinor: int`), tuyệt đối không dùng `double` cho số tiền kế toán; chuyển khoản nội bộ giữa hai ví và trả dư nợ thẻ tín dụng không tính vào tổng chi tiêu; giao dịch từ thông báo là `provisional` chờ xác nhận hoặc đối soát nâng cấp thành `verified`; không bao giờ diễn giải `accumulated=0` thành số dư 0đ; hủy giao dịch đã xác nhận tạo bút toán đảo (`reversal`) giữ lịch sử kiểm toán.
6. **Data entities:** `UserEntity`, `WalletEntity`, `CategoryEntity`, `TransactionEntity`, `BudgetEntity`, `FundEntity`, `FundContributionEntity`, `FundExpenseRequestEntity`, `FamilyEntity`, `FamilyMemberEntity`, `ShoppingItemEntity`, `CalendarEventEntity`, `TaskEntity`, `VehicleEntity`, `MaintenanceRecordEntity`, `RecurringBillEntity`, `SourceConsentEntity`, `BankNotificationCandidate`, `TodayDashboardEntity`.
7. **Authentication requirements:** Firebase Authentication (Email/Password Sign-up, Sign-in, Sign-out, Password Reset, Session Restoration qua `authStateChanges()`), quản lý duy nhất bởi `AuthBloc`.
8. **Authorization requirements:** Tách biệt tuyệt đối không gian `users/{uid}/...` (dữ liệu cá nhân, ví riêng, giao dịch riêng, quỹ riêng, sự kiện `PRIVATE_EVENT`) khỏi không gian `families/{familyId}/...` (dữ liệu chia sẻ cho `memberIds`). Chủ gia đình (`owner`/`admin`) **không có quyền đọc dữ liệu cá nhân** của thành viên khác.
9. **Module đã hoàn thiện trước khi bắt đầu:** Chưa có mã nguồn nghiệp vụ Flutter (0%), mới có bộ tài liệu đặc tả sản phẩm, tài chính và design system.
10. **Module cần xây dựng cho MVP:** Toàn bộ nền tảng Clean Architecture, DI, Router, Theme Tammy × Apple, Firebase bootstrap, Firestore Rules/Indexes, 9 feature modules (Domain + Data + BLoC + UI), Android Kotlin `NotificationListenerService` và hệ thống kiểm thử tự động.
11. **Vấn đề kiến trúc cần phòng tránh:** Tránh dùng `Cubit`, tránh truy cập `FirebaseFirestore` từ Widget/BLoC, tránh phụ thuộc chéo giữa các BLoC, tránh race condition khi bấm lưu giao dịch nhiều lần (bắt buộc áp dụng `bloc_concurrency` + `operationId` idempotency).
12. **Rủi ro xung đột tài liệu & Cách xử lý (Quy tắc 13):** Tài liệu nghiên cứu ban đầu gợi ý Riverpod/NestJS, trong khi yêu cầu mới nhất của người dùng quy định rõ **Flutter + Feature-First Clean Architecture + BLoC Event-Driven (không Cubit) + Firebase Auth + Cloud Firestore + Security Rules**. Theo quy tắc ưu tiên yêu cầu rõ ràng và mới nhất, kiến trúc ứng dụng tuân thủ 100% chuẩn Flutter Clean Architecture + BLoC + Firebase, đồng thời giữ nguyên toàn bộ quy tắc nghiệp vụ tài chính, sổ cái, khử trùng lặp và quyền riêng tư từ bộ tài liệu gốc.
