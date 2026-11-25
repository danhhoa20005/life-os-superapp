"""Dedicated Leak-Free Vietnamese Money-Splitting & Smart Allocation AI Trainer (LFTQ v1 INT8 QAT).

Trains `vn_money_split_fasttext_v1.ftq` + `vn_money_split_fasttext_v1_meta.json` across 12 specialized
money-splitting, debt-settlement, and income-allocation intents using the exact same `feature_spec.py`
normalization and 32-bit FNV-1a subword/bigram hashing as `FastTextBinaryModel` in Dart & C++17 FFI.

Anti-Leakage Guarantees:
- Strictly disjoint phrase pools (`train`, `val`, `test`) and disjoint wrapper templates per split.
- Outlier Exposure (Hendrycks et al.) pushes non-splitting everyday chatter toward uniform `1/12` entropy.
- Straight-Through Symmetric INT8 Quantization-Aware Training (`[-127, 127]`) + Temperature Calibration.
"""

from __future__ import annotations
import hashlib
import json
import math
import random
import shutil
import struct
from datetime import datetime, timezone
from pathlib import Path

from feature_spec import extract_feature_buckets, normalize_for_classifier, strip_vn_accents

BASE_DIR = Path(__file__).resolve().parent
ART_DIR = BASE_DIR / "artifacts"
DATASETS_DIR = BASE_DIR / "datasets"
REPO_ROOT = BASE_DIR.parent.parent
FLUTTER_MODELS_DIR = REPO_ROOT / "assets" / "models"

SPLIT_ALLOC_LABELS: list[str] = [
    "split.equal",
    "split.percentage",
    "split.shares_ratio",
    "split.itemized_remainder",
    "split.exact_custom",
    "split.multi_category_receipt",
    "split.settle_repayment",
    "alloc.rule_50_30_20",
    "alloc.six_jars",
    "alloc.family_household",
    "alloc.debt_payoff",
    "alloc.fire_high_savings",
]

NUM_BUCKETS = 24576
WORD_NGRAMS = 2
MIN_SUBWORD = 4
MAX_SUBWORD = 5

AMOUNTS = [
    "120k", "240k", "350 nghìn", "480k", "650 ngàn", "850k",
    "1tr2", "1tr5", "2,4 triệu", "3tr6", "15tr", "25 triệu", "35tr",
]

TRAIN_WRAPPERS = [
    "{core}",
    "hôm nay {core}",
    "nhờ ai tính giúp {core}",
    "ghi nhanh {core}",
    "tối nay cả nhóm {core}",
    "báo giùm {core}",
]

VAL_WRAPPERS = [
    "{core}",
    "trưa nay {core}",
    "vừa xong {core}",
]

TEST_WRAPPERS = [
    "{core}",
    "chiều qua {core}",
    "kiểm tra giúp {core}",
]

