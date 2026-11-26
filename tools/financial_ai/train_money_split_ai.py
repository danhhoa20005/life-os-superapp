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

from audit_leakage import find_near_duplicates, index_target_rows
from evaluate import QuantizedFastTextReader, evaluate_model_on_splits
from feature_spec import (
    MONEY_SPLIT_THRESHOLDS,
    OOD_LABEL,
    extract_feature_buckets,
    normalize_for_classifier,
    strip_vn_accents,
)

BASE_DIR = Path(__file__).resolve().parent
ART_DIR = BASE_DIR / "artifacts"
DATASETS_DIR = BASE_DIR / "datasets"
REPO_ROOT = BASE_DIR.parent.parent
FLUTTER_MODELS_DIR = REPO_ROOT / "assets" / "models"

FROZEN_MS_TEST_SHA256 = "d01941975c3db896b82b1939dd4a157899eaf01bb306eea78a104c5a98c13d2d"
FROZEN_MS_OOD_TEST_SHA256 = "97e60371b653624c12fa000f0f45c2d93f7981b722264e96f6abb0775c99576f"

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

SPLIT_ALLOC_ALL_LABELS: list[str] = [*SPLIT_ALLOC_LABELS, OOD_LABEL]

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
    "nhờ tính giúp {core}",
    "ghi nhanh {core}",
    "báo giùm {core}",
    "chốt nhanh {core}",
    "xem giùm {core}",
]

VAL_WRAPPERS = [
    "{core}",
    "tính giúp {core}",
    "hỗ trợ tính {core}",
]

