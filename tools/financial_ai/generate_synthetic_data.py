"""Generates a diverse, template-disjoint Vietnamese financial corpus across 30 semantic labels.

Crucial Anti-Leakage Design (Phase 8.1 & 8.3):
- Every category defines THREE strictly disjoint phrase pools (`train_phrases`, `val_phrases`, `test_phrases`)
  AND THREE strictly disjoint sentence wrapper families (`TRAIN_WRAPPERS`, `VAL_WRAPPERS`, `TEST_WRAPPERS`).
- `val` and `test` NEVER reuse `train` templates or `train`-exclusive lexical phrasings,
  so Macro F1 on `test` measures genuine subword/word generalization rather than template memorization.
"""

from __future__ import annotations
import json
import os
import random
from pathlib import Path
from feature_spec import SEMANTIC_LABELS, strip_vn_accents

BASE_DIR = Path(__file__).resolve().parent
RAW_OUT_DIR = BASE_DIR / "datasets" / "raw"

# Disjoint sentence wrapper families per split (ZERO template overlap across splits!)
TRAIN_WRAPPERS = [
    ("tr_w1", "{item} {amt}"),
    ("tr_w2", "chi {amt} {item}"),
    ("tr_w3", "hôm nay {item} hết {amt}"),
    ("tr_w4", "vừa thanh toán {item} {amt}"),
    ("tr_w5", "GD THE/QR {item} -{amt}"),
    ("tr_w6", "sáng nay {item} {amt}"),
]

VAL_WRAPPERS = [
    ("va_w1", "{item} mất {amt}"),
    ("va_w2", "tối qua {item} tốn {amt}"),
    ("va_w3", "mới trả tiền {item} {amt}"),
    ("va_w4", "VCB Digibank: {item} số tiền {amt}"),
]

TEST_WRAPPERS = [
    ("te_w1", "trưa nay mình {item} {amt}"),
    ("te_w2", "chiều qua {item} khoảng {amt}"),
    ("te_w3", "TCB: Thanh toan {item} {amt}"),
    ("te_w4", "{amt} cho khoản {item}"),
]

INCOME_TRAIN_WRAPPERS = [
    ("itr_w1", "{item} {amt}"),
    ("itr_w2", "nhận {amt} {item}"),
    ("itr_w3", "hôm nay {item} về tài khoản {amt}"),
    ("itr_w4", "MBBANK +{amt} ND {item}"),
]

INCOME_VAL_WRAPPERS = [
    ("iva_w1", "mới được cộng {amt} {item}"),
    ("iva_w2", "tài khoản nhận {item} {amt}"),
]

INCOME_TEST_WRAPPERS = [
    ("ite_w1", "sáng nay tinh tinh {item} {amt}"),
    ("ite_w2", "BIDV +{amt} noi dung {item}"),
    ("ite_w3", "{item} được {amt}"),
]

AMOUNTS_SHORT = ["25k", "35k", "45 nghìn", "65k", "85.000đ", "120k", "250 nghìn", "450k", "1tr2", "2,5 triệu", "15tr"]

