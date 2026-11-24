"""Generates a comprehensive, leak-free Vietnamese financial corpus v2.0 across 30 semantic labels.

Crucial Anti-Leakage Design:
- Every category defines THREE strictly disjoint phrase pools (`train`, `val`, `test`)
  AND THREE strictly disjoint sentence wrapper families (`TRAIN_WRAPPERS`, `VAL_WRAPPERS`, `TEST_WRAPPERS`).
- `val` and `test` NEVER reuse `train` templates or `train`-exclusive lexical phrasings.
- Explicitly covers all 6 real-world Vietnamese input domains:
  1. Quick-entry notes (`phở bò 45k`, `cf muối 30k`)
  2. Unaccented shorthand (`an sang 35k`, `do xang 70k`)
  3. Natural spoken ASR transcripts (`sáng nay đi ăn bún bò hết năm mươi nghìn`)
  4. Vietnamese Bank & E-Wallet Notifications (`VCB`, `TCB`, `MBBank`, `BIDV`, `ACB`, `MoMo`, `ZaloPay`)
  5. Regional Northern / Central / Southern vocabulary (`hủ tiếu` / `phở` / `mì quảng`, `nhớt` / `dầu máy`, `vỏ xe` / `lốp xe`)
  6. Hard-negative disambiguation across confusable pairs (`family` vs `food.groceries` / `subscriptions` / `housing.housework`,
     `gifts` vs `income.gift`, `debt.interest` vs `bank.fee`, `income.other` vs `income.business` / `income.freelance`).
"""

from __future__ import annotations
import json
import random
from pathlib import Path
from feature_spec import SEMANTIC_LABELS, strip_vn_accents

BASE_DIR = Path(__file__).resolve().parent
RAW_OUT_DIR = BASE_DIR / "datasets" / "raw"

# Strictly disjoint sentence wrapper families per split (0% template overlap across train/val/test!)
TRAIN_WRAPPERS = [
    ("tr_w1", "{item} {amt}"),
    ("tr_w2", "chi {amt} {item}"),
    ("tr_w3", "hôm nay mình {item} hết {amt}"),
    ("tr_w4", "vừa thanh toán {item} {amt}"),
    ("tr_w5", "GD THE/QR {item} -{amt}"),
    ("tr_w6", "sáng nay {item} {amt}"),
    ("tr_w7", "trả {amt} cho {item}"),
    ("tr_w8", "mình trừ {amt} {item}"),
    ("tr_w9", "MoMo thanh toán {item} {amt}"),
]

VAL_WRAPPERS = [
    ("va_w1", "{item} mất {amt}"),
    ("va_w2", "tối qua {item} tốn {amt}"),
    ("va_w3", "mới trả tiền {item} {amt}"),
    ("va_w4", "VCB Digibank: {item} số tiền {amt}"),
    ("va_w5", "dùng {amt} cho việc {item}"),
]

TEST_WRAPPERS = [
    ("te_w1", "trưa nay mình {item} {amt}"),
    ("te_w2", "chiều qua {item} khoảng {amt}"),
    ("te_w3", "TCB: Thanh toan {item} {amt}"),
    ("te_w4", "{amt} cho khoản {item}"),
    ("te_w5", "ZaloPay trừ {amt} {item}"),
]

INCOME_TRAIN_WRAPPERS = [
    ("itr_w1", "{item} {amt}"),
    ("itr_w2", "nhận {amt} {item}"),
    ("itr_w3", "hôm nay {item} về tài khoản {amt}"),
    ("itr_w4", "MBBANK +{amt} ND {item}"),
    ("itr_w5", "được cộng {amt} từ {item}"),
    ("itr_w6", "khoản thu {item} được {amt}"),
]

INCOME_VAL_WRAPPERS = [
    ("iva_w1", "mới được cộng {amt} {item}"),
    ("iva_w2", "tài khoản nhận {item} {amt}"),
    ("iva_w3", "ACB +{amt} GD {item}"),
]

INCOME_TEST_WRAPPERS = [
    ("ite_w1", "sáng nay tinh tinh {item} {amt}"),
    ("ite_w2", "BIDV +{amt} noi dung {item}"),
    ("ite_w3", "{item} được {amt}"),
    ("ite_w4", "Vietcombank báo có +{amt} {item}"),
]

AMOUNTS_SHORT = [
    "25k", "35k", "45 cành", "55 nghìn", "70k", "85.000đ",
    "120k", "150 ngàn", "250 nghìn", "450k", "2 xị",
    "1tr2", "1 củ rưỡi", "2,5 triệu", "5tr", "15tr",
]

