# NGHIÊN CỨU CHUYÊN SÂU & ĐẶC TẢ NGHIỆP VỤ: TÀI CHÍNH CÁ NHÂN · HỘI NHÓM · GIA ĐÌNH TRÊN NỀN TẢNG SEPAY-LIKE LIFE OS

**Phiên bản:** 2.0 | **Cập nhật:** 22/11/2026 | **Kiến trúc:** Flutter Feature-First Clean Architecture + BLoC Event-Driven + Cloud Firestore

> Tài liệu này tổng hợp và mở rộng chiều sâu từ `SePay_LifeOS_Blueprint_2026.md`, `SePay_LifeOS_Blueprint_2026.docx` và `Bao_cao_nghien_cuu_Super_App_LifeOS_2026.docx`, chuyển hóa thành mô hình toán học, kiến trúc dữ liệu và luồng trải nghiệm cho **3 không gian sống thực tế tại Việt Nam**: **Cá nhân độc lập**, **Hội nhóm / Ở ghép / Chuyến đi**, và **Hộ Gia đình / Cặp đôi**.

---

## 1. TỔNG HỢP CỐT LÕI TỪ TÀI LIỆU SEPAY CHO QUẢN LÝ TÀI CHÍNH CÁ NHÂN

Từ đặc tả kỹ thuật SePay (Bank Hub, SePay Webhooks, Android Notification Listener và Canonical Ledger), hệ thống quản lý tài chính cá nhân của Life OS tuân thủ **6 bất biến kế toán & bảo mật**:

1. **Zero-Credential Banking:** Tuyệt đối không thu thập mật khẩu ngân hàng, mã PIN hay OTP. Thông báo chứa OTP/mã xác thực bị hủy ngay trên RAM thiết bị (`OtpRedactor`).
2. **Phân tầng Độ tin cậy Dữ liệu (`Verification Tier`):**
   - `VERIFIED`: Nguồn đối soát chính thức (Bank Hub API / IPN đã xác thực chữ ký & mapping tài khoản).
   - `USER_CONFIRMED`: Người dùng tự ghi sổ hoặc duyệt xác nhận từ gợi ý thông báo; hạch toán chính thức vào sổ cái nhưng không đánh đồng là "ngân hàng đã xác nhận".
   - `PROVISIONAL`: Tín hiệu quan sát từ `NotificationListenerService` Android — nằm ở hàng đợi chờ duyệt, **chưa cộng/trừ vào chi tiêu hay số dư thực**.
3. **Bất biến Số dư (`T14`, `T15`):** Không bao giờ diễn giải trường `accumulated = 0` của IPN thành số dư tài khoản bằng `0 ₫`. Ví tự khai hoặc ngân hàng chỉ hỗ trợ một chiều giao dịch luôn gắn nhãn rõ **Số dư ước tính (`isEstimatedBalance = true`)**.
4. **Sổ cái Bất biến & Loại trừ Chuyển khoản Nội bộ (`T16`):**
   - Chuyển tiền giữa hai ví cá nhân (`transfer`) hoặc trả dư nợ thẻ tín dụng (`creditCardPayment`) chỉ dịch chuyển tài sản giữa các ví, **không làm phình tổng thu nhập hay tổng chi tiêu tháng**.
   - Không xóa cứng giao dịch (`allow delete: if false`); mọi sai sót hoặc hoàn tiền được xử lý bằng **Bút toán đảo (`reversal`)** nguyên tử.
5. **Tách Giao dịch Đa Danh mục (`Split Transaction` — Mục 4.4 & 11 SePay Blueprint):**
   - Một lần thanh toán thực tế (ví dụ đi siêu thị hết `500.000 ₫`) thường bao gồm nhiều mục đích (*Ăn uống* `320.000 ₫` + *Việc nhà & Vật tư gia dụng* `180.000 ₫`).
   - Life OS hỗ trợ `splitLines` ngay trên `TransactionEntity` với ràng buộc toán học $\sum \text{line.amountMinor} = \text{tx.amountMinor}$ (số nguyên dương VND), tự động phân bổ chính xác vào báo cáo phân tích và hạn mức ngân sách của từng danh mục con.
