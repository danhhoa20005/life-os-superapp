# BẢO MẬT FIREBASE & RANH GIỚI HỆ THỐNG TIN CẬY (FIREBASE SECURITY)

## 1. Chính sách Firestore Security Rules (`firestore.rules`)
1. **Mặc định Từ chối Tất cả (`Default Deny`):** Mọi đường dẫn không khai báo tường minh đều bị chặn bởi `match /{document=**} { allow read, write: if false; }`.
2. **Cô lập Tuyệt đối Dữ liệu Cá nhân:** Toàn bộ nhánh `/users/{userId}/**` chỉ chấp nhận `request.auth != null && request.auth.uid == userId`. Kể cả người có vai trò `owner` trong cùng gia đình cũng bị từ chối `PERMISSION_DENIED` nếu cố truy cập ví, giao dịch hay `private_events` của thành viên khác.
3. **Chống Tự Nâng Quyền Gia đình (`Privilege Escalation Prevention`):**
   - Khi tạo gia đình mới, người tạo bắt buộc là `request.auth.uid` với vai trò `'owner'`.
   - Khi người dùng mới tham gia gia đình qua `family_invites/{code}`, Security Rules kiểm tra sự tồn tại của mã mời hợp lệ đối chiếu đúng `familyId` và **ép buộc vai trò mới phải là `'member'`** (`request.resource.data.memberRoles[request.auth.uid] == 'member'`), ngăn chặn hoàn toàn việc client tự gửi `'owner'` hay `'admin'`.
   - Khi thành viên rời nhóm, `uid` của họ bị xóa khỏi `memberIds`, khiến mọi truy vấn tiếp theo vào `/families/{familyId}/**` lập tức thất bại ở tầng máy chủ Firestore.
4. **Tính Toàn vẹn Tài chính & Chống Giả mạo Chủ sở hữu:**
   - Giao dịch bắt buộc `amountMinor is int && amountMinor > 0` và `currencyCode == 'VND'`.
   - Trường `ownerId` và `createdBy` bị khóa bất biến khi cập nhật (`request.resource.data.ownerId == resource.data.ownerId`).
   - Cấm xóa cứng (`allow delete: if false`) đối với `/users/{userId}/transactions/{txId}`.

## 2. Ranh giới Trusted Backend (Theo Mục 18 & Đặc tả SePay)
Để đảm bảo trung thực kiến trúc và không vi phạm bảo mật:
- **Tuyệt đối không đặt khóa bí mật trong Flutter Client:** `SEPAY_CLIENT_SECRET`, `SEPAY_WEBHOOK_API_KEY`, Google OAuth Client Secret hay Firebase Admin Service Account **không bao giờ** xuất hiện trong mã nguồn Flutter.
- **Những gì chạy an toàn trên Client + Firestore Rules trong MVP:**
  - Xác thực Firebase Auth, ghi sổ thu chi cá nhân & chuyển ví nguyên tử, ngân sách, quỹ riêng/chung, lịch riêng/chung, giao việc đồng thuận, phương tiện/hóa đơn, và bộ phân tích thông báo ngân hàng cục bộ trên Android (`NotificationListenerService` + lọc chặn OTP ngay trên thiết bị).
- **Những gì cần Trusted Backend Server ở giai đoạn mở rộng (P2):**
  - Nhận HTTP Webhook IPN trực tiếp từ SePay Bank Hub, giữ `client_secret` để tạo Hosted Link Token, và gửi Push Notification chủ động qua FCM Admin SDK.
