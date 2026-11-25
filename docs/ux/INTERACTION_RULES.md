# LifeOS Super App — Quy Chuẩn Tương Tác (Interaction Rules)

Tài liệu quy định các quy tắc tương tác bắt buộc cho toàn bộ thành phần UI của LifeOS nhằm đảm bảo **nhanh cho người quen, an toàn cho người mới, dễ chạm cho người lớn tuổi**.

---

## 1. Quy Tắc An Toàn Tài Chính (Financial Safety Invariants)

1. **Không tự động thực thi hành động làm thay đổi tiền:**
   - Gợi ý từ Behavior Engine (`RecommendationEngine`) chỉ mở màn hình hoặc điền sẵn bản nháp xem trước, **không bao giờ** tự ghi giao dịch, tự chuyển tiền hay tự duyệt chi quỹ.
   - Bản nháp từ ngôn ngữ tự nhiên hoặc giọng nói luôn hiển thị đầy đủ: loại nghiệp vụ, số tiền định dạng VND (`FontFeature.tabularFigures()`), ví áp dụng và nút xác nhận rõ nghĩa (`Lưu giao dịch`, `Xác nhận`).
2. **Không hiển thị "Thành công" giả:**
   - Mọi thao tác ghi giao dịch phải chờ BLoC trả về trạng thái `success` hoặc `failure` trước khi đóng hộp thoại hay phát `LifeOsTopToast` thành công.
   - Khi chỉ mới tạo bản nháp (draft) hoặc chờ đối soát ngân hàng, luôn hiển thị `Chờ xác nhận` — tuyệt đối không ghi `Thành công`.
3. **Chống lưu trùng do bấm đúp (Double-Tap Idempotency):**
   - Mỗi phiên form tạo một `operationId` duy nhất (`Uuid().v4()`) ngay khi mở hoặc khởi tạo bản nháp, kết hợp khóa `_isSubmitting` làm mờ/vô hiệu hóa nút gửi trong lúc đang xử lý.
4. **Hoàn tác chuẩn nghiệp vụ kế toán:**
   - Nút `Hoàn tác` trên `LifeOsTopToast` gửi `TransactionReverseRequested` tạo bút toán đảo (`isReversed = true`, trạng thái `Đã đảo bút toán`) thay vì xóa lén dữ liệu lịch sử.

---

## 2. Quy Tắc Form, Tiền VND, Thời Gian & Bản Nháp

1. **Nhập tiền VND thông minh nhưng không xâm lấn:**
   - Hỗ trợ đầy đủ: `35000`, `35k`, `1tr2`, `1 triệu 200 nghìn`, `500 nghìn`.
   - Khi người dùng gõ số ngắn (ví dụ `35`), hiển thị chip gợi ý (`35.000 ₫`, `350.000 ₫`, `3.500.000 ₫`) để người dùng **chủ động chạm chọn** — tuyệt đối không âm thầm biến `35 ₫` thành `35.000 ₫` mà không có xác nhận.
   - Luôn hiển thị dòng xác nhận trực tiếp ngay dưới ô nhập (`Số tiền sẽ lưu: 35.000 ₫`) trước khi bấm lưu.
2. **Chọn ngày giờ tương đối có giải nghĩa:**
   - Cung cấp bộ chip nhanh: `Hôm nay`, `Ngày mai`, `Cuối tuần`, `15 phút nữa`, `Thứ Hai tuần sau` và `Chọn ngày giờ...`.
   - Luôn hiển thị dòng giải nghĩa tường minh (`Hiểu là: Thứ Hai, 30/11 lúc 09:00`) để tránh hiểu nhầm thời điểm.
3. **Bảo toàn bản nháp an toàn theo tài khoản (`LocalDraftStore`):**
   - Tự động lưu bản nháp khi đóng bàn phím, chuyển màn hình, app xuống nền (`paused`/`inactive`), mất mạng hoặc gặp lỗi đồng bộ.
   - Xóa bản nháp chỉ sau khi lưu thành công.
   - Bản nháp được mã hóa cục bộ qua `NativeSecureVaultBridge`, phân vùng chặt theo `userId` và kiểm tra khớp `ownerUserId` khi khôi phục — tuyệt đối không khôi phục nháp của Tài khoản A cho Tài khoản B.

---

## 3. Quy Tắc Chạm Một Tay, Cử Chỉ & Khả Năng Tiếp Cận

1. **Kích thước vùng chạm tối thiểu `48 × 48 logical dp`:**
   - Toàn bộ nút bấm chính, nút đóng/mở, nút biểu tượng trên thanh công cụ và chip tương tác tuân thủ chuẩn Android 48dp (hoặc tối thiểu 44–48dp trên thanh đỉnh hẹp 360dp nhờ mở rộng vùng hit target mà không làm tràn chiều ngang).
2. **Không ép buộc cử chỉ ẩn (No Hidden-Only Gestures):**
   - Ngăn kéo cạnh trái (`shell_left_edge_drawer_swipe_zone`) có nút Logo/Menu thay thế trực quan.
   - Thanh dock vuốt ngang (`LiquidGlassSlidingDock`) hỗ trợ chạm trực tiếp vào từng tab.
   - Mọi thao tác hoãn/xóa đều có nút bấm rõ ràng bên cạnh cử chỉ vuốt (nếu có).
3. **Chống tràn & Chống xếp chữ dọc:**
   - Không dùng `TextOverflow` cắt cụt nội dung quan trọng; mọi nhãn tiếng Việt dài dùng `Wrap`, `Expanded`, `Flexible` hoặc `FittedBox(fit: BoxFit.scaleDown)` hợp lý.
   - Không tự thu nhỏ cỡ chữ quan trọng xuống dưới mức dễ đọc; tôn trọng cỡ chữ trợ năng hệ điều hành (`MediaQuery.textScaler`).

---

## 4. Quy Tắc Phản Hồi, Chuyển Động & Hành Vi Lành Mạnh

1. **Thông báo phản hồi ở đỉnh màn hình (`LifeOsTopToast`):**
   - Toàn bộ phản hồi nhanh hiển thị trên đỉnh màn hình theo kiểu platter sáng/tối gọn gàng, không che nút `+` và thanh điều hướng dưới (cấm `.showSnackBar(`).
2. **Chuyển động có mục đích & Tôn trọng Reduce Motion:**
   - Mọi chuyển động đi qua `lib/core/motion/`, không khóa thao tác người dùng trong lúc chuyển cảnh, dừng ticker khi branch ở chế độ offstage (`TickerMode`), và chuyển tức thì sang fade nhẹ khi OS bật `Reduce Motion` / `Disable Animations`.
3. **Không thao túng hành vi (Anti-Dark-Pattern Policy):**
   - Không dùng đồng hồ đếm ngược giả, không phạt mất chuỗi (guilt streak), không gửi cảnh báo giả để kéo lượt mở app, không ẩn nút tắt/bỏ qua/đặt lại.
   - Nút hủy, bỏ qua và đặt lại luôn hiện rõ, trung thực và ngang hàng về quyền kiểm soát của người dùng.