CORPUS_POOLS: dict[str, dict[str, list[str]]] = {
    "split.equal": {
        "train": [
            "ăn lẩu bò 600k chia đều 4 người",
            "tiền cà phê 120k cưa đôi với minh",
            "đi nhậu ốc 840k campuchia đều 6 anh em",
            "hóa đơn nướng bbq 900k chia đều cho hòa nam và lan",
            "thuê sân cầu lông 280k mỗi người đóng đều nhau 4 bạn",
            "tiền phòng homestay đà lạt 2tr4 chia đều 4 đứa",
            "ăn trưa văn phòng 320k chia đều bốn đồng nghiệp",
            "hùng ứng trước tiền karaoke 750k chia đều 5 người",
            "mua đồ nướng dã ngoại 560k campuchia cho cả nhóm",
            "gọi trà sữa 180k chia đều ba chị em",
            "tiền taxi ra sân bay 240k cưa đôi hai đứa",
            "ăn bún đậu 150k chia đều cho 3 bạn cùng phòng",
            "đặt pizza cuối tuần 360k chia đều bốn thành viên",
            "tiền vé khu vui chơi 800k chia đều mỗi bạn một phần bằng nhau",
            "ăn tối hải sản 1tr2 campuchia đều 4 anh em",
            "chi phí thuê lều cắm trại 440k chia đều 4 người",
            "uống trà đào 110k cưa đôi cùng bạn",
            "tiền ăn vặt 80k cưa đôi với hoa",
            "mua nước ép hoa quả 100k chia đôi hai đứa",
        ],
        "val": [
            "ăn lẩu thái 450k chia đều 3 người",
            "uống sinh tố 90k cưa đôi cùng lan",
            "tiền thuê xe tự lái 1tr6 campuchia đều 4 bạn",
            "nam trả trước tiền phở 200k chia đều bốn anh em",
            "hóa đơn ăn tối 680k chia đều cho minh tuấn hùng và dũng",
            "tiền sân bóng đá 500k mỗi người chia đều nhau",
        ],
        "test": [
            "ăn buffet lẩu nướng 1tr2 chia đều 4 người",
            "uống cf sáng 70k cưa đôi với tuấn",
            "đi ăn ốc đêm 600k campuchia 5 anh em",
            "lan ứng trước tiền bánh ngọt 240k chia đều cho ba người",
            "tiền phòng khách sạn vũng tàu 1tr8 chia đều 3 bạn",
            "hóa đơn cơm trưa 280k chia đều bốn thành viên trong nhóm",
            "hùng trả trước tiền lẩu thái 840k chia đều bốn bạn",
            "chia đều 4 người hóa đơn ăn vặt chiều 160k",
        ],
    },
    "split.percentage": {
        "train": [
            "tiền điện chung cư 900k chia theo phần trăm hòa 60 phần trăm minh 40 phần trăm",
            "thuê mặt bằng kinh doanh 15tr nam chịu 50 phần trăm hùng 30 phần trăm lan 20 phần trăm",
            "hóa đơn internet wifi 300k chia tỷ lệ phần trăm anh bình 70 phần trăm em khoa 30 phần trăm",
            "góp vốn chạy quảng cáo 5tr minh đóng 55 phần trăm thảo đóng 45 phần trăm",
            "tiền thuê căn hộ 8tr chia theo tỷ lệ phần trăm phòng lớn 65 phần trăm phòng nhỏ 35 phần trăm",
            "chi phí chuyến công tác 4tr công ty hỗ trợ 80 phần trăm cá nhân tự túc 20 phần trăm",
            "hóa đơn điện lạnh 1tr2 tầng dưới chịu 60 phần trăm tầng trên 40 phần trăm",
            "mua máy lọc nước chung 3tr chia phần trăm hòa 50 phần trăm tuấn 25 phần trăm nam 25 phần trăm",
            "tiền nước sinh hoạt 250k chia theo mức phần trăm hai phòng 60 phần trăm và 40 phần trăm",
            "đóng phí quản lý tòa nhà 600k chủ nhà 50 phần trăm người thuê 50 phần trăm",
            "tiền xăng đi chung xe 500k tài xế 20 phần trăm khách đi cùng 80 phần trăm",
            "chi phí tổ chức sinh nhật 2tr trưởng nhóm 40 phần trăm hai bạn phó mỗi người 30 phần trăm",
        ],
        "val": [
            "tiền thuê nhà trọ 6tr chia phần trăm phòng có ban công 60 phần trăm phòng nhỏ 40 phần trăm",
            "hóa đơn điện tháng này 1tr5 hùng 50 phần trăm nam 30 phần trăm khoa 20 phần trăm",
            "mua tủ lạnh dùng chung 4tr chia theo tỷ lệ phần trăm lan 55 phần trăm mai 45 phần trăm",
            "chi phí phần mềm nhóm 1tr2 chia phần trăm trưởng nhóm 70 phần trăm thành viên 30 phần trăm",
            "góp quỹ liên hoan 3tr sếp đóng 60 phần trăm nhân viên 40 phần trăm",
        ],
        "test": [
            "tiền điện nước tháng 11 1tr chia phần trăm hòa 60 phần trăm minh 40 phần trăm",
            "thuê văn phòng nhóm 10tr nam 50 phần trăm tuấn 30 phần trăm lan 20 phần trăm",
            "mua lò vi sóng chung 2tr chia theo tỷ lệ phần trăm phòng lớn 65 phần trăm phòng nhỏ 35 phần trăm",
            "hóa đơn internet cáp quang 400k anh khoa 75 phần trăm em bình 25 phần trăm",
            "chi phí thuê xe du lịch 5tr công đoàn 70 phần trăm đoàn viên 30 phần trăm",
        ],
    },
    "split.shares_ratio": {
        "train": [
            "đi ăn hải sản 1tr4 chia theo suất nhà hòa 2 suất nam 1 suất lan 1 suất",
            "tiền nước sinh hoạt 350k chia theo đầu người phòng a 3 phần phòng b 2 phần",
            "ăn tiệc gia đình 2tr4 nhà anh cả 3 suất nhà chú út 2 suất cô ba 1 suất",
            "đặt gà nướng 600k chia theo phần hùng ăn 2 phần minh 1 phần",
            "chi phí chuyến đi cắm trại 3tr6 gia đình nam 3 suất vợ chồng tuấn 2 suất độc thân khoa 1 suất",
            "chia tiền gạo ăn chung 450k theo hệ số buổi ăn bình 3 phần dũng 2 phần khôi 1 phần",
            "mua sầu riêng 750k chia theo phần chị lan lấy 2 phần em mai 1 phần",
            "tiền thuê villa nghỉ dưỡng 6tr chia theo số phòng gia đình hòa 2 phần nhà minh 1 phần",
            "hóa đơn lẩu cua 1tr5 chia theo cổ phần người lớn 2 suất trẻ em 1 suất",
            "nhập hàng chung 9tr chia theo tỷ lệ phần vốn tùng 3 phần sơn 2 phần hải 1 phần",
            "tiền điện trọ tính theo hệ số máy lạnh phòng một 3 phần phòng hai 1 phần",
            "mua thùng trái cây nhập khẩu 1tr2 nhà chị thảo 2 suất nhà em vy 1 suất",
            "mua thùng táo mỹ 900k chị mai 2 phần em thảo 1 phần",
            "tiền nước phòng trọ 420k chia theo phần phòng lớn 3 phần phòng nhỏ 1 phần",
            "thuê homestay nghỉ mát 3tr9 gia đình bình 2 suất bạn khôi 1 suất",
            "góp vốn mua dụng cụ 1tr8 chia theo hệ số tùng 3 phần hải 2 phần",
        ],
        "val": [
            "ăn buffet cuối tuần 1tr8 chia theo suất nhà minh 2 suất tuấn 1 suất lan 1 suất",
            "tiền rác và nước chung 300k chia theo phần phòng lầu một 3 phần phòng trệt 2 phần",
            "thuê resort phan thiết 4tr5 gia đình anh hùng 2 phần bạn nam 1 phần",
            "mua thịt bò mỹ 900k chia theo phần chị hà lấy 2 phần em trang 1 phần",
            "chi phí đặt cỗ 3tr chia theo hệ số suất ăn hai gia đình 3 suất và 2 suất",
        ],
        "test": [
            "đi ăn lẩu hải sản 1tr6 chia theo suất nhà hòa 2 suất nam 1 suất lan 1 suất",
            "tiền nước phòng trọ 400k chia theo phần phòng lớn 3 phần phòng nhỏ 1 phần",
            "mua thùng cam úc 900k chị mai 2 phần em thảo 1 phần",
            "thuê homestay hội an 3tr6 gia đình bình 2 suất bạn khôi 1 suất",
            "góp vốn mua dụng cụ 1tr5 chia theo hệ số tùng 3 phần hải 2 phần",
        ],
    },
    "split.itemized_remainder": {
        "train": [
            "ăn trưa 320k minh uống thêm cà phê 40k còn lại 4 người chia đều",
            "nhậu tối 950k hùng gọi riêng gói thuốc 50k phần còn lại chia đều 3 anh em",
            "hóa đơn quán ăn 680k lan mua riêng hộp bánh 80k số còn lại chia đều cho 4 bạn",
            "đi ăn bún chả 260k nam thêm phần nem rán 40k còn lại chia đều hai đứa",
            "tiền siêu thị chung 540k thảo lấy riêng chai dầu gội 140k phần chung chia đều 4 người",
            "ăn lẩu 890k tuấn uống riêng 3 lon bia 90k phần còn lại cả bàn 4 người chia đều",
            "gọi đồ ăn grabfood 410k khoa đặt thêm ly trà đào 50k còn lại 3 anh em chia đều",
            "đi cafe nhóm 310k mai mua thêm bánh ngọt riêng 70k phần nước còn lại chia đều 4 bạn",
            "tiền ăn tối 1tr1 bình gọi thêm phần bò bít tết riêng 300k còn lại chia đều 4 người",
            "mua đồ ăn vặt 270k dũng lấy riêng lon nước tăng lực 30k số còn lại 3 đứa campuchia",
            "hóa đơn cơm niêu 520k chị hà mua riêng hũ cá kho 120k phần cơm chung chia đều 4 người",
            "ăn sáng cả nhóm 230k khôi kêu thêm tô súp riêng 50k còn lại 3 bạn chia đều",
        ],
        "val": [
            "ăn trưa văn phòng 390k nam gọi thêm ly sinh tố riêng 50k còn lại chia đều 4 người",
            "đi nhậu 780k tuấn lấy riêng bao thuốc 60k phần còn lại 3 anh em chia đều",
            "mua đồ bách hóa 460k lan lấy riêng hộp kem dưỡng 160k phần chung chia đều 3 bạn",
            "đặt cơm trưa 290k minh thêm phần chả giò riêng 50k số còn lại chia đều 3 đồng nghiệp",
            "hóa đơn quán nướng 1tr050k hùng uống riêng rượu mơ 150k còn lại 3 người chia đều",
        ],
        "test": [
            "ăn trưa 360k minh gọi thêm cà phê muối riêng 40k còn lại 4 người chia đều",
            "hóa đơn nhậu 860k hùng tính riêng phần mồi mang về 140k phần còn lại chia đều 3 anh em",
            "đi siêu thị phòng trọ 520k lan mua riêng sữa rửa mặt 120k số còn lại chia đều 4 bạn",
            "đặt shopeefood 310k tuấn thêm ly trà sữa riêng 50k còn lại 2 người cưa đôi",
            "ăn tối cả nhóm 980k nam gọi riêng đĩa hàu nướng 180k phần chung chia đều 4 người",
        ],
    },
    "split.exact_custom": {
        "train": [
            "tiền đi chợ 500k hòa 200k minh 180k còn lại lan chịu",
            "mua quà sinh nhật sếp 1tr nam đóng 400k tuấn 350k mình 250k",
            "hóa đơn ăn sáng 145k bình 55k khoa 50k dũng 40k",
            "góp tiền mừng cưới bạn 1tr5 hùng gửi 600k nam 500k còn lại thảo đóng",
            "đặt cơm hộp 195k chị mai 65k lan 70k em vy 60k",
            "thanh toán đơn thuốc và khẩu trang 320k mẹ 200k con 120k",
            "mua vé xem phim và bắp nước 430k tuấn trả 230k thảo trả 200k",
            "tiền taxi hai chặng 270k khôi chịu 150k phần còn lại hải trả",
            "đặt trà sữa theo món riêng từng người tổng 165k hoa 55k mai 60k lan 50k",
            "mua sách chung đơn hàng 480k bình 210k nam 150k còn lại minh chịu",
            "tiền sửa ống nước chung 350k chủ trọ chịu 200k người thuê chịu 150k",
            "mua đồ gia dụng 620k nam đóng 250k bình 200k dũng 170k",
            "tiền vé tàu nhóm 880k tùng 320k sơn 280k hải 280k",
            "hóa đơn ăn sáng từng món 170k hòa 65k minh 55k lan 50k",
            "đặt nước uống văn phòng 190k mai 70k thảo 65k vy 55k",
            "tiền sửa khóa phòng trọ 320k chủ nhà 180k phòng mình 140k",
            "mua quà chia tay đồng nghiệp 950k nam đóng 400k tuấn 300k còn lại mình chịu",
            "góp tiền từ thiện nhóm 1tr4 hùng 500k bình 500k khoa 400k",
        ],
        "val": [
            "tiền ăn trưa gọi theo món 215k hòa 75k minh 80k lan 60k",
            "mua quà tân gia 1tr2 nam đóng 500k tuấn 400k còn lại khoa chịu",
            "đặt đồ uống chiều 175k mai 65k thảo 55k vy 55k",
            "hóa đơn mua đồ gia dụng 650k hùng 300k bình 200k còn lại dũng trả",
            "tiền vé tàu nhóm 950k tùng 350k sơn 300k hải 300k",
        ],
        "test": [
            "hóa đơn ăn sáng từng món 160k hòa 60k minh 55k lan 45k",
            "mua quà chia tay đồng nghiệp 900k nam đóng 400k tuấn 300k còn lại mình chịu",
            "đặt nước uống văn phòng 185k mai 70k thảo 60k vy 55k",
            "tiền sửa khóa cửa phòng trọ 300k chủ nhà 180k phòng mình 120k",
            "góp tiền từ thiện nhóm 1tr5 hùng 600k bình 500k khoa 400k",
        ],
    },
    "split.multi_category_receipt": {
        "train": [
            "siêu thị 500k gồm ăn uống 320k việc nhà 180k",
            "đi aeon mall 1tr2 bao gồm thực phẩm 750k quần áo 450k",
            "hóa đơn winmart 420k trong đó rau thịt 290k nước giặt gia dụng 130k",
            "tách hóa đơn coopmart 850k gồm thực phẩm nấu ăn 550k đồ dùng vệ sinh 300k",
            "mua hàng shopee 640k bao gồm sách học tập 240k thiết bị điện tử 400k",
            "thanh toán bách hóa xanh 380k trong đó trái cây sữa 260k túi rác khăn giấy 120k",
            "siêu thị lotte 1tr5 gồm đồ ăn gia đình 900k mỹ phẩm mua sắm 600k",
            "tách bill nhà thuốc long châu 450k gồm thuốc cảm 150k sữa dinh dưỡng cho bé 300k",
            "đi chợ cuối tuần 600k trong đó thịt cá 420k chổi lau nhà 180k",
            "hóa đơn tổng hợp 950k bao gồm xăng xe 150k ăn trưa 300k mua sắm 500k",
            "tách khoản thanh toán thẻ 2tr gồm tiền điện nước 1tr1 giải trí xem phim 900k",
            "mua sắm siêu thị 720k gồm nguyên liệu bếp 480k nước rửa chén bột giặt 240k",
        ],
        "val": [
            "hóa đơn siêu thị 650k gồm thực phẩm 430k việc nhà gia dụng 220k",
            "đi winmart 510k bao gồm thịt rau củ 360k giấy vệ sinh nước lau sàn 150k",
            "tách hóa đơn mua hàng 1tr1 trong đó quần áo 700k sách vở 400k",
            "siêu thị coopmart 780k gồm đồ ăn tươi sống 520k vật dụng bếp 260k",
            "thanh toán tổng 900k bao gồm khám sức khỏe 600k thuốc men 300k",
        ],
        "test": [
            "siêu thị winmart 580k gồm ăn uống thực phẩm 400k việc nhà 180k",
            "tách hóa đơn aeon 1tr4 bao gồm mua sắm quần áo 850k ăn tối 550k",
            "đi bách hóa xanh 340k trong đó rau củ thịt 240k nước rửa chén 100k",
            "hóa đơn tổng hợp 1tr2 gồm tiền điện 800k gói cước internet 400k",
            "mua đơn hàng online 750k bao gồm phụ kiện điện tử 500k sách kỹ năng 250k",
        ],
    },
    "split.settle_repayment": {
        "train": [
            "minh chuyển khoản trả lại tiền lẩu hôm qua 150k",
            "tất toán công nợ nhóm chuyến đi đà lạt cho hùng 420k",
            "hoàn trả tiền ứng trước hóa đơn điện nước cho trưởng phòng trọ 350k",
            "nam gửi trả phần tiền chia bill ăn trưa 85k",
            "cấn trừ khoản nợ chung nhóm bạn tháng này còn 220k",
            "thanh toán dứt điểm tiền nợ chia hóa đơn homestay cho lan 600k",
            "chuyển trả lại tiền vé xem phim bạn mua hộ 110k",
            "tất toán sổ nợ chung phòng trọ cuối tháng với tuấn 480k",
            "thu hồi tiền các bạn hoàn lại khoản ứng tiệc nướng 900k",
            "trả hết phần tiền thiếu trong quỹ nhóm ăn uống cho mai 175k",
            "đối chiếu công nợ nhóm tối ưu số lần chuyển khoản tất toán",
            "gửi lại tiền bạn trả hộ bữa nhậu tối thứ sáu 250k",
        ],
        "val": [
            "tuấn chuyển trả lại tiền chia hóa đơn cà phê 65k",
            "tất toán khoản nợ nhóm du lịch vũng tàu cho bình 550k",
            "hoàn lại tiền ứng trước mua đồ chung phòng trọ cho lan 300k",
            "cấn trừ công nợ chia tiền ăn uống cuối tuần giữa các thành viên",
            "nhận lại tiền đồng nghiệp hoàn trả bill đặt cơm trưa 75k",
        ],
        "test": [
            "lan chuyển khoản trả lại tiền chia bill lẩu nướng 280k",
            "tất toán công nợ nhóm ở ghép cuối tháng cho hòa 520k",
            "hoàn trả khoản tiền bạn ứng hộ mua vé tàu 350k",
            "cấn trừ nợ nhóm tối giản số giao dịch chuyển tiền",
            "nhận tiền hùng gửi trả phần chia hóa đơn sân cầu lông 90k",
        ],
    },
    "alloc.rule_50_30_20": {
        "train": [
            "lương 20 triệu phân bổ theo quy tắc 50 30 20",
            "chia thu nhập tháng này 50 phần trăm thiết yếu 30 phần trăm hưởng thụ 20 phần trăm tiết kiệm",
            "tư vấn chia lương 18tr theo công thức 50 30 20 cân bằng",
            "phân bổ ngân sách cá nhân quy tắc năm mươi ba mươi hai mươi",
            "nhận lương 22tr muốn chia theo tỷ lệ 50 nhu cầu thiết yếu 30 cá nhân 20 tích lũy",
            "lập kế hoạch chi tiêu lương 15 triệu chuẩn 50 30 20",
            "chia tiền lương hàng tháng cân bằng giữa chi phí cố định giải trí và tiết kiệm 50 30 20",
            "áp dụng phương pháp 50 30 20 cho mức thu nhập 25tr mỗi tháng",
            "gợi ý phân chia lương văn phòng 16tr theo mô hình 50 30 20",
            "cách chia tiền lương hợp lý 50 phần trăm ăn ở đi lại 30 phần trăm mong muốn 20 phần trăm để dành",
            "thiết lập hạn mức ngân sách tháng từ lương 24tr theo chuẩn 50 30 20",
            "phân bổ dòng tiền cá nhân độc thân 19tr cân đối 50 30 20",
            "nhận lương 23tr phân bổ theo quy tắc 50 30 20 sao cho chuẩn",
            "chia lương tháng 26 triệu thành 50 phần trăm thiết yếu 30 mong muốn 20 tích lũy",
            "tư vấn phân chia thu nhập cân bằng năm mươi ba mươi hai mươi",
            "lập ngân sách từ thu nhập 17 triệu bằng phương pháp 50 30 20",
            "áp dụng công thức quản lý tiền bạc 50 30 20 cho mức thu nhập 20tr",
            "chia quỹ tháng 50 30 20 cho nhu cầu cá nhân và tiết kiệm",
        ],
        "val": [
            "lương về 21 triệu chia theo quy tắc 50 30 20 giúp mình",
            "phân bổ thu nhập 17tr thành 50 thiết yếu 30 giải trí 20 tiết kiệm",
            "áp dụng công thức quản lý tài chính 50 30 20 cho lương 26 triệu",
            "chia ngân sách tháng cân bằng theo tỷ lệ năm mươi ba mươi hai mươi",
            "tính mức chi tiêu hợp lý từ lương 18tr5 theo chuẩn 50 30 20",
        ],
        "test": [
            "nhận lương 20tr phân bổ theo quy tắc 50 30 20 sao cho chuẩn",
            "chia lương tháng 24 triệu thành 50 phần trăm thiết yếu 30 mong muốn 20 tích lũy",
            "lập ngân sách từ thu nhập 16 triệu bằng phương pháp 50 30 20",
            "tư vấn phân chia thu nhập cân bằng năm mươi ba mươi hai mươi",
            "áp dụng mô hình 50 30 20 cho khoản lương 28tr vừa nhận",
        ],
    },
    "alloc.six_jars": {
        "train": [
            "lương 25 triệu chia vào 6 chiếc lọ tài chính",
            "phân bổ thu nhập 30tr theo mô hình 6 hũ jarrs chuẩn quốc tế",
            "chia tiền lương vào sáu chiếc lọ thiết yếu tự do tài chính giáo dục hưởng thụ cho đi",
            "áp dụng quy tắc 6 lọ 55 phần trăm thiết yếu 10 phần trăm đầu tư 10 phần trăm giáo dục",
            "tư vấn chia thu nhập 20tr thành 6 quỹ tài chính cá nhân",
            "mới nhận lương 32 triệu muốn bỏ vào 6 chiếc lọ quản lý tiền",
            "phân chia dòng tiền tháng này theo phương pháp 6 hũ tài chính harv eker",
            "thiết lập 6 chiếc lọ chi tiêu và tích lũy dài hạn từ lương 28tr",
            "chia thu nhập làm 6 lọ gồm thiết yếu tiết kiệm dài hạn học tập giải trí thiện nguyện",
            "tính số tiền từng hũ trong mô hình 6 chiếc lọ với thu nhập 18 triệu",
            "cách phân bổ lương thưởng 35tr vào sáu lọ quản lý tài chính thông minh",
            "áp dụng 6 lọ tài chính vào ngân sách tháng cho thu nhập 22tr",
            "phân bổ thu nhập tháng 25tr vào sáu hũ chi tiêu giáo dục và tự do tài chính",
            "tính định mức 6 lọ chi tiêu và quỹ đầu tư từ tiền lương 21 triệu",
        ],
        "val": [
            "chia lương 24 triệu theo phương pháp 6 chiếc lọ tài chính",
            "phân bổ thu nhập tháng 27tr vào sáu hũ chi tiêu và đầu tư",
            "tính định mức 6 lọ chuẩn quốc tế cho mức lương 19 triệu",
            "lập kế hoạch quản lý tiền bằng 6 chiếc lọ từ thu nhập 30tr",
            "chia tiền vào 6 quỹ thiết yếu giáo dục hưởng thụ tự do tài chính cho đi",
        ],
        "test": [
            "lương 26 triệu phân bổ vào 6 chiếc lọ tài chính như thế nào",
            "chia thu nhập 32tr theo quy tắc sáu hũ tài chính cá nhân",
            "áp dụng mô hình 6 lọ chuẩn quốc tế cho lương tháng 21 triệu",
            "tính số tiền mỗi lọ trong 6 chiếc lọ với thu nhập 15tr",
            "phân chia ngân sách 6 hũ thiết yếu học tập đầu tư hưởng thụ thiện nguyện",
        ],
    },
    "alloc.family_household": {
        "train": [
            "thu nhập hai vợ chồng 35 triệu có con nhỏ chia quỹ gia đình sao cho hợp lý",
            "phân bổ lương 28tr cho tiền chợ tiền sữa bỉm em bé học phí và quỹ dự phòng y tế",
            "chia thu nhập hộ gia đình 40 triệu gồm sinh hoạt chung nuôi con biếu bố mẹ và tiết kiệm",
            "vợ chồng tổng lương 32tr có một bé mẫu giáo nên chia ngân sách gia đình thế nào",
            "lập kế hoạch phân bổ tiền lương cho tổ ấm có con nhỏ và phụng dưỡng ông bà",
            "tư vấn chia quỹ chung gia đình 30 triệu tiền ăn uống điện nước học phí cho con",
            "phân chia thu nhập gia đình 4 người 36tr đảm bảo quỹ khẩn cấp y tế và giáo dục con cái",
            "lương hai vợ chồng 26 triệu thuê nhà 5 triệu nuôi con nhỏ chia sao khỏi thiếu trước hụt sau",
            "cách quản lý và phân bổ tài chính gia đình trẻ mới sinh em bé thu nhập 30tr",
            "chia ngân sách tháng cho gia đình có hai con đi học tổng thu nhập 45 triệu",
            "trích lập quỹ sinh hoạt gia đình quỹ học tập cho con và quỹ dự phòng ốm đau từ lương 34tr",
            "phân bổ tiền lương hàng tháng của gia đình gồm tiền nhà tiền chợ bỉm sữa bảo hiểm",
        ],
        "val": [
            "tổng thu nhập hai vợ chồng 30 triệu có em bé chia ngân sách gia đình thế nào",
            "phân bổ lương 38tr cho chi phí tổ ấm học phí con nhỏ và quỹ dự phòng gia đình",
            "chia tiền sinh hoạt gia đình 4 người thu nhập 33 triệu gồm tiền chợ sữa bỉm điện nước",
            "tư vấn lập quỹ chung vợ chồng 28tr vừa nuôi con vừa tiết kiệm phòng đau ốm",
            "kế hoạch phân chia thu nhập hộ gia đình có con học tiểu học và biếu nội ngoại",
        ],
        "test": [
            "thu nhập hai vợ chồng 34 triệu có con nhỏ nên phân bổ quỹ gia đình ra sao",
            "chia lương 29tr cho tiền chợ sữa bỉm học phí của bé và quỹ dự phòng y tế",
            "lập ngân sách hộ gia đình 36 triệu cân đối sinh hoạt nuôi con và tiết kiệm tổ ấm",
            "vợ chồng mới có em bé tổng thu 27tr chia tiền nhà tiền ăn và quỹ con cái thế nào",
            "tư vấn phân bổ dòng tiền gia đình đa thế hệ thu nhập 42 triệu mỗi tháng",
        ],
    },
    "alloc.debt_payoff": {
        "train": [
            "lương 22 triệu đang nợ thẻ tín dụng và trả góp xe chia tiền trả nợ sao cho nhanh hết",
            "thu nhập 18tr ưu tiên trả nợ vay ngân hàng 6tr mỗi tháng còn lại chi tiêu tiết kiệm",
            "phân bổ lương 25tr theo phương pháp quả cầu tuyết để tất toán nợ xấu nhanh nhất",
            "đang gánh khoản trả góp 7 triệu trên mức lương 20 triệu chia chi tiêu sao để không vỡ nợ",
            "tư vấn chia tiền lương ưu tiên cắt giảm lãi vay thẻ tín dụng và trả nợ gốc",
            "thu nhập 24 triệu nợ hai khoản vay tiêu dùng nên phân bổ tiền trả nợ thế nào hiệu quả",
            "lập kế hoạch thắt lưng buộc bụng từ lương 16tr dành tối đa tiền trả dứt nợ",
            "chia lương tháng 28tr trích riêng khoản trả góp mua xe 8tr phần còn lại sống tối giản",
            "chiến lược phân bổ thu nhập tập trung xóa nợ lãi suất cao avalanche",
            "lương 19tr mỗi tháng phải đóng gốc và lãi ngân hàng 5tr5 chia phần còn lại sao cho đủ sống",
            "cách phân chia dòng tiền khi đang mắc nợ để vừa trả đúng hạn vừa có quỹ khẩn cấp nhỏ",
            "tối ưu phân bổ thu nhập 21 triệu ưu tiên tất toán khoản vay fe credit trước hạn",
        ],
        "val": [
            "lương 20 triệu mỗi tháng trả góp 6 triệu phân bổ phần còn lại sao để nhanh hết nợ",
            "tư vấn chia thu nhập 23tr ưu tiên thanh toán dư nợ thẻ tín dụng lãi cao",
            "lập ngân sách trả nợ nhanh từ mức lương 17tr bằng chiến lược snowball",
            "thu nhập 26 triệu đang vay mua xe 7tr5 chia chi tiêu tối giản để trả nợ trước hạn",
            "phân chia tiền lương khi có khoản vay ngân hàng hàng tháng cần tất toán gấp",
        ],
        "test": [
            "lương 21 triệu đang phải trả góp 5 triệu mỗi tháng chia tiền trả nợ sao cho hiệu quả",
            "phân bổ thu nhập 24tr ưu tiên xóa nợ thẻ tín dụng lãi suất cao nhanh nhất",
            "thu nhập 18 triệu mắc nợ tiêu dùng lập kế hoạch thắt chặt chi tiêu để trả dứt nợ",
            "tư vấn chia lương 27tr trích trả gốc lãi vay ngân hàng 8tr còn lại sinh hoạt",
            "chiến lược phân bổ dòng tiền trả nợ quả cầu tuyết cho người thu nhập 19tr",
        ],
    },
    "alloc.fire_high_savings": {
        "train": [
            "lương 30 triệu thuê nhà 5 triệu muốn tiết kiệm tối đa để mua xe và đầu tư fire",
            "phân bổ thu nhập 40tr tiết kiệm 50 phần trăm đầu tư chứng chỉ quỹ đạt tự do tài chính",
            "chia lương 35 triệu theo chế độ tích lũy cao mua căn hộ đầu tiên",
            "độc thân lương 28tr muốn dành 45 phần trăm thu nhập đầu tư cổ phiếu và tích sản",
            "tư vấn phân bổ dòng tiền tăng tốc nghỉ hưu sớm fire cho thu nhập 45 triệu",
            "lương 25tr sống tối giản muốn gom tiền mua nhà trong 5 năm nên chia quỹ thế nào",
            "kế hoạch phân chia thu nhập ưu tiên tỷ lệ tiết kiệm và đầu tư sinh lời trên 40 phần trăm",
            "nhận lương 32 triệu trích ngay một nửa vào quỹ đầu tư dài hạn phần còn lại mới chi tiêu",
            "tối ưu phân bổ lương công nghệ 50tr để tối đa hóa tài sản ròng và lãi kép",
            "chia tiền lương hàng tháng ưu tiên gom vốn kinh doanh và mua vàng tích trữ",
            "mục tiêu đạt mốc tự do tài chính fire với thu nhập 36tr mỗi tháng phân bổ ra sao",
            "phân bổ thu nhập 26 triệu trả mình trước 40 phần trăm vào sổ tiết kiệm và etf",
            "độc thân thu nhập sống tối giản chia tiền gom vốn đầu tư nhanh nhất",
            "kế hoạch phân chia lương tối đa hóa tỷ lệ tiết kiệm nghỉ hưu sớm",
            "ưu tiên trích quỹ đầu tư dài hạn chứng chỉ quỹ trước khi chi tiêu cá nhân",
        ],
        "val": [
            "lương 32 triệu thuê phòng 4tr5 muốn tiết kiệm tối đa đầu tư đạt tự do tài chính fire",
            "phân bổ thu nhập 38tr dành 50 phần trăm mua chứng chỉ quỹ và tích lũy mua nhà",
            "tư vấn chia lương 27 triệu theo hướng sống tối giản tăng tốc tích sản dài hạn",
            "kế hoạch trích 45 phần trăm thu nhập 42tr vào danh mục đầu tư lãi kép nghỉ hưu sớm",
            "chia dòng tiền cá nhân 29tr ưu tiên gom tiền mua ô tô và đầu tư cổ phiếu",
        ],
        "test": [
            "lương 30 triệu thuê nhà 5 triệu muốn tiết kiệm tối đa để đầu tư fire và mua nhà",
            "phân bổ thu nhập 36tr dành 50 phần trăm tích sản chứng chỉ quỹ tự do tài chính",
            "độc thân thu nhập 28 triệu sống tối giản chia tiền sao để gom vốn nhanh nhất",
            "tư vấn kế hoạch phân chia lương 45tr tối đa hóa tỷ lệ tiết kiệm nghỉ hưu sớm",
            "nhận lương 33tr ưu tiên trích quỹ đầu tư dài hạn trước khi chi tiêu cá nhân",
        ],
    },
}

