# LifeOS Super App — Hồ Sơ Người Dùng Kiểm Thử (Synthetic Test Personas)

> **Tuyên bố minh bạch dữ liệu:** Tất cả 5 persona dưới đây là **persona giả định phục vụ thiết kế và kiểm thử tự động (synthetic test personas)**, được xây dựng từ phân tích nghiệp vụ và tài liệu HCI (Nielsen, Fitts, Hick, Cognitive Load Theory). Chúng **KHÔNG** phải là dữ liệu phỏng vấn hay nghiên cứu định lượng từ người dùng thật (`LIVE_USER_RESEARCH: NOT_MEASURED`).

---

## 1. Năm Persona Kiểm Thử Cốt Lõi

### Persona 1: Minh Anh — Sinh viên đại học (20 tuổi)
- **Mục tiêu (JTBD):** Ghi nhanh các khoản ăn uống/cà phê trong 5 giây bằng một tay, chia tiền đi ăn nhóm và phòng trọ rõ ràng, tránh tiêu lố tiền sinh hoạt cuối tháng, không quên deadline bài tập.
- **Tác vụ tần suất cao:** Ghi chi tiêu nhanh (`35k`, `45k`), chia hóa đơn nhóm (`ăn lẩu 600k chia 4`), theo dõi hạn mức tháng, tạo việc cần làm / lịch học.
- **Bối cảnh thiết bị:** Màn hình tầm trung `360×800dp`, hay dùng bằng **1 tay** khi đang xếp hàng hoặc ngồi xe buýt, mạng 4G chập chờn.
- **Điểm ma sát cần loại bỏ:** Form hỏi quá nhiều trường bắt buộc, bàn phím số không nhập được `35k`, nút quan trọng đặt quá cao trên đỉnh màn hình, bấm nhầm `Chia tiền nhóm` bị ép nói khi đang ở giảng đường yên tĩnh.
- **Kịch bản kiểm thử ánh xạ:** `QuickCreateHubSheet` 1 tay + chip gợi ý `35.000 ₫` không tự ý ghi đè + form chia tiền thủ công 2 chạm + xem nhanh hạn mức còn tiêu/ngày.

### Persona 2: Hoàng Nam — Nhân viên văn phòng (29 tuổi)
- **Mục tiêu (JTBD):** Theo dõi lương và nhiều ví (ngân hàng + tiền mặt), duyệt nhanh giao dịch ngân hàng tự động, quản lý lịch họp + công việc, không quên ngày đóng tiền điện/Internet và lịch thay nhớt xe máy.
- **Tác vụ tần suất cao:** Duyệt giao dịch chờ xác nhận, gõ câu tự nhiên đa tác vụ (*"Ăn sáng 35k, đổ xăng 70k và nhắc tôi họp vào 14h"*), tìm kiếm nhanh (`thay nhớt`, `tiền điện`, `tiền nhà`), xem tổng kết cuối tháng.
- **Bối cảnh thiết bị:** `390×844dp` hoặc `412×915dp`, thao tác vội giữa các cuộc họp, hay chuyển đổi app liên tục (rủi ro mất bản nháp).
- **Điểm ma sát cần loại bỏ:** Mất dữ liệu đang nhập khi chuyển màn hình hoặc app xuống nền; nhầm lẫn giữa giao dịch chờ xác nhận và giao dịch đã đối soát; thông báo lặp gây mất tập trung trong giờ nghỉ.
- **Kịch bản kiểm thử ánh xạ:** Lưu nháp theo tài khoản (`LocalDraftStore`), đa ý định ngôn ngữ tự nhiên có xem trước xác nhận, từ điển đồng nghĩa tìm kiếm, Giờ yên lặng (`22:00–07:00`).

