# LifeOS Super App — User Journey Maps & Task Flows

**Mục tiêu thiết kế:** Đưa mọi tác vụ tần suất cao về **1–3 thao tác chạm** mà **không bao giờ cắt bỏ xác nhận an toàn tài chính** và luôn có lối khôi phục (Recovery) rõ ràng.

---

## 1. Bảng Đối Chiếu Số Thao Tác Mục Tiêu vs Thực Tế Sau Nâng Cấp

| # | Tác vụ tần suất cao | Mục tiêu (Section 6) | Số chạm Trước (Baseline `3e11941`) | Số chạm Sau (Nâng cấp UX) | Lộ trình tối ưu nhất | Ghi chú an toàn |
|---|---|---:|---:|---:|---|---|
| 1 | Mở ghi chi tiêu nhanh | **1** | 1–2 | **1** (mở `+` hoặc thanh nhập trên `+`) | Chạm `+` (giữa thanh dưới) → nhập ngay câu tự nhiên hoặc chọn `Ghi thu chi` | Không tự lưu khi chưa xác nhận số tiền |
| 2 | Ghi lại khoản chi quen thuộc | **1–3** | 3–4 | **2–3** | Chạm `+` → chọn `Ghi thu chi` / gõ `35k` hoặc chạm chip `35.000 ₫` → `Lưu khoản này` | Khóa chống double-tap + nút `Hoàn tác` |
| 3 | Tạo lịch mới | **2–3** | 3 (8+ nếu đổi giờ) | **2–3** | Chạm `+` → `Thêm lịch hẹn` (bỏ popup nhấp nháy trung gian) → `Lưu lịch hẹn` | Hiển thị rõ ngày giờ hiểu được |
| 4 | Tạo việc cần làm | **2–3** | 3–4 | **2–3** | Chạm `+` → `Thêm việc làm` → chọn chip `Hôm nay` / `Ngày mai` / `Cuối tuần` / `15 phút nữa` → `Lưu công việc` | Lưu nháp tự động nếu đóng giữa chừng |
| 5 | Mở trợ lý giọng nói | **1–2** | 1–2 | **1–2** | 1 chạm `Nói ghi nhanh` ngay trên `TodayPage` hoặc 2 chạm (`+` → `Nói`) | Luôn cho sửa transcript + nhập thủ công dự phòng |
| 6 | Kiểm tra số dư | **0–1** | 0 (1 nếu đang ẩn) | **0–1** | Hiển thị ngay trên Hero Card `Hôm nay` (1 chạm mắt để mở/ẩn riêng tư) | Gắn rõ phạm vi `Ví cá nhân · Riêng tư` |
| 7 | Duyệt giao dịch ngân hàng | **2–3** | 2–3 | **2** | Chạm `Duyệt` trực tiếp từ `Việc cần chú ý` trên `Hôm nay` hoặc `+` → `Duyệt GD tự động` | Chờ xác nhận BLoC thật trước khi hiện toast |
| 8 | Mở chia tiền | **1–2** | 5 (thủ công) / lỗi mở Voice | **2** | Chạm `+` → `Chia tiền nhóm` (mở form chia tiền thủ công kèm nút `Nói` tùy chọn) | Tính chia nguyên VND chính xác từng đồng |
| 9 | Tìm tính năng / dữ liệu | **1–3** | 2–3 (lỗi thiếu từ đồng nghĩa) | **2** | Chạm `🔍` trên thanh đỉnh → gõ `thay nhớt` / `tiền nhà` / `mật khẩu` / `chia bill` / `tiền điện` → chạm kết quả | Lọc nghiêm ngặt RBAC theo tài khoản |
| 10 | Đánh dấu hoàn thành công việc | **1** | 1 | **1** | Chạm `✓ Xong` ngay trong danh sách `Việc cần chú ý` hoặc tab `Công việc` | Phản hồi ngay qua `LifeOsTopToast` |

---

## 2. Chi Tiết 8 Giai Đoạn Cho 6 Hành Trình Cốt Lõi