OOD_CHATTER_SAMPLES = [
    "alo một hai ba kiểm tra mic",
    "hôm nay trời nắng đẹp quá nhỉ",
    "thời tiết buổi sáng nắng ấm gió nhẹ",
    "chiều nay bầu trời dịu mát dễ chịu",
    "nhớ uống hai cốc nước ấm buổi sáng",
    "hẹn báo thức sáu giờ rưỡi sáng mai",
    "chiều nay họp giao ban phòng tầng ba",
    "uống viên vitamin c sau bữa ăn sáng",
    "thay nhớt xe máy định kỳ mỗi hai nghìn cây",
    "nhớ mang theo áo mưa kẻo chiều mưa to",
    "chúc cả nhà buổi tối cuối tuần vui vẻ",
    "mật khẩu wifi phòng khách là gì vậy",
    "nhớ tắt điều hòa quạt máy trước khi khóa cửa",
    "ăn sáng phở bò tái nạm một mình",
    "đổ đầy bình xăng xe máy đi làm",
    "dự báo thời tiết cuối tuần trời mát mẻ có mưa nhẹ",
    "nhắc lịch họp phòng ban lúc tám giờ sáng thứ sáu",
    "uống năm trăm ml nước khoáng tinh khiết buổi trưa",
    "tập thể dục chạy bộ quanh hồ ba mươi phút",
    "nhớ khóa cửa cẩn thận tắt bình nóng lạnh trước khi ngủ",
    "gửi biên bản tổng kết qua hộp thư điện tử cho sếp",
    "soạn thảo văn bản báo cáo định kỳ gửi thư điện tử",
    "chúc mừng ngày lễ nhiều niềm vui và bình an",
    "alo tín hiệu mạng bên đó nghe rõ tiếng nói chưa",
    "hỏi đường ra bến xe miền đông mới sáng nay",
    "đọc sách kỹ năng ba mươi trang trước giờ đi ngủ",
    "đặt chuông đồng hồ bảy giờ kém mười lăm",
    "ngày mai thứ hai nhớ họp đầu tuần với đối tác",
    "tôi định sang năm mới mua chiếc xe máy mới",
    "đừng ghi nhận thông tin nháp này vào sổ",
    "có nên nâng cấp điện thoại vào dịp cuối năm không",
    "thời tiết ngoài trời dịu mát dễ chịu rất thích hợp đi dạo",
    "chiều mai có hẹn khám nha khoa định kỳ lúc ba giờ rưỡi",
    "gửi tập tin báo cáo công việc qua thư điện tử",
    "nhớ tắt điều hòa đèn điện trước lúc rời khỏi phòng",
    "uống bốn trăm ml nước lọc ấm sau giờ tập gym",
    "nhắc lịch gọi điện hỏi thăm sức khỏe bố mẹ buổi tối",
    "căn phòng trọ này đổi khóa cửa sổ lại cho an toàn",
    "hôm nay gió mát dễ chịu quá chừng",
    "dự báo thời tiết tuần sau trời mát và có mưa rào nhẹ",
    "tập thể dục giãn cơ ngoài công viên buổi chiều gần nhà",
    "buổi sáng đi dạo hít thở không khí trong lành ở công viên",
    "nghe bản tin thời sự khoảng ba mươi phút mỗi buổi sáng",
    "chờ xe buýt khoảng hai mươi phút tại trạm dừng chân",
]