6. **Chuẩn Mã Thanh toán VietQR / SePay (`SEVQR` Prefix — Mục 2 & 3 SePay Blueprint):**
   - Mọi khoản góp quỹ hoặc tất toán chia tiền nhóm/gia đình đều sinh mã tham chiếu chuyển khoản định dạng `SEVQR LIFEOS <MÃ_NGẮN>` (giữ nguyên tiền tố `SEVQR` theo yêu cầu tương thích VietinBank/Bank Hub) để người dùng sao chép 1 chạm khi chuyển khoản ngân hàng và sẵn sàng tự động khớp lệnh khi nối IPN.

---

## 2. HỆ PHÂN LOẠI DANH MỤC ĐỜI SỐNG VIỆT NAM (16 NHÓM CHUẨN)

Khởi tạo sẵn cho mọi tài khoản mới để bao phủ trọn vẹn chi phí sinh hoạt cá nhân, việc nhà và gia đình:

| Mã danh mục | Tên hiển thị | Chiều | Ứng dụng Phân tích & Liên kết Super App |
|---|---|---|---|
| `cat_food` | **Ăn uống & Cafe** | Chi (`debit`) | Theo dõi chi phí ăn ngoài, cơm văn phòng, cafe hằng ngày |
| `cat_groceries` | **Chợ & Siêu thị** | Chi (`debit`) | Nguyên liệu nấu ăn tại nhà, thực phẩm tươi sống |
| `cat_housework` | **Việc nhà & Gia dụng** | Chi (`debit`) | Dọn dẹp theo giờ, giặt ủi, nước rửa chén/bột giặt, sửa chữa nhỏ |
| `cat_housing` | **Nhà cửa & Thuê nhà** | Chi (`debit`) | Tiền thuê phòng/nhà, phí quản lý chung cư, gửi xe tháng |
| `cat_utilities` | **Điện/Nước/Internet** | Chi (`debit`) | EVN, cấp nước, cáp quang Viettel/VNPT/FPT, 4G/5G |
| `cat_vehicle` | **Xe cộ & Di chuyển** | Chi (`debit`) | Đổ xăng, Grab/XanhSM, phí cầu đường ePass/VETC |
| `cat_vehicle_maint` | **Bảo dưỡng & Sửa xe** | Chi (`debit`) | Thay nhớt, lốp, ắc quy — tự bật cờ gợi ý cập nhật Odometer xe |
| `cat_shopping` | **Mua sắm cá nhân** | Chi (`debit`) | Quần áo, đồ công nghệ, thương mại điện tử Shopee/Lazada |
| `cat_health` | **Sức khỏe & Y tế** | Chi (`debit`) | Khám bệnh, thuốc men, bảo hiểm, thể thao |
| `cat_education` | **Giáo dục & Học tập** | Chi (`debit`) | Học phí, sách vở, khóa học kỹ năng, ngoại ngữ |
| `cat_entertainment` | **Giải trí & Đăng ký** | Chi (`debit`) | Xem phim, du lịch cá nhân, Netflix/Spotify/iCloud |
| `cat_family_social` | **Hiếu hỉ & Đối ngoại** | Chi (`debit`) | Mừng cưới, biếu tặng bố mẹ, quỹ lớp/đồng nghiệp |
| `cat_debt` | **Trả nợ & Cho vay** | Chi (`debit`) | Trả khoản vay, trả góp định kỳ |
| `cat_bank_fee` | **Phí ngân hàng** | Chi (`debit`) | Phí thường niên, phí SMS biến động số dư |
| `cat_other_exp` | **Chi tiêu khác** | Chi (`debit`) | Khoản chi phát sinh chưa phân nhóm |
| `cat_salary` / `cat_other_inc` | **Lương & Thu nhập / Khác** | Thu (`credit`) | Nguồn đầu vào cho Bộ Phân bổ Thu nhập Thông minh |

---