# Held-out test splits (`money_split_test.jsonl` & `ood_money_split_test.jsonl`) are FROZEN on disk.

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
            "hóa đơn ăn tối 640k chia đều cho bình khoa minh và sơn",
            "hóa đơn cơm tối 480k chia đều bốn bạn nam hòa tuấn khôi",
            "cả bàn ăn tối 520k chia đều cho tất cả thành viên nhóm",
            "uống trà sữa và nước ép 140k cưa đôi hai bạn",
            "ăn tối cơm niêu cá kho 360k chia đều cho bốn người",
            "mua vé xem phim và bắp nước 320k cưa đôi hai đứa",
            "góp tiền mua bình nước chung phòng trọ 120k chia đều 4 bạn",
            "uống nước mát 95k cưa đôi cùng bạn",
            "uống cà phê đá 80k cưa đôi với hùng",
            "tiền thuê xe máy du lịch 500k campuchia đều bạn bè",
            "chia đều 3 người hóa đơn ăn vặt bún thịt nướng 180k",
            "cưa đôi với bạn tiền trà chanh hướng dương 90k",
            "campuchia đều cả bàn 6 người tiền lẩu cua 1tr5",
            "chia đôi tiền gửi xe và vé cầu lông 140k",
            "uống cf muối 65k cưa đôi với nam",
            "chia bill ăn sáng bún bò 160k đều bốn anh em",
            "share đều tiền đặt grabfood trưa nay 240k cho 4 người",
            "mỗi đứa góp đều một nửa tiền quà chung 300k",
            "chia đều năm thành viên tiền thuê xe đi vũng tàu 2tr5",
            "uống sinh tố bơ 95k cưa đôi hai bạn",
            "mua sinh tố xoài 80k chia đều đôi bạn",
            "chia đều tiền ăn uống cho cả nhóm bạn",
            "cưa đôi hóa đơn ăn uống hôm nay với bạn",
            "mỗi người đóng đều phần tiền chia chung",
            "campuchia hóa đơn đi ăn đều cho mọi người",
            "nam ứng trước tiền ăn tối chia đều cả nhóm",
            "chia bill ăn trưa đều cho bốn đồng nghiệp",
            "minh trả trước tiền nước chia đều ba bạn",
            "cà phê sáng chia đều hai bạn 80k",
            "mỗi người một nửa hóa đơn ăn sáng 100k",
            "tiền đi nhậu tối qua campuchia đều 600k",
            "chia bill ăn trưa bạn trả hộ đều nhau 200k",
        ],
        "val": [
            "ăn lẩu thái 450k chia đều 3 người",
            "uống sinh tố 90k cưa đôi cùng lan",
            "tiền thuê xe tự lái 1tr6 campuchia đều 4 bạn",
            "nam trả trước tiền phở 200k chia đều bốn anh em",
            "hóa đơn ăn tối 680k chia đều cho minh tuấn hùng và dũng",
            "tiền sân bóng đá 500k mỗi người chia đều nhau",
            "chia đều 5 người tiền đặt bánh tráng trộn trà tắc 150k",
            "uống trà sữa 85k cưa đôi hai đứa",
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
            "chia tiền dọn phòng theo phần trăm lan 60% mai 40%",
            "tiền thuê kho hàng 12tr chia tỷ lệ phần trăm công ty 75% đối tác 25%",
            "hóa đơn gas nấu ăn chung 400k phòng ngoài chịu 55 phần trăm phòng trong 45 phần trăm",
            "góp tiền mua máy chiếu 6tr đội thiết kế 65 phần trăm đội kỹ thuật 35 phần trăm",
            "hóa đơn chia theo phần trăm mỗi bên đóng góp",
            "chi phí chung chia phần trăm từng người chịu",
            "chia tiền phòng theo tỷ lệ phần trăm từng thành viên",
            "hóa đơn chia theo mức phần trăm giữa các phòng",
        ],
        "val": [
            "tiền thuê nhà trọ 6tr chia phần trăm phòng có ban công 60 phần trăm phòng nhỏ 40 phần trăm",
            "hóa đơn điện tháng này 1tr5 hùng 50 phần trăm nam 30 phần trăm khoa 20 phần trăm",
            "mua tủ lạnh dùng chung 4tr chia theo tỷ lệ phần trăm lan 55 phần trăm mai 45 phần trăm",
            "chi phí phần mềm nhóm 1tr2 chia phần trăm trưởng nhóm 70 phần trăm thành viên 30 phần trăm",
            "góp quỹ liên hoan 3tr sếp đóng 60 phần trăm nhân viên 40 phần trăm",
            "tiền mạng văn phòng 550k phòng kinh doanh 70 phần trăm phòng hành chính 30 phần trăm",
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
            "chia tiền thịt nướng 1tr2 theo tỷ lệ phần anh dũng 2 phần em sơn 1 phần",
            "tiền đặt tiệc tất niên 4tr5 gia đình chị hoa 3 suất bạn minh 1 suất",
        ],
        "val": [
            "ăn buffet cuối tuần 1tr8 chia theo suất nhà minh 2 suất tuấn 1 suất lan 1 suất",
            "tiền rác và nước chung 300k chia theo phần phòng lầu một 3 phần phòng trệt 2 phần",
            "thuê resort phan thiết 4tr5 gia đình anh hùng 2 phần bạn nam 1 phần",
            "mua thịt bò mỹ 900k chia theo phần chị hà lấy 2 phần em trang 1 phần",
            "chi phí đặt cỗ 3tr chia theo hệ số suất ăn hai gia đình 3 suất và 2 suất",
            "chia hóa đơn ăn tối 1tr1 người lớn 2 phần trẻ con 1 phần",
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
            "thanh toán bill quán ốc 740k sơn gọi riêng đĩa sò điệp 140k phần còn lại 4 người chia đều",
            "đi ăn phở nhóm 280k hải ăn thêm chén tiết trứng 30k số còn lại 5 bạn campuchia",
            "bill bách hóa chung 620k vy mua riêng tuýp kem chống nắng 220k phần đồ chung chia đều 4 người",
            "tiền karaoke 1tr2 nam kêu thêm chai rượu riêng 300k phần còn lại chia đều 6 người",
            "đặt đồ ăn đêm 430k tùng lấy riêng phần chân gà 70k phần còn lại 3 anh em cưa đều",
            "hóa đơn ăn tối 960k hòa đặt riêng món lươn 160k số còn lại cả nhóm 4 người chia đều",
        ],
        "val": [
            "ăn trưa văn phòng 390k nam gọi thêm ly sinh tố riêng 50k còn lại chia đều 4 người",
            "đi nhậu 780k tuấn lấy riêng bao thuốc 60k phần còn lại 3 anh em chia đều",
            "mua đồ bách hóa 460k lan lấy riêng hộp kem dưỡng 160k phần chung chia đều 3 bạn",
            "đặt cơm trưa 290k minh thêm phần chả giò riêng 50k số còn lại chia đều 3 đồng nghiệp",
            "hóa đơn quán nướng 1tr050k hùng uống riêng rượu mơ 150k còn lại 3 người chia đều",
            "đi cafe học nhóm 340k khoa gọi riêng bánh croissant 60k phần nước còn lại 4 bạn chia đều",
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
            "ăn trưa gọi từng món riêng 210k bình 75k khoa 70k sơn 65k",
            "đặt đồ uống văn phòng 160k bình 60k hòa 50k nam 50k",
            "tiền ăn gọi theo món hòa 70k bình 65k khôi 55k",
        ],
        "val": [
            "tiền ăn trưa gọi theo món 215k hòa 75k minh 80k lan 60k",
            "mua quà tân gia 1tr2 nam đóng 500k tuấn 400k còn lại khoa chịu",
            "đặt đồ uống chiều 175k mai 65k thảo 55k vy 55k",
            "hóa đơn mua đồ gia dụng 650k hùng 300k bình 200k còn lại dũng trả",
            "tiền vé tàu nhóm 950k tùng 350k sơn 300k hải 300k",
            "đặt đồ ăn vặt gọi từng món 240k lan 90k vy 80k mai 70k",
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
            "siêu thị coopmart 620k gồm đồ ăn tươi sống 400k vật dụng gia đình 220k",
            "thanh toán tổng hợp 850k bao gồm khám sức khỏe 550k thuốc 300k",
            "tách hóa đơn mua hàng trực tuyến 900k gồm quần áo 550k đồ bếp 350k",
            "hóa đơn tổng hợp tháng này 1tr3 bao gồm tiền điện 850k gói cước truyền hình 450k",
            "mua đơn hàng thương mại điện tử 780k gồm phụ kiện máy tính 480k sách vở 300k",
            "đi siêu thị big c 690k trong đó thực phẩm tươi 490k hóa mỹ phẩm 200k",
            "tách bill siêu thị go 1tr1 gồm thực phẩm 700k hóa chất tẩy rửa 400k",
            "thanh toán thẻ tín dụng kỳ này 3tr2 trong đó ăn uống 1tr8 di chuyển 600k mua sắm 800k",
            "tách hóa đơn siêu thị 650k gồm thực phẩm thịt rau củ 420k giấy vệ sinh nước lau sàn 230k",
            "tách bill siêu thị 700k phần đồ ăn 450k phần hóa mỹ phẩm gia dụng 250k",
            "hóa đơn tổng hợp 820k tiền thực phẩm 520k tiền đồ dùng sinh hoạt 300k",
            "phân loại khoản chi trên một hóa đơn siêu thị 600k ăn uống và mua sắm",
            "tách các hạng mục trong bill mua sắm 950k thành ăn uống gia dụng và cá nhân",
            "chia hóa đơn đi siêu thị nhiều mục thực phẩm 400k quần áo 300k đồ bếp 200k",
            "tách chi tiêu hóa đơn coopmart thành tiền đồ ăn và tiền đồ dùng",
            "bill mua sắm tổng hợp 720k phần thực phẩm và phần việc nhà gia dụng",
            "chia hóa đơn siêu thị nhiều nhóm đồ ăn 450k và gia dụng 250k",
            "hóa đơn mua sắm tổng hợp nhiều mục tiền ăn 500k và đồ dùng 300k",
            "tách tổng tiền bill siêu thị gồm thực phẩm 600k và vệ sinh nhà 200k",
            "tách hóa đơn mua sắm gồm ăn uống 400k và đồ cá nhân 350k",
            "đi siêu thị winmart mua tổng 650k trong đó rau thịt 450k và nước lau sàn 200k",
            "tách bill đi chợ gồm thực phẩm 350k đồ dùng gia đình 180k",
        ],
        "val": [
            "hóa đơn siêu thị 650k gồm thực phẩm 430k việc nhà gia dụng 220k",
            "đi winmart 510k bao gồm thịt rau củ 360k giấy vệ sinh nước lau sàn 150k",
            "tách hóa đơn mua hàng 1tr1 trong đó quần áo 700k sách vở 400k",
            "siêu thị coopmart 780k gồm đồ ăn tươi sống 520k vật dụng bếp 260k",
            "thanh toán tổng 900k bao gồm khám sức khỏe 600k thuốc men 300k",
            "tách chi tiêu hóa đơn lotte 840k gồm đồ ăn 540k đồ gia dụng 300k",
            "tách hạng mục hóa đơn siêu thị 550k phần thực phẩm 350k phần đồ gia dụng 200k",
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
            "tất toán khoản nợ nhóm bạn đi chơi cuối tuần với nhau",
            "hoàn lại tiền đồng nghiệp ứng trước đặt cơm buổi trưa",
            "cấn trừ công nợ chia hóa đơn chung giữa các thành viên phòng trọ",
            "chuyển khoản trả lại phần tiền bạn ứng hộ mua đồ du lịch 320k",
            "cấn trừ nợ nhóm bạn tối giản số lượt chuyển khoản ngân hàng",
            "nhận tiền thành viên nhóm gửi trả phần chia hóa đơn thể thao 140k",
            "trả lại tiền đồng nghiệp đã ứng hộ bữa trưa",
            "chuyển khoản hoàn trả tiền ăn bạn đặt giúp hôm qua",
            "tất toán khoản nợ phòng trọ tháng này",
            "trả lại phần tiền bạn ứng hộ đi siêu thị 250k",
            "thanh toán dứt điểm tiền bạn ứng mua đồ tuần trước",
            "trả lại tiền cà phê bạn trả hộ hôm qua",
            "nhận lại tiền đồng nghiệp trả phần ăn trưa",
            "gửi trả bạn tiền cà phê đã ứng trước",
            "thu hồi tiền đồng nghiệp trả lại hôm qua",
        ],
        "val": [
            "tuấn chuyển trả lại tiền chia hóa đơn cà phê 65k",
            "tất toán khoản nợ nhóm du lịch vũng tàu cho bình 550k",
            "hoàn lại tiền ứng trước mua đồ chung phòng trọ cho lan 300k",
            "cấn trừ công nợ chia tiền ăn uống cuối tuần giữa các thành viên",
            "nhận lại tiền đồng nghiệp hoàn trả bill đặt cơm trưa 75k",
            "gửi trả lại tiền chia hóa đơn đi ăn chung cho khôi 130k",
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
            "áp dụng công thức quản lý tài chính 50 30 20 chia lương hàng tháng",
            "chia quỹ tháng 50 30 20 cho nhu cầu cá nhân và tiết kiệm",
            "phân bổ thu nhập theo quy tắc năm mươi ba mươi hai mươi chuẩn tài chính",
            "lập kế hoạch tài chính cá nhân theo tỷ lệ 50 30 20 từng tháng",
            "áp dụng mô hình năm mươi ba mươi hai mươi cho khoản lương 25tr vừa nhận",
            "chia thu nhập năm mươi ba mươi hai mươi theo tỷ lệ thiết yếu giải trí tiết kiệm",
            "phân bổ lương tháng 22tr theo công thức năm mươi ba mươi hai mươi",
            "mô hình chia lương cân bằng 50 thiết yếu 30 mong muốn và 20 tích lũy",
            "tính ngân sách cá nhân theo ba quỹ thiết yếu cá nhân tiết kiệm năm mươi ba mươi hai mươi",
            "chia lương theo phương pháp cân đối 50 nhu cầu cơ bản 30 sở thích 20 để dành",
            "phân bổ thu nhập 21tr thành 50 thiết yếu 30 giải trí 20 tiết kiệm",
            "chia lương tháng thành ba quỹ 50 thiết yếu 30 giải trí cá nhân 20 tích lũy",
            "áp dụng mô hình năm mươi ba mươi hai mươi cho tiền lương tháng này",
            "chia tiền lương mới nhận thành ba phần thiết yếu hưởng thụ và tích lũy",
            "áp dụng phương pháp ba quỹ thiết yếu mong muốn tiết kiệm từ tiền lương",
            "chia tiền lương theo quy tắc năm mươi ba mươi hai mươi",
        ],
        "val": [
            "lương về 21 triệu chia theo quy tắc 50 30 20 giúp mình",
            "phân bổ thu nhập 17tr thành 50 thiết yếu 30 giải trí 20 tiết kiệm",
            "áp dụng công thức quản lý tài chính 50 30 20 cho lương 26 triệu",
            "chia ngân sách tháng cân bằng theo tỷ lệ năm mươi ba mươi hai mươi",
            "tính mức chi tiêu hợp lý từ lương 18tr5 theo chuẩn 50 30 20",
            "áp dụng mô hình 50 30 20 cho khoản tiền lương tháng này mới nhận",
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
            "quản lý tiền bằng mô hình chiếc lọ chia lương hàng tháng",
            "lập kế hoạch quản lý tiền bằng chiếc lọ cho thu nhập tháng",
            "chia lương 29tr vào 6 hũ nhỏ gồm hũ giáo dục hũ hưởng thụ và hũ cho đi",
            "phân bổ tiền lương vào sáu chiếc lọ theo phương pháp quản lý tài chính harv eker",
            "phân chia ngân sách sáu hũ gồm thiết yếu học tập đầu tư hưởng thụ và thiện nguyện",
            "áp dụng mô hình sáu chiếc lọ jarrs để chia tiền lương hàng tháng",
            "tính các hũ chi tiêu giáo dục tự do tài chính cho thu nhập 24tr",
            "chia tiền vào 6 cái lọ chi tiêu đầu tư học tập thiện nguyện",
            "chia thu nhập vào sáu hũ nhỏ tài chính hàng tháng",
            "phương pháp sáu chiếc lọ chia lương hàng tháng",
            "chia lương theo sáu chiếc lọ tài chính cá nhân",
            "bỏ tiền lương vào sáu lọ tiết kiệm và giáo dục",
            "sáu hũ tài chính jarrs chia thu nhập hàng tháng",
            "chia lương vào sáu chiếc hũ quản lý tiền harv eker",
            "hũ thiết yếu hũ giáo dục hũ hưởng thụ hũ tiết kiệm dài hạn",
            "lương chia vào 6 hũ",
            "chia tiền lương 6 lọ jarrs",
            "phân bổ thu nhập 6 hũ tài chính",
            "lương 20tr chia 6 lọ",
            "phân bổ thu nhập theo 6 hũ",
        ],
        "val": [
            "chia lương 24 triệu theo phương pháp 6 chiếc lọ tài chính",
            "phân bổ thu nhập tháng 27tr vào sáu hũ chi tiêu và đầu tư",
            "tính định mức 6 lọ chuẩn quốc tế cho mức lương 19 triệu",
            "lập kế hoạch quản lý tiền bằng 6 chiếc lọ từ thu nhập 30tr",
            "chia tiền vào 6 quỹ thiết yếu giáo dục hưởng thụ tự do tài chính cho đi",
            "áp dụng mô hình 6 hũ tài chính jarrs cho lương 23tr",
            "chia lương theo phương pháp sáu hũ tài chính",
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
            "hai vợ chồng thu nhập 38tr vừa nuôi con đi học vừa chăm lo bố mẹ chia quỹ sao",
            "kế hoạch phân chia tiền lương hộ gia đình có ông bà sống chung và hai con nhỏ",
            "chia dòng tiền tổ ấm 31tr cân đối chi tiêu ăn uống nuôi bé và tiết kiệm gia đình",
            "tư vấn quản lý ngân sách hộ gia đình đa thế hệ tổng lương 44 triệu",
            "lập bảng phân bổ thu nhập gia đình gồm quỹ con cái quỹ nội ngoại và sinh hoạt",
            "vợ chồng trẻ lương 25tr có con sơ sinh chia tiền sữa tã và tiền nhà thế nào",
        ],
        "val": [
            "tổng thu nhập hai vợ chồng 30 triệu có em bé chia ngân sách gia đình thế nào",
            "phân bổ lương 38tr cho chi phí tổ ấm học phí con nhỏ và quỹ dự phòng gia đình",
            "chia tiền sinh hoạt gia đình 4 người thu nhập 33 triệu gồm tiền chợ sữa bỉm điện nước",
            "tư vấn lập quỹ chung vợ chồng 28tr vừa nuôi con vừa tiết kiệm phòng đau ốm",
            "kế hoạch phân chia thu nhập hộ gia đình có con học tiểu học và biếu nội ngoại",
            "ngân sách gia đình có con nhỏ tổng thu nhập 35tr cân đối nuôi bé và dự phòng y tế",
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
            "thu nhập hàng tháng 23tr chia tỷ lệ trả gốc lãi vay mua nhà và sinh hoạt tối thiểu",
            "lập kế hoạch chia lương 20tr ưu tiên thanh toán hết dư nợ thẻ tín dụng lãi cao",
            "cách chia ngân sách tháng từ lương 17tr để vừa trả góp hàng tháng vừa thoát nợ sớm",
            "tư vấn phân bổ dòng tiền trả nợ từng bước cho người đang vay vốn ngân hàng",
            "chia thu nhập 26tr dành tối đa phần dư trả dứt điểm khoản vay tiêu dùng",
            "kế hoạch phân chia tiền lương hàng tháng để xử lý nợ vay lãi suất cao nhanh gọn",
            "phân chia tiền lương khi có khoản vay ngân hàng hàng tháng để tất toán nhanh",
            "lập ngân sách trả nợ nhanh từ mức lương theo chiến lược quả cầu tuyết",
            "chia dòng tiền từ thu nhập ưu tiên trả nợ vay và sinh hoạt tối thiểu",
            "tư vấn lập kế hoạch chia tiền lương tất toán khoản vay ngân hàng trước hạn",
            "chia ngân sách hàng tháng từ tiền lương để trả dứt nợ thẻ tín dụng",
        ],
        "val": [
            "lương 20 triệu mỗi tháng trả góp 6 triệu phân bổ phần còn lại sao để nhanh hết nợ",
            "tư vấn chia thu nhập 23tr ưu tiên thanh toán dư nợ thẻ tín dụng lãi cao",
            "lập ngân sách trả nợ nhanh từ mức lương 17tr bằng chiến lược snowball",
            "thu nhập 26 triệu đang vay mua xe 7tr5 chia chi tiêu tối giản để trả nợ trước hạn",
            "phân chia tiền lương khi có khoản vay ngân hàng hàng tháng cần tất toán gấp",
            "chia dòng tiền từ lương 22tr để ưu tiên trả gốc lãi vay ngân hàng đúng hạn",
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
            "chia thu nhập 42tr theo nguyên tắc tích sản mạnh đạt tự do tài chính trước bốn mươi tuổi",
            "tối đa hóa tỷ lệ tiết kiệm từ mức lương 34tr để mua đất và đầu tư quỹ mở",
            "chia dòng tiền cá nhân 30tr ưu tiên gom tiền mua ô tô và đầu tư cổ phiếu",
        ],
        "val": [
            "lương 32 triệu thuê phòng 4tr5 muốn tiết kiệm tối đa đầu tư đạt tự do tài chính fire",
            "phân bổ thu nhập 38tr dành 50 phần trăm mua chứng chỉ quỹ và tích lũy mua nhà",
            "tư vấn chia lương 27 triệu theo hướng sống tối giản tăng tốc tích sản dài hạn",
            "kế hoạch trích 45 phần trăm thu nhập 42tr vào danh mục đầu tư lãi kép nghỉ hưu sớm",
            "chia dòng tiền cá nhân 29tr ưu tiên gom tiền mua ô tô và đầu tư cổ phiếu",
            "phân bổ lương 35tr ưu tiên tích lũy tài sản và đầu tư dài hạn nghỉ hưu sớm",
        ],
    },
}