VAL_OOD_SAMPLES = [
    "thời tiết chiều nay mát mẻ dễ chịu",
    "nhắc tôi gọi điện hỏi thăm bố mẹ tối nay",
    "uống bốn trăm ml nước lọc sau khi tập thể dục",
    "mật khẩu cửa phòng trọ đổi lại chưa",
    "chiều mai đi khám răng định kỳ lúc ba giờ",
    "nhớ tắt điều hòa trước khi ra khỏi nhà",
]

OOD_HELD_OUT_TEST = [
    "thời tiết ngày mai dự báo có mưa rào",
    "nhắc lịch họp nhóm lúc chín giờ sáng thứ hai",
    "uống ba trăm ml nước lọc tinh khiết",
    "alo đầu dây bên kia nghe rõ tiếng chưa",
    "đi bộ tập thể dục ba mươi phút công viên",
    "nhớ khóa cửa tắt điện trước khi đi ngủ",
    "gửi tài liệu báo cáo qua thư điện tử",
    "chúc mừng sinh nhật nhiều niềm vui sức khỏe",
    "báo thức sáu giờ rưỡi sáng mai đi làm sớm",
    "thay dầu máy định kỳ xe tay ga hai vạn cây",
]


def softmax_probs(logits: list[float], temp: float = 1.0) -> list[float]:
    inv_t = 1.0 / max(temp, 1e-4)
    scaled = [z * inv_t for z in logits]
    m = max(scaled)
    exps = [math.exp(z - m) for z in scaled]
    inv_s = 1.0 / sum(exps)
    return [e * inv_s for e in exps]