## 3. NGHIÊN CỨU SO SÁNH SÂU 3 MÔ HÌNH: CÁ NHÂN · HỘI NHÓM · GIA ĐÌNH

Một sai lầm phổ biến của các ứng dụng tài chính truyền thống là dùng chung một mô hình "ví chung" cho cả bạn cùng phòng lẫn vợ chồng, gây ra **lo ngại lộ thu nhập riêng** hoặc **nhập nhằng công nợ**. Life OS tách bạch rõ 3 chế độ vận hành:

| Tiêu chí Nghiên cứu | 1. Cá nhân (`Personal`) | 2. Hội nhóm / Ở ghép (`Roommates` & `Group`) | 3. Hộ Gia đình / Cặp đôi (`Family`) |
|---|---|---|---|
| **Đối tượng điển hình** | Người độc thân, freelancer, sinh viên tự lập, hoặc không gian riêng của người đã lập gia đình | Bạn cùng phòng trọ/chung cư, nhóm bạn đi du lịch, câu lạc bộ, nhóm ăn trưa văn phòng | Vợ chồng, gia đình đa thế hệ, cặp đôi cam kết tài chính dài hạn |
| **Triết lý Quyền riêng tư** | **Cô lập tuyệt đối (`100% Owner-Only`)** tại `/users/{uid}/**` | **Zero-Trust giữa các thành viên**: Chỉ thấy hóa đơn chung đã khai báo; không ai biết lương hay ví riêng của ai | **Riêng tư có chọn lọc**: Ví riêng & Lịch riêng vẫn khóa chặt (`T17`, `T18`); chia sẻ Quỹ mục tiêu, Lịch gia đình & Việc nhà |
| **Bài toán Chia tiền Trọng tâm** | Tách 1 giao dịch thành nhiều danh mục (`Split Transaction`) & Phân bổ lương tháng vào các hũ ngân sách | **Ai ứng tiền trước — Ai nợ ai bao nhiêu (`Split Bill`)**: Tiền phòng, điện nước, ăn nhậu, mua đồ dùng chung | **Quỹ chung (`Shared Funds`) + Chia chi phí sinh hoạt / Việc nhà** theo tỷ lệ đóng góp hoặc vai trò |
| **Phương thức Chia tiền Ưu tiên** | Theo % thu nhập (`50/30/20`, `60/20/20`) | `Chia đều (Equal)`, `Số tiền chính xác (Exact)` theo món ăn, `Theo phần/ngày ở (Shares)` | `Theo tỷ lệ % thu nhập (Percentage)`, `Chia đều (Equal)`, hoặc trích từ `Quỹ Gia đình` kèm duyệt chi |
| **Gắn kết Việc nhà (`Chores`)** | Nhiệm vụ cá nhân & thói quen định kỳ | Phân công trực nhật, đổ rác, mua nước bình, đi chợ nấu ăn chung kèm hóa đơn | Giao việc nhà có luồng *Nhận việc / Đổi lịch*, gắn chi phí đi chợ/sửa nhà vào sổ chung |
| **Chu kỳ Quyết toán** | Cuối tháng đối chiếu Ngân sách & Tỷ lệ tiết kiệm | Cuối chuyến đi hoặc ngày 01–05 hằng tháng (chốt tiền nhà + điện nước + ăn chung) | Liên tục theo tháng/năm (Quỹ học phí con, Quỹ sắm Tết, Quỹ khẩn cấp gia đình) |
| **Thuật toán Quyết toán** | Cân đối Dòng tiền ròng (`Thu - Chi`) & Tốc độ chi ngày (`Daily Burn Rate`) | **Tối giản hóa đồ thị nợ (`Debt Simplification`)**: Rút gọn nợ vòng tròn A→B→C thành số lệnh chuyển khoản ít nhất | Kết hợp Góp quỹ định kỳ (`FundContribution`) + Tất toán khoản ứng trước (`Settlement`) |
| **Khi Rời Nhóm** | Không áp dụng | Kiểm tra công nợ tồn đọng; thu hồi quyền xem nhóm ngay lập tức; giữ nguyên dữ liệu cá nhân | Chủ hộ duy nhất không được bỏ rơi nhóm khi còn thành viên; thu hồi token chia sẻ an toàn |