# Rich disjoint negative OOD augmentations for `ood_money_split_train.jsonl` & `ood_money_split_val.jsonl`
# (explicitly contrasted against single-person transactions that share debt/shopping/family/savings words!)
AUG_MS_OOD_POOLS: dict[str, dict[str, list[str]]] = {
    "e_single_person_near_ood": {
        "train": [
            # Single-person debt/loan/credit card payments (NOT alloc.debt_payoff plans!)
            "trả nợ thẻ tín dụng 2tr",
            "thanh toán dư nợ thẻ tín dụng vpbank 3tr5",
            "đóng tiền trả góp xe máy tháng này 2tr4",
            "trả góp điện thoại iphone qua fe credit 1tr2",
            "trả tiền lãi vay ngân hàng bidv tháng này 1tr8",
            "chuyển khoản trả nợ tiền mượn bạn hôm trước 500k",
            "tất toán khoản vay tiêu dùng home credit 4tr5",
            "đóng kỳ trả góp laptop ở thế giới di động 1tr6",
            "trả tiền vay mua đồ gia dụng tuần rồi 300k",
            "nộp tiền gốc lãi vay mua nhà tháng này 7tr5",
            "đóng trả góp hd saison kỳ này 1tr4",
            "thanh toán sao kê thẻ tín dụng techcombank 5tr",
            "trả nợ tiền hàng nhập tuần trước 3tr",
            "chuyển khoản trả góp tủ lạnh máy giặt 900k",
            "trả tiền vay nóng bạn bè 2tr5",
            "tra no the tin dung 2tr",
            "dong tien tra gop xe may 2tr5",
            "thanh toan du no the visa 3tr",
            "tra tien lai vay ngan hang 1tr5",
            "tat toan khoan vay fe credit 4tr",
            # Single-person supermarket / grocery (single-item focus, NOT split.multi_category_receipt!)
            "đi siêu thị mua chai nước giặt 180k",
            "ăn trưa cơm tấm và uống trà sữa hết 95k",
            "ra nhà thuốc long châu mua thuốc cảm 180k",
            "đi chợ mua thịt heo cá thu rau cải hết 220k",
            "ghé circle k mua nước suối và bánh mì 85k",
            "đi siêu thị lotte mart mua hộp sữa tươi 65k",
            "ăn sáng phở bò và gọi ly cà phê đá 80k",
            "ghé guardian mua kem chống nắng 450k",
            "đặt đơn tiki mua bàn phím không dây 720k",
            "di cho mua thit ca rau cu 250k",
            "mua đôi giày thể thao trên shopee 420k",
            # Single-person family / children / parents expenses (NOT alloc.family_household!)
            "đóng tiền học cho con 3tr",
            "nộp học phí mầm non cho bé 4tr",
            "mua sữa bỉm cho em bé ở con cưng 650k",
            "gửi tiền biếu bố mẹ ở quê 2tr",
            "chuyển khoản phụng dưỡng ông bà nội 3tr",
            "mua đồ chơi và quần áo cho con 450k",
            "nộp tiền ăn bán trú cho bé tháng này 1tr2",
            "đưa con đi khám nhi bệnh viện nhi đồng 400k",
            "đóng tiền học thêm toán cho con 1tr5",
            "mua váng sữa và tã giấy cho bé 520k",
            "dong tien hoc cho con 3tr",
            "mua sua bim cho em be 600k",
            "gui tien bieu bo me o que 2tr",
            # Single-person savings / investment / salary / standalone expenses (NOT alloc.fire / alloc.rule_50_30_20!)
            "gửi tiết kiệm 5tr",
            "gửi sổ tiết kiệm ngân hàng 10tr",
            "nạp tiền mua chứng chỉ quỹ tháng này 3tr",
            "mua cổ phiếu tích sản dài hạn 5tr",
            "mua một chỉ vàng tích trữ cuối tháng 8tr",
            "nhận lương tháng này 22tr",
            "chuyển tiền vào quỹ dự phòng cá nhân 2tr",
            "bỏ ống heo tiết kiệm cuối tuần 500k",
            "tất toán sổ tiết kiệm nhận lãi 1tr2",
            "rút tiền mặt cây atm vietcombank 2tr",
            "chuyển khoản tiền thuê phòng trọ tháng này 3tr5",
            "đóng tiền điện nước internet tháng này 950k",
            "tự đi uống cà phê sáng một mình ở quán quen 45k",
            "mua trà sữa uống một mình buổi chiều 55k",
            "nhận thưởng kpi quý này 6tr",
            "gui tiet kiem ngan hang 5tr",
            "nhan luong thang nay 20tr",
            "chuyen khoan tien thue nha 4tr",
            "dong tien dien nuoc thang nay 800k",
            "chốt lời cổ phiếu nhận về 12tr",
            "chốt lời lợi nhuận đầu tư chứng chỉ quỹ 5tr",
            "nhận cổ tức chứng khoán quý này 2tr5",
            "bán chốt lời chứng chỉ quỹ mở 8tr",
            "nạp tiền đầu tư cổ phiếu chứng chỉ quỹ 4tr",
            "trả nợ gốc khoản vay ngân hàng 5tr",
            "nhận tạm ứng lương đợt một 6tr",
            "nhận tiền lương thực nhận cuối tháng 19tr",
            "payroll lương chính thức công ty 21tr",
            "nhận thưởng lương tháng thứ mười ba 15tr",
            "chi tiêu cá nhân lặt vặt chưa phân nhóm 200k",
            "tra no goc khoan vay ngan hang 5tr",
            "nhan tam ung luong dot mot 6tr",
            "đăng ký gói cước 4g tháng này 90k",
            "đăng ký 4g viettel tháng này 90k",
            "lấy cao răng nha khoa 250k",
            "trám răng sâu nha khoa 300k",
            "ủng hộ thiện nguyện cuối năm 500k",
            "ăn tối lẩu nướng một mình 180k",
            "đi siêu thị coopmart mua đồ ăn 450k",
            "mua đơn hàng shopee mỹ phẩm 380k",
            "đóng tiền sao kê nợ thẻ tín dụng 2tr",
            "góp tiền mua trả góp tủ lạnh 1tr2",
            "thanh toán lãi quá hạn khoản vay 500k",
            "trả lãi vay thế chấp mua nhà ngân hàng 5tr",
            "thanh toán tiền lãi vay cá nhân 900k",
            "trả tiền gốc lãi vay ngân hàng mỗi tháng 4tr",
            "đang trả góp điện thoại mỗi tháng 1tr2",
            "mỗi tháng đóng tiền điện nước nhà trọ 700k",
            "đang chờ nhận hàng đặt trên shopee 250k",
            "đóng tiền lãi suất vay vốn kinh doanh 2tr",
            "trả nợ ngân hàng hàng tháng 3tr",
            "trả nợ tiền hàng nhập tuần này 2tr",
            "đang trả góp xe máy mỗi tháng 2tr4",
            "tra no ngan hang 3tr",
            "tra goc lai vay mua nha moi thang 4tr",
            "dang tra gop dien thoai moi thang 1tr2",
            "dong tien lai suat vay von 2tr",
            "dang ky 4g thang 90k",
            "đóng trả góp mua xe ô tô tháng này 6tr",
            "trả tiền nợ vay ngân hàng tháng này 3tr",
            "chuyen khoan tra no vay ngan hang 4tr",
            "mua chung chi quy co phieu dau tu 5tr",
            "chot loi dau tu chung chi quy mo 6tr",
            "đóng tiền góp điện thoại hàng tháng 1tr3",
            "thanh toán thẻ tín dụng kỳ sao kê tháng này 4tr2",
            "trả tiền vay mua xe máy tháng mười một 2tr8",
            "gửi tiết kiệm ngân hàng kỳ hạn một năm 15tr",
            "nạp tiền vào tài khoản chứng khoán đầu tư 7tr",
            "đáo hạn thẻ tín dụng tháng này 5tr",
            "rút tiền mặt thẻ tín dụng 3tr",
            "trả góp qua thẻ tín dụng kỳ này 2tr2",
            "chuyển khoản trả nợ gốc và lãi tháng mười một 4tr5",
            "đóng tiền góp xe tháng này 2tr6",
            "cho bạn vay mượn tạm 2tr cuối tháng trả",
            "thu hồi tiền cho bạn mượn tháng trước 1tr5",
            "thanh toán dư nợ vay tiêu dùng tháng này 3tr2",
            "trả tiền lãi vay mua nhà hàng tháng 6tr",
            "mua đồ ăn sáng bánh mì thêm ly cà phê 65k",
            "gọi thêm phần cơm và trà sữa hết 120k",
            "dao han the tin dung thang nay 5tr",
            "tra gop qua the tin dung 2tr",
            "dong tien gop hang thang 2tr5",
            "cho ban vay tam 2tr cuoi thang tra",
            "thanh toan du no the tin dung 4tr",
            # Single-person travel / booking / transport (NOT split.exact_custom!)
            "đặt vé tàu hỏa khứ hồi về quê 900k",
            "đặt vé tàu lửa khứ hồi 850k",
            "mua vé máy bay khứ hồi đi công tác 2tr8",
            "đặt phòng khách sạn một đêm 750k",
            "đi grab car ra sân bay hết 220k",
            "đổ đầy bình xăng xe máy 95k",
            "đưa xe đi thay nhớt bảo dưỡng 350k",
            "nạp tiền thẻ thu phí không dừng vetc 500k",
            "dat ve tau hoa khu hoi ve que 900k",
            # Single-person discounts / cashback / interest rate (without 'hóa đơn' split collision)
            "mua áo khoác được giảm giá 20 phần trăm",
            "phí dịch vụ nhà hàng 10 phần trăm hết 65k",
            "gửi tiết kiệm kỳ hạn mười hai tháng lãi suất 6 phần trăm",
            "hoan tien 5 phan tram the tin dung",
            # Single-person meal/order with extra item (NOT split.itemized_remainder!)
            "ăn phở bò gọi thêm quẩy và trà đá hết 65k",
            "đặt hộp cơm trưa thêm phần sườn nướng 70k",
            "uống trà sữa thêm trân châu trắng hết 55k",
            "ăn bún chả thêm hai cái nem rán 75k",
            # Single-person refunds / deposits / personal transfers (NOT split.settle_repayment!)
            "nhận tiền hoàn đơn hàng shopee về ví 250k",
            "lấy lại tiền đặt cọc thuê phòng trọ cũ 3tr",
            "hoàn tiền vé xem phim bị hủy suất chiếu 180k",
            "chuyển khoản trả tiền thuê nhà tháng này cho chủ trọ 4tr",
            "chuyển tiền thanh toán đơn hàng giao tận nhà 320k",
            # Single-person debt payment / interest / bank fee / installment (NOT alloc.debt_payoff plan!)
            "đóng tiền lãi vay mua nhà ngân hàng tháng này 5tr",
            "trả tiền lãi vay thế chấp sổ đỏ 6tr",
            "đóng tiền góp hàng tháng mua laptop trả góp 1tr5",
            "phí phạt trả chậm sao kê thẻ tín dụng 250k",
            "đóng tiền lãi thẻ tín dụng tháng này 400k",
            "thanh toán một phần dư nợ thẻ tín dụng 2tr",
            "trả bớt tiền vay mua xe tháng mười một 3tr",
            "chuyển khoản đóng kỳ góp mua điện thoại 1tr1",
            "tất toán hết dư nợ thẻ tín dụng trước hạn 6tr",
            "đóng tiền trả góp qua ví momo tháng này 950k",
            "nộp tiền trả nợ vay tín chấp ngân hàng 3tr5",
            "trả tiền gốc và lãi kỳ này cho ngân hàng 4tr2",
            "đóng tiền góp mua tivi tủ lạnh hàng tháng 1tr2",
            "trả lãi khoản vay tín chấp ngân hàng 650k",
            "đóng tiền trả góp điện thoại home credit 1tr2",
            "thanh toán kỳ trả góp fe credit tháng này 1tr5",
            "đóng tiền góp khoản vay tiêu dùng tháng này 1tr8",
            "dong tien lai vay ngan hang thang nay 5tr",
            "dong tien gop hang thang mua laptop 1tr5",
            "thanh toan mot phan du no the tin dung 2tr",
            "phi phat tra cham the tin dung 250k",
            "tra lai khoan vay tin chap ngan hang",
            # Single-person family / salary standalone (NOT alloc.family_household / alloc.rule_50_30_20!)
            "nhận tiền lương chuyển khoản tháng này 18tr",
            "lãnh tiền thưởng hiệu suất cuối quý 5tr",
            "đóng tiền học phí học kỳ mới cho con 6tr",
            "mua sữa bột và đồ ăn dặm cho em bé 800k",
            "chuyển tiền biếu bố mẹ mua thuốc bổ 2tr",
            "nộp tiền bảo hiểm y tế gia đình cả năm 2tr5",
            "chi tiêu cá nhân hôm nay 200k",
            "chi tiêu cuối tuần này hết 350k",
            "chi tiêu lặt vặt trong ngày 150k",
            "trả nợ bạn 300k",
            "trả nợ xong rồi 1tr",
            "đang trả nợ thẻ tín dụng 2tr",
            "nợ cũ trả rồi 500k",
            "mua đồ gia dụng nhà bếp 500k",
            "đi siêu thị 350k",
            "tiền nhà tháng này 4tr",
            "ăn trưa ngoài quán 60k",
            "uống cà phê một mình 45k",
            "sắm đồ gia dụng phòng bếp 420k",
            "đi vay bạn 2tr tuần sau trả",
            "vay tiền ngân hàng mua xe máy 5tr",
            "vay tiêu dùng cá nhân 3tr",
            "sợ dính nợ xấu ngân hàng cic",
            "kiểm tra nợ xấu cic cá nhân",
            "mua điện thoại trả góp không phần trăm 2tr",
            "đóng trả góp hàng tháng 2tr",
            "tổng khoản vay mua nhà 500tr",
            "đang vay mua xe 3tr",
            "trả góp qua thẻ tín dụng mỗi tháng 1tr5",
            "mua sắm được giảm 20 phần trăm còn 380k",
            "hóa đơn ăn uống giảm 15 phần trăm khi thanh toán ví",
            "thanh toán thẻ được chiết khấu 10 phần trăm còn 450k",
            "mua đồ được giảm 10 phần trăm còn 270k",
            "lãi suất vay ngân hàng 12 phần trăm một năm",
            "nhận hoàn tiền hàng lỗi về ví 150k",
            "chuyển trả tiền mua đồ hôm trước 200k",
            "trích khoản nhỏ bỏ ống heo tiết kiệm 500k",
        ],
        "val": [
            "trả nợ thẻ tín dụng ngân hàng acb 2tr8",
            "đóng tiền trả góp xe máy tháng này 2tr2",
            "chuyển khoản trả tiền mượn bạn hôm qua 400k",
            "đi siêu thị coopmart mua đồ ăn 460k",
            "mua đơn hàng shopee mỹ phẩm 390k",
            "ghé nhà thuốc pharmacity mua thuốc ho và vitamin 160k",
            "đóng học phí mầm non cho con tháng này 3tr5",
            "mua sữa bột và tã bỉm cho bé ở kids plaza 700k",
            "gửi sổ tiết kiệm online kỳ hạn sáu tháng 8tr",
            "mua chứng chỉ quỹ đầu tư tháng này 4tr",
            "mời đồng nghiệp uống cà phê chiều hết 120k",
            "đóng tiền điện nước wifi phòng trọ tháng này 750k",
            "chốt lời lợi nhuận đầu tư cổ phiếu tuần này 5tr",
            "mua vé máy bay khứ hồi đi công tác 2tr6",
            "đóng tiền lãi vay mua nhà ngân hàng tháng này 4tr8",
            "nhận tiền hoàn đơn hàng bị hủy về ví momo 300k",
            "đặt hộp cơm trưa thêm phần trứng ốp la 60k",
            "thanh toán hóa đơn được giảm 15 phần trăm còn 420k",
        ],
    },
    "a_chatter_homonyms": {
        "train": [
            "ngắm bình hoa thủy tinh phòng khách rất đẹp",
            "xếp gọn đồ gia vị hạt khô trên kệ bếp",
            "cất gọn chén bát vào trong tủ bếp",
            "pin điện thoại chỉ còn mười lăm phần trăm thôi",
            "lắng nghe chia sẻ kinh nghiệm từ các anh chị đi trước",
            "đứng đợi ở tiền sảnh khách sạn chờ bạn",
            "bác lương cạnh nhà sáng nào cũng chạy bộ",
            "trời nóng bức cả phòng nghỉ giải lao uống nước mát",
            "chờ một lát nhé bạn ơi mình sắp tới nơi",
            "chúc cả nhà buổi tối thật nhiều niềm vui nha",
            "kệ nó đi đừng suy nghĩ nhiều nữa",
            "để nó tự làm việc đó đi nhé",
            "hôm qua nó bảo chiều nay mới xong",
            "cái máy tính này nó hơi chậm rồi",
            "tại nó quên mang chìa khóa xe thôi",
            "chắc nó đang bận họp trên văn phòng",
            "cho nó mượn cái bút một lát nhé",
            "sao nó cứ báo lỗi hoài vậy ta",
            "thời gian còn lại không nhiều đâu bạn",
            "mấy trang sách còn lại đọc cho xong",
            "áp dụng quy định mới từ thứ hai tới",
            "kế hoạch đi dã ngoại cuối tuần này rất vui",
            "chiến lược chơi cờ vua này hay thật",
            "còn nợ bạn một ly cà phê nhé",
            "đóng góp ý kiến xây dựng bài thuyết trình",
        ],
        "val": [
            "đặt bình hoa ly tươi trên bàn làm việc",
            "dung lượng pin laptop chỉ còn hai mươi phần trăm",
        ],
    },
    "b_non_financial_lifeos": {
        "train": [
            "nhắc lịch đóng tiền điện trước thứ sáu tuần này",
            "tạo lịch hẹn khám nha khoa chiều thứ năm",
            "cập nhật odo xe máy đạt hai vạn năm nghìn km",
            "tạo danh sách đi siêu thị mua rau thịt trái cây",
            "nhắc uống thuốc bổ mắt sau bữa ăn tối",
            "tạo lịch họp nhóm dự án sáng thứ tư",
            "nhắc gửi tài liệu tổng kết cho cả nhóm",
            "làm bài tập nhóm cùng các bạn cuối tuần",
            "lưu việc cần làm nộp hồ sơ công việc trước chiều mai",
        ],
        "val": [
            "nhắc lịch đóng tiền nước trước ngày cuối tháng",
            "lên lịch khám sức khỏe tổng quát sáng thứ bảy",
        ],
    },
    "c_english_gibberish_code_fragments": {
        "train": [
            "please split the screen into two panels vertically",
            "allocate buffer memory for incoming audio stream",
            "SELECT user_id, ratio FROM split_metrics WHERE active = true;",
            '{"split_mode": "none", "status": "ok", "latency_ms": 3}',
            "git cherry-pick fix/settlement-rounding-error",
            "push nhánh code lên git repo trước giờ nghỉ trưa",
            "merge pull request nhánh backend trước khi nghỉ lễ",
            "asdfghjkl zxcvbnm qwerty123",
            "check the pull request diff before merging",
            "kubectl rollout restart deployment/billing-worker",
            "cargo test --workspace --release",
            "chào buổi sáng mọi người nhé",
            "chào buổi chiều cả nhà ạ",
            "chào buổi tối mọi người",
            "chúc cả nhà buổi trưa vui vẻ",
            "hello everyone how are you",
            "hi there good morning team",
            "good afternoon have a nice day",
            "ok thanks see you tomorrow",
            "test message only please ignore",
            "follow the coding style rule strictly",
            "firewall blocked incoming request port",
            "trigger fire event on button click",
            "store dry beans in glass jars",
            "screen aspect ratio sixteen by nine",
            "remaining unit tests pass cleanly",
            "sprint retrospective discussion notes",
            "technical debt cleanup pull request",
        ],
        "val": [
            "ratio between train and validation splits looks balanced",
            "[INFO] Worker isolate finished parsing payload in 2ms",
            "poiuytrewq lkjhgfdsa 998877zz",
        ],
    },
    "d_negated_hypothetical_balance_otp": {
        "train": [
            "đừng ghi nhận khoản chia tiền ăn lẩu 300k này",
            "hủy lệnh chia bill cà phê vừa tạo nhầm nhé",
            "xóa giúp tôi khoản tất toán nợ nhóm vừa nhập sai",
            "nếu chia lương theo tỷ lệ đó thì có ổn không",
            "tổng quỹ nhóm hiện tại đang còn bao nhiêu tiền",
            "tổng số dư các ví cá nhân hiện còn bao nhiêu",
            "kiểm tra số dư còn lại trong tất cả tài khoản ngân hàng",
            "mã otp xác thực chuyển tiền của bạn là 491028",
            "dư nợ thẻ tín dụng hiện tại còn bao nhiêu",
            "tổng nợ vay ngân hàng còn lại mấy triệu vậy",
            "tháng này còn phải đóng mấy kỳ trả góp nữa",
            "hỏi thử lãi suất vay thế chấp hiện giờ bao nhiêu phần trăm",
            "số dư thẻ tín dụng khả dụng còn lại bao nhiêu",
            "đừng ghi khoản trả góp 3 triệu này vào sổ chi tiêu",
            "hủy bút toán trả nợ ngân hàng vừa nhập nhầm",
            "tôi định sang năm mới vay ngân hàng mua xe trả góp",
            "nếu vay thêm 50 triệu trả góp thì có ổn không nhỉ",
            "có nên vay thẻ tín dụng lúc này không",
            "tổng chi phí sinh hoạt gia đình tháng vừa rồi hết bao nhiêu",
            "tổng chi tiêu ăn uống từ đầu tháng đến nay hết bao nhiêu",
            "xem giúp tổng tiền mua sắm tháng này hết bao nhiêu",
            "kiểm tra tổng tiền chi ăn uống tháng vừa rồi hết bao nhiêu",
            "du no the tin dung hien con bao nhieu",
            "dung ghi khoan tra gop nay vao so",
            "neu vay ngan hang tra gop thi co on khong",
            "huy giao dich tra gop the tin dung nhap sai",
        ],
        "val": [
            "không lưu khoản chia tiền nhóm vừa đọc nhầm nhé",
            "có nên áp dụng cách chia quỹ đó cho tháng sau không",
            "mã xác nhận smartotp giao dịch là 827391",
            "dư nợ vay tiêu dùng tháng này còn lại bao nhiêu",
            "đừng ghi khoản thanh toán trả góp 2tr vừa nói vào sổ",
            "nếu vay trả góp mua laptop thì mỗi tháng trả khoảng mấy triệu",
        ],
    },
}


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