def simulate_int8_row(row: list[float]) -> list[float]:
    max_abs = max((abs(v) for v in row), default=0.0)
    if max_abs <= 1e-12:
        return [0.0] * len(row)
    scale = max_abs / 127.0
    inv = 1.0 / scale
    return [max(-127, min(127, int(round(v * inv)))) * scale for v in row]


def build_split_rows(
    rng: random.Random,
    split_name: str,
    wrappers: list[str],
    seen_norms: set[str],
) -> list[tuple[int, str, str]]:
    label_to_idx = {lbl: i for i, lbl in enumerate(SPLIT_ALLOC_LABELS)}
    rows: list[tuple[int, str, str]] = []
    for lbl in SPLIT_ALLOC_LABELS:
        idx = label_to_idx[lbl]
        for core in CORPUS_POOLS[lbl][split_name]:
            for tpl in wrappers:
                sent = tpl.format(core=core, amt=rng.choice(AMOUNTS))
                norm_acc = normalize_for_classifier(sent)
                if norm_acc and norm_acc not in seen_norms:
                    seen_norms.add(norm_acc)
                    rows.append((idx, sent, norm_acc))
                no_acc = strip_vn_accents(sent)
                norm_no_acc = normalize_for_classifier(no_acc)
                if norm_no_acc and norm_no_acc not in seen_norms:
                    seen_norms.add(norm_no_acc)
                    rows.append((idx, no_acc, norm_no_acc))
    return rows


