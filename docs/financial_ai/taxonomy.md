# Taxonomy & Semantic Category Mapping — Life OS Financial AI

## 1. Nguyên tắc Thiết kế

1. **Tách biệt hoàn toàn Nhãn Ngữ nghĩa AI (`semanticKey`) và `categoryId` trong Cơ sở dữ liệu:**
   - Mô hình FastText và Rule Engine **chỉ dự đoán `semanticKey` ổn định** (ví dụ: `transport.fuel`, `food.meals`, `income.salary`).
   - Hệ thống **tuyệt đối không ghi cứng `categoryId`** từ mô hình thẳng vào `TransactionEntity`.
2. **Ánh xạ Động qua `ResolveUserCategoryUseCase`:**
   - Tra cứu danh sách `CategoryEntity` thực tế của người dùng (`/users/{uid}/categories`).
   - Kiểm tra đồng thời: `direction` (`debit` cho chi tiêu, `credit` cho thu nhập), quy tắc cá nhân hóa còn hiệu lực, tên danh mục chuẩn hoặc danh mục tùy chỉnh của người dùng.
   - Nếu người dùng đã xóa danh mục mặc định hoặc chưa có danh mục tương ứng: trả về `resolvedCategoryId: null`, giữ `suggestedCategoryName` tiếng Việt rõ ràng và đặt `requiresConfirmation = true` (không tự tạo danh mục ngầm, không ghi vào ID mồ côi).
   - Nếu người dùng tạo nhiều danh mục trùng ngữ nghĩa (ví dụ: `"Ăn uống cá nhân"` và `"Ăn uống công ty"`), nếu chưa có `PersonalizationRule` phân giải cho merchant đó, hệ thống đánh dấu `AmbiguityFlag.multipleMatchingCategories` và yêu cầu xác nhận.

---

## 2. Bảng Ánh xạ 28 Nhãn Ngữ nghĩa (`semanticKey`) sang 15 Danh mục Hệ thống Life OS

### 2.1. Nhóm Chi tiêu (`direction = debit`)

| Semantic Key (`__label__`) | Tên gợi ý chuẩn (Tiếng Việt) | Danh mục Life OS mặc định (`name`) | System Seed ID (nếu còn tồn tại) | Từ khóa / Ngữ cảnh điển hình |
| :--- | :--- | :--- | :--- | :--- |
| `food.meals` | Ăn uống hằng ngày | `Ăn uống` | `cat_food` | ăn sáng, phở, cơm tấm, bún bò, lẩu, nướng |
| `food.drinks` | Cà phê & Đồ uống | `Ăn uống` | `cat_food` | cafe, cf, trà sữa, Highlands, Phúc Long, mua nước |
| `food.groceries` | Thực phẩm & Đi chợ | `Chợ & Mua sắm` | `cat_shopping` | đi chợ, rau thịt, Bách Hóa Xanh, WinMart, Coopmart |
| `transport.fuel` | Xăng dầu & Sạc điện | `Xe cộ & Di chuyển` | `cat_vehicle` | đổ xăng, Petrolimex, PVOIL, sạc xe điện |
| `transport.ride_hailing` | Gọi xe công nghệ & Taxi | `Xe cộ & Di chuyển` | `cat_vehicle` | Grab, Xanh SM, Be, đi taxi, xe ôm |
| `transport.public` | Vé xe, Cầu đường & Gửi xe | `Xe cộ & Di chuyển` | `cat_vehicle` | gửi xe, vé xe buýt, metro, ePass, VETC |
| `transport.maintenance` | Bảo dưỡng & Sửa chữa xe | `Bảo dưỡng & Sửa xe` | `cat_vehicle_maint` | thay nhớt, sửa xe, vá lốp, rửa xe, HEAD Honda |
| `housing.rent` | Tiền thuê nhà & Quản lý | `Nhà cửa & Thuê nhà` | `cat_housing` | tiền trọ, thuê nhà, tiền phòng, phí chung cư |
| `housing.utilities` | Điện, Nước, Internet & Viễn thông | `Điện/Nước/Internet` | `cat_utilities` | tiền điện EVN, tiền nước, wifi FPT, Viettel, nạp 4G |
| `housing.housework` | Việc nhà & Đồ gia dụng | `Việc nhà & Gia dụng` | `cat_housework` | nước giặt, nước rửa chén, lau nhà, bTaskee, túi rác |
| `shopping.clothes` | Quần áo & Thời trang | `Chợ & Mua sắm` | `cat_shopping` | mua áo quần, giày dép, Uniqlo, Shopee thời trang |
| `shopping.electronics` | Thiết bị & Điện tử | `Chợ & Mua sắm` | `cat_shopping` | tai nghe, cáp sạc, chuột máy tính, Thế Giới Di Động |
| `shopping.general` | Mua sắm tiêu dùng | `Chợ & Mua sắm` | `cat_shopping` | mua đồ, siêu thị, Lazada, TikTok Shop, Mall |
| `health.medicine` | Thuốc & Dược phẩm | `Sức khỏe & Giáo dục` | `cat_health` | mua thuốc, vitamin, nhà thuốc Long Châu, Pharmacity |
| `health.hospital` | Khám chữa bệnh & Thể chất | `Sức khỏe & Giáo dục` | `cat_health` | khám bệnh, xét nghiệm, nha khoa, bệnh viện, tập gym |
| `education` | Học tập & Sách vở | `Sức khỏe & Giáo dục` | `cat_health` | mua sách, học phí, khóa học tiếng Anh, văn phòng phẩm |
| `entertainment` | Giải trí & Du lịch | `Giải trí & Đăng ký` | `cat_entertainment` | xem phim CGV, du lịch, vé khu vui chơi, bóng đá |
| `subscriptions` | Gói đăng ký định kỳ số | `Giải trí & Đăng ký` | `cat_entertainment` | Netflix, Spotify, YouTube Premium, iCloud, Google One |
| `family` | Chi phí gia đình & Con cái | `Hiếu hỉ & Đối ngoại` | `cat_family_social` | biếu bố mẹ, sữa bỉm cho bé, phụ cấp gia đình |
| `gifts` | Hiếu hỉ, Quà tặng & Đối ngoại | `Hiếu hỉ & Đối ngoại` | `cat_family_social` | mừng cưới, lì xì, quà sinh nhật, thăm ốm |
| `debt.interest` | Trả nợ, Lãi vay & Trả góp | `Trả nợ & Cho vay` | `cat_debt` | trả góp, lãi vay, trả nợ thẻ, FE Credit, Home Credit |
| `bank.fee` | Phí dịch vụ ngân hàng | `Phí ngân hàng` | `cat_bank_fee` | phí SMS banking, phí thường niên, phí duy trì TK |
| `other` | Chi tiêu chưa rõ nhóm | `Chi tiêu khác` | `cat_other_exp` | khoản chi chung chưa nêu rõ mặt hàng |