def _read_jsonl(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def _write_jsonl_dicts(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")


def build_split_rows(
    rng: random.Random,
    split_name: str,
    wrappers: list[str],
    seen_norms: set[str],
    forbidden_asc: set[str],
    frozen_test_rows: list[dict[str, str]],
    frozen_test_indexed: list[tuple[dict[str, str], str, str, set[str], set[str]]],
) -> tuple[list[tuple[int, str, str]], set[str]]:
    label_to_idx = {lbl: i for i, lbl in enumerate(SPLIT_ALLOC_LABELS)}
    rows: list[tuple[int, str, str]] = []
    split_asc: set[str] = set()
    for lbl in SPLIT_ALLOC_LABELS:
        idx = label_to_idx[lbl]
        for core in CORPUS_POOLS[lbl][split_name]:
            for tpl in wrappers:
                sent = tpl.format(core=core, amt=rng.choice(AMOUNTS))
                for raw_cand in (sent, strip_vn_accents(sent)):
                    norm = normalize_for_classifier(raw_cand)
                    if not norm:
                        continue
                    asc = strip_vn_accents(norm)
                    if norm in seen_norms or asc in forbidden_asc:
                        continue
                    if find_near_duplicates(
                        [{"normalized_text": norm}],
                        frozen_test_rows,
                        token_jaccard_thresh=0.78,
                        char4_jaccard_thresh=0.80,
                        preindexed_targets=frozen_test_indexed,
                    ):
                        continue
                    seen_norms.add(norm)
                    split_asc.add(asc)
                    rows.append((idx, raw_cand, norm))
    return rows, split_asc


def load_ood_entries(split_name: str) -> list[tuple[str, str]]:
    path = DATASETS_DIR / f"ood_money_split_{split_name}.jsonl"
    out: list[tuple[str, str]] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            obj = json.loads(line)
            norm = obj.get("normalized_text") or obj.get("normalized") or ""
            stratum = obj.get("stratum") or "unknown"
            if norm:
                out.append((stratum, norm))
    return out


def load_ood_norms(split_name: str) -> list[str]:
    return [norm for _, norm in load_ood_entries(split_name)]


def predict_probs_q(
    norm: str,
    q_a_dequant: list[list[float]],
    logit_gain: float,
    b: list[float],
    temp: float,
    total_classes: int,
) -> list[float]:
    b_ids = extract_feature_buckets(
        norm,
        num_buckets=NUM_BUCKETS,
        word_ngrams=WORD_NGRAMS,
        min_subword=MIN_SUBWORD,
        max_subword=MAX_SUBWORD,
    )
    if not b_ids:
        return [1.0 / total_classes] * total_classes
    scale = logit_gain / len(b_ids)
    h = [0.0] * total_classes
    for b_id in b_ids:
        r = q_a_dequant[b_id]
        for c in range(total_classes):
            h[c] += r[c]
    logits = [b[c] + scale * h[c] for c in range(total_classes)]
    return softmax_probs(logits, temp=temp)


def is_ood_decision(
    probs: list[float],
    ood_idx: int,
    ood_reject_threshold: float,
    low_conf_threshold: float,
) -> bool:
    pred_y = max(range(len(probs)), key=lambda c: probs[c])
    ood_prob = probs[ood_idx]
    best_id_prob = max(probs[c] for c in range(ood_idx))
    return (
        pred_y == ood_idx
        or ood_prob >= ood_reject_threshold
        or best_id_prob < low_conf_threshold
    )


def evaluate_ood_rejection(
    ood_norms: list[str],
    q_a_dequant: list[list[float]],
    logit_gain: float,
    b: list[float],
    temp: float,
    ood_reject_threshold: float,
    low_conf_threshold: float,
) -> float:
    if not ood_norms:
        return 1.0
    total_classes = len(SPLIT_ALLOC_ALL_LABELS)
    ood_idx = total_classes - 1
    rejected = 0
    for norm in ood_norms:
        probs = predict_probs_q(norm, q_a_dequant, logit_gain, b, temp, total_classes)
        if is_ood_decision(probs, ood_idx, ood_reject_threshold, low_conf_threshold):
            rejected += 1
    return rejected / len(ood_norms)


def evaluate_quantized(
    rows: list[tuple[int, str, str]],
    q_a_dequant: list[list[float]],
    logit_gain: float,
    b: list[float],
    temp: float,
    ood_reject_threshold: float,
    low_conf_threshold: float,
    high_conf_threshold: float,
) -> tuple[float, float, float, float, float]:
    in_k = len(SPLIT_ALLOC_LABELS)
    total_classes = len(SPLIT_ALLOC_ALL_LABELS)
    ood_idx = total_classes - 1
    tp = [0] * in_k
    fp = [0] * in_k
    fn = [0] * in_k
    confs: list[float] = []
    accs: list[int] = []
    false_high = 0
    false_ood = 0

    for true_y, _, norm in rows:
        probs = predict_probs_q(norm, q_a_dequant, logit_gain, b, temp, total_classes)
        pred_y = max(range(total_classes), key=lambda c: probs[c])
        rejected = is_ood_decision(probs, ood_idx, ood_reject_threshold, low_conf_threshold)
        top_p = probs[pred_y]
        ok = 1 if (not rejected and pred_y == true_y) else 0
        confs.append(top_p)
        accs.append(ok)
        if rejected:
            false_ood += 1
            fn[true_y] += 1
        else:
            if top_p >= high_conf_threshold and pred_y != true_y:
                false_high += 1
            if pred_y == true_y:
                tp[true_y] += 1
            else:
                fp[pred_y] += 1
                fn[true_y] += 1

    f1s: list[float] = []
    for c in range(in_k):
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

    return sum(accs) / n, sum(f1s) / in_k, ece, false_high / n, false_ood / n


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
    ood_norms: list[str],
    q_a_dequant: list[list[float]],
    logit_gain: float,
    b: list[float],
    temp: float,
    ood_reject_threshold: float,
    low_conf_threshold: float,
) -> dict[str, object]:
    total_classes = len(SPLIT_ALLOC_ALL_LABELS)
    ood_idx = total_classes - 1
    conf_mat = [[0] * total_classes for _ in range(total_classes)]

    for true_y, _, norm in rows:
        probs = predict_probs_q(norm, q_a_dequant, logit_gain, b, temp, total_classes)
        rejected = is_ood_decision(probs, ood_idx, ood_reject_threshold, low_conf_threshold)
        pred_y = ood_idx if rejected else max(range(ood_idx), key=lambda c: probs[c])
        conf_mat[true_y][pred_y] += 1

    for norm in ood_norms:
        probs = predict_probs_q(norm, q_a_dequant, logit_gain, b, temp, total_classes)
        rejected = is_ood_decision(probs, ood_idx, ood_reject_threshold, low_conf_threshold)
        pred_y = ood_idx if rejected else max(range(ood_idx), key=lambda c: probs[c])
        conf_mat[ood_idx][pred_y] += 1

    per_class = {}
    for c, lbl in enumerate(SPLIT_ALLOC_ALL_LABELS):
        tp = conf_mat[c][c]
        fp = sum(conf_mat[r][c] for r in range(total_classes) if r != c)
        fn = sum(conf_mat[c][col] for col in range(total_classes) if col != c)
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
        "labels": SPLIT_ALLOC_ALL_LABELS,
        "confusionMatrix": conf_mat,
        "perClass": per_class,
    }