### Persona 3: Chị Thảo — Quản lý gia đình 4 thành viên (37 tuổi)
- **Mục tiêu (JTBD):** Vận hành quỹ chung minh bạch với chồng, chia sẻ danh sách đi chợ và việc nhà, theo dõi hóa đơn điện nước và hồ sơ giấy tờ gia đình, đồng thời **biết chắc ví cá nhân của mình là riêng tư**.
- **Tác vụ tần suất cao:** Góp quỹ chung, duyệt khoản chi quỹ, tạo danh sách mua sắm, kiểm tra phạm vi dữ liệu `Cá nhân · Riêng tư` vs `Gia đình · Chia sẻ`, xem hóa đơn điện nước.
- **Bối cảnh thiết bị:** Dùng cả điện thoại lẫn máy tính bảng (`900dp`), hay thao tác buổi tối ở nhà trong điều kiện thiếu sáng (Dark Mode).
- **Điểm ma sát cần loại bỏ:** Nhầm lẫn ví cá nhân có bị người nhà nhìn thấy không; trạng thái duyệt chi quỹ hiển thị sai (`CHỜ DUYỆT` cho khoản đã đối soát/tranh chấp); nhiều người dùng chung máy bị lẫn bản nháp hoặc lịch sử tìm kiếm.
- **Kịch bản kiểm thử ánh xạ:** Huy hiệu `Cá nhân · Riêng tư` / `Gia đình · Chia sẻ`, 8 trạng thái `FinancialTrustStatusBadge`, phân vùng tuyệt đối theo `userId` khi đổi tài khoản.

### Persona 4: Chú Hùng — Người lớn tuổi (64 tuổi)
- **Mục tiêu (JTBD):** Ghi nhớ giờ uống thuốc sáng/tối, lịch tái khám định kỳ và ghi lại chi tiêu hằng ngày một cách nhẹ nhàng, chữ to rõ, không sợ bấm nhầm hay gặp thuật ngữ tiếng Anh khó hiểu.
- **Tác vụ tần suất cao:** Đánh dấu đã uống thuốc, xem lịch khám hôm nay, bật cỡ chữ lớn & tương phản cao, ghi khoản chi đơn giản hoặc nói giọng nói có màn hình kiểm tra lại.
- **Bối cảnh thiết bị:** Bật cỡ chữ trợ năng hệ điều hành (`125%–150%`), cần chế độ Tương phản cao (High Contrast), thị lực giảm khi ra nắng, không quen thao tác vuốt ẩn.
- **Điểm ma sát cần loại bỏ:** App tự ép cỡ chữ về `0.92` bất chấp cài đặt OS; nút bấm nhỏ `34dp`; chữ bị cắt `...` hoặc xuống dòng mỗi chữ 1 dòng; thuật ngữ khó hiểu (`PROVISIONAL`, `Auto-Ledger`, `Copy mã`, `Calendar`, raw exception); lỗi độ tương phản chữ trắng trên xanh lá ở Dark Mode.
- **Kịch bản kiểm thử ánh xạ:** Tôn trọng `MediaQuery.textScaler` OS, chế độ Tương phản cao chuẩn WCAG 2.2 AA/AAA, vùng chạm `>= 48dp`, tiếng Việt tự nhiên, mọi thao tác đều có nút rõ ràng không ép cử chỉ ẩn.

### Persona 5: Quang Minh — Người dùng chuyên sâu / Power User (33 tuổi)
- **Mục tiêu (JTBD):** Kiểm soát tài sản đa tài khoản, phân tích ngân sách, công nợ nhóm, tùy chỉnh tiện ích trên Dashboard, bật tự động hóa có hoàn tác và tìm mọi dữ liệu/chức năng trong 2 giây.
- **Tác vụ tần suất cao:** Mở Global Search (`🔍`) nhảy tới giao dịch/hóa đơn/tài liệu, tùy chỉnh tiện ích ghim, bật/tắt hoặc đặt lại Behavior Engine, xem trạng thái đối soát và đảo bút toán kế toán đúng nghiệp vụ.
- **Bối cảnh thiết bị:** Thao tác nhanh (dễ bấm đúp nút lưu), dùng chế độ Reduce Motion hoặc nhiều tính năng chuyên sâu theo nhu cầu (Progressive Disclosure).
- **Điểm ma sát cần loại bỏ:** Double-tap tạo giao dịch trùng; thiếu cách tắt hoặc đặt lại cá nhân hóa; giao diện tự nhảy vị trí nút làm hỏng trí nhớ cơ bắp (muscle memory).
- **Kịch bản kiểm thử ánh xạ:** Chống double-tap tuyệt đối, vị trí 5 trụ điều hướng & thao tác chính cố định, công tắc bật/tắt & đặt lại dữ liệu hành vi, nhóm kết quả tìm kiếm toàn ứng dụng.