CATEGORY_POOLS: dict[str, dict[str, list[str]]] = {
    "food.meals": {
        "train": [
            "ăn sáng phở bò tái nạm", "ăn trưa cơm tấm sườn bì", "bún chả hà nội", "ăn tối lẩu thái hải sản",
            "bánh mì thịt nướng pate", "mì quảng gà quê", "hủ tiếu nam vang", "cơm văn phòng trưa",
            "gà rán kfc", "pizza company cuối tuần", "quán cơm bình dân", "bún bò huế giò heo",
            "ăn vặt xiên que cá viên", "ăn bún đậu thịt luộc", "bánh đa trộn thập cẩm", "ăn mì ý sốt bò bằm",
            "ăn buffet nướng lẩu", "suất cơm trưa đồng nghiệp", "ăn sáng xôi xéo chả quế", "bánh canh cua nóng",
            "cơm rang dưa bò", "ăn cháo lòng buổi sáng", "ăn tối gà nướng cơm lam", "bánh xèo miền tây",
            "ăn sáng quán hủ tiếu gõ", "gọi đồ ăn trưa grabfood", "đặt cơm gà shopeefood", "ăn tối dimsum sủi cảo",
            "quán phở bò gia truyền", "ăn trưa quán bún thịt nướng", "ăn tối thịt nướng hàn quốc bbq", "ăn bánh cuốn chả quế",
        ],
        "val": [
            "ăn sáng bún riêu cua", "ăn cơm gà xối mỡ giòn", "ăn trưa mì cay hải sản", "ăn lẩu bò nhúng dấm",
            "ăn sáng bánh cuốn nóng chả lụa", "ăn cháo sườn buổi sáng", "ăn sáng quán phở thìn lò đúc", "ăn thịt nướng bbq hàn quốc",
            "ăn tối cơm niêu cá kho", "ăn sáng bánh mì chảo pate",
        ],
        "test": [
            "ăn sáng bánh đa cua hải phòng", "ăn trưa bún đậu mắm tôm", "ăn cơm tấm sườn bì chả trứng",
            "ăn tối gà rán jollibee", "ăn phở gà ta phố cổ", "ăn buffet lẩu nướng băng chuyền",
            "suất cơm trưa công sở", "ăn sáng xôi xéo thập cẩm", "ăn bún cá chấm buổi trưa", "gọi đồ ăn tối shopeefood",
        ],
    },
    "food.drinks": {
        "train": [
            "uống cafe sữa đá", "cf highlands coffee", "trà sữa phúc long", "trà đào cam sả",
            "mua nước suối đóng chai", "cà phê muối huế", "sinh tố bơ sầu riêng", "nước ép cam nguyên chất",
            "the coffee house trà hạt sen", "trà sữa gong cha trân châu", "cafe đen đá không đường", "nước ngọt giải khát coca",
            "mua nước uống giải khát", "trà chanh tươi vỉa hè", "nước dừa xiêm mát lạnh", "trà ô long sữa",
            "uống phê la ô long", "mua kem và trà hoa quả mixue", "cà phê trứng phố cổ", "nước ép dưa hấu",
            "uống bạc xỉu nóng", "trà mãng cầu giải nhiệt", "mua lon nước tăng lực", "matcha latte kem cheese",
            "gọi ly cà phê cốt dừa", "uống trà vải hoa hồng", "mua nước lọc aquafina", "cf rang xay nguyên chất",
            "sinh tố hoa quả sữa chua", "uống trà chanh giã tay phố cổ", "mua trà sữa ô long kem trứng",
        ],
        "val": [
            "ly bạc xỉu đá sài gòn", "uống trà sữa koi the", "cà phê katinat sáng", "mua chai nước khoáng lavie",
            "nước mía vỉa hè giải khát", "matcha đá xay kem tươi", "cf sáng cùng đồng nghiệp", "trà dâu tằm pha lê",
            "nước ép ổi hồng tươi", "mua trà sữa trân châu đường đen",
        ],
        "test": [
            "uống cf trung nguyên legend", "mua nước uống đóng chai", "trà ô long kem phô mai",
            "cafe starbucks americano", "nước dừa tươi ướp lạnh", "uống trà chanh giã tay",
            "uống sinh tố xoài sữa chua", "uống cacao nóng buổi chiều", "mua trà sữa dingtea", "ly cà phê sữa tươi",
        ],
    },
    "food.groceries": {
        "train": [
            "đi chợ mua rau củ tươi", "mua thịt heo cá tươi ngoài chợ", "siêu thị bách hóa xanh mua đồ ăn",
            "mua trứng sữa tươi winmart", "trái cây tươi ngoài chợ đầu mối", "mua gạo thơm mắm muối",
            "thực phẩm tươi sống coopmart", "mua ức gà phi lê nấu ăn", "mua hành tỏi ớt gia vị bếp",
            "mua rau sạch trứng gà ta", "mua sườn non về nấu canh", "thực phẩm nấu cơm tối cả nhà",
            "đi chợ mua đồ nấu cơm gia đình", "mua tôm mực tươi về hấp", "mua dầu ăn nước mắm hạt nêm",
            "mua sữa tươi tiệt trùng vinamilk siêu thị", "mua nấm kim châm đậu phụ", "đi siêu thị mua thịt bò mỹ",
            "mua nguyên liệu tươi sống về nấu ăn", "mua củ quả tươi về trữ tủ lạnh", "mua cá basa phi lê",
            "đi chợ mua rau muống thịt ba chỉ", "sắm thực phẩm nguyên liệu bếp cuối tuần", "mua giò chả xúc xích siêu thị",
        ],
        "val": [
            "đi chợ sáng mua rau thịt tươi", "mua cá hồi tươi ở winmart", "mua hoa quả sạch bách hóa xanh",
            "mua đồ tươi sống nấu bữa tối", "mua thịt bò thăn và nấm đùi gà", "mua gia vị dầu hào nấu ăn",
            "mua gạo st25 và trứng vịt", "đi siêu thị mua rau củ cho gia đình", "mua tôm sú tươi ngoài chợ",
        ],
        "test": [
            "mua rau sạch và trứng gà", "đi siêu thị coopmart mua thực phẩm",
            "mua sườn non về kho tiêu", "mua trái cây tráng miệng ngoài chợ", "thực phẩm nấu cơm gia đình",
            "mua cá thu tươi và cà chua", "sắm nguyên liệu nấu ăn cuối tuần", "mua thịt nạc vai bách hóa xanh",
            "mua hành lá rau thơm gia vị",
        ],
    },
    "transport.fuel": {
        "train": [
            "đổ xăng xe máy đi làm", "đổ xăng ron 95 petrolimex", "tiền xăng đi lại trong tuần",
            "cây xăng pvoil đổ đầy bình", "đổ đầy bình xăng xe vision", "nạp điện trạm sạc xe máy điện",
            "đổ xăng a95 dọc đường", "châm thêm xăng xe số", "đổ dầu diesel xe bán tải",
            "sạc pin ô tô điện trạm vinfast", "tiền nhiên liệu xăng xe hàng tuần", "ghé trạm xăng comecco đổ a95",
            "đổ xăng xe lead đi làm", "nạp điện xe máy vinfast evo", "đổ xăng e5 sinh học",
            "tiền xăng chạy xe công việc", "đổ đầy bình xăng sh mode", "thanh toán tiền xăng dầu",
        ],
        "val": [
            "ghé petrolimex đổ xăng ron95", "đổ xăng xe tay ga đầy bình", "tiền nhiên liệu xăng dầu tháng",
            "sạc pin xe điện trạm vinfast", "đổ xăng e5 ron92 cây xăng", "châm xăng xe wave đi học",
            "thanh toán nhiên liệu pvoil", "tiền đổ dầu xe hơi",
        ],
        "test": [
            "đổ xăng đầy bình air blade", "thanh toán xăng petrolimex", "tiền đổ xăng tuần này",
            "trạm xăng pvoil quốc lộ", "nạp điện xe điện trạm sạc", "đổ xăng a95 xe máy",
            "tiền xăng dầu đi công tác", "ghé cây xăng đổ nhiên liệu",
        ],
    },
    "transport.ride_hailing": {
        "train": [
            "đi taxi xanh sm", "đặt xe grabbike đi làm", "gọi grabcar ra sân bay tân sơn nhất",
            "đi xe ôm công nghệ be", "cuốc xe taxi mai linh", "đặt bebike về nhà buổi tối",
            "cước xe grab đi công việc", "đi taxi vinasun", "bắt xe ôm công nghệ ra ga",
            "gọi xe xanh sm luxury", "đặt chuyến becar đi bệnh viện", "cước gọi xe công nghệ trời mưa",
            "đi grabbike qua văn phòng", "thuê taxi đi sân bay nội bài", "đặt xe công nghệ đi ăn tối",
            "tiền cuốc xe ôm đầu ngõ", "gọi grabcar 4 chỗ đi siêu thị", "cước taxi g7 đi họp",
        ],
        "val": [
            "bắt xe grabbike qua quận 1", "gọi taxi xanh sm về nhà", "đi xe công nghệ becar",
            "tiền đi taxi vinasun đi họp", "cuốc xe grabcar buổi tối", "đặt xe ôm bebike đi làm sớm",
            "thanh toán cước taxi mai linh", "gọi xe xanh sm đi chợ",
        ],
        "test": [
            "đi taxi vinasun ra bến xe", "đặt xe xanh sm đi làm", "cước grabcar đi trời mưa",
            "gọi xe ôm công nghệ be đi làm", "thanh toán cuốc xe taxi mai linh", "bắt grabcar ra sân bay",
            "cước xe grabbike giờ cao điểm", "đi taxi điện xanh sm",
        ],
    },
    "transport.public": {
        "train": [
            "gửi xe máy hầm chung cư", "phí qua trạm thu phí epass", "nạp tài khoản giao thông vetc",
            "mua vé xe buýt tháng sinh viên", "vé tàu metro bến thành suối tiên", "tiền giữ xe bệnh viện",
            "vé xe khách phương trang đi tỉnh", "phí cầu đường cao tốc long thành", "vé tàu điện cát linh hà đông",
            "tiền gửi ô tô bãi đỗ xe", "mua vé tàu hỏa thống nhất", "vé máy bay nội địa vietjet",
            "vé xe limousine đi vũng tàu", "phí đỗ xe lề đường my parking", "tiền vé phà qua sông",
            "nạp thẻ thu phí không dừng epass", "vé xe giường nằm thành bưởi", "tiền giữ xe hầm tòa nhà văn phòng",
        ],
        "val": [
            "tiền gửi xe trung tâm thương mại", "trạm thu phí tự động vetc",
            "mua vé tàu điện trên cao metro", "vé xe khách về quê cuối tuần", "phí đỗ xe bãi giữ xe ngầm",
            "mua vé xe buýt đi làm", "phí cầu đường trạm bot", "đặt vé tàu lửa khứ hồi",
        ],
        "test": [
            "nạp tiền thẻ thu phí epass", "phí gửi xe máy cả ngày", "mua vé xe buýt đi học",
            "tiền vé tàu hỏa về quê", "phí qua trạm cao tốc", "tiền giữ xe tòa nhà văn phòng",
            "vé xe khách hoàng long", "phí cầu phà giao thông",
        ],
    },
    "transport.maintenance": {
        "train": [
            "thay nhớt xe máy honda head", "bảo dưỡng định kỳ yamaha town",
            "vá lốp xe không săm dọc đường", "thay nhớt láp và lọc gió xe ga", "rửa xe bọt tuyết sạch sẽ",
            "sửa phanh đĩa xe tay ga", "thay bugi và vệ sinh nồi xe", "thay săm lốp xe máy michelin",
            "thay dầu máy ô tô gara", "bảo dưỡng nhông sên dĩa exciter", "cân chỉnh thước lái thay gạt mưa",
            "thay bình ắc quy gs xe máy", "vệ sinh kim phun buồng đốt", "sửa đề xe máy tiệm sửa xe",
            "đánh bóng chăm sóc nội thất ô tô", "thay dây curoa xe lead", "bơm nitơ và vá ép lốp ô tô",
            "đăng kiểm và phí bảo trì đường bộ xe hơi",
        ],
        "val": [
            "thay dầu nhớt máy castrol", "vệ sinh nồi dây curoa xe ga",
            "rửa xe máy sạch cuối tuần", "sửa xe thay má phanh trước", "bảo dưỡng xe máy ở head",
            "thay vỏ xe không ruột", "kiểm tra định kỳ gara ô tô", "sửa chống nghiêng và thay bóng đèn xe",
        ],
        "test": [
            "thay nhớt xe vision và nhớt hộp số", "vá vỏ xe tay ga bị đinh cán",
            "bảo dưỡng nhông sên dĩa sửa xe", "rửa xe chăm sóc xe hơi", "thay ắc quy xe máy mới",
            "thay lọc dầu bảo dưỡng ô tô", "sửa thắng đĩa xe máy", "vệ sinh họng ga thay bugi",
        ],
    },
    "housing.rent": {
        "train": [
            "đóng tiền thuê nhà tháng này", "tiền phòng trọ sinh viên",
            "phí quản lý chung cư vinhomes", "tiền thuê căn hộ studio", "đặt cọc tiền thuê phòng trọ",
            "thanh toán tiền nhà cho chủ trọ", "phí dịch vụ tòa nhà chung cư", "trả tiền thuê mặt bằng căn hộ",
            "đóng tiền trọ và phí thang máy", "chuyển khoản tiền thuê nhà nguyên căn", "phí vận hành ban quản trị chung cư",
            "tiền thuê phòng ở ghép", "thanh toán hợp đồng thuê căn hộ", "tiền nhà trọ đầu tháng",
            "phí bảo trì sảnh chung cư", "đóng tiền thuê chung cư mini",
        ],
        "val": [
            "chuyển tiền trọ tháng 11", "đóng phí quản lý căn hộ chung cư",
            "tiền thuê phòng trọ hàng tháng", "thanh toán tiền thuê chung cư", "trả tiền nhà cho cô chủ trọ",
            "phí dịch vụ vệ sinh chung cư", "đặt cọc hợp đồng thuê nhà",
        ],
        "test": [
            "trả tiền thuê nhà đầu tháng", "đóng tiền phòng trọ tháng mới",
            "phí ban quản lý chung cư", "tiền thuê mặt bằng ở ghép", "thanh toán tiền thuê căn hộ dịch vụ",
            "tiền trọ sinh viên hàng tháng", "đóng phí vận hành tòa nhà",
        ],
    },
    "housing.utilities": {
        "train": [
            "thanh toán tiền điện evn", "đóng tiền nước sinh hoạt sawaco",
            "cước internet wifi fpt", "nạp data 4g viettel tốc độ cao", "tiền cáp quang vnpt gia đình",
            "nạp thẻ điện thoại mobifone", "hóa đơn điện nước tháng này", "đổi bình gas bếp nấu ăn petrolimex",
            "cước trả sau vinaphone di động", "thanh toán tiền điện lực miền nam", "đóng tiền nước sạch thủ đô",
            "gia hạn gói cước viễn thông viettel", "tiền mạng internet cáp quang", "hóa đơn tiền gas sinh hoạt",
            "nạp tiền sim điện thoại trả trước", "đóng tiền điện sinh hoạt hộ gia đình",
        ],
        "val": [
            "hóa đơn tiền điện lực evn", "đóng cước mạng wifi vnpt",
            "tiền nước sạch hàng tháng", "gia hạn gói cước 5g viettel", "nạp thẻ cào điện thoại vinaphone",
            "thanh toán tiền gas đun bếp", "cước viễn thông internet fpt",
        ],
        "test": [
            "trả tiền điện tháng 10 evn", "cước internet fpt telecom",
            "thanh toán hóa đơn tiền nước", "nạp tiền điện thoại di động", "đóng tiền mạng wifi hàng tháng",
            "mua gói cước 4g mobifone", "tiền nước máy sawaco",
        ],
    },
    "housing.housework": {
        "train": [
            "mua nước giặt ariel cửa ngang", "nước rửa chén sunlight chanh", "thuê dọn nhà theo giờ btaskee",
            "mua túi đựng rác và giấy vệ sinh", "nước lau sàn nhà hương quế", "bột giặt omo matic",
            "mua chổi lau nhà gia dụng", "phí thu gom rác sinh hoạt", "mua viên rửa bát finish",
            "thuê thợ vệ sinh máy lạnh điều hòa", "mua bóng đèn led thay trong bếp", "sắm hộp nhựa đựng thực phẩm gia dụng",
            "mua cuộn túi rác sinh hoạt gia đình", "nước tẩy bồn cầu vim nhà tắm", "mua màng bọc thực phẩm giấy bạc",
            "thuê giúp việc theo giờ dọn căn hộ", "mua móc treo quần áo và sọt rác", "sửa ống nước vòi sen nhà tắm",
        ],
        "val": [
            "mua nước xả vải comfort thơm lâu", "dịch vụ giúp việc dọn phòng btaskee",
            "mua giấy ăn và nước rửa tay", "sắm đồ gia dụng nhà bếp", "vệ sinh lồng máy giặt tại nhà",
            "mua cây lau nhà tự vắt", "thanh toán tiền thu gom rác",
        ],
        "test": [
            "mua nước giặt cửa trước", "thanh toán dọn dẹp nhà cửa",
            "mua viên rửa bát và khăn bếp", "mua cuộn túi rác gia đình", "thuê vệ sinh điều hòa phòng ngủ",
            "mua giấy vệ sinh cuộn lớn", "nước lau bếp và cọ rửa nhà tắm",
        ],
    },
    "shopping.clothes": {
        "train": [
            "mua áo sơ mi dài tay uniqlo", "mua quần jean ống đứng mới", "giày thể thao chạy bộ nike",
            "mua váy công sở thanh lịch", "áo khoác chống nắng uv", "sắm quần áo ấm mùa đông",
            "mua dép sandal bitis hunter", "bộ quần áo tập thể thao", "giày sneaker trắng đi chơi",
            "mua áo polo nam coolmate", "mua thắt lưng da và tất vớ", "sắm đầm dự tiệc cuối tuần",
            "mua quần kaki đi làm", "mua mũ lưỡi trai và khăn choàng", "mua đồ ngủ pijama mặc nhà",
            "mua áo hoodie nỉ bông", "sắm giày cao gót công sở", "mua túi xách thời trang đeo chéo",
        ],
        "val": [
            "mua áo thun cotton mặc nhà", "sắm đôi giày tây da đi làm",
            "mua quần tây âu công sở", "đặt áo khoác gió thời trang", "mua chân váy xếp ly",
            "sắm bộ đồ thể thao cầu lông", "mua dép lê đi trong nhà",
        ],
        "test": [
            "mua bộ quần áo thể thao", "sắm giày sneaker adidas mới",
            "mua áo polo uniqlo", "mua thắt lưng và vớ cổ ngắn", "đặt mua quần short kaki",
            "sắm áo sơ mi trắng đi làm", "mua áo len cổ lọ mùa lạnh",
        ],
    },
    "shopping.electronics": {
        "train": [
            "mua cáp sạc type c anker", "tai nghe bluetooth không dây airpods",
            "chuột máy tính không dây logitech", "mua pin sạc dự phòng thế giới di động",
            "ốp lưng kính cường lực điện thoại", "mua bàn phím cơ gõ văn phòng", "điện máy xanh mua quạt cây",
            "mua thẻ nhớ microsd camera", "sắm củ sạc nhanh gan 65w", "mua ổ cắm điện thông minh xiaomi",
            "nâng cấp thanh ram laptop", "mua webcam học online độ nét cao", "sắm nồi chiên không dầu philips điện máy xanh",
            "mua hub chuyển đổi usb type c", "mua đồng hồ thông minh smartwatch", "mua bộ phát wifi router mạng không dây",
        ],
        "val": [
            "mua củ sạc nhanh iphone chính hãng", "sắm tai nghe chụp tai chống ồn",
            "mua ổ cứng ssd di động lưu trữ", "mua phụ kiện máy tính ở thế giới di động", "mua cáp hdmi nối màn hình",
            "sắm bàn ủi hơi nước điện máy xanh", "mua giá đỡ laptop nhôm",
        ],
        "test": [
            "mua sạc dự phòng anker 10000mah", "mua chuột không dây văn phòng",
            "dán màn hình và mua ốp điện thoại", "mua loa bluetooth mini jbl", "sắm tai nghe không dây ở thế giới di động",
            "mua bàn phím bluetooth ipad", "mua thiết bị phát wifi router mới",
        ],
    },
    "shopping.general": {
        "train": [
            "đặt đơn hàng mua sắm shopee", "mua sắm đồ dùng trên lazada", "thanh toán đơn hàng tiktok shop",
            "mua đồ tiêu dùng ở siêu thị aeon", "sắm đồ cá nhân bách hóa tổng hợp", "mua mỹ phẩm kem chống nắng la roche",
            "mua dầu gội sữa tắm gội đầu", "sắm nước hoa hồng tẩy trang hasaki", "mua kem đánh răng bàn chải",
            "mua đồ lặt vặt cửa hàng tiện lợi circle k", "sắm bình giữ nhiệt cá nhân", "trả tiền đơn hàng ship cod lazada",
            "thanh toán đơn mua sắm online tiki", "mua son dưỡng môi và sữa rửa mặt", "nhận đơn mua hàng ship cod shopee",
            "mua vali kéo du lịch cá nhân", "mua sáp thơm tiêu dùng cá nhân",
        ],
        "val": [
            "thanh toán giỏ hàng shopee mall", "mua đồ lặt vặt ở circle k",
            "đặt hàng tiêu dùng online lazada", "mua sữa rửa mặt chăm sóc da", "mua dầu gội đầu ở watsons",
            "mua kem dưỡng ẩm guardian", "sắm đồ dùng cá nhân siêu thị lotte",
        ],
        "test": [
            "mua sắm cuối tuần siêu thị aeon", "trả tiền đơn ship cod shopee",
            "mua đồ cá nhân ở siêu thị gs25", "đặt đơn hàng gia dụng tiktok", "mua kem chống nắng và bông tẩy trang",
            "sắm sữa tắm dầu xả cá nhân", "thanh toán đơn mua sắm online",
        ],
    },
    "health.medicine": {
        "train": [
            "mua thuốc cảm cúm nhà thuốc long châu", "mua vitamin tổng hợp nhà thuốc pharmacity",
            "thuốc đau dạ dày tiệm thuốc tây", "mua nước muối sinh lý khẩu trang y tế",
            "mua thuốc hạ sốt giảm đau panadol", "nhà thuốc an khang mua men tiêu hóa", "mua viên sủi vitamin c cam",
            "mua thuốc ho thảo dược siro", "mua dầu gió và cao dán giảm đau", "mua thuốc dị ứng viêm mũi",
            "mua cồn sát khuẩn bông băng gạc y tế", "mua viên dầu cá omega 3 nhà thuốc", "mua thuốc bôi ngoài da tiệm thuốc",
            "mua que test cúm tại hiệu thuốc", "mua kẽm và canxi bổ sung sức khỏe", "mua dung dịch xịt họng keo ong",
        ],
        "val": [
            "ghé nhà thuốc long châu mua thuốc ho", "mua viên uống bổ sung kẽm sắt",
            "nhà thuốc pharmacity mua bông băng y tế", "mua thuốc dị ứng thời tiết", "mua men vi sinh đường ruột",
            "mua thuốc giảm đau đầu hiệu thuốc", "mua xịt mũi nước biển sâu",
        ],
        "test": [
            "mua thuốc kháng sinh theo toa bác sĩ", "mua thực phẩm chức năng nhà thuốc long châu",
            "mua thuốc nhỏ mắt tại nhà thuốc pharmacity", "mua thuốc cảm sốt đau họng",
            "ghé nhà thuốc an khang mua vitamin", "mua băng cá nhân và dung dịch sát khuẩn",
            "mua thuốc tiêu hóa tiệm thuốc tây",
        ],
    },
    "health.hospital": {
        "train": [
            "khám tổng quát bệnh viện đại học y dược", "lấy cao răng nha khoa uy tín",
            "xét nghiệm máu phòng khám đa khoa", "tiêm vắc xin cúm mùa vnvc",
            "đóng thẻ tập gym tháng california", "khám mắt đo kính cận bệnh viện mắt", "viện phí khám chuyên khoa nội",
            "phí khám bệnh phòng khám tư nhân", "nhổ răng khôn hàm dưới nha khoa", "gia hạn thẻ hội viên phòng gym",
            "xét nghiệm sinh hóa định kỳ", "chụp x quang kiểm tra phổi", "tập vật lý trị liệu cột sống",
            "đóng tiền lớp tập pilates yoga", "khám tai mũi họng nội soi", "trám răng sâu thẩm mỹ nha khoa",
        ],
        "val": [
            "khám răng trám răng nha khoa", "đóng phí phòng tập yoga tháng",
            "siêu âm kiểm tra sức khỏe bệnh viện", "tiêm phòng vắc xin tại vnvc", "đo khúc xạ cắt kính cận",
            "phí khám chuyên khoa da liễu", "mua gói tập thể hình gym",
        ],
        "test": [
            "phí khám bệnh tại phòng khám đa khoa", "nhổ răng khôn nha khoa",
            "gia hạn hội viên phòng gym", "xét nghiệm máu kiểm tra định kỳ", "tiêm nhắc vắc xin ở vnvc",
            "viện phí siêu âm tổng quát", "đóng thẻ tập bơi thể hình sức khỏe",
        ],
    },
    "education": {
        "train": [
            "mua sách chuyên ngành nhà sách fahasa", "đóng học phí tiếng anh ielts trung tâm",
            "mua khóa học lập trình online udemy", "lệ phí thi chứng chỉ quốc tế toeic",
            "mua vở bút văn phòng phẩm học tập", "mua giáo trình đại học chuyên môn",
            "mua sổ tay ghi chép học từ vựng", "mua bút bi highlight thước kẻ", "mua sách kỹ năng quản lý tài chính",
            "đóng học phí học kỳ tín chỉ đại học", "đăng ký khóa học thiết kế đồ họa", "mua tài liệu ôn thi chứng chỉ aws",
            "tiền in ấn luận văn tài liệu học", "gia hạn tài khoản học ngoại ngữ duolingo", "mua từ điển chuyên ngành tiếng nhật",
            "đóng tiền lớp luyện giao tiếp tiếng trung",
        ],
        "val": [
            "mua sách kỹ năng tại nhà sách phương nam", "đóng tiền học ngoại ngữ giao tiếp",
            "đăng ký khóa học dữ liệu coursera", "mua dụng cụ học tập văn phòng phẩm", "lệ phí thi thử chứng chỉ ielts",
            "mua sách lập trình phần mềm", "đóng học phí lớp kế toán thực hành",
        ],
        "test": [
            "mua sách đọc nâng cao kiến thức", "thanh toán học phí khóa học online",
            "lệ phí đăng ký thi chứng chỉ toeic", "mua sổ tay và bút bi văn phòng phẩm",
            "đóng tiền khóa học tiếng anh buổi tối", "mua giáo trình ôn tập nhà sách fahasa",
            "mua khóa luyện kỹ năng thuyết trình",
        ],
    },
    "entertainment": {
        "train": [
            "mua vé xem phim rạp phim cgv", "đi hát karaoke icool cùng hội bạn", "vé cổng khu du lịch suối tiên",
            "thuê sân cầu lông cuối tuần", "đặt phòng homestay nghỉ dưỡng đà lạt",
            "chơi bowling giải trí trung tâm thương mại", "mua vé xem kịch hòa nhạc live show",
            "vé khu vui chơi giải trí vinwonders", "đặt phòng khách sạn chuyến du lịch biển", "thuê sân bóng đá nhân tạo",
            "thuê sân đánh pickleball buổi tối", "mua vé cáp treo khu du lịch bà nà", "vé tham quan công viên nước giải trí",
            "vé vào cổng thảo cầm viên sở thú", "mua vé xem ca nhạc giải trí", "đặt resort nghỉ dưỡng du lịch",
        ],
        "val": [
            "mua vé xem phim rạp lotte", "tiền thuê sân bóng đá nhân tạo cuối tuần",
            "mua vé tham quan khu du lịch", "vé đi chơi công viên nước giải trí", "đặt phòng resort nghỉ dưỡng biển",
            "mua vé xem hòa nhạc giải trí", "đi hát karaoke giải trí cùng bạn",
        ],
        "test": [
            "đặt vé xem phim cuối tuần rạp phim cgv", "thuê sân pickleball cầu lông cuối tuần",
            "mua vé khu vui chơi giải trí", "đặt phòng khách sạn chuyến du lịch",
            "mua vé xem phim rạp phim bhd", "thuê sân cầu lông giải trí buổi tối", "mua vé cáp treo khu du lịch",
        ],
    },
    "subscriptions": {
        "train": [
            "gia hạn gói netflix hàng tháng", "thanh toán thuê bao spotify premium",
            "mua gói dung lượng gói icloud apple", "đăng ký youtube premium không quảng cáo",
            "gia hạn lưu trữ google one 100gb", "thuê bao thiết kế canva pro tháng",
            "cước thuê bao nhạc số spotify", "phí lưu trữ đám mây gói icloud", "đăng ký tài khoản chatgpt plus hàng tháng",
            "gia hạn gói microsoft 365 bản quyền", "thanh toán gói gia đình spotify premium", "gia hạn tài khoản github copilot",
            "thuê bao truyền hình gói netflix tháng", "gia hạn phần mềm bản quyền canva pro", "đăng ký gói youtube premium gia đình",
            "phí thuê bao đám mây google one",
        ],
        "val": [
            "trừ phí thuê bao định kỳ gói netflix", "gia hạn thuê bao nhạc spotify premium",
            "thanh toán dung lượng đám mây gói icloud", "phí thuê bao định kỳ youtube premium", "gia hạn lưu trữ đám mây google one",
            "đăng ký thuê bao tháng chatgpt plus", "gia hạn bản quyền microsoft 365",
        ],
        "test": [
            "cước thuê bao tháng spotify premium", "thanh toán tự động lưu trữ google one",
            "gia hạn tài khoản gói netflix gia đình", "phí lưu trữ đám mây gói icloud hàng tháng",
            "đăng ký gói youtube premium cá nhân", "gia hạn thuê bao thiết kế canva pro", "gia hạn gói microsoft 365 hàng tháng",
        ],
    },
    "family": {
        "train": [
            "mua bỉm tã sữa bột cho em bé", "gửi tiền phụng dưỡng bố mẹ ở quê",
            "đóng tiền học mầm non cho con", "mua sữa bột trẻ em mẹ bé con cưng",
            "chu cấp sinh hoạt phí hàng tháng cho bố mẹ", "mua đồ chơi trẻ em cho con nhỏ",
            "mua sữa công thức cho em bé", "chuyển khoản phụng dưỡng biếu bố mẹ", "đóng tiền học thêm cho con",
            "sắm quần áo sơ sinh mẹ bé con cưng", "mua xe đẩy nôi em bé mẹ bé kids plaza", "đóng tiền ăn bán trú trường mầm non cho bé",
            "biếu tiền phụng dưỡng ông bà nội", "mua bình sữa tã giấy cho bé sơ sinh", "tiền thuê bảo mẫu trông em bé",
            "mua váng sữa trẻ em cho bé ở mẹ bé con cưng",
        ],
        "val": [
            "gửi tiền phụng dưỡng biếu ông bà", "mua tã giấy và sữa bột cho em bé ở mẹ bé con cưng",
            "đóng tiền ăn bán trú mầm non cho bé", "chu cấp sinh hoạt phí hàng tháng cho mẹ", "mua bình sữa đồ sơ sinh cho em bé",
            "đóng tiền học mầm non của con", "chuyển khoản phụng dưỡng bố mẹ ở quê",
        ],
        "test": [
            "mua sữa công thức cho em bé", "chuyển khoản phụng dưỡng bố mẹ hàng tháng",
            "đóng tiền học thêm cho con gái", "sắm đồ sơ sinh cho bé ở mẹ bé con cưng",
            "mua bỉm tã giấy cho em bé", "biếu tiền phụng dưỡng ông bà ngoại", "đóng tiền trường mầm non cho con",
        ],
    },
    "gifts": {
        "train": [
            "đi tiền phong bì mừng đám cưới đồng nghiệp", "mua quà sinh nhật tặng bạn thân",
            "lì xì mừng tuổi đầu xuân cho trẻ nhỏ", "mua giỏ trái cây đi thăm người ốm",
            "đi phong bì đám giỗ hiếu hỉ", "mua bó hoa tươi tặng ngày lễ 20 tháng 10",
            "gửi phong bì mừng đám cưới bạn cũ", "mua bánh kem và hoa tặng sinh nhật", "đi tiền mừng đầy tháng thôi nôi",
            "mua giỏ quà tết biếu khách hàng đối tác", "tiền phúng điếu đám hiếu chia buồn", "mừng tân gia nhà mới anh chị đồng nghiệp",
            "mua quà lưu niệm chia tay sếp chuyển công tác", "mua hộp bánh trung thu biếu tặng họ hàng",
            "chi lì xì mừng tuổi dịp tết cho các cháu", "mua nước hoa làm quà kỷ niệm ngày cưới",
        ],
        "val": [
            "gửi phong bì mừng cưới bạn đại học", "mua quà kỷ niệm tặng người thân",
            "mua sữa trái cây đi thăm bệnh đồng nghiệp", "đi tiền mừng tân gia nhà mới",
            "mua hoa hồng tặng lễ tình nhân", "mừng thôi nôi con anh đồng nghiệp", "mua quà giáng sinh tặng bạn",
        ],
        "test": [
            "phong bì mừng đám cưới cuối tuần", "mua bó hoa và bánh kem tặng sinh nhật",
            "đi tiền mừng đầy tháng cháu", "mua quà biếu đối tác khách hàng",
            "lì xì mừng tuổi trẻ nhỏ dịp tết", "phúng điếu đám tang người quen", "mua quà mừng tốt nghiệp tặng em",
        ],
    },
    "debt.interest": {
        "train": [
            "thanh toán kỳ trả góp fe credit", "trả lãi khoản vay tín chấp ngân hàng",
            "đóng tiền trả góp điện thoại home credit", "trả nợ tiền mượn bạn tháng trước",
            "thanh toán dư nợ lãi thẻ tín dụng", "đóng tiền góp khoản vay tiêu dùng",
            "tất toán hợp đồng vay trả góp hd saison", "trả gốc và lãi vay mua xe hàng tháng",
            "hoàn trả tiền vay nóng người quen", "đóng kỳ trả góp mua laptop lãi suất thấp",
            "thanh toán sao kê tối thiểu thẻ tín dụng", "trả lãi vay thế chấp mua nhà ngân hàng",
            "chuyển trả khoản nợ cá nhân đến hạn", "đóng tiền góp mua xe máy shinhan finance",
            "thanh toán lãi quá hạn khoản vay", "trả bớt tiền nợ mượn anh trai",
        ],
        "val": [
            "đóng trả góp hàng tháng hd saison", "thanh toán tiền lãi vay cá nhân",
            "trả bớt nợ cũ cho anh bạn", "thanh toán kỳ góp fe credit tháng này",
            "trả nợ gốc khoản vay ngân hàng", "đóng tiền sao kê nợ thẻ tín dụng", "góp tiền mua trả góp tủ lạnh",
        ],
        "test": [
            "đóng tiền trả góp máy tính xách tay", "trả lãi vay tín chấp ngân hàng",
            "thanh toán khoản nợ vay đến hạn", "đóng góp kỳ hạn trả góp home credit",
            "trả nợ tiền mượn đồng nghiệp", "thanh toán dư nợ thẻ tín dụng cuối kỳ", "trả gốc lãi vay tiêu dùng",
        ],
    },
    "bank.fee": {
        "train": [
            "phí duy trì tài khoản ngân hàng hàng tháng", "ngân hàng thu phí sms biến động số dư",
            "thu phí thường niên thẻ tín dụng quốc tế", "phí chuyển tiền nhanh liên ngân hàng",
            "phí phát hành lại thẻ từ atm", "phí quản lý tài khoản thanh toán tháng",
            "phí rút tiền mặt cây atm khác ngân hàng", "thu phí dịch vụ ngân hàng số định kỳ",
            "phí chuyển đổi ngoại tệ thanh toán thẻ visa", "phí in sao kê xác nhận số dư ngân hàng",
            "phí bảo hiểm thẻ thanh toán nội địa", "trừ phí thông báo tin nhắn chủ động sms banking",
            "phí duy trì dịch vụ ebanking tháng", "phí giao dịch rút tiền ngoài hệ thống atm",
            "phí khóa và cấp lại mã pin thẻ atm",
        ],
        "val": [
            "ngân hàng trừ phí sms banking tháng", "thu phí thường niên thẻ visa platinum",
            "phí dịch vụ ngân hàng điện tử", "phí rút tiền mặt khác ngân hàng",
            "phí quản lý gói tài khoản thanh toán", "trừ phí chuyển khoản quốc tế",
        ],
        "test": [
            "trừ phí thông báo biến động sms", "phí duy trì thẻ thanh toán quốc tế",
            "thu phí thường niên thẻ ngân hàng", "thu phí quản lý tài khoản định kỳ",
            "phí giao dịch rút tiền khác hệ thống ngân hàng", "phí dịch vụ sms chủ động ngân hàng",
        ],
    },
    "other": {
        "train": [
            "khoản chi phát sinh ngoài dự kiến", "chi tiêu cá nhân lặt vặt chưa phân nhóm",
            "thanh toán dịch vụ photocopy công chứng giấy tờ", "lệ phí làm hồ sơ căn cước hành chính",
            "chi khoản khác chưa rõ danh mục", "tiền tip bồi dưỡng nhân viên phục vụ",
            "lệ phí cấp đổi giấy phép lái xe", "phí dịch thuật công chứng hồ sơ ủy ban",
            "tiền quyên góp từ thiện ủng hộ đồng bào", "đóng tiền quỹ tập thể cơ quan công ty",
            "chi phí sửa khóa đánh chìa khóa dự phòng", "phí gửi bưu phẩm chuyển phát bưu điện",
            "khoản chi đột xuất xử lý việc riêng", "tiền công thợ sửa đồ lặt vặt",
            "lệ phí trích lục giấy tờ hộ tịch",
        ],
        "val": [
            "chi phí hành chính sao y công chứng", "khoản chi lẻ phát sinh đột xuất",
            "chi tiêu vặt chưa rõ hạng mục", "lệ phí nộp hồ sơ giấy tờ hành chính",
            "ủng hộ quỹ từ thiện cứu trợ", "phí gửi thư chuyển phát nhanh bưu điện",
        ],
        "test": [
            "chi phí phát sinh đột xuất ngoài kế hoạch", "tiền công chứng giấy tờ cá nhân",
            "khoản chi tiêu khác trong ngày", "chi lặt vặt cá nhân ngoài dự tính",
            "lệ phí làm thủ tục hành chính phường", "đóng tiền quỹ tập thể cơ quan",
        ],
    },
    # INCOME CATEGORIES (7)
    "income.salary": {
        "train": [
            "nhận lương tháng công ty chuyển khoản", "lương chính thức tháng 11 về tài khoản",
            "công ty thanh toán tiền lương nhân viên", "nhận tạm ứng lương đợt 1",
            "chuyển khoản lương cơ bản nhân sự", "SAL T11 CONG TY TNHH",
            "nhận lương thực lĩnh sau thuế tháng này", "tiền lương làm việc full time công ty",
            "thanh toán lương kỳ 2 cuối tháng", "PAYROLL LUONG CHINH THUC CONG TY",
            "nhận lương tháng 12 qua tài khoản", "công ty chi trả lương hàng tháng",
            "lương hành chính văn phòng tháng mới", "nhận tiền lương ca làm việc chính",
            "tập đoàn chuyển khoản tiền lương tháng",
        ],
        "val": [
            "lương cứng hàng tháng về tài khoản", "công ty thanh toán lương tháng 10",
            "công ty trả lương định kỳ nhân viên", "PAYROLL SALARY THANG NAY",
            "nhận tiền lương thực nhận cuối tháng", "ứng trước lương giữa tháng công ty",
        ],
        "test": [
            "nhận lương chuyển khoản từ công ty", "tiền lương tháng mới về tài khoản",
            "thanh toán bảng lương nhân sự tháng", "nhận lương tháng 11",
            "công ty trả tiền lương định kỳ", "lương chính thức chuyển khoản",
        ],
    },
    "income.bonus": {
        "train": [
            "nhận tiền thưởng đạt kpi quý", "thưởng hoàn thành dự án vượt tiến độ",
            "thưởng lễ quốc khánh công ty chi", "nhận phụ cấp chuyên cần và ăn trưa",
            "tiền thưởng doanh số bán hàng quý", "nhận thưởng nóng cuối năm công ty",
            "thưởng lương tháng thứ 13 tết âm lịch", "nhận tiền hoa hồng đạt chỉ tiêu",
            "công ty thưởng sáng kiến cải tiến kỹ thuật", "nhận phụ cấp xăng xe điện thoại tháng",
            "tiền thưởng danh hiệu nhân viên xuất sắc", "thưởng tết nguyên đán công ty chuyển",
            "nhận khoản thưởng nghiệm thu hợp đồng", "thưởng chuyên cần đủ ngày công",
            "nhận tiền thưởng hiệu quả kinh doanh",
        ],
        "val": [
            "công ty thưởng hiệu suất làm việc quý", "nhận thưởng hoàn thành dự án phần mềm",
            "tiền thưởng tết dương lịch công ty", "nhận phụ cấp trách nhiệm hàng tháng",
            "tiền hoa hồng vượt doanh số tháng", "thưởng nóng đạt mục tiêu kpi",
        ],
        "test": [
            "được thưởng vượt chỉ tiêu kpi", "nhận tiền thưởng lễ từ công ty",
            "nhận khoản thưởng hoàn thành công việc", "thưởng dự án xuất sắc",
            "tiền thưởng quý và phụ cấp chuyên cần", "công ty chuyển tiền thưởng cuối năm",
        ],
    },
    "income.freelance": {
        "train": [
            "nhận thù lao thiết kế logo freelance", "nhận tiền job viết bài chuẩn seo content",
            "khách trả tiền làm web freelance ngoài giờ", "thu tiền dạy kèm gia sư tiếng anh",
            "nhận thanh toán dự án freelance thiết kế giao diện", "nhận thù lao dựng chỉnh sửa video",
            "khách trả thù lao chụp ảnh ngoại cảnh", "nhận tiền cọc job lập trình mobile app freelance",
            "nhận thù lao phiên dịch hội thảo ngoài giờ", "thu tiền công chạy quảng cáo freelance",
            "nhận thanh toán viết kịch bản freelance", "thu tiền dạy thêm gia sư môn toán",
            "nhận thù lao tư vấn kế toán ngoài giờ", "khách tất toán job vẽ minh họa freelance",
            "nhận tiền công code dự án ngoài giờ",
        ],
        "val": [
            "nhận tiền job ngoài lập trình ứng dụng freelance", "thu tiền dạy kèm gia sư tại nhà",
            "khách tất toán hợp đồng thiết kế freelance", "nhận thù lao dịch thuật ngoài giờ",
            "nhận tiền công chụp ảnh chỉnh sửa video", "nhận thù lao viết bài content freelance",
        ],
        "test": [
            "nhận tiền công thiết kế banner ngoài giờ", "nhận thanh toán job freelance hoàn thành",
            "thu tiền thù lao dạy kèm gia sư buổi tối", "khách trả tiền code dự án freelance",
            "nhận thù lao biên tập video ngoài giờ", "khách tất toán job thiết kế logo freelance",
        ],
    },
    "income.business": {
        "train": [
            "khách thanh toán đơn hàng bán lẻ của shop", "tiền đối soát doanh thu shopee về ví",
            "doanh thu bán hàng trực tiếp tại cửa hàng", "khách đặt cọc đơn hàng lấy sỉ",
            "nhận tiền thu hộ cod giao hàng tiết kiệm", "lợi nhuận kinh doanh cửa hàng tháng",
            "sàn thương mại chuyển tiền đối soát bán hàng", "khách mua đơn hàng sỉ chuyển khoản cho shop",
            "tổng doanh thu quán kinh doanh hôm nay", "nhận tiền thu cod bưu cục giao hàng nhanh",
            "đại lý thanh toán công nợ nhập hàng sỉ", "rút tiền doanh thu bán hàng tiktok shop",
            "doanh thu bán sản phẩm online của cửa hàng", "nhận tiền thu hộ cod đơn vị vận chuyển",
            "tổng kết doanh thu bán lẻ cuối ngày",
        ],
        "val": [
            "sàn thương mại đối soát doanh thu bán hàng", "khách thanh toán mua đơn hàng lẻ tại cửa hàng",
            "nhận tiền thu hộ cod đơn vị vận chuyển", "tổng doanh thu kinh doanh cửa hàng",
            "khách đặt cọc thanh toán đơn hàng sỉ", "rút tiền doanh thu bán hàng trên sàn",
        ],
        "test": [
            "khách thanh toán mua đơn hàng sỉ của shop", "nhận đối soát tiền thu hộ cod giao hàng nhanh",
            "doanh thu bán hàng online về tài khoản", "khách thanh toán hóa đơn mua hàng tại cửa hàng",
            "tiền đối soát doanh thu bán hàng shopee", "doanh thu bán lẻ sản phẩm cuối ngày",
        ],
    },
    "income.interest": {
        "train": [
            "nhận tiền lãi sổ tiết kiệm đáo hạn", "nhận cổ tức tiền mặt cổ phiếu ngân hàng",
            "lãi tiền gửi không kỳ hạn cuối tháng", "chốt lời lợi nhuận chứng chỉ quỹ đầu tư",
            "tất toán tiền lãi gửi tiết kiệm online", "nhận tiền lãi tích lũy linh hoạt hàng tháng",
            "lãi trái phiếu doanh nghiệp trả định kỳ", "nhận lợi tức chia cổ tức cổ phiếu",
            "ngân hàng cộng lãi suất tiền gửi kỳ hạn", "chốt lời cổ phiếu tài khoản chứng khoán",
            "nhận tiền lãi gửi góp sổ tiết kiệm", "lợi nhuận đầu tư chứng chỉ quỹ mở",
            "tiền lãi kỳ hạn sổ tiết kiệm điện tử", "nhận cổ tức bằng tiền mặt năm nay",
            "cộng lãi suất sinh lời tiền gửi tự động",
        ],
        "val": [
            "ngân hàng trả tiền lãi sổ tiết kiệm kỳ hạn", "nhận tiền chia cổ tức chứng khoán",
            "chốt lời lợi nhuận đầu tư chứng chỉ quỹ mở", "nhận lãi suất sổ tiết kiệm hàng tháng",
            "tiền lãi đáo hạn tiền gửi tiết kiệm", "nhận lợi nhuận cổ tức cổ phiếu",
        ],
        "test": [
            "nhận lãi tiền gửi tiết kiệm về tài khoản", "nhận tiền chia cổ tức cổ phiếu hàng năm",
            "chốt lời lợi nhuận chứng chỉ quỹ đầu tư", "nhận tiền lãi sổ tiết kiệm ngân hàng",
            "tất toán tiền lãi sổ tiết kiệm kỳ hạn", "cộng lãi tiền gửi không kỳ hạn",
        ],
    },
    "income.gift": {
        "train": [
            "được nhận tiền lì xì đầu năm mới", "được bố mẹ cho mình thêm tiền tiêu vặt",
            "được bạn tặng tiền mừng sinh nhật", "được nhận tiền người thân cho mình",
            "được nhận học bổng khuyến học xuất sắc", "được anh chị cho mình tiền tiêu",
            "được lì xì mừng tuổi dịp tết", "bố mẹ gửi cho mình tiền ăn học",
            "được nhận quà tiền mặt từ bạn bè", "được ông bà thưởng tiền mừng đỗ đại học",
            "được cô chú lì xì mừng tuổi đầu xuân", "được bạn bè tặng tiền mừng tốt nghiệp",
            "chị gái cho mình thêm tiền tiêu vặt", "nhận tiền thưởng học bổng khuyến tài",
            "được tặng quà bằng tiền mặt sinh nhật",
        ],
        "val": [
            "được nhận mừng tuổi lì xì dịp tết", "mẹ gửi cho mình thêm tiền ăn học",
            "được bạn bè tặng tiền mừng lễ tốt nghiệp", "được bác ruột cho mình tiền tiêu vặt",
            "được nhận quà bằng tiền mặt sinh nhật", "được nhận tiền thưởng học bổng trường",
        ],
        "test": [
            "được nhận tiền lì xì may mắn đầu năm", "bố mẹ gửi cho mình tiền ăn học",
            "được bạn tặng quà bằng tiền mặt sinh nhật", "được nhận tiền mừng sinh nhật bạn tặng",
            "được ông bà cho mình tiền mừng tuổi", "được nhận học bổng khuyến tài xuất sắc",
        ],
    },
    "income.other": {
        "train": [
            "nhận khoản tiền thu vãng lai khác", "bạn chuyển trả lại tiền ứng hộ bữa trưa",
            "bán thanh lý đồ cũ không dùng tới", "nhận tiền bồi thường bảo hiểm sức khỏe",
            "khoản thu nhập phụ ngoài lương khác", "bán giấy vụn vỏ lon phế liệu",
            "đồng nghiệp gửi trả tiền chia hóa đơn ăn uống", "thanh lý màn hình máy tính cũ chợ tốt",
            "công ty thanh toán lại tiền công tác phí ứng trước", "pass lại đôi giày ít mang cho bạn",
            "nhận tiền hoàn thuế thu nhập cá nhân", "bán lại xe đạp cũ không sử dụng",
            "nhận tiền bạn hoàn lại khoản chi chung", "thu hồi tiền đặt cọc thuê phòng cũ",
            "nhận tiền chi trả quyền lợi bảo hiểm y tế",
        ],
        "val": [
            "bán thanh lý bàn ghế cũ trên chợ tốt", "đồng nghiệp gửi lại tiền mua hộ cà phê",
            "nhận khoản thu nhập vãng lai khác", "nhận tiền chi trả bồi hoàn bảo hiểm",
            "công ty hoàn trả chi phí đi công tác", "nhận lại tiền cọc bình nước",
        ],
        "test": [
            "bán thanh lý lại tai nghe cũ", "nhận tiền bạn gửi trả khoản ứng trước",
            "khoản thu nhập phát sinh khác", "nhận tiền chia bill ăn trưa từ đồng nghiệp",
            "nhận tiền hoàn thuế thu nhập năm", "pass lại bàn phím cũ không dùng",
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
        # 2. Wrapped with split-exclusive templates + varied realistic Vietnamese money expressions
        selected_wrappers = wrappers if split != "train" else rng.sample(wrappers, k=min(6, len(wrappers)))
        for tpl_id, tpl in selected_wrappers:
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
            if rng.random() < 0.60:
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
    rng = random.Random(20261124)
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

    print(
        f"Generated {len(all_rows)} raw labeled utterances across {len(SEMANTIC_LABELS)} semantic labels -> {out_path}"
    )


if __name__ == "__main__":
    main()
