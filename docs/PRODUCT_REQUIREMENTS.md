# ĐẶC TẢ YÊU CẦU SẢN PHẨM (PRODUCT REQUIREMENTS DOCUMENT — PRD)

## 1. Tầm nhìn Sản phẩm
**Life OS** là ứng dụng quản lý cuộc sống cá nhân và phối hợp gia đình thế hệ mới dành cho người dùng Việt Nam, giải quyết bài toán phân mảnh khi phải dùng rời rạc 4–5 ứng dụng (sổ thu chi, lịch cá nhân, nhắc việc nhà, sổ quỹ chung, sổ bảo dưỡng xe), đồng thời bảo vệ nghiêm ngặt **quyền riêng tư mặc định của từng thành viên**.

## 2. Nguyên tắc Sản phẩm Bất biến
1. **Privacy by Default (Riêng tư mặc định):** Tham gia một nhóm gia đình không bao giờ làm lộ tài khoản ngân hàng cá nhân, chi tiêu riêng hay sự kiện lịch riêng (`PRIVATE_EVENT`) cho chủ gia đình hoặc các thành viên khác.
2. **Độ tin cậy dữ liệu minh bạch:** Phân biệt rõ giao dịch nhập thủ công/đã xác nhận (`USER_CONFIRMED`), giao dịch đối soát chính thức (`VERIFIED`), và tín hiệu trích xuất tự động từ thông báo ngân hàng (`PROVISIONAL`). Hiển thị rõ trạng thái đồng bộ Cloud (`Đã đồng bộ` vs `Chờ đồng bộ Offline`).
3. **Kế toán tiền tệ chính xác (`VND`):** Sử dụng số nguyên đồng (`amountMinor: int`), loại trừ chuyển khoản nội bộ giữa hai ví và trả nợ thẻ tín dụng khỏi thống kê chi tiêu, xử lý hoàn tiền bằng bút toán đảo thay vì xóa dấu vết lịch sử, và không diễn giải `accumulated=0` của thông báo biến động thành số dư thực tế bằng 0.
4. **Quỹ ảo minh bạch:** Quỹ cá nhân và quỹ chung gia đình là sổ phân bổ/ghi nhận đóng góp kế toán, tuyệt đối không giữ tiền hộ hay tự ý thực hiện lệnh chuyển khoản ngân hàng.
5. **Không ép cấp quyền nhạy cảm & Chống thu thập OTP:** Mọi tính năng cốt lõi đều sử dụng bình thường mà không cần cấp quyền đọc thông báo. Khi người dùng chủ động bật nhận diện thông báo ngân hàng trên Android, hệ thống chỉ lọc các package ngân hàng nằm trong danh sách cho phép và loại bỏ tức thì mọi nội dung chứa OTP, mã PIN, CVV hoặc mật khẩu.
6. **Ngôn ngữ thiết kế “Tammy × Apple”:** Cấu trúc điều hướng tĩnh lặng chuẩn Apple HIG kết hợp cá tính xanh lá Tammy (`#0B7A2A` Light / `#19C23E` Dark), tương phản chuẩn WCAG 2.2 AA, vùng chạm tối thiểu `44 × 44 pt`, không bao giờ truyền đạt trạng thái chỉ bằng màu sắc.

## 3. Yêu cầu Phi Chức năng
- **Hiệu năng & Firebase Spark Free Tier:** Giới hạn số lượng tài liệu đọc bằng phân trang/giới hạn hợp lý, hủy toàn bộ stream subscription khi đóng BLoC, không đọc toàn bộ lịch sử không giới hạn.
- **Đa thiết bị & Thích ứng (Adaptive UI):** Chuyển đổi mượt giữa màn hình điện thoại (Bottom Navigation 5 tab kính mờ) và màn hình rộng Tablet/Web (NavigationRail bên trái + vùng nội dung cân đối).
- **An toàn ngoại tuyến (Offline-First):** Mem-cache / disk-cache của Cloud Firestore cho phép xem và tạo dữ liệu khi chập chờn mạng, gắn cờ `isPendingSync` trung thực trên UI cho tới khi máy chủ xác nhận.