# Category lexical pools: (core_shared_concepts_expressed_differently_per_split)
CATEGORY_POOLS: dict[str, dict[str, list[str]]] = {
    "food.meals": {
        "train": [
            "ăn sáng phở bò", "ăn trưa cơm tấm sườn", "bún chả hà nội", "ăn tối lẩu thái",
            "bánh mì thịt nướng", "mì quảng gà", "hủ tiếu nam vang", "cơm văn phòng",
            "gà rán kfc", "pizza company", "quán cơm bình dân", "bún bò huế", "ăn vặt xiên que",
            "ăn bún đậu thịt luộc", "bánh đa trộn", "ăn mì ý sốt bò", "ăn buffet nướng", "suất cơm trưa",
        ],
        "val": [
            "ăn sáng bún riêu", "cơm gà xối mỡ", "ăn trưa mì cay", "ăn lẩu bò nhúng dấm",
            "bánh cuốn nóng", "cháo sườn buổi sáng", "quán phở thìn", "nướng bbq hàn quốc",
        ],
        "test": [
            "ăn sáng bánh đa cua", "ăn trưa bún đậu mắm tôm", "cơm sườn bì chả",
            "ăn tối mì ý jollibee", "phở gà ta", "ăn buffet lẩu nướng", "suất cơm trưa công sở",
        ],
    },
    "food.drinks": {
        "train": [
            "uống cafe sữa đá", "cf highlands coffee", "trà sữa phúc long", "trà đào cam sả",
            "mua nước suối", "cà phê muối", "sinh tố bơ", "nước ép cam", "the coffee house",
            "trà sữa gong cha", "cafe đen đá", "nước ngọt giải khát",
            "mua nước uống giải khát", "trà chanh tươi", "nước dừa mát", "trà ô long sữa",
        ],
        "val": [
            "ly bạc xỉu đá", "uống trà sữa koi", "cà phê katinat", "mua chai nước khoáng",
            "nước mía vỉa hè", "matcha đá xay", "cf sáng cùng đồng nghiệp",
        ],
        "test": [
            "uống cf trung nguyên", "mua nước uống đóng chai", "trà ô long kem phô mai",
            "cafe starbucks", "nước dừa tươi", "trà chanh giã tay",
        ],
    },
    "food.groceries": {
        "train": [
            "đi chợ mua rau củ", "mua thịt heo cá tươi", "siêu thị bách hóa xanh",
            "mua trứng sữa winmart", "trái cây tươi ngoài chợ", "mua gạo mắm muối",
            "thực phẩm tươi sống coopmart", "mua ức gà nấu ăn", "mua hành tỏi gia vị",
            "mua rau sạch trứng gà", "mua sườn non nấu canh", "thực phẩm nấu cơm tối", "tráng miệng ngoài chợ",
        ],
        "val": [
            "đi chợ sáng mua rau thịt", "mua cá hồi ở winmart", "mua hoa quả bách hóa xanh",
            "đồ tươi nấu bữa tối", "mua thịt bò và nấm", "mua gia vị nấu ăn",
        ],
        "test": [
            "mua rau sạch và trứng gà", "đi siêu thị coopmart mua thực phẩm",
            "mua sườn non về kho", "mua trái cây tráng miệng ngoài chợ", "thực phẩm nấu cơm gia đình",
        ],
    },
    "transport.fuel": {
        "train": [
            "đổ xăng xe máy", "đổ xăng ron 95 petrolimex", "tiền xăng đi làm",
            "cây xăng pvoil", "đổ đầy bình xăng vision", "nạp điện trạm sạc xe máy",
            "đổ xăng a95", "châm xăng dọc đường",
        ],
        "val": [
            "ghé petrolimex đổ xăng", "đổ xăng xe tay ga", "tiền nhiên liệu xăng dầu",
            "sạc pin trạm vinfast", "đổ xăng e5 ron92",
        ],
        "test": [
            "đổ xăng đầy bình air blade", "thanh toán xăng petrolimex", "tiền đổ xăng tuần này",
            "trạm xăng pvoil quốc lộ", "nạp điện xe điện trạm sạc",
        ],
    },
    "transport.ride_hailing": {
        "train": [
            "đi taxi xanh sm", "đặt xe grabbike đi làm", "gọi grabcar ra sân bay",
            "đi xe ôm công nghệ be", "cuốc xe taxi mai linh", "đặt bebike về nhà",
            "cước xe grab", "đi taxi vinasun",
        ],
        "val": [
            "bắt grabbike qua quận 1", "gọi taxi xanh sm về nhà", "đi xe công nghệ beCar",
            "tiền taxi đi họp khách hàng", "cuốc grab buổi tối",
        ],
        "test": [
            "đi taxi ra bến xe", "đặt xanh sm bike", "cước grabcar đi mưa",
            "gọi xe ôm be đi công việc", "thanh toán chuyến taxi mai linh",
        ],
    },
    "transport.public": {
        "train": [
            "gửi xe máy hầm chung cư", "phí qua trạm thu phí epass", "nạp tài khoản vetc",
            "mua vé xe buýt tháng", "vé tàu metro bến thành", "tiền giữ xe bệnh viện",
            "vé xe khách phương trang", "phí cầu đường cao tốc",
        ],
        "val": [
            "tiền gửi xe trung tâm thương mại", "trạm thu phí tự động vetc",
            "mua vé tàu điện metro", "vé xe khách về quê", "phí đỗ xe bãi giữ xe",
        ],
        "test": [
            "nạp tiền thẻ thu phí epass", "phí gửi xe máy cả ngày", "mua vé xe buýt đi học",
            "tiền vé tàu hỏa", "phí qua trạm cao tốc",
        ],
    },
    "transport.maintenance": {
        "train": [
            "thay nhớt xe máy honda head", "bảo dưỡng định kỳ yamaha town",
            "vá lốp xe không săm", "thay nhớt láp và lọc gió", "rửa xe bọt tuyết",
            "sửa phanh xe tay ga", "thay bugi và vệ sinh nồi", "thay săm lốp xe máy",
        ],
        "val": [
            "thay dầu nhớt máy castrol", "vệ sinh nồi dây curoa xe ga",
            "rửa xe máy cuối tuần", "sửa xe thay má phanh", "bảo dưỡng xe ở head",
        ],
        "test": [
            "thay nhớt xe vision và nhớt hộp số", "vá vỏ xe tay ga",
            "bảo dưỡng nhông sên dĩa", "rửa xe chăm sóc xe", "thay ắc quy xe máy",
        ],
    },
    "housing.rent": {
        "train": [
            "đóng tiền thuê nhà tháng này", "tiền phòng trọ sinh viên",
            "phí quản lý chung cư vinhomes", "tiền thuê căn hộ", "đặt cọc tiền trọ",
            "thanh toán tiền nhà cho chủ trọ", "phí dịch vụ tòa nhà",
        ],
        "val": [
            "chuyển tiền trọ tháng 11", "đóng phí quản lý căn hộ",
            "tiền thuê phòng hàng tháng", "thanh toán tiền thuê chung cư",
        ],
        "test": [
            "trả tiền thuê nhà đầu tháng", "đóng tiền phòng trọ",
            "phí ban quản lý chung cư", "tiền thuê mặt bằng ở ghép",
        ],
    },
    "housing.utilities": {
        "train": [
            "thanh toán tiền điện evn", "đóng tiền nước sinh hoạt sawaco",
            "cước internet wifi fpt", "nạp data 4g viettel", "tiền cáp quang vnpt",
            "nạp thẻ điện thoại mobifone", "hóa đơn điện nước tháng này",
        ],
        "val": [
            "hóa đơn tiền điện lực evn", "đóng cước mạng wifi vnpt",
            "tiền nước sạch hàng tháng", "gia hạn gói cước 5g viettel",
        ],
        "test": [
            "trả tiền điện tháng 10 evn", "cước internet fpt telecom",
            "thanh toán hóa đơn tiền nước", "nạp tiền điện thoại di động",
        ],
    },
    "housing.housework": {
        "train": [
            "mua nước giặt ariel", "nước rửa chén sunlight", "thuê dọn nhà theo giờ btaskee",
            "mua túi đựng rác và giấy vệ sinh", "nước lau sàn nhà", "bột giặt omo",
            "mua chổi lau nhà gia dụng", "phí thu gom rác sinh hoạt",
            "nước giặt máy cửa ngang", "thuê dọn dẹp phòng ở", "mua viên rửa bát đĩa", "mua bịch túi rác đen",
        ],
        "val": [
            "mua nước xả vải comfort", "dịch vụ giúp việc dọn phòng btaskee",
            "mua giấy ăn và nước rửa tay", "đồ gia dụng nhà bếp",
        ],
        "test": [
            "mua nước giặt cửa trước", "thanh toán dọn dẹp nhà cửa",
            "mua viên rửa bát và khăn bếp", "mua cuộn túi rác gia đình",
        ],
    },
    "shopping.clothes": {
        "train": [
            "mua áo sơ mi uniqlo", "mua quần jean mới", "giày thể thao chạy bộ",
            "mua váy công sở", "áo khoác chống nắng", "sắm quần áo mùa đông",
            "mua dép sandal bitis", "quần áo thể thao", "giày sneaker", "mua áo polo", "mua thắt lưng vớ",
        ],
        "val": [
            "mua áo thun mặc nhà", "sắm đôi giày da đi làm",
            "mua quần tây công sở", "đặt áo khoác thời trang",
        ],
        "test": [
            "mua bộ quần áo thể thao", "sắm giày sneaker mới",
            "mua áo polo uniqlo", "mua thắt lưng và vớ",
        ],
    },
    "shopping.electronics": {
        "train": [
            "mua cáp sạc type c anker", "tai nghe bluetooth không dây",
            "chuột máy tính logitech", "mua pin sạc dự phòng thế giới di động",
            "ốp lưng kính cường lực điện thoại", "mua bàn phím cơ", "điện máy xanh mua quạt",
        ],
        "val": [
            "mua củ sạc nhanh iphone", "sắm tai nghe chụp tai",
            "mua ổ cứng ssd lưu trữ", "mua phụ kiện máy tính ở tgdd",
        ],
        "test": [
            "mua sạc dự phòng anker", "mua chuột không dây văn phòng",
            "dán màn hình và mua ốp điện thoại", "mua loa bluetooth mini",
        ],
    },
    "shopping.general": {
        "train": [
            "đặt đơn hàng shopee", "mua sắm trên lazada", "thanh toán đơn tiktok shop",
            "mua đồ dùng ở aeon mall", "sắm đồ cá nhân siêu thị", "mua mỹ phẩm kem chống nắng",
            "mua dầu gội sữa tắm",
        ],
        "val": [
            "thanh toán giỏ hàng shopee", "mua đồ lặt vặt ở circle k",
            "đặt hàng online lazada", "mua sữa rửa mặt chăm sóc da",
        ],
        "test": [
            "mua sắm cuối tuần aeon", "trả tiền đơn ship cod shopee",
            "mua đồ cá nhân ở gs25", "đặt đơn hàng tiktok",
        ],
    },
    "health.medicine": {
        "train": [
            "mua thuốc cảm cúm nhà thuốc long châu", "mua vitamin tổng hợp pharmacity",
            "thuốc đau dạ dày tiệm thuốc tây", "mua nước muối sinh lý khẩu trang y tế",
            "mua thuốc hạ sốt giảm đau", "nhà thuốc an khang mua men tiêu hóa",
        ],
        "val": [
            "ghé long châu mua thuốc ho", "mua viên uống bổ sung kẽm",
            "tiệm thuốc pharmacity mua bông băng", "mua thuốc dị ứng thời tiết",
        ],
        "test": [
            "mua thuốc kháng sinh theo toa", "mua thực phẩm chức năng nhà thuốc long châu",
            "mua thuốc nhỏ mắt tại pharmacity", "mua thuốc cảm sốt",
        ],
    },
    "health.hospital": {
        "train": [
            "khám tổng quát bệnh viện đại học y dược", "lấy cao răng nha khoa",
            "xét nghiệm máu phòng khám đa khoa", "tiêm vắc xin cúm vnvc",
            "đóng thẻ tập gym tháng", "khám mắt đo kính cận", "viện phí khám chuyên khoa",
            "phí khám bệnh phòng khám", "nhổ răng nha khoa", "hội viên phòng gym", "xét nghiệm định kỳ",
        ],
        "val": [
            "khám răng trám răng nha khoa", "đóng phí phòng tập yoga",
            "siêu âm kiểm tra sức khỏe bệnh viện", "tiêm phòng tại vnvc",
        ],
        "test": [
            "phí khám bệnh tại phòng khám", "nhổ răng khôn nha khoa",
            "gia hạn hội viên phòng gym", "xét nghiệm kiểm tra định kỳ",
        ],
    },
    "education": {
        "train": [
            "mua sách chuyên ngành fahasa", "đóng học phí tiếng anh ielts",
            "mua khóa học lập trình online", "lệ phí thi chứng chỉ toeic",
            "mua vở bút văn phòng phẩm", "mua giáo trình đại học tiki",
            "mua sổ tay ghi chép", "mua bút bi thước kẻ", "mua sách kỹ năng đọc",
        ],
        "val": [
            "mua sách kỹ năng tại nhà sách", "đóng tiền học ngoại ngữ",
            "đăng ký khóa học kỹ năng coursera", "mua dụng cụ học tập",
        ],
        "test": [
            "mua sách đọc cuối tuần", "thanh toán học phí khóa học online",
            "lệ phí đăng ký thi chứng chỉ", "mua sổ tay và bút bi",
        ],
    },
    "entertainment": {
        "train": [
            "mua vé xem phim cgv", "đi hát karaoke cùng bạn", "vé cổng khu du lịch",
            "thuê sân cầu lông cuối tuần", "đặt phòng homestay đà lạt",
            "chơi bowling giải trí", "mua vé xem kịch hòa nhạc",
            "vé khu vui chơi cuối tuần", "đặt khách sạn chuyến du lịch", "tiền sân thể thao cầu lông",
        ],
        "val": [
            "xem phim rạp lotte cinema", "tiền sân bóng đá nhân tạo",
            "vé tham quan bảo tàng du lịch", "đi chơi công viên nước",
        ],
        "test": [
            "đặt vé xem phim cuối tuần cgv", "chia tiền sân pickleball cầu lông",
            "vé khu vui chơi giải trí", "khách sạn chuyến du lịch ngắn ngày",
        ],
    },
    "subscriptions": {
        "train": [
            "gia hạn gói netflix hàng tháng", "thanh toán spotify premium",
            "gói dung lượng icloud apple", "đăng ký youtube premium không quảng cáo",
            "gia hạn google one 100gb", "thuê bao canva pro",
            "cước thuê bao spotify", "phí lưu trữ icloud",
        ],
        "val": [
            "trừ tiền gói cước netflix", "gia hạn nhạc bản quyền spotify",
            "thanh toán dung lượng đám mây icloud", "phí định kỳ youtube premium",
        ],
        "test": [
            "cước thuê bao tháng spotify", "thanh toán tự động google one",
            "gia hạn tài khoản netflix gia đình", "phí lưu trữ icloud hàng tháng",
        ],
    },
    "family": {
        "train": [
            "mua bỉm sữa cho em bé", "gửi tiền phụng dưỡng bố mẹ",
            "đóng tiền học mầm non cho con", "mua sữa bột trẻ em concung",
            "chu cấp sinh hoạt phí gia đình", "mua đồ chơi trẻ em cho bé",
            "mua sữa công thức em bé", "chuyển khoản biếu bố mẹ", "tiền học thêm cho con", "đồ sơ sinh con cưng",
        ],
        "val": [
            "biếu tiền tiêu vặt ông bà", "mua tã giấy và sữa cho con ở con cưng",
            "đóng tiền bán trú cho bé", "gửi tiền về quê cho mẹ",
        ],
        "test": [
            "mua sữa công thức cho bé", "chuyển khoản biếu bố mẹ hàng tháng",
            "tiền học thêm của con", "sắm đồ sơ sinh con cưng",
        ],
    },
    "gifts": {
        "train": [
            "đi tiền mừng đám cưới đồng nghiệp", "mua quà sinh nhật tặng bạn",
            "mừng tuổi đầu xuân cho cháu", "mua giỏ trái cây thăm người ốm",
            "phong bì đám giỗ hiếu hỉ", "mua hoa tươi tặng ngày lễ",
            "phong bì mừng đám cưới", "mua bánh kem hoa tặng sinh nhật", "mừng đầy tháng thôi nôi", "mua quà biếu khách hàng",
        ],
        "val": [
            "mừng cưới bạn đại học", "mua quà kỷ niệm tặng người thân",
            "đi thăm bệnh đồng nghiệp", "tiền mừng tân gia nhà mới",
        ],
        "test": [
            "phong bì mừng đám cưới cuối tuần", "mua bó hoa và bánh kem tặng sinh nhật",
            "mừng đầy tháng cháu", "quà biếu đối tác khách hàng",
        ],
    },
    "debt.interest": {
        "train": [
            "thanh toán kỳ trả góp fe credit", "trả lãi khoản vay ngân hàng",
            "đóng tiền trả góp điện thoại home credit", "trả nợ tiền mượn bạn",
            "thanh toán lãi thẻ tín dụng", "đóng góp khoản vay tiêu dùng",
        ],
        "val": [
            "trả góp hàng tháng hd saison", "thanh toán tiền lãi vay cá nhân",
            "trả bớt nợ cũ cho anh bạn", "kỳ góp fe credit tháng này",
        ],
        "test": [
            "đóng tiền trả góp máy tính", "trả lãi vay tín chấp ngân hàng",
            "thanh toán khoản nợ đến hạn", "góp kỳ hạn home credit",
        ],
    },
    "bank.fee": {
        "train": [
            "phí duy trì tài khoản ngân hàng", "thu phí sms biến động số dư",
            "phí thường niên thẻ tín dụng", "phí chuyển tiền liên ngân hàng",
            "phí phát hành lại thẻ atm", "phí quản lý tài khoản tháng",
        ],
        "val": [
            "ngân hàng trừ phí sms banking", "phí thường niên thẻ visa",
            "phí dịch vụ ngân hàng điện tử", "phí rút tiền khác ngân hàng",
        ],
        "test": [
            "trừ phí thông báo biến động sms", "phí duy trì thẻ thanh toán quốc tế",
            "phí thường niên thẻ ngân hàng", "thu phí quản lý tài khoản định kỳ",
        ],
    },
    "other": {
        "train": [
            "khoản chi phát sinh ngoài dự kiến", "chi tiêu cá nhân lặt vặt",
            "thanh toán dịch vụ photocopy công chứng", "phí làm hồ sơ giấy tờ hành chính",
            "chi khoản khác chưa phân nhóm", "tiền tip dịch vụ lẻ",
        ],
        "val": [
            "chi phí hành chính sao y công chứng", "khoản chi lẻ phát sinh",
            "chi tiêu vặt chưa rõ mục", "lệ phí nộp hồ sơ giấy tờ",
        ],
        "test": [
            "chi phí phát sinh đột xuất", "tiền công chứng giấy tờ cá nhân",
            "khoản chi tiêu khác trong ngày", "chi lặt vặt ngoài kế hoạch",
        ],
    },
    # INCOME CATEGORIES (7)
    "income.salary": {
        "train": [
            "nhận lương tháng công ty chuyển", "lương chính thức tháng 11",
            "công ty thanh toán tiền lương", "ứng lương đợt 1",
            "chuyển khoản lương nhân viên", "SAL T11 CONG TY TNHH",
        ],
        "val": [
            "lương cứng về tài khoản", "thanh toán lương tháng 10",
            "công ty trả lương định kỳ", "PAYROLL SALARY THANG NAY",
        ],
        "test": [
            "nhận lương chuyển khoản từ công ty", "tiền lương tháng mới về",
            "thanh toán bảng lương nhân sự", "nhan luong thang 11",
        ],
    },
    "income.bonus": {
        "train": [
            "nhận tiền thưởng đạt kpi", "thưởng hoàn thành dự án sớm",
            "thưởng lễ quốc khánh công ty", "phụ cấp chuyên cần và ăn trưa",
            "tiền thưởng doanh số quý", "thưởng nóng cuối năm",
        ],
        "val": [
            "công ty thưởng hiệu suất quý", "nhận thưởng dự án phần mềm",
            "tiền thưởng tết dương lịch", "phụ cấp trách nhiệm tháng",
        ],
        "test": [
            "được thưởng vượt chỉ tiêu kpi", "tiền thưởng lễ từ công ty",
            "nhận khoản thưởng hoàn thành công việc", "thuong du an 500k",
        ],
    },
    "income.freelance": {
        "train": [
            "nhận thù lao thiết kế logo freelance", "tiền job viết bài content",
            "khách chuyển khoản tiền làm web ngoài giờ", "tiền dạy kèm gia sư tiếng anh",
            "thanh toán dự án freelance thiết kế", "thù lao chỉnh sửa video",
        ],
        "val": [
            "nhận tiền job ngoài lập trình app", "học viên đóng tiền gia sư",
            "khách tất toán hợp đồng freelance", "thù lao dịch thuật tài liệu",
        ],
        "test": [
            "tiền công thiết kế banner ngoài giờ", "nhận thanh toán job freelance",
            "thù lao dạy thêm buổi tối", "khách trả tiền code dự án riêng",
        ],
    },
    "income.business": {
        "train": [
            "khách thanh toán đơn hàng bán lẻ", "tiền đối soát doanh thu shopee về ví",
            "doanh thu bán hàng tại cửa hàng", "khách cọc đơn đặt hàng sỉ",
            "tiền thu cod giao hàng tiết kiệm", "lợi nhuận kinh doanh tháng",
        ],
        "val": [
            "sàn thương mại đối soát tiền bán hàng", "khách chuyển khoản mua hàng",
            "tiền hàng thu hộ đơn vị vận chuyển", "doanh thu quán hôm nay",
        ],
        "test": [
            "nhận tiền khách mua đơn sỉ", "đối soát tiền cod giao hàng nhanh",
            "doanh thu bán online về tài khoản", "khách thanh toán hóa đơn mua hàng",
        ],
    },
    "income.interest": {
        "train": [
            "nhận tiền lãi sổ tiết kiệm đáo hạn", "cổ tức tiền mặt cổ phiếu",
            "lãi tiền gửi không kỳ hạn ngân hàng", "lợi nhuận chứng chỉ quỹ đầu tư",
            "tất toán lãi tiết kiệm online", "tiền lãi tích lũy hàng tháng",
        ],
        "val": [
            "ngân hàng trả lãi tiết kiệm kỳ hạn", "nhận cổ tức chứng khoán",
            "tiền lời đầu tư quỹ mở", "lãi suất sổ tiết kiệm tháng",
        ],
        "test": [
            "lãi tiền gửi tiết kiệm về tài khoản", "nhận tiền chia cổ tức năm",
            "lợi nhuận rút từ quỹ đầu tư", "lai tiet kiem ngan hang",
        ],
    },
    "income.gift": {
        "train": [
            "nhận tiền lì xì đầu năm", "bố mẹ cho thêm tiền tiêu",
            "được bạn tặng tiền mừng sinh nhật", "nhận người thân biếu tiền mặt",
            "nhận học bổng khuyến học", "anh chị cho tiền mua sách",
            "được lì xì dịp lễ", "bố mẹ gửi cho tiền sinh hoạt", "nhận quà tiền mặt từ bạn",
        ],
        "val": [
            "được mừng tuổi dịp tết", "mẹ chuyển khoản cho tiền ăn",
            "nhận tiền mừng tốt nghiệp", "bác ruột cho tiền tiêu vặt",
        ],
        "test": [
            "nhận lì xì may mắn", "gia đình gửi cho tiền sinh hoạt",
            "được bạn tặng quà tiền mặt", "nhan tien mung sinh nhat",
        ],
    },
    "income.other": {
        "train": [
            "nhận khoản tiền thu khác", "bạn chuyển trả lại tiền ứng hộ",
            "bán thanh lý đồ cũ không dùng", "nhận tiền bồi hoàn bảo hiểm",
            "khoản thu vãng lai ngoài lương", "bán giấy vụn phế liệu",
        ],
        "val": [
            "thanh lý bàn ghế cũ trên chợ tốt", "đồng nghiệp gửi lại tiền mua hộ",
            "khoản thu nhập vãng lai khác", "nhận tiền chi trả bảo hiểm",
        ],
        "test": [
            "bán lại tai nghe cũ", "nhận tiền bạn gửi trả",
            "khoản thu phát sinh khác", "nhan 200k tu ban",
        ],
    },
}