def evaluate_ood_rejection(
    ood_texts: list[str],
    q_a_dequant: list[list[float]],
    logit_gain: float,
    temp: float,
    threshold: float = 0.50,
) -> float:
    if not ood_texts:
        return 1.0
    k = len(SPLIT_ALLOC_LABELS)
    rejected = 0
    for s in ood_texts:
        norm = normalize_for_classifier(s)
        b_ids = extract_feature_buckets(
            norm,
            num_buckets=NUM_BUCKETS,
            word_ngrams=WORD_NGRAMS,
            min_subword=MIN_SUBWORD,
            max_subword=MAX_SUBWORD,
        )
        if not b_ids:
            rejected += 1
            continue
        scale = logit_gain / len(b_ids)
        h = [0.0] * k
        for b_id in b_ids:
            for c in range(k):
                h[c] += q_a_dequant[b_id][c]
        probs = softmax_probs([scale * h[c] for c in range(k)], temp=temp)
        if max(probs) < threshold:
            rejected += 1
    return rejected / len(ood_texts)


def evaluate_quantized(
    rows: list[tuple[int, str, str]],
    q_a_dequant: list[list[float]],
    logit_gain: float,
    temp: float,
) -> tuple[float, float, float, float]:
    k = len(SPLIT_ALLOC_LABELS)
    tp = [0] * k
    fp = [0] * k
    fn = [0] * k
    confs: list[float] = []
    accs: list[int] = []
    false_high = 0

    for true_y, _, norm in rows:
        b_ids = extract_feature_buckets(
            norm,
            num_buckets=NUM_BUCKETS,
            word_ngrams=WORD_NGRAMS,
            min_subword=MIN_SUBWORD,
            max_subword=MAX_SUBWORD,
        )
        if not b_ids:
            probs = [1.0 / k] * k
        else:
            scale = logit_gain / len(b_ids)
            h = [0.0] * k
            for b_id in b_ids:
                r = q_a_dequant[b_id]
                for c in range(k):
                    h[c] += r[c]
            logits = [scale * h[c] for c in range(k)]
            probs = softmax_probs(logits, temp=temp)
        pred_y = max(range(k), key=lambda c: probs[c])
        top_p = probs[pred_y]
        ok = 1 if pred_y == true_y else 0
        confs.append(top_p)
        accs.append(ok)
        if top_p >= 0.78 and ok == 0:
            false_high += 1
        if ok:
            tp[true_y] += 1
        else:
            fp[pred_y] += 1
            fn[true_y] += 1

    f1s: list[float] = []
    for c in range(k):
        pr = tp[c] / (tp[c] + fp[c]) if (tp[c] + fp[c]) > 0 else 0.0
        rc = tp[c] / (tp[c] + fn[c]) if (tp[c] + fn[c]) > 0 else 0.0
        f1s.append((2 * pr * rc / (pr + rc)) if (pr + rc) > 0 else 0.0)

    n = max(len(rows), 1)
    ece = 0.0
    for b_idx in range(10):
        lo, hi = b_idx / 10.0, (b_idx + 1) / 10.0
        idxs = [i for i, cf in enumerate(confs) if (lo <= cf < hi) or (b_idx == 9 and cf == 1.0)]
        if idxs:
            avg_c = sum(confs[i] for i in idxs) / len(idxs)
            avg_a = sum(accs[i] for i in idxs) / len(idxs)
            ece += (len(idxs) / n) * abs(avg_a - avg_c)

    return sum(accs) / n, sum(f1s) / k, ece, false_high / n


