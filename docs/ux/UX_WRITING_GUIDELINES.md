# LifeOS Super App — Hướng Dẫn Ngôn Ngữ Giao Diện Tiếng Việt (UX Writing Guidelines)

**Mục tiêu:** Mọi chữ trên màn hình phải **ngắn gọn, rõ ràng, tự nhiên như người Việt nói hằng ngày**, giúp người mới và người lớn tuổi hiểu ngay mà không cần kiến thức kế toán hay lập trình.

---

## 1. Năm Nguyên Tắc Giọng Điệu (Voice & Tone)

1. **Tự nhiên, không thuật ngữ kỹ thuật:** Nói bằng ngôn ngữ đời sống thay vì tên bảng cơ sở dữ liệu hay thuật ngữ tiếng Anh.
2. **Trung thực trạng thái:** Phân biệt rõ *đã lưu*, *chờ xác nhận*, *đang đồng bộ* và *đồng bộ thất bại*. Không bao giờ nói *"Thành công"* khi mới tạo bản nháp.
3. **Không đổ lỗi & Không gây hoảng sợ:** Khi xảy ra lỗi mạng hoặc sai định dạng, nói rõ chuyện gì đã xảy ra và người dùng cần làm gì tiếp theo, giữ nguyên dữ liệu vừa nhập.
4. **Không phán xét chi tiêu:** Không chê bai (*"Bạn tiêu hoang quá!"*) và không tạo cảm giác tội lỗi (*"Bạn sắp mất chuỗi!"*).
5. **Nút bấm mang hành động cụ thể:** Tuyệt đối tránh nút chung chung `OK` / `Submit`; dùng động từ rõ hậu quả (`Lưu giao dịch`, `Xác nhận`, `Thử lại`, `Hủy`, `Hoàn tác`, `Bỏ qua`).

---

## 2. Bảng Chuẩn Hóa Thuật Ngữ (Trước → Sau)

| Không dùng (Kỹ thuật / Tiếng Anh / Mơ hồ) | Dùng chuẩn trong LifeOS | Ghi chú ngữ cảnh |
|---|---|---|
| `PROVISIONAL` | `Chờ xác nhận` | Giao dịch ngân hàng/AI chưa xác thực |
| `Sync pending` | `Đang đồng bộ` / `Đang chờ đồng bộ` | Dữ liệu đã lưu trên máy, chờ lên đám mây |
| `Sync failed` | `Đồng bộ thất bại` | Kèm nút `Thử lại` rõ ràng |
| `Reconciled` / `BIÊN LAI SỔ CÁI ĐÃ ĐỐI SOÁT` | `Đã đối soát` | Giao dịch khớp chứng từ / ngân hàng |
| `Needs review` | `Cần kiểm tra lại` | Cần người dùng chọn đúng ví hoặc kiểm tra số tiền |
| `REVERSED` / `BÚT TOÁN ĐÃ ĐẢO NGƯỢC` | `Đã đảo bút toán` | Hoàn tác giao dịch chuẩn kế toán |
| `DISPUTED` | `Đang tranh chấp` | Khoản chi quỹ/chia tiền đang khiếu nại |
| `Invalid input` | `Vui lòng kiểm tra lại thông tin` | Kèm gợi ý cụ thể (ví dụ: *"Nhập số tiền lớn hơn 0 ₫"*) |
| `Operation failed` / `$e` / `err.toString()` | `Không thể lưu lúc này. Vui lòng kiểm tra kết nối và thử lại.` | Cấm tuyệt đối rò raw Dart/Firebase exception |
| `Settlement` | `Tất toán công nợ` | Thanh toán xong phần nợ nhóm |
| `Liquidity` / `Liquid Cash` | `Tiền sẵn sàng chi tiêu` / `Tiền mặt & Ngân hàng` | Dễ hiểu cho cả người không rành tài chính |
| `Copy mã` | `Sao chép mã` | Nhất quán 100% tiếng Việt |
| `Calendar` (tab onboarding) | `Lịch trình` | Đồng bộ với thanh điều hướng chính |
| `OK` | `Lưu giao dịch` / `Xác nhận` / `Đã hiểu` / `Thử lại` | Tùy đúng hành động |
| `Không có dữ liệu` (trống trơn) | `Bắt đầu theo dõi chi tiêu của bạn.` + nút `Ghi giao dịch đầu tiên` | Luôn có hướng dẫn và bước tiếp theo |

---

## 3. Mẫu Câu Chuẩn Cho 4 Tình Huống Quan Trọng

- **Xin quyền Just-in-Time (4 câu hỏi bắt buộc):**
  - *Vì sao cần quyền?* "Giúp bạn đọc nhanh khoản chi hoặc lịch hẹn bằng giọng nói."
  - *Dữ liệu nào được truy cập?* "Chỉ âm thanh khi bạn chủ động bấm nút micro."
  - *Dữ liệu được xử lý ở đâu?* "Chuyển thành chữ để bạn xem và chỉnh sửa trước khi lưu."
  - *Làm thế nào để tắt quyền?* "Bạn có thể tắt bất cứ lúc nào trong Cài đặt thiết bị."
- **Xác nhận số tiền VND:** `"Số tiền sẽ lưu: 35.000 ₫"` (không âm thầm đổi `35` thành `35.000`).
- **Giải nghĩa thời gian tương đối:** `"Hiểu là: Thứ Hai, 30/11 lúc 09:00"`.
- **Phạm vi dữ liệu gia đình:** `"Cá nhân · Riêng tư"` vs `"Gia đình · Chia sẻ"`.