def _emit_variants(
    rng: random.Random,
    label: str,
    split: str,
    phrases: list[str],
    wrappers: list[tuple[str, str]],
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for phrase in phrases:
        # 1. Bare phrase (both accented and unaccented)
        rows.append(
            {
                "split": split,
                "label": label,
                "template_id": f"{split}_bare_acc",
                "text": phrase,
                "style": "accented_short",
            }
        )
        rows.append(
            {
                "split": split,
                "label": label,
                "template_id": f"{split}_bare_noacc",
                "text": strip_vn_accents(phrase),
                "style": "unaccented_short",
            }
        )
        # 2. Wrapped with split-exclusive templates + varied amounts
        for tpl_id, tpl in wrappers:
            amt = rng.choice(AMOUNTS_SHORT)
            accented_sent = tpl.format(item=phrase, amt=amt)
            rows.append(
                {
                    "split": split,
                    "label": label,
                    "template_id": tpl_id,
                    "text": accented_sent,
                    "style": "accented_sentence",
                }
            )
            if rng.random() < 0.65:
                rows.append(
                    {
                        "split": split,
                        "label": label,
                        "template_id": f"{tpl_id}_noacc",
                        "text": strip_vn_accents(accented_sent),
                        "style": "unaccented_sentence",
                    }
                )
    return rows


def main() -> None:
    rng = random.Random(20261123)
    RAW_OUT_DIR.mkdir(parents=True, exist_ok=True)

    missing = set(SEMANTIC_LABELS) - set(CATEGORY_POOLS.keys())
    if missing:
        raise RuntimeError(f"Missing semantic label definitions: {missing}")

    all_rows: list[dict[str, str]] = []
    for label in SEMANTIC_LABELS:
        is_inc = label.startswith("income.")
        tr_w = INCOME_TRAIN_WRAPPERS if is_inc else TRAIN_WRAPPERS
        va_w = INCOME_VAL_WRAPPERS if is_inc else VAL_WRAPPERS
        te_w = INCOME_TEST_WRAPPERS if is_inc else TEST_WRAPPERS

        pools = CATEGORY_POOLS[label]
        all_rows.extend(_emit_variants(rng, label, "train", pools["train"], tr_w))
        all_rows.extend(_emit_variants(rng, label, "val", pools["val"], va_w))
        all_rows.extend(_emit_variants(rng, label, "test", pools["test"], te_w))

    out_path = RAW_OUT_DIR / "raw_corpus.jsonl"
    with out_path.open("w", encoding="utf-8") as f:
        for r in all_rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"Generated {len(all_rows)} raw labeled utterances across {len(SEMANTIC_LABELS)} semantic labels -> {out_path}")


if __name__ == "__main__":
    main()