### Hành trình A: Ghi nhanh khoản chi tiêu hằng ngày (Sinh viên / NVVP)
1. **Trigger:** Vừa trả tiền cà phê 35.000 ₫ tại quầy, chỉ có 1 tay rảnh.
2. **Intent:** Ghi ngay khoản chi 35.000 ₫ vào ví hay dùng để không quên.
3. **Discovery:** Nút `+` nổi bật chính giữa thanh điều hướng dưới (luôn cố định ở mọi tab).
4. **Action:** Chạm `+` → gõ `"cà phê 35k"` (hoặc chọn `Ghi thu chi`, gõ `35`, chạm chip gợi ý `35.000 ₫`) → kiểm tra dòng `"Số tiền sẽ lưu: 35.000 ₫"` → chạm `Lưu khoản này`.
5. **Feedback:** Nút chuyển trạng thái đang lưu (khóa bấm đúp); sau khi BLoC xác nhận thành công mới đóng sheet và hiện `LifeOsTopToast` ở đỉnh màn hình.
6. **Completion:** Số dư ví và chi tiêu hôm nay cập nhật đồng bộ; huy hiệu trạng thái hiển thị `Đã lưu` (hoặc `Đang đồng bộ` nếu đang offline).
7. **Recovery:** Chạm nút `Hoàn tác` ngay trên `LifeOsTopToast` để đảo bút toán đúng chuẩn kế toán; nếu rớt mạng/lỗi, form giữ nguyên dữ liệu trong `LocalDraftStore` để thử lại mà không gõ lại.
8. **Follow-up:** Ghi nhớ ví dùng gần nhất (`UserBehaviorPrefs.rememberWallet`) và tích lũy thói quen cục bộ (không lưu nội dung nhạy cảm ra ngoài) để gợi ý thông minh vào khung giờ quen thuộc.

### Hành trình B: Nhập câu tự nhiên đa tác vụ (NVVP đang vội)
1. **Trigger:** Vừa ăn sáng, đổ xăng và nhớ ra lịch họp 14h chiều.
2. **Intent:** Lưu cùng lúc 3 việc mà không phải mở 3 màn hình khác nhau.
3. **Discovery:** Ô nhập tự nhiên ngay đầu `QuickCreateHubSheet` (`+`).
4. **Action:** Gõ `"Ăn sáng 35k, đổ xăng 70k và nhắc tôi họp vào 14h"` → xem danh sách 3 bản nháp riêng biệt (mỗi bản nháp có loại, số tiền/thời gian, nút bỏ chọn nếu muốn chỉnh) → kiểm tra tổng tiền xác nhận → chạm `Lưu`.
5. **Feedback:** Hiển thị từng thẻ xem trước có màu + biểu tượng riêng; chỉ lưu sau khi người dùng chủ động nhấn xác nhận.
6. **Completion:** Thông báo số lượng tác vụ đã thực thi thành công và xóa bản nháp đã lưu.
7. **Recovery:** Nếu bất kỳ mệnh đề nào mơ hồ hoặc AI không phân tích được, giữ nguyên nội dung đã nhập và cung cấp lối chuyển 1 chạm sang form nhập thủ công tương ứng.
8. **Follow-up:** Nhắc việc 14h xuất hiện trong `Lịch sắp tới` và `Việc cần chú ý` trên màn hình `Hôm nay`.

### Hành trình C: Chia hóa đơn nhóm (Sinh viên / Gia đình)
1. **Trigger:** Vừa thanh toán bữa ăn 240.000 ₫ cho 4 người.
2. **Intent:** Chia đều nhanh để ghi nhận chính xác phần tiền mỗi người.
3. **Discovery:** Chạm `+` → chọn `Chia tiền nhóm` (hoặc gõ `chia bill` trên thanh tìm kiếm toàn ứng dụng).
4. **Action:** Nhập tiêu đề, nhập `240` → chạm chip `240.000 ₫`, chọn 4 người → xem ngay phần tiền mỗi người (`60.000 ₫/người`) → xác nhận lưu (hoặc chuyển 1 chạm sang thu âm nếu muốn đọc tên từng người).
5. **Feedback:** Xác nhận bằng trạng thái rõ ràng (`Đã lưu` / `Chờ xác nhận` nếu gửi nhóm gia đình).
6. **Completion:** Khoản chia xuất hiện trong tab `Gia đình` với phép chia nguyên VND chính xác tuyệt đối.
7. **Recovery:** Cho phép chỉnh sửa hoặc hủy/đảo bút toán khi có sai lệch, không xóa dấu vết kế toán trái phép.
8. **Follow-up:** Tạo VietQR hoặc theo dõi công nợ tất toán ở tab `Gia đình`.