---

## 4. ĐẶC TẢ TOÁN HỌC: BỘ CHIA TIỀN & TỐI GIẢN CÔNG NỢ NGUYÊN ĐỒNG VND

Vì tiền Việt Nam (`VND`) sử dụng số nguyên dương (`int`, đơn vị `1 ₫`, không dùng số thực dấu phẩy động `double`), mọi phép chia tỷ lệ hoặc chia đều cho $k$ người đều có thể sinh số dư phép chia nguyên ($100.000 \div 3 = 33.333$ dư $1$). Nếu làm tròn cẩu thả sẽ gây lệch sổ kế toán!

### 4.1 Bốn Chế độ Chia Hóa đơn Chung (`SplitMethod`)

Cho tổng hóa đơn $T \in \mathbb{Z}^+$ (`totalAmountMinor > 0`) và danh sách $n \ge 1$ thành viên tham gia $M = [m_0, m_1, \dots, m_{n-1}]$ (được sắp xếp ổn định, ưu tiên người trả tiền $p$ đứng đầu để nhận hoặc gánh phần lẻ 1 đồng minh bạch):

1. **Chia đều (`SplitMethod.equal`):**
   - Mức cơ sở: $q = \lfloor T / n \rfloor$, số dư: $r = T \bmod n$ ($0 \le r < n$).
   - Với $i \in [0, n-1]$: $\text{share}_i = q + (1 \text{ nếu } i < r \text{ ngược lại } 0)$.
   - **Ví dụ:** Ăn tối `100.000 ₫` chia 3 người $\rightarrow$ `[33.334 ₫, 33.333 ₫, 33.333 ₫]`, tổng đúng `100.000 ₫`.

2. **Chia theo Phần / Hệ số (`SplitMethod.shares` — Largest Remainder / Hamilton Method):**
   - Mỗi thành viên có trọng số nguyên dương $w_i > 0$, tổng trọng số $W = \sum_{i=0}^{n-1} w_i$.
   - Phần nguyên ban đầu: $q_i = \lfloor (T \times w_i) / W \rfloor$, phần dư tử số: $\text{rem}_i = (T \times w_i) \bmod W$.
   - Số đồng còn thiếu $R = T - \sum q_i$ ($0 \le R < n$) được cộng thêm `+1 ₫` cho $R$ thành viên có $\text{rem}_i$ lớn nhất.
   - **Ứng dụng:** Phòng master tính `3 phần`, phòng nhỏ `2 phần`; hoặc người đã làm việc nhà cả tuần chỉ chịu `1 phần` tiền dọn dẹp/ăn uống so với `2 phần`.

3. **Chia theo Tỷ lệ Phần trăm (`SplitMethod.percentage`):**
   - Mỗi thành viên nhập tỷ lệ nguyên phần trăm $p_i \ge 0$ sao cho $\sum p_i = 100$.
   - Quy về bài toán trọng số với $W = 100$, áp dụng chính xác thuật toán *Largest Remainder* ở trên để đảm bảo tổng tiền chia bằng đúng $T$.
   - **Ứng dụng:** Vợ chồng đóng góp chi phí gia đình & việc nhà theo tỷ lệ thu nhập `60% - 40%`.

4. **Chia Số tiền Cụ thể (`SplitMethod.exact`):**
   - Người tạo nhập số tiền nguyên đồng $a_i \ge 0$ cho từng thành viên.
   - Kiểm tra bắt buộc tại UseCase: $\sum_{i=0}^{n-1} a_i == T$; nếu lệch báo lỗi rõ số tiền chênh lệch để người dùng điều chỉnh ngay.

### 4.2 Thuật toán Tối giản Công nợ Đa chiều (`DebtSimplifier`)