def pack_lftq_binary(
    labels: list[str],
    A: list[list[float]],
    logit_gain: float,
    b: list[float],
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
    parts.append(struct.pack(f"<{k}f", *b))
    return b"".join(parts)


def main() -> None:
    rng = random.Random(20261125)
    ART_DIR.mkdir(parents=True, exist_ok=True)
    DATASETS_DIR.mkdir(parents=True, exist_ok=True)
    FLUTTER_MODELS_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Verify & load FROZEN held-out test sets (NEVER overwrite or modify these files!)
    ms_test_path = DATASETS_DIR / "money_split_test.jsonl"
    ms_ood_test_path = DATASETS_DIR / "ood_money_split_test.jsonl"
    actual_ms_sha = hashlib.sha256(ms_test_path.read_bytes()).hexdigest()
    actual_ms_ood_sha = hashlib.sha256(ms_ood_test_path.read_bytes()).hexdigest()
    if actual_ms_sha != FROZEN_MS_TEST_SHA256:
        raise RuntimeError(
            f"Frozen money_split_test.jsonl SHA-256 mismatch: {actual_ms_sha} != {FROZEN_MS_TEST_SHA256}"
        )
    if actual_ms_ood_sha != FROZEN_MS_OOD_TEST_SHA256:
        raise RuntimeError(
            f"Frozen ood_money_split_test.jsonl SHA-256 mismatch: {actual_ms_ood_sha} != {FROZEN_MS_OOD_TEST_SHA256}"
        )

    label_to_idx = {lbl: i for i, lbl in enumerate(SPLIT_ALLOC_LABELS)}
    test_raw_objs = _read_jsonl(ms_test_path)
    ood_test_objs = _read_jsonl(ms_ood_test_path)
    test_rows: list[tuple[int, str, str]] = [
        (label_to_idx[obj["label"]], str(obj.get("text") or ""), str(obj["normalized"]))
        for obj in test_raw_objs
    ]
    frozen_test_rows = test_raw_objs + ood_test_objs
    frozen_test_indexed = index_target_rows(frozen_test_rows)

    # Pre-seed seen_norms / seen_asc with ALL frozen test rows & base OOD rows so zero leakage can occur
    base_ood_tr = [
        r for r in _read_jsonl(DATASETS_DIR / "ood_money_split_train.jsonl")
        if not str(r.get("template_id", "")).startswith("aug_ms_")
    ]
    base_ood_va = [
        r for r in _read_jsonl(DATASETS_DIR / "ood_money_split_val.jsonl")
        if not str(r.get("template_id", "")).startswith("aug_ms_")
    ]

    forbidden_id_norms: set[str] = {
        str(r.get("normalized_text") or r.get("normalized") or "").strip()
        for r in frozen_test_rows + base_ood_tr + base_ood_va
        if (r.get("normalized_text") or r.get("normalized"))
    }
    forbidden_id_asc: set[str] = {strip_vn_accents(n) for n in forbidden_id_norms}

    seen_id_norms: set[str] = set(forbidden_id_norms)
    forbidden_id_for_train_asc: set[str] = set(forbidden_id_asc)

    train_rows, train_id_asc = build_split_rows(
        rng, "train", TRAIN_WRAPPERS, seen_id_norms, forbidden_id_for_train_asc, frozen_test_rows, frozen_test_indexed
    )
    val_rows, _ = build_split_rows(
        rng, "val", VAL_WRAPPERS, seen_id_norms, forbidden_id_for_train_asc | train_id_asc, frozen_test_rows, frozen_test_indexed
    )

    export_jsonl(DATASETS_DIR / "money_split_train.jsonl", "train", train_rows)
    export_jsonl(DATASETS_DIR / "money_split_val.jsonl", "val", val_rows)

    # 2. Idempotently augment OOD train/val (NEVER touching ood_money_split_test.jsonl!)
    all_id_norms: set[str] = (
        {norm for _, _, norm in train_rows + val_rows + test_rows}
    )
    all_id_asc: set[str] = {strip_vn_accents(n) for n in all_id_norms}
    seen_ood_norms: set[str] = {
        str(r.get("normalized_text") or "").strip()
        for r in base_ood_tr + base_ood_va + ood_test_objs
        if r.get("normalized_text")
    }
    forbidden_ood_asc: set[str] = {
        strip_vn_accents(str(r.get("normalized_text") or "").strip())
        for r in ood_test_objs
        if r.get("normalized_text")
    }

    aug_ood_by_split: dict[str, list[dict[str, str]]] = {"train": [], "val": []}
    ood_split_asc: dict[str, set[str]] = {"train": set(), "val": set()}
    for stratum, splits in AUG_MS_OOD_POOLS.items():
        for split in ("train", "val"):
            other_split_asc = ood_split_asc["train"] if split == "val" else set()
            for idx_p, phrase in enumerate(splits[split]):
                variants = [(f"aug_ms_{split}_{stratum[:5]}_acc", phrase, "aug_accented")]
                noacc = strip_vn_accents(phrase)
                if noacc != phrase:
                    variants.append((f"aug_ms_{split}_{stratum[:5]}_noacc", noacc, "aug_unaccented"))
                for tid, raw_txt, style in variants:
                    norm = normalize_for_classifier(raw_txt)
                    if len(norm) < 2:
                        continue
                    asc = strip_vn_accents(norm)
                    if (
                        norm in seen_ood_norms
                        or asc in forbidden_ood_asc
                        or asc in other_split_asc
                        or norm in all_id_norms
                        or asc in all_id_asc
                    ):
                        continue
                    cand_obj = {
                        "split": split,
                        "stratum": stratum,
                        "label": OOD_LABEL,
                        "template_id": f"{tid}_{idx_p}",
                        "raw_text": raw_txt,
                        "normalized_text": norm,
                        "style": style,
                    }
                    if find_near_duplicates(
                        [cand_obj],
                        frozen_test_rows,
                        token_jaccard_thresh=0.78,
                        char4_jaccard_thresh=0.80,
                        preindexed_targets=frozen_test_indexed,
                    ):
                        continue
                    seen_ood_norms.add(norm)
                    ood_split_asc[split].add(asc)
                    aug_ood_by_split[split].append(cand_obj)

    # Also draw verified-disjoint single-person debt/bank/salary examples from financial train.jsonl
    # so e_single_person_near_ood contrasts cleanly against alloc.debt_payoff & alloc.rule_50_30_20.
    fin_train_path = DATASETS_DIR / "train.jsonl"
    if fin_train_path.exists():
        fin_rows = [
            r for r in _read_jsonl(fin_train_path)
            if not str(r.get("template_id", "")).startswith("aug_")
        ]
        fin_rows.sort(key=lambda r: str(r.get("normalized_text") or ""))
        random.Random(20261125).shuffle(fin_rows)
        split_guard = (
            "chia", "nhom", "phan bo", "phan tram", "ty le", "50 30 20",
            "6 lo", "6 hu", "ung ho", "cua doi", "campuchia", "minh tru",
            "momo", "cong ty chuyen khoan", "anh trai", "nguoi quen", "muon ban",
            "hoan tra", "dong nghiep", "ung truoc", "hoa don",
        )
        added_fin = 0
        added_debt = 0
        added_sal = 0
        for f_idx, frow in enumerate(fin_rows):
            if added_fin >= 44:
                break
            lbl_f = frow.get("label")
            if lbl_f == "debt.interest":
                if added_debt >= 32:
                    continue
            elif lbl_f == "income.salary":
                if added_sal >= 12:
                    continue
            else:
                continue
            raw_txt = str(frow.get("raw_text") or "").strip()
            norm = normalize_for_classifier(raw_txt)
            if len(norm) < 4:
                continue
            asc = strip_vn_accents(norm)
            if any(tok in asc for tok in split_guard):
                continue
            if (
                norm in seen_ood_norms
                or asc in forbidden_ood_asc
                or asc in ood_split_asc["val"]
                or norm in all_id_norms
                or asc in all_id_asc
            ):
                continue
            cand_obj = {
                "split": "train",
                "stratum": "e_single_person_near_ood",
                "label": OOD_LABEL,
                "template_id": f"aug_ms_fin_nearood_{f_idx}",
                "raw_text": raw_txt,
                "normalized_text": norm,
                "style": str(frow.get("style") or "single_person_tx"),
            }
            if find_near_duplicates(
                [cand_obj],
                frozen_test_rows,
                token_jaccard_thresh=0.75,
                char4_jaccard_thresh=0.78,
                preindexed_targets=frozen_test_indexed,
            ):
                continue
            seen_ood_norms.add(norm)
            ood_split_asc["train"].add(asc)
            aug_ood_by_split["train"].append(cand_obj)
            added_fin += 1
            if lbl_f == "debt.interest":
                added_debt += 1
            else:
                added_sal += 1

    final_ood_tr = base_ood_tr + aug_ood_by_split["train"]
    final_ood_va = base_ood_va + aug_ood_by_split["val"]
    _write_jsonl_dicts(DATASETS_DIR / "ood_money_split_train.jsonl", final_ood_tr)
    _write_jsonl_dicts(DATASETS_DIR / "ood_money_split_val.jsonl", final_ood_va)

    # Anti-leakage verification against frozen test sets
    tr_va_id_norms = {norm for _, _, norm in train_rows + val_rows}
    te_id_norms = {norm for _, _, norm in test_rows}
    te_ood_norms = {str(r.get("normalized_text") or "").strip() for r in ood_test_objs}
    tr_va_ood_norms = {str(r.get("normalized_text") or "").strip() for r in final_ood_tr + final_ood_va}
    assert tr_va_id_norms.isdisjoint(te_id_norms)
    assert tr_va_id_norms.isdisjoint(te_ood_norms)
    assert tr_va_ood_norms.isdisjoint(te_ood_norms)
    assert tr_va_ood_norms.isdisjoint(all_id_norms)

    ood_train_entries = load_ood_entries("train")
    ood_val_entries = load_ood_entries("val")
    ood_test_entries = load_ood_entries("test")

    k = len(SPLIT_ALLOC_ALL_LABELS)
    ood_idx = k - 1
    logit_gain = 28.0
    lr = 0.36
    l2 = 6e-6
    l2_bias = 0.015
    epochs = 30
    qat_epochs = 8
    label_smoothing = 0.008

    A = [[0.0] * k for _ in range(NUM_BUCKETS)]
    b = [-0.06] * k
    b[ood_idx] = 0.82
    gA = [[1e-2] * k for _ in range(NUM_BUCKETS)]
    gb = [1e-2] * k

    # (y, scale_factor, bucket_counts, weight, skip_thresh, is_zero)
    compiled: list[tuple[int, float, list[tuple[int, int]], float, float, bool]] = []

    def compile_sample(
        y: int,
        buckets: list[int],
        weight: float,
        skip_thresh: float,
        is_zero: bool = False,
    ) -> None:
        if not buckets:
            compiled.append((y, 0.0, [], weight, skip_thresh, True))
            return
        cnts: dict[int, int] = {}
        for b_id in buckets:
            cnts[b_id] = cnts.get(b_id, 0) + 1
        compiled.append((y, logit_gain / len(buckets), list(cnts.items()), weight, skip_thresh, is_zero))

    id_class_counts: dict[int, int] = {}
    for y, _, _ in train_rows:
        id_class_counts[y] = id_class_counts.get(y, 0) + 1
    sorted_id_counts = sorted(id_class_counts.values())
    median_id_cnt = sorted_id_counts[len(sorted_id_counts) // 2] if sorted_id_counts else 220

    id_bucket_set: set[int] = set()
    preamble_fillers = (
        "giúp tôi",
        "xem giúp",
    )
    for row_idx, (y, _, norm) in enumerate(train_rows):
        b_ids = extract_feature_buckets(
            norm,
            num_buckets=NUM_BUCKETS,
            word_ngrams=WORD_NGRAMS,
            min_subword=MIN_SUBWORD,
            max_subword=MAX_SUBWORD,
        )
        if b_ids:
            id_bucket_set.update(b_ids)
            c_cnt = max(id_class_counts.get(y, median_id_cnt), 1)
            bal = min(1.06, max(0.95, (median_id_cnt / c_cnt) ** 0.18))
            is_alloc = SPLIT_ALLOC_LABELS[y].startswith("alloc.")
            if is_alloc:
                compile_sample(y, b_ids, 1.55 * bal, 0.996)
                if len(b_ids) >= 16:
                    compile_sample(y, rng.sample(b_ids, k=max(10, (len(b_ids) * 4) // 5)), 0.68 * bal, 0.994)
            else:
                compile_sample(y, b_ids, 1.52 * bal, 0.996)
                if len(b_ids) >= 16:
                    compile_sample(y, rng.sample(b_ids, k=max(9, (len(b_ids) * 3) // 4)), 0.78 * bal, 0.994)
                toks = norm.split(" ")
                if len(toks) >= 7:
                    trimmed_norm = " ".join(toks[1:])
                    t_bkts = extract_feature_buckets(
                        trimmed_norm,
                        num_buckets=NUM_BUCKETS,
                        word_ngrams=WORD_NGRAMS,
                        min_subword=MIN_SUBWORD,
                        max_subword=MAX_SUBWORD,
                    )
                    if t_bkts:
                        id_bucket_set.update(t_bkts)
                        compile_sample(y, t_bkts, 0.55 * bal, 0.992)
            if row_idx % 4 == 0:
                filler = preamble_fillers[row_idx % len(preamble_fillers)]
                aug_norm = f"{filler} {norm}"
                a_bkts = extract_feature_buckets(
                    aug_norm,
                    num_buckets=NUM_BUCKETS,
                    word_ngrams=WORD_NGRAMS,
                    min_subword=MIN_SUBWORD,
                    max_subword=MAX_SUBWORD,
                )
                if a_bkts:
                    id_bucket_set.update(a_bkts)
                    compile_sample(y, a_bkts, 0.50 * bal, 0.993)

    unseen_pool = [b_id for b_id in range(NUM_BUCKETS) if b_id not in id_bucket_set]
    if not unseen_pool:
        unseen_pool = list(range(NUM_BUCKETS))

    for stratum, norm in ood_train_entries:
        b_ids = extract_feature_buckets(
            norm,
            num_buckets=NUM_BUCKETS,
            word_ngrams=WORD_NGRAMS,
            min_subword=MIN_SUBWORD,
            max_subword=MAX_SUBWORD,
        )
        if not b_ids:
            continue
        if stratum == "e_single_person_near_ood":
            compile_sample(ood_idx, b_ids, 0.85, 0.93)
            if len(b_ids) >= 12:
                kept = rng.sample(b_ids, k=max(6, (len(b_ids) * 2) // 3))
                compile_sample(ood_idx, kept, 0.26, 0.89)
        elif stratum == "c_english_gibberish_code_fragments":
            compile_sample(ood_idx, b_ids, 0.72, 0.94)
            if len(b_ids) >= 8:
                kept = rng.sample(b_ids, k=max(4, (len(b_ids) * 2) // 3))
                compile_sample(ood_idx, kept, 0.32, 0.90)
        elif stratum == "d_negated_hypothetical_balance_otp":
            compile_sample(ood_idx, b_ids, 0.66, 0.91)
        else:
            compile_sample(ood_idx, b_ids, 0.60, 0.91)

    for _ in range(120):
        compile_sample(ood_idx, [], 0.44, 0.50, is_zero=True)
    for _ in range(140):
        compile_sample(ood_idx, rng.sample(unseen_pool, k=rng.randint(3, 12)), 0.44, 0.50, is_zero=True)

    smooth_neg = label_smoothing / k
    smooth_pos = (1.0 - label_smoothing) + smooth_neg
    indices = list(range(len(compiled)))

    for ep in range(epochs):
        rng.shuffle(indices)
        cur_lr = lr * (0.18 + 0.82 * 0.5 * (1.0 + math.cos(math.pi * ep / max(epochs - 1, 1))))
        bias_lr = cur_lr * 0.018
        for idx in indices:
            y, scale_factor, bucket_counts, weight, skip_thresh, is_zero = compiled[idx]
            if not bucket_counts:
                logits = list(b)
            else:
                h = [0.0] * k
                for b_id, cnt in bucket_counts:
                    row = A[b_id]
                    for c in range(k):
                        h[c] += row[c] * cnt
                logits = [b[c] + scale_factor * h[c] for c in range(k)]
            probs = softmax_probs(logits)
            if (is_zero or y == ood_idx or ep >= 6) and probs[y] > skip_thresh:
                continue
            grad_z = [
                weight * (probs[c] - (smooth_pos if c == y else smooth_neg))
                for c in range(k)
            ]
            for c in range(k):
                bias_target = 0.84 if c == ood_idx else 0.0
                bg = grad_z[c] + l2_bias * (b[c] - bias_target)
                gb[c] += bg * bg
                b[c] -= (bias_lr / math.sqrt(gb[c])) * bg
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
        bias_lr = qat_lr * 0.018
        for idx in indices:
            y, scale_factor, bucket_counts, weight, skip_thresh, is_zero = compiled[idx]
            if not bucket_counts:
                logits = list(b)
            else:
                h = [0.0] * k
                for b_id, cnt in bucket_counts:
                    qrow = qA[b_id]
                    for c in range(k):
                        h[c] += qrow[c] * cnt
                logits = [b[c] + scale_factor * h[c] for c in range(k)]
            probs = softmax_probs(logits)
            if (is_zero or y == ood_idx or qep >= 0) and probs[y] > skip_thresh:
                continue
            grad_z = [
                weight * (probs[c] - (smooth_pos if c == y else smooth_neg))
                for c in range(k)
            ]
            for c in range(k):
                bias_target = 0.84 if c == ood_idx else 0.0
                bg = grad_z[c] + l2_bias * (b[c] - bias_target)
                gb[c] += bg * bg
                b[c] -= (bias_lr / math.sqrt(gb[c])) * bg
            for b_id, cnt in bucket_counts:
                row = A[b_id]
                grow = gA[b_id]
                mult = scale_factor * cnt
                for c in range(k):
                    g = grad_z[c] * mult + l2 * row[c]
                    grow[c] += g * g
                    row[c] -= (qat_lr / math.sqrt(grow[c])) * g
                qA[b_id] = simulate_int8_row(row)

    ood_rej_th = MONEY_SPLIT_THRESHOLDS["oodReject"]
    low_th = MONEY_SPLIT_THRESHOLDS["lowConfidence"]
    high_th = MONEY_SPLIT_THRESHOLDS["highConfidence"]

    # Joint (temperature, b[__ood__] delta) calibration strictly on disjoint val + ood_val
    base_ftq = pack_lftq_binary(SPLIT_ALLOC_ALL_LABELS, A, logit_gain, b, 1.0)
    cal_reader = QuantizedFastTextReader(base_ftq)

    def precompute_logits(norm: str) -> list[float] | None:
        b_ids = extract_feature_buckets(
            norm,
            num_buckets=NUM_BUCKETS,
            word_ngrams=WORD_NGRAMS,
            min_subword=MIN_SUBWORD,
            max_subword=MAX_SUBWORD,
        )
        if not b_ids:
            return None
        h = [0.0] * k
        for b_id in b_ids:
            sc = cal_reader.scales[b_id]
            if sc == 0.0:
                continue
            base = b_id * k
            for d in range(k):
                h[d] += cal_reader.q_a[base + d] * sc
        inv_len = 1.0 / len(b_ids)
        for d in range(k):
            h[d] *= inv_len
        out_logits: list[float] = []
        for c in range(k):
            w_base = c * k
            s = cal_reader.b[c]
            for d in range(k):
                s += cal_reader.w[w_base + d] * h[d]
            out_logits.append(s)
        return out_logits

    val_id_logits = [(y, precompute_logits(norm)) for y, _, norm in val_rows]
    val_ood_logits = [(stratum, precompute_logits(norm)) for stratum, norm in ood_val_entries]
    uniform_probs = [1.0 / k] * k

    def eval_cal_pair(cand_t: float, delta: float) -> tuple[float, dict[str, float]]:
        conf_mat = [[0] * k for _ in range(k)]
        confs: list[float] = []
        accs: list[int] = []
        false_auto = 0
        false_ood = 0
        ood_rej = 0
        id_ok = 0
        nll_sum = 0.0
        stratum_totals: dict[str, int] = {}
        stratum_rejs: dict[str, int] = {}

        for true_y, raw_l in val_id_logits:
            if raw_l is None:
                probs = uniform_probs
            else:
                adj = list(raw_l)
                adj[ood_idx] += delta
                probs = softmax_probs(adj, temp=cand_t)
            nll_sum -= math.log(max(probs[true_y], 1e-12))
            top_c = max(range(k), key=lambda c: probs[c])
            best_id_c = max(range(ood_idx), key=lambda c: probs[c])
            best_id_p = probs[best_id_c]
            rejected = (
                top_c == ood_idx
                or probs[ood_idx] >= ood_rej_th
                or best_id_p < low_th
            )
            pred_c = ood_idx if rejected else best_id_c
            conf_mat[true_y][pred_c] += 1
            ok = 1 if (not rejected and best_id_c == true_y) else 0
            id_ok += ok
            confs.append(probs[top_c])
            accs.append(ok)
            if rejected:
                false_ood += 1
            elif best_id_p >= high_th and ok == 0:
                false_auto += 1

        for stratum, raw_l in val_ood_logits:
            if raw_l is None:
                probs = uniform_probs
            else:
                adj = list(raw_l)
                adj[ood_idx] += delta
                probs = softmax_probs(adj, temp=cand_t)
            nll_sum -= math.log(max(probs[ood_idx], 1e-12))
            top_c = max(range(k), key=lambda c: probs[c])
            best_id_c = max(range(ood_idx), key=lambda c: probs[c])
            best_id_p = probs[best_id_c]
            rejected = (
                top_c == ood_idx
                or probs[ood_idx] >= ood_rej_th
                or best_id_p < low_th
            )
            conf_mat[ood_idx][ood_idx if rejected else best_id_c] += 1
            confs.append(probs[top_c])
            accs.append(1 if rejected else 0)
            stratum_totals[stratum] = stratum_totals.get(stratum, 0) + 1
            if rejected:
                ood_rej += 1
                stratum_rejs[stratum] = stratum_rejs.get(stratum, 0) + 1
            elif best_id_p >= high_th:
                false_auto += 1

        n_all = max(len(val_id_logits) + len(val_ood_logits), 1)
        val_ece = 0.0
        for b_i in range(10):
            lo, hi = b_i / 10.0, (b_i + 1) / 10.0
            idxs = [i for i, cf in enumerate(confs) if (lo <= cf < hi) or (b_i == 9 and cf == 1.0)]
            if idxs:
                val_ece += (len(idxs) / n_all) * abs(
                    sum(accs[i] for i in idxs) / len(idxs)
                    - sum(confs[i] for i in idxs) / len(idxs)
                )
        f1s: list[float] = []
        for c in range(ood_idx):
            tp = conf_mat[c][c]
            fp = sum(conf_mat[r][c] for r in range(k) if r != c)
            fn = sum(conf_mat[c][col] for col in range(k) if col != c)
            pr = tp / (tp + fp) if (tp + fp) > 0 else 0.0
            rc = tp / (tp + fn) if (tp + fn) > 0 else 0.0
            f1s.append((2 * pr * rc / (pr + rc)) if (pr + rc) > 0 else 0.0)
        val_macro_f1 = sum(f1s) / ood_idx
        val_id_acc = id_ok / max(len(val_id_logits), 1)
        val_ood_rate = ood_rej / max(len(val_ood_logits), 1)
        val_min_stratum_ood = min(
            (stratum_rejs.get(s, 0) / max(tot, 1) for s, tot in stratum_totals.items()),
            default=val_ood_rate,
        )
        val_false_rate = false_auto / n_all
        val_false_ood_rate = false_ood / max(len(val_id_logits), 1)
        val_nll = nll_sum / n_all

        score = (
            0.35 * val_nll
            + 2.0 * val_ece
            + 38.0 * val_false_rate
            + 24.0 * val_false_ood_rate
            + 24.0 * (1.0 - val_id_acc)
            + 12.0 * max(0.0, 0.988 - val_ood_rate)
            + 10.0 * max(0.0, 0.975 - val_min_stratum_ood)
            - 3.5 * val_macro_f1
        )
        return score, {
            "valIdAcc": round(val_id_acc, 4),
            "valMacroF1": round(val_macro_f1, 4),
            "valOodRejection": round(val_ood_rate, 4),
            "valMinStratumOod": round(val_min_stratum_ood, 4),
            "valFalseAuto": round(val_false_rate, 4),
            "valEce": round(val_ece, 4),
            "valNll": round(val_nll, 4),
        }

    best_temp = 1.00
    best_ood_delta = 0.0
    best_score = 1e9
    best_val_stats: dict[str, float] = {}

    for step_t in range(72, 126, 6):
        cand_t = step_t / 100.0
        for step_d in range(-5, 0, 1):
            delta = step_d * 0.10
            sc, st = eval_cal_pair(cand_t, delta)
            if sc < best_score:
                best_score = sc
                best_temp = cand_t
                best_ood_delta = delta
                best_val_stats = st

    t_lo = max(70, int(round((best_temp - 0.04) * 100)))
    t_hi = min(134, int(round((best_temp + 0.04) * 100)))
    d_lo = max(-0.56, round(best_ood_delta - 0.06, 2))
    d_hi = min(-0.08, round(best_ood_delta + 0.06, 2))
    for step_t in range(t_lo, t_hi + 1, 2):
        cand_t = step_t / 100.0
        d = d_lo
        while d <= d_hi + 1e-9:
            sc, st = eval_cal_pair(cand_t, round(d, 4))
            if sc < best_score:
                best_score = sc
                best_temp = cand_t
                best_ood_delta = round(d, 4)
                best_val_stats = st
            d += 0.03

    # Bake best_ood_bias_delta into b[__ood__] before packing into quantized LFTQ binary
    b[ood_idx] += best_ood_delta
    ftq_bytes = pack_lftq_binary(SPLIT_ALLOC_ALL_LABELS, A, logit_gain, b, best_temp)
    sha256_hex = hashlib.sha256(ftq_bytes).hexdigest()

    art_ftq = ART_DIR / "vn_money_split_fasttext_v1.ftq"
    dst_ftq = FLUTTER_MODELS_DIR / "vn_money_split_fasttext_v1.ftq"
    art_ftq.write_bytes(ftq_bytes)
    shutil.copy2(art_ftq, dst_ftq)

    test_id_pairs = [(SPLIT_ALLOC_LABELS[y], norm) for y, _, norm in test_rows]
    final_reader = QuantizedFastTextReader(ftq_bytes)
    test_rep = evaluate_model_on_splits(
        model=final_reader,
        id_rows=test_id_pairs,
        ood_rows=ood_test_entries,
        ood_reject_threshold=ood_rej_th,
        low_conf_threshold=low_th,
        high_conf_threshold=high_th,
    )

    metadata = {
        "modelId": "vn_money_split_fasttext_v1",
        "modelVersion": "2.0.0",
        "architecture": "FastText QAT Subword + Word Bigram + Explicit __ood__ Class (INT8 LFTQ v1)",
        "license": "MIT",
        "language": "vi",
        "assetPath": "assets/models/vn_money_split_fasttext_v1.ftq",
        "sizeBytes": len(ftq_bytes),
        "sha256": sha256_hex,
        "numClasses": len(SPLIT_ALLOC_LABELS),
        "totalOutputClasses": k,
        "hasExplicitOodClass": True,
        "oodLabel": OOD_LABEL,
        "labels": SPLIT_ALLOC_ALL_LABELS,
        "hyperparameters": {
            "numBuckets": NUM_BUCKETS,
            "dim": k,
            "wordNgrams": WORD_NGRAMS,
            "minSubword": MIN_SUBWORD,
            "maxSubword": MAX_SUBWORD,
            "logitGain": logit_gain,
            "epochs": epochs,
            "qatEpochs": qat_epochs,
            "oodBiasDelta": best_ood_delta,
        },
        "calibratedTemperature": round(best_temp, 4),
        "thresholds": MONEY_SPLIT_THRESHOLDS,
        "metrics": {
            "trainSamples": len(train_rows),
            "valSamples": len(val_rows),
            "heldOutTestSamples": test_rep["test_samples"],
            "heldOutOodTestSamples": test_rep["ood_test_samples"],
            "testAccuracy": test_rep["accuracy"],
            "testMacroF1": test_rep["macro_f1"],
            "expectedCalibrationError": test_rep["ece"],
            "falseAutoAssignmentRate": test_rep["false_auto_assignment_rate"],
            "inDomainFalseOodRejectionRate": test_rep["in_domain_false_ood_rejection_rate"],
            "oodUnknownRejectionRate": test_rep["ood_unknown_rejection_rate"],
            "oodAuroc": test_rep["ood_auroc"],
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
                "oodBiasDelta": best_ood_delta,
                "valCalibration": best_val_stats,
                **test_rep,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    print(
        f"[MONEY SPLIT AI v2.0 + OOD] Size={len(ftq_bytes):,}B | SHA256={sha256_hex}\n"
        f"Train={len(train_rows)} (+{len(ood_train_entries)} OOD) | Val={len(val_rows)} (+{len(ood_val_entries)} OOD) | "
        f"Test={test_rep['test_samples']} (+{test_rep['ood_test_samples']} OOD) | Temp={best_temp:.2f} | "
        f"delta={best_ood_delta:+.2f} | b[__ood__]={b[ood_idx]:.3f} | val_cal={best_val_stats}\n"
        f"Test Accuracy={float(test_rep['accuracy']):.4f} | Macro F1={float(test_rep['macro_f1']):.4f} | ECE={float(test_rep['ece']):.4f} | "
        f"False Auto-Assign={float(test_rep['false_auto_assignment_rate']):.4f} | "
        f"ID->OOD={float(test_rep['in_domain_false_ood_rejection_rate']):.4f} | "
        f"OOD Rejection={float(test_rep['ood_unknown_rejection_rate']):.2%} | AUROC={float(test_rep['ood_auroc']):.4f}"
    )


if __name__ == "__main__":
    main()