---

## 2. Ma Trận 10 Bối Cảnh Sử Dụng Thực Tế

| # | Bối cảnh sử dụng | Thách thức HCI / Nhận thức | Đáp ứng kiến trúc UX trong LifeOS |
|---|---|---|---|
| 1 | **Đang đi đường** | Thời gian chú ý < 5s, rung lắc | Nút `+` nằm chính giữa vùng ngón cái dưới màn hình; hỗ trợ ghi bằng giọng nói có xem & sửa transcript trước khi lưu. |
| 2 | **Đang đứng thanh toán** | Vội, ngại lộ số dư cho người đứng sau | Nút ẩn số dư 1 chạm (`•••••••• ₫`) ngay trên Hero Card; chip gợi ý VND (`35` → `35.000 ₫`) giúp nhập siêu tốc không cần gõ nhiều số `0`. |
| 3 | **Chỉ có một tay rảnh** | Vùng chạm thuận ngón cái ở nửa dưới màn hình | Thanh điều hướng dưới + nút `+` trung tâm + bottom sheet mở từ dưới lên + nút CTA chính nằm cuối sheet. |
| 4 | **Đang vội** | Dễ bấm đúp hoặc gõ tắt không dấu | Chống lưu trùng khi bấm đúp (`operationId` đơn nhất + khóa nút); tìm kiếm & nhập tự nhiên hiểu không dấu, viết tắt (`cf`, `ck`, `35k`, `1tr2`). |
| 5 | **Mất mạng (Offline)** | Sợ mất dữ liệu hoặc không biết đã lưu chưa | Lưu nháp cục bộ theo tài khoản (`LocalDraftStore`), hàng đợi đồng bộ offline, hiển thị rõ `Đang đồng bộ` / `Đồng bộ thất bại` kèm nút `Thử lại`. |
| 6 | **Ánh sáng ngoài trời** | Màn hình lóa, giảm tương phản | Nâng Primary Light lên `#0B7A2A` (~5.44:1), Warning `#B45309` (~5.02:1), hỗ trợ High Contrast ngay trong bảng `Aa`. |
| 7 | **Ban đêm** | Chói mắt, thông báo làm phiền giấc ngủ | True Slate Dark Mode dịu mắt (`#161B22` / `#202731`), chữ trên nút chính Dark đạt ~9.5:1 (`#04260E` trên `#19C23E`), hỗ trợ Giờ yên lặng (`22:00–07:00`). |
| 8 | **Màn hình nhỏ (`320–360dp`)** | Tràn khung `RenderFlex`, chữ xếp dọc 1 từ/dòng | Cấm `TextOverflow` cắt chữ; dùng `Wrap`/`Expanded`/`FittedBox` kiểm thử tự động từ `320dp` đến Tablet `900dp`. |
| 9 | **Người dùng thị lực kém** | Khó đọc chữ nhỏ và phân biệt màu đơn lẻ | Tôn trọng cỡ chữ Accessibility của hệ điều hành, không dùng màu làm tín hiệu duy nhất (luôn cặp Icon + Nhãn + Viền + `Semantics`). |
| 10 | **Chưa hiểu nghiệp vụ tài chính** | Sợ bấm sai gây mất tiền hoặc sai sổ sách | Ngôn ngữ tiếng Việt đời thường, xem trước số tiền chính xác trước khi lưu, cảnh báo rõ bản nháp vs đã lưu, hỗ trợ `Hoàn tác` bằng bút toán đảo đúng chuẩn kế toán. |