Giả sử nhóm bạn ở ghép gồm **An, Bình, Chi**:
- An trả tiền **Đi chợ & Đồ việc nhà** `300.000 ₫` (chia đều 3 người: mỗi người `100.000 ₫`).
- Bình trả tiền **Điện nước Internet** `600.000 ₫` (chia đều 3 người: mỗi người `200.000 ₫`).
- Chi trả tiền **Ăn bún chả chung** `150.000 ₫` (chia đều 3 người: mỗi người `50.000 ₫`).

Thay vì bắt mọi người chuyển khoản chéo 6 lần cho nhau:
1. Tổng chi bình quân mỗi người là `350.000 ₫`:
   - $\text{Net}_{\text{An}} = 300.000 - 350.000 = -50.000\text{ ₫}$ (An cần trả thêm `50.000 ₫`)
   - $\text{Net}_{\text{Bình}} = 600.000 - 350.000 = +250.000\text{ ₫}$ (Bình cần nhận về `250.000 ₫`)
   - $\text{Net}_{\text{Chi}} = 150.000 - 350.000 = -200.000\text{ ₫}$ (Chi cần trả thêm `200.000 ₫`)
   - Kiểm chứng bất biến: $(-50.000) + (+250.000) + (-200.000) = 0\text{ ₫}$.
2. `DebtSimplifier` sinh đúng **2 lệnh chuyển khoản tối ưu**:
   - **Chi $\rightarrow$ Bình:** `200.000 ₫` (Mã CK: `SEVQR LIFEOS ...`)
   - **An $\rightarrow$ Bình:** `50.000 ₫` (Mã CK: `SEVQR LIFEOS ...`)
3. Khi Chi nhấn **“Ghi nhận đã tất toán”** `200.000 ₫` cho Bình, bản ghi `DebtSettlementEntity` được lưu vào `/families/{familyId}/settlements/{id}`, cập nhật tức thì $\text{Net}_{\text{Chi}} = 0\text{ ₫}$ và $\text{Net}_{\text{Bình}} = +50.000\text{ ₫}$ theo thời gian thực!

---

## 5. BỘ PHÂN BỔ THU NHẬP CÁ NHÂN & GIA ĐÌNH (`IncomeAllocationEngine`)

Để giúp người dùng trả lời câu hỏi *"Tháng này có 20.000.000 ₫ thì nên chia vào Ăn uống, Việc nhà, Hóa đơn, Xe cộ và Tiết kiệm bao nhiêu?"*, Domain Layer cung cấp `IncomeAllocationEngine` thuần Dart (0 phụ thuộc UI/Firebase) với 3 cấu hình nghiên cứu thực tiễn:

1. **Cá nhân Cân bằng (`50 / 30 / 20`):**
   - Ăn uống & Chợ (`22%`) · Nhà cửa & Điện nước (`18%`) · Việc nhà & Di chuyển (`10%`) · Mua sắm, Giải trí & Phát triển bản thân (`30%`) · Quỹ Tiết kiệm & Dự phòng (`20%`).
2. **Hộ Gia đình & Tổ ấm (`60 / 20 / 20`):**
   - Ăn uống & Chợ gia đình (`25%`) · Nhà cửa, Điện nước & Việc nhà (`20%`) · Sức khỏe, Con cái & Giáo dục (`15%`) · Hiếu hỉ, Đối ngoại & Sinh hoạt chung (`20%`) · Quỹ Tích lũy & Khẩn cấp (`20%`).
3. **Ở ghép / Nhóm Tiết kiệm (`55 / 20 / 25`):**
   - Thuê phòng & Điện nước chia chung (`25%`) · Ăn uống & Đi lại (`22%`) · Đóng góp đồ việc nhà chung (`8%`) · Học tập & Giải trí cá nhân (`20%`) · Tiết kiệm mục tiêu (`25%`).

Mọi phương án phân bổ đều dùng *Largest Remainder Method* để tổng các hạn mức đề xuất khớp 100% số tiền đầu vào và cho phép **Áp dụng đồng loạt vào Ngân sách tháng** chỉ bằng một thao tác.
