# LifeOS Super App — Chiến Lược Trải Nghiệm Thông Báo (Notification Strategy)

**Mô-đun lõi:** `lib/features/notifications/domain/services/smart_inbox_engine.dart` (Pure Dart) + `lib/features/notifications/presentation/pages/activity_and_settings_pages.dart` (`ActivityNotificationsPage`).

---

## 1. Phân Loại 4 Tầng Ưu Tiên (`SmartInboxTier`)

| Tầng ưu tiên | Nhãn tiếng Việt | Ví dụ nghiệp vụ trong LifeOS | Xử lý trong Giờ yên lặng |
|---|---|---|---|
| **1. `critical`** | `Khẩn cấp` | Cảnh báo bảo mật, lỗi đồng bộ tài chính quan trọng, giao dịch tranh chấp hoặc công việc quá hạn nghiêm trọng | **Luôn hiển thị ngay** (không bị chặn bởi Giờ yên lặng hay tắt danh mục) |
| **2. `timeSensitive`** | `Đúng giờ` | Lịch hẹn sắp diễn ra, báo thức, nhắc uống thuốc đã cấu hình, hóa đơn sắp đến hạn | Tôn trọng Giờ yên lặng (trừ lịch báo thức/thuốc do người dùng tự đặt giờ) |
| **3. `actionable`** | `Cần xử lý` | Giao dịch ngân hàng chờ duyệt, công việc được giao, lời mời gia đình, yêu cầu duyệt quỹ/tất toán | Gom vào hàng chờ yên lặng / Tóm tắt hằng ngày |
| **4. `informational`** | `Thông tin` | Tổng kết chi tiêu, báo cáo tháng, nhắc bảo dưỡng định kỳ sớm, gợi ý tính năng | Gom vào Tóm tắt hằng ngày, có thể tắt hoàn toàn |

---

## 2. Cơ Chế Chống Quá Tải & Tôn Trọng Sự Tập Trung

1. **Khử trùng lặp tất định (Deterministic Deduplication):**
   - Mỗi sự kiện dùng `dedupKey` ổn định theo miền + mã thực thể (`bank_provisional::<txId>`, `task_open::<taskId>`, `event_upcoming::<eventId>`), **không gắn chỉ số mảng `$idx`**, đảm bảo một sự kiện không bao giờ sinh 2 thẻ thông báo và trạng thái đọc/hoãn không bị sai lệch khi danh sách thay đổi.
2. **Phân nhóm theo loại (`groupedByKind`):**
   - Hiển thị các thẻ thông báo theo từng nhóm rõ ràng (`Giao dịch ngân hàng chờ duyệt`, `Lịch hẹn sắp diễn ra`, `Nhiệm vụ cần hoàn thành`, `Hóa đơn định kỳ sắp đến hạn`, v.v.) kèm số lượng chưa đọc.
3. **Giờ yên lặng (`Quiet Hours`):**
   - Hỗ trợ cấu hình khung giờ nghỉ qua đêm (mặc định `22:00 – 07:00`, xử lý đúng phép so sánh vòng tròn qua `00:00`). Trong giờ yên lặng, thông báo không khẩn cấp được giữ lại trong danh sách `quietDeferredItems` để không làm phiền giấc ngủ.
4. **Hoãn nhắc linh hoạt (`Snooze`) & Lưu bền vững theo tài khoản:**
   - Hỗ trợ chọn nhanh `15 phút`, `1 giờ`, `Tối nay`, `Ngày mai`; toàn bộ trạng thái đã đọc, đã bỏ qua, thời điểm hoãn và cài đặt thông báo được lưu mã hóa cục bộ theo `userId` (`__u_<uid>`).
5. **Tóm tắt hằng ngày (`Daily Digest`) & Tùy chọn theo danh mục (`Category Preferences`):**
   - Người dùng bật/tắt từng danh mục thông báo (Ngân hàng, Lịch hẹn, Công việc, Gia đình & Quỹ, Hóa đơn, Sức khỏe/Thuốc, Xe cộ, Giấy tờ) ngay trong `Trung tâm Thông báo` → `Cài đặt thông báo`.
6. **Deep Linking có kiểm tra quyền truy cập:**
   - Mọi thông báo dẫn đúng đến màn hình xử lý tương ứng và luôn kiểm tra lại quyền sở hữu/thành viên gia đình tại thời điểm mở.

---

## 3. Cam Kết Không Làm Phiền & Không Thao Túng

- **Không gửi thông báo lặp lại gây phiền** cho cùng một `dedupKey`.
- **Không tạo cảnh báo giả** để câu lượt mở ứng dụng.
- **Không dùng đếm ngược hoặc thông điệp gây áp lực tài chính / tội lỗi** (*"Chi tiêu sắp vỡ trận!"*, *"Đừng để mất chuỗi!"*).
- **Không xin quyền `POST_NOTIFICATIONS` / FCM ngay khi mở app lần đầu** — chỉ xin đúng lúc khi người dùng chủ động bật tính năng nhận thông báo.