### Hành trình D: Người mới mở ứng dụng lần đầu (FTUE)
1. **Trigger:** Vừa đăng ký tài khoản LifeOS lần đầu.
2. **Intent:** Hiểu ứng dụng làm được gì mà không bị choáng ngợp bởi hàng chục tính năng và popup xin quyền.
3. **Discovery:** Màn hình chào mừng gọn nhẹ (`/onboarding`), không xin quyền Android hàng loạt.
4. **Action:** Chọn 1 hoặc nhiều nhóm nhu cầu quan tâm (`Quản lý chi tiêu`, `Quản lý lịch`, `Quản lý gia đình`, `Quản lý nhà cửa`, `Quản lý xe cộ`, `Tất cả`) rồi chạm `Bắt đầu` — HOẶC chạm `Bỏ qua` ở góc trên phải.
5. **Feedback:** Vào thẳng Dashboard `Hôm nay` với bố cục mặc định gọn gàng (không giả định thói quen tài chính, không chèn dữ liệu giả như dữ liệu thật).
6. **Completion:** Thấy thẻ gợi ý ngữ cảnh đầu tiên (`Bắt đầu trong 10 giây` → `Ghi khoản chi đầu tiên`) có thể ẩn vĩnh viễn.
7. **Recovery:** Nếu bỏ qua hoặc muốn đổi nhóm quan tâm sau này, luôn chỉnh được trong nút `Tùy chỉnh` ngay trên Dashboard hoặc `Cài đặt`.
8. **Follow-up:** Chỉ khi người dùng lần đầu bấm micro / kết nối lịch / bật đọc thông báo ngân hàng, hộp thoại giải thích 4 ý về quyền riêng tư mới xuất hiện đúng lúc (Just-in-Time).

### Hành trình E: Tìm kiếm toàn ứng dụng bằng ngôn ngữ đời thường
1. **Trigger:** Người dùng cần ghi lịch thay nhớt xe hoặc tìm nơi đổi mã PIN nhưng không nhớ nằm ở tab nào.
2. **Intent:** Tìm đúng chức năng trong 2 giây mà không cần thuộc cấu trúc menu.
3. **Discovery:** Biểu tượng kính lúp `🔍` luôn nằm ở thanh đỉnh của 4 màn hình chính.
4. **Action:** Gõ `"thay nhot"` (hoặc `"tien nha"`, `"mat khau"`, `"chia bill"`, `"tien dien"`) → chọn kết quả được phân nhóm rõ theo `Lệnh nhanh` / `Tính năng` / `Giao dịch` / `Hóa đơn` / `Phương tiện`.
5. **Feedback:** Debounce mượt (`120ms`), kết quả lọc nghiêm ngặt theo quyền truy cập tài khoản hiện tại.
6. **Completion:** Điều hướng thẳng đến màn hình đích; lưu truy vấn vào `Tìm kiếm gần đây` (có nút `Xóa lịch sử` 1 chạm).
7. **Recovery:** Khi không có kết quả (`Zero-result`), giải thích rõ, gợi ý xóa bộ lọc hoặc mở `Thêm nhanh (+)` ngay bên dưới.
8. **Follow-up:** Ghi nhận số liệu ẩn danh cục bộ (`searchSuccess` / `zeroResultSearch`) giúp đánh giá chất lượng từ điển đồng nghĩa.

### Hành trình F: Xử lý thông báo & Giờ yên lặng (Người dùng bận rộn / Gia đình)
1. **Trigger:** Cuối ngày muốn kiểm tra hóa đơn, công việc và giao dịch chờ duyệt mà không bị làm phiền lúc nửa đêm.
2. **Intent:** Nhìn rõ việc nào khẩn cấp, việc nào có thể hoãn, và tắt bớt loại thông báo không cần thiết.
3. **Discovery:** Biểu tượng chuông thông báo trên thanh đỉnh → `Trung tâm Thông báo`.
4. **Action:** Xem thông báo đã khử trùng lặp và phân nhóm theo loại + 4 mức ưu tiên (`Khẩn cấp`, `Đúng giờ`, `Cần xử lý`, `Thông tin`); chạm `Hoãn` chọn `15 phút` / `1 giờ` / `Tối nay` / `Ngày mai`; mở `Cài đặt thông báo` để bật `Giờ yên lặng (22:00–07:00)`, `Tóm tắt hằng ngày` hoặc tắt từng nhóm thông báo.
5. **Feedback:** Các thông báo không khẩn cấp trong giờ yên lặng được gom êm ái vào tóm tắt thay vì làm phiền; trạng thái đọc/hoãn được lưu bền vững theo từng tài khoản.
6. **Completion:** Hộp thư gọn gàng, không có thông điệp gây tội lỗi hay ép chuỗi ngày (zero dark patterns).
7. **Recovery:** Chuyển sang bộ lọc `Đã hoãn` để khôi phục bất kỳ mục nào trước hạn.
8. **Follow-up:** Chạm vào mục bất kỳ để mở đúng màn hình xử lý có kiểm tra quyền truy cập.
