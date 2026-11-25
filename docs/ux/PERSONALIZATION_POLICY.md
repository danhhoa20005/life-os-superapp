# LifeOS Super App — Chính Sách Cá Nhân Hóa & Quyền Riêng Tư Hành Vi (Personalization Policy)

**Triết lý:** Cá nhân hóa phải giúp người dùng **nhẹ đầu hơn, thao tác nhanh hơn và cảm thấy được tôn trọng** — không bao giờ làm thay quyết định tài chính, không ép buộc và không che giấu cách tắt.

---

## 1. Năm Nguyên Tắc Bất Biến

1. **Minh bạch lý do (Explainability):**
   - Mọi thẻ gợi ý theo ngữ cảnh trên `TodayPage` đều hiển thị lý do ngắn gọn bằng tiếng Việt (ví dụ: *"Hóa đơn sắp đến hạn"*, *"Phù hợp mục tiêu bạn chọn"*, *"Thói quen khung giờ này của bạn"*).
2. **Ưu tiên lựa chọn chủ động của người dùng (User Agency Override):**
   - Tiện ích người dùng **ghim thủ công** luôn được ưu tiên hơn suy đoán thuật toán.
   - Bấm **`Ẩn gợi ý này`** ngay lập tức ghi nhận `recommendationDismissed` và áp dụng `DismissalPenalty` để hệ thống ngừng làm phiền lặp lại.
3. **Ổn định bố cục chính (Zero Layout Jitter):**
   - Năm trụ điều hướng (`Hôm nay · Tài chính · [ + ] · Lịch & Việc · Gia đình` + nút `Menu` thanh đỉnh) và 2 nút thao tác chính trên Hero Card (`Nói ghi nhanh`, `Thêm lịch / việc`) **không bao giờ tự đổi vị trí** theo thuật toán.
4. **Không tự động thực thi hành động tài chính:**
   - Mọi đề xuất có `isFinancialMutation == true` buộc có `autoExecuteAllowed = false`. Người dùng luôn thấy màn hình xem trước rõ số tiền, ví và bấm xác nhận chủ động.
5. **Quyền tắt & Xóa toàn bộ dữ liệu hành vi trong 2 chạm:**
   - Ngay từ tiêu đề khối gợi ý trên `TodayPage` (nút `Tùy chỉnh`) hoặc từ `Cài đặt`, người dùng có thể:
     - Bật/tắt công tắc **`Bật gợi ý thông minh`** (tắt → không thu thập sự kiện mới và ẩn toàn bộ gợi ý thích ứng).
     - Thay đổi các **nhóm nhu cầu quan tâm** bất cứ lúc nào.
     - Nhấn **`Đặt lại dữ liệu hành vi`** để xóa toàn bộ lịch sử thói quen, lượt từ chối và chỉ số cục bộ của **riêng tài khoản đang đăng nhập**.

---

## 2. Quy Trình Cold Start Cho Tài Khoản Mới

| Trạng thái tài khoản | Hành vi hệ thống |
|---|---|
| Chưa hoàn tất Onboarding | Hiển thị màn hình chọn nhóm nhu cầu quan tâm (có nút `Bỏ qua` lưu bền vững theo `userId`). |
| Mới vào Dashboard (`0` giao dịch, `0` lịch) | Hiển thị bố cục đơn giản, 1 thẻ gợi ý thao tác đầu tiên (`Bắt đầu trong 10 giây` → `Ghi khoản chi đầu tiên`), có nút `Ẩn gợi ý`. Không hiển thị dữ liệu mẫu giả như dữ liệu thật. |
| Số tín hiệu hành vi `< 3` (`coldStartMinSignals`) | Chỉ gợi ý nhẹ dựa trên nhóm nhu cầu đã chọn và dữ liệu thật hiện có (nếu có); không suy đoán thói quen chi tiêu. |
| Số tín hiệu hành vi `≥ 3` & `enabled == true` | Kích hoạt chấm điểm 7 yếu tố chuẩn hóa (`RecommendationEngine`), học theo giờ sinh hoạt thực tế của chính người dùng. |

---

## 3. Phân Vùng Quyền Riêng Tư & Anti-Dark-Pattern

- **Phân vùng 3 lớp:** Mọi khóa lưu trữ đều tách biệt theo `userId` (`__u_<uid>`), lưu mã hóa cục bộ trong `NativeSecureVaultBridge` (Android Keystore AES-256-GCM) và kiểm tra cờ `consentGranted` trước khi ghi.
- **Không gửi dữ liệu nhạy cảm ra máy chủ analytics:** Không ghi nội dung giao dịch, ghi chú, tài liệu, bản ghi giọng nói hay dữ liệu sức khỏe vào kho hành vi.
- **Cấm tuyệt đối cơ chế thao túng:** Không ép streak hằng ngày, không gửi thông báo tạo cảm giác tội lỗi (*"Bạn đã bỏ lỡ chuỗi..."*), không đếm ngược giả, không phán xét mức chi tiêu và không che giấu nút hủy/bỏ qua.