### 2.2. Nhóm Thu nhập (`direction = credit`)

| Semantic Key (`__label__`) | Tên gợi ý chuẩn (Tiếng Việt) | Danh mục Life OS mặc định (`name`) | System Seed ID (nếu còn tồn tại) | Từ khóa / Ngữ cảnh điển hình |
| :--- | :--- | :--- | :--- | :--- |
| `income.salary` | Tiền lương chính | `Lương & Thu nhập` | `cat_salary` | nhận lương, lương tháng, ứng lương công ty |
| `income.bonus` | Tiền thưởng & Phụ cấp | `Lương & Thu nhập` | `cat_salary` | thưởng dự án, thưởng KPI, thưởng Tết, phụ cấp |
| `income.freelance` | Thu nhập Freelance / Làm thêm | `Lương & Thu nhập` | `cat_salary` | tiền job ngoài, thù lao thiết kế, dạy thêm |
| `income.business` | Doanh thu bán hàng / Kinh doanh | `Thu nhập khác` | `cat_other_inc` | khách thanh toán đơn hàng, tiền hàng về, doanh thu |
| `income.interest` | Lãi tiết kiệm & Đầu tư | `Thu nhập khác` | `cat_other_inc` | lãi sổ tiết kiệm, cổ tức, lời chứng khoán |
| `income.gift` | Được tặng, Biếu & Trợ cấp | `Thu nhập khác` | `cat_other_inc` | nhận lì xì, bố mẹ cho tiền, bạn tặng quà |
| `income.other` | Khoản thu khác | `Thu nhập khác` | `cat_other_inc` | nhận tiền chuyển khoản chưa rõ nguồn lương |

### 2.3. Các Nghiệp vụ Phi Thu-Chi (Không đi qua Category Thu/Chi thông thường)

- `internal_transfer` (chuyển tiền giữa 2 ví của cùng người dùng / rút tiền mặt ATM từ thẻ ngân hàng của chính mình): ánh xạ sang `TransactionKind.transfer`, **không cộng vào Thu nhập hay Chi tiêu**.
- `refund` / `reversal`: đánh dấu rõ nghiệp vụ hoàn tiền / đảo bút toán, không tính gộp vào doanh thu/lương.
- `non_transaction` (câu thông báo số dư *"còn 2 triệu trong tài khoản"*, phủ định *"không mua gì"*, lệnh hủy *"hủy giao dịch vừa nhập"*): **chặn an toàn ngay từ Type Detector**, tạo `0` giao dịch ghi sổ.