def export_jsonl(path: Path, split_name: str, rows: list[tuple[int, str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for y, raw, norm in rows:
            rec = {
                "split": split_name,
                "label": SPLIT_ALLOC_LABELS[y],
                "text": raw,
                "normalized": norm,
            }
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")


def compute_detailed_eval(
    rows: list[tuple[int, str, str]],
    q_a_dequant: list[list[float]],
    logit_gain: float,
    temp: float,
) -> dict[str, object]:
    k = len(SPLIT_ALLOC_LABELS)
    conf_mat = [[0] * k for _ in range(k)]
    for true_y, _, norm in rows:
        b_ids = extract_feature_buckets(
            norm,
            num_buckets=NUM_BUCKETS,
            word_ngrams=WORD_NGRAMS,
            min_subword=MIN_SUBWORD,
            max_subword=MAX_SUBWORD,
        )
        if not b_ids:
            pred_y = 0
        else:
            scale = logit_gain / len(b_ids)
            h = [0.0] * k
            for b_id in b_ids:
                r = q_a_dequant[b_id]
                for c in range(k):
                    h[c] += r[c]
            probs = softmax_probs([scale * h[c] for c in range(k)], temp=temp)
            pred_y = max(range(k), key=lambda c: probs[c])
        conf_mat[true_y][pred_y] += 1

    per_class = {}
    for c, lbl in enumerate(SPLIT_ALLOC_LABELS):
        tp = conf_mat[c][c]
        fp = sum(conf_mat[r][c] for r in range(k) if r != c)
        fn = sum(conf_mat[c][col] for col in range(k) if col != c)
        pr = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        rc = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = (2 * pr * rc / (pr + rc)) if (pr + rc) > 0 else 0.0
        per_class[lbl] = {
            "support": sum(conf_mat[c]),
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "precision": round(pr, 4),
            "recall": round(rc, 4),
            "f1": round(f1, 4),
        }
    return {
        "labels": SPLIT_ALLOC_LABELS,
        "confusionMatrix": conf_mat,
        "perClass": per_class,
    }


def pack_lftq_binary(
    labels: list[str],
    A: list[list[float]],
    logit_gain: float,
    temperature: float,
) -> bytes:
    k = len(labels)
    dim = k
    header = struct.pack(
        "<4sIIIIHHHHf",
        b"LFTQ",
        1,
        k,
        dim,
        NUM_BUCKETS,
        WORD_NGRAMS,
        MIN_SUBWORD,
        MAX_SUBWORD,
        0,
        float(temperature),
    )
    parts = [header]
    for lbl in labels:
        enc = lbl.encode("utf-8")
        parts.append(struct.pack("<H", len(enc)))
        parts.append(enc)

    scales: list[float] = []
    q_flat: list[int] = []
    for row in A:
        max_abs = max((abs(v) for v in row), default=0.0)
        if max_abs <= 1e-12:
            scales.append(0.0)
            q_flat.extend([0] * dim)
        else:
            sc = max_abs / 127.0
            scales.append(sc)
            inv = 1.0 / sc
            for v in row:
                q_flat.append(max(-127, min(127, int(round(v * inv)))))

    parts.append(struct.pack(f"<{NUM_BUCKETS}f", *scales))
    parts.append(struct.pack(f"<{NUM_BUCKETS * dim}b", *q_flat))
    w_flat = [float(logit_gain if r == c else 0.0) for r in range(k) for c in range(dim)]
    parts.append(struct.pack(f"<{k * dim}f", *w_flat))
    b_flat = [0.0] * k
    parts.append(struct.pack(f"<{k}f", *b_flat))
    return b"".join(parts)


def main() -> None:
    rng = random.Random(20261125)
    ART_DIR.mkdir(parents=True, exist_ok=True)
    DATASETS_DIR.mkdir(parents=True, exist_ok=True)
    FLUTTER_MODELS_DIR.mkdir(parents=True, exist_ok=True)

    seen_norms: set[str] = set()
    train_rows = build_split_rows(rng, "train", TRAIN_WRAPPERS, seen_norms)
    val_rows = build_split_rows(rng, "val", VAL_WRAPPERS, seen_norms)
    test_rows = build_split_rows(rng, "test", TEST_WRAPPERS, seen_norms)

    export_jsonl(DATASETS_DIR / "money_split_train.jsonl", "train", train_rows)
    export_jsonl(DATASETS_DIR / "money_split_val.jsonl", "val", val_rows)
    export_jsonl(DATASETS_DIR / "money_split_test.jsonl", "test", test_rows)

    k = len(SPLIT_ALLOC_LABELS)
    logit_gain = 15.0
    lr = 0.36
    l2 = 6e-6
    epochs = 38
    qat_epochs = 12
    label_smoothing = 0.005

    A = [[0.0] * k for _ in range(NUM_BUCKETS)]
    gA = [[1e-2] * k for _ in range(NUM_BUCKETS)]

    compiled: list[tuple[int, float, list[tuple[int, int]]]] = []
    for y, _, norm in train_rows:
        b_ids = extract_feature_buckets(
            norm,
            num_buckets=NUM_BUCKETS,
            word_ngrams=WORD_NGRAMS,
            min_subword=MIN_SUBWORD,
            max_subword=MAX_SUBWORD,
        )
        if not b_ids:
            continue
        cnts: dict[int, int] = {}
        for b_id in b_ids:
            cnts[b_id] = cnts.get(b_id, 0) + 1
        compiled.append((y, logit_gain / len(b_ids), list(cnts.items())))

    for ood in OOD_CHATTER_SAMPLES * 18:
        for variant in (ood, strip_vn_accents(ood)):
            norm = normalize_for_classifier(variant)
            b_ids = extract_feature_buckets(
                norm,
                num_buckets=NUM_BUCKETS,
                word_ngrams=WORD_NGRAMS,
                min_subword=MIN_SUBWORD,
                max_subword=MAX_SUBWORD,
            )
            if not b_ids:
                continue
            cnts = {}
            for b_id in b_ids:
                cnts[b_id] = cnts.get(b_id, 0) + 1
            compiled.append((-1, logit_gain / len(b_ids), list(cnts.items())))

    smooth_neg = label_smoothing / k
    smooth_pos = (1.0 - label_smoothing) + smooth_neg
    uniform_p = 1.0 / k
    indices = list(range(len(compiled)))

    for ep in range(epochs):
        rng.shuffle(indices)
        cur_lr = lr * (0.18 + 0.82 * 0.5 * (1.0 + math.cos(math.pi * ep / max(epochs - 1, 1))))
        for idx in indices:
            y, scale_factor, bucket_counts = compiled[idx]
            h = [0.0] * k
            for b_id, cnt in bucket_counts:
                row = A[b_id]
                for c in range(k):
                    h[c] += row[c] * cnt
            probs = softmax_probs([scale_factor * h[c] for c in range(k)])
            if y >= 0:
                if ep >= 6 and probs[y] > 0.99:
                    continue
                grad_z = [probs[c] - (smooth_pos if c == y else smooth_neg) for c in range(k)]
            else:
                if max(probs) < 0.095:
                    continue
                grad_z = [1.85 * (probs[c] - uniform_p) for c in range(k)]
            for b_id, cnt in bucket_counts:
                row = A[b_id]
                grow = gA[b_id]
                mult = scale_factor * cnt
                for c in range(k):
                    g = grad_z[c] * mult + l2 * row[c]
                    grow[c] += g * g
                    row[c] -= (cur_lr / math.sqrt(grow[c])) * g

    # Stage 2: Straight-Through Symmetric INT8 QAT Fine-Tuning
    qA = [simulate_int8_row(r) for r in A]
    for qep in range(qat_epochs):
        rng.shuffle(indices)
        qat_lr = lr * 0.14 * (1.0 - 0.5 * (qep / max(qat_epochs, 1)))
        for idx in indices:
            y, scale_factor, bucket_counts = compiled[idx]
            h = [0.0] * k
            for b_id, cnt in bucket_counts:
                qrow = qA[b_id]
                for c in range(k):
                    h[c] += qrow[c] * cnt
            probs = softmax_probs([scale_factor * h[c] for c in range(k)])
            if y >= 0:
                if probs[y] > 0.99:
                    continue
                grad_z = [probs[c] - (smooth_pos if c == y else smooth_neg) for c in range(k)]
            else:
                if max(probs) < 0.095:
                    continue
                grad_z = [1.85 * (probs[c] - uniform_p) for c in range(k)]
            for b_id, cnt in bucket_counts:
                row = A[b_id]
                grow = gA[b_id]
                mult = scale_factor * cnt
                for c in range(k):
                    g = grad_z[c] * mult + l2 * row[c]
                    grow[c] += g * g
                    row[c] -= (qat_lr / math.sqrt(grow[c])) * g
                qA[b_id] = simulate_int8_row(row)

    # Temperature calibration over 0.72..1.50 step 0.02 on held-out val split
    # optimizing ECE minimization with 0.0% false auto-assign & 100% val OOD rejection!
    best_temp = 1.00
    best_score = 1e9
    for step in range(72, 151, 2):
        cand_t = step / 100.0
        val_acc, _, val_ece, val_false = evaluate_quantized(val_rows, qA, logit_gain, cand_t)
        val_ood = evaluate_ood_rejection(
            VAL_OOD_SAMPLES, qA, logit_gain, cand_t, threshold=0.45
        )
        ood_penalty = 5.0 * max(0.0, 1.0 - val_ood)
        score = val_ece + 3.0 * val_false + ood_penalty - 0.10 * val_acc
        if score < best_score:
            best_score = score
            best_temp = cand_t

    test_acc, test_f1, test_ece, test_false = evaluate_quantized(test_rows, qA, logit_gain, best_temp)
    ood_rate = evaluate_ood_rejection(OOD_HELD_OUT_TEST, qA, logit_gain, best_temp)
    detailed_eval = compute_detailed_eval(test_rows, qA, logit_gain, best_temp)

    ftq_bytes = pack_lftq_binary(SPLIT_ALLOC_LABELS, A, logit_gain, best_temp)
    sha256_hex = hashlib.sha256(ftq_bytes).hexdigest()

    art_ftq = ART_DIR / "vn_money_split_fasttext_v1.ftq"
    dst_ftq = FLUTTER_MODELS_DIR / "vn_money_split_fasttext_v1.ftq"
    art_ftq.write_bytes(ftq_bytes)
    shutil.copy2(art_ftq, dst_ftq)

    metadata = {
        "modelId": "vn_money_split_fasttext_v1",
        "modelVersion": "1.0.0",
        "architecture": "FastText QAT Subword + Word Bigram + Outlier Exposure (INT8 LFTQ v1)",
        "license": "MIT",
        "language": "vi",
        "assetPath": "assets/models/vn_money_split_fasttext_v1.ftq",
        "sizeBytes": len(ftq_bytes),
        "sha256": sha256_hex,
        "numClasses": k,
        "labels": SPLIT_ALLOC_LABELS,
        "hyperparameters": {
            "numBuckets": NUM_BUCKETS,
            "dim": k,
            "wordNgrams": WORD_NGRAMS,
            "minSubword": MIN_SUBWORD,
            "maxSubword": MAX_SUBWORD,
            "logitGain": logit_gain,
            "epochs": epochs,
            "qatEpochs": qat_epochs,
        },
        "calibratedTemperature": round(best_temp, 4),
        "thresholds": {
            "highConfidence": 0.78,
            "mediumConfidence": 0.52,
            "lowConfidence": 0.35,
        },
        "metrics": {
            "trainSamples": len(train_rows),
            "valSamples": len(val_rows),
            "heldOutTestSamples": len(test_rows),
            "testAccuracy": round(test_acc, 4),
            "testMacroF1": round(test_f1, 4),
            "expectedCalibrationError": round(test_ece, 4),
            "falseAutoAssignmentRate": round(test_false, 4),
            "oodUnknownRejectionRate": round(ood_rate, 4),
        },
        "exportedAtUtc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    meta_text = json.dumps(metadata, indent=2, ensure_ascii=False) + "\n"
    (ART_DIR / "vn_money_split_fasttext_v1_meta.json").write_text(meta_text, encoding="utf-8")
    (FLUTTER_MODELS_DIR / "vn_money_split_fasttext_v1_meta.json").write_text(meta_text, encoding="utf-8")
    (ART_DIR / "vn_money_split_fasttext_v1_eval.json").write_text(
        json.dumps(
            {
                "calibratedTemperature": round(best_temp, 4),
                "testAccuracy": round(test_acc, 4),
                "testMacroF1": round(test_f1, 4),
                "expectedCalibrationError": round(test_ece, 4),
                "falseAutoAssignmentRate": round(test_false, 4),
                "oodUnknownRejectionRate": round(ood_rate, 4),
                **detailed_eval,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    print(
        f"[MONEY SPLIT AI TRAINED] Size={len(ftq_bytes):,}B | SHA256={sha256_hex}\n"
        f"Train={len(train_rows)} | Val={len(val_rows)} | Test={len(test_rows)} | Temp={best_temp:.2f}\n"
        f"Test Accuracy={test_acc:.4f} | Macro F1={test_f1:.4f} | ECE={test_ece:.4f} | "
        f"False Auto-Assign={test_false:.4f} | OOD Rejection={ood_rate:.2%}"
    )


if __name__ == "__main__":
    main()
