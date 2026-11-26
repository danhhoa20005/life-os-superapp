"""Augments ONLY train and val splits for Financial AI (ID + OOD) while keeping all test splits frozen.

Strict Anti-Leakage Guarantees:
- NEVER modifies test.jsonl, ood_financial_test.jsonl, money_split_test.jsonl, ood_money_split_test.jsonl, or hard_v2_test.jsonl.
- Strips any prior `aug_*` rows before regenerating so runs are deterministic and idempotent.
- Enforces 0% exact normalized, 0% ASCII-folded exact, and 0% near-duplicate (token Jaccard >= 0.78 / char 4-gram Jaccard >= 0.80)
  leakage against ALL held-out test files (test.jsonl, ood_financial_test.jsonl, hard_v2_test.jsonl).
- Enforces 0% train <-> val overlap and 0% ID <-> OOD cross-contamination.
"""

from __future__ import annotations

import json
import random
from collections import Counter
from pathlib import Path

from audit_leakage import find_near_duplicates, index_target_rows
from feature_spec import (
    OOD_LABEL,
    SEMANTIC_LABELS,
    normalize_for_classifier,
    strip_vn_accents,
)

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "datasets"

# Augmented ID phrase pools (disjoint from original train/val/test & hard_v2_test)
AUG_ID_POOLS: dict[str, dict[str, list[str]]] = {
    "housing.housework": {
        "train": [
            "thuê giúp việc nhà theo giờ cuối tuần",
            "dịch vụ dọn dẹp căn hộ btaskee",
            "đặt lịch lau dọn nhà cửa theo giờ",
            "vệ sinh máy lạnh treo tường phòng khách",
            "rửa cục nóng cục lạnh điều hòa tại nhà",
            "bảo trì vệ sinh máy giặt lồng ngang",
            "giặt hấp sofa thảm phòng khách tại nhà",
            "giặt sấy quần áo chăn mền tiệm giặt là",
            "mua nước giặt đậm đặc omo cửa trước",
            "mua bột giặt tide túi lớn gia đình",
            "mua nước xả vải downy hương nắng mai",
            "mua nước rửa chén lix siêu sạch chanh",
            "mua chai nước lau sàn sunlight tinh dầu",
            "mua nước lau kính xịt cửa sổ trong nhà",
            "mua dung dịch tẩy rửa nhà tắm gift",
            "mua viên tẩy bồn cầu diệt khuẩn hương chanh",
            "mua cuộn giấy ăn lụa hộp rút phòng khách",
            "mua lốc giấy vệ sinh không lõi mềm mịn",
            "mua bịch túi đựng rác có dây rút tiện lợi",
            "mua cây chổi quét nhà kèm ky hốt rác",
            "mua bộ lau nhà xoay tay vắt nước thông minh",
            "mua miếng bọt biển cọ rửa bát đĩa xoong nồi",
            "mua găng tay cao su rửa bát dọn bếp",
            "thông tắc bồn rửa chén bị nghẹt ống thoát",
            "thợ sửa vòi nước bồn rửa mặt bị rỉ",
            "thay vòi xịt vệ sinh và dây cấp nước",
            "thay bóng đèn tuýp led chiếu sáng nhà bếp",
            "đóng tiền phí đổ rác khu dân cư cuối tháng",
            "tiền thuê người dọn dẹp sau chuyển nhà",
            "mua móc phơi quần áo inox chống gỉ",
            "mua viên khử mùi tủ lạnh và tủ quần áo",
            "dịch vụ phun thuốc diệt muỗi côn trùng trong nhà",
            "giup viec don nha theo gio cuoi tuan",
            "ve sinh dieu hoa treo tuong phong ngu",
            "mua nuoc lau san dung dich tay rua nha tam",
            "thue tho thong tac cong nha ve sinh",
            "giat ui quan ao chan men ngoai tiem",
            "mua giay an tui rac do dung don dep nha",
            "vs may giat lồng đứng tại nhà",
            "thue nguoi giup viec don phong tro",
            "mua nuoc giat surf hoa co 3 tui",
            "sua voi sen nha tam bi ri nuoc",
            "thay bóng đèn hành lang cầu thang bị hỏng",
            "lắp bóng đèn led chiếu sáng ban công phòng ngủ",
            "sửa mái che ban công sân thượng bị dột mưa",
            "lau dọn vệ sinh khu vực ban công và hành lang nhà",
            "mua vật tư sửa chữa đồ điện nước bóng đèn trong nhà",
            "mua dụng cụ vệ sinh lau chùi phòng bếp nhà tắm",
        ],
        "val": [
            "đặt dịch vụ giúp việc dọn dẹp btaskee sáng nay",
            "vệ sinh điều hòa âm trần văn phòng tại nhà",
            "mua nước giặt tide và nước xả vải downy",
            "mua chổi quét nhà và thùng đựng rác có nắp",
            "thợ sửa ống thoát nước bồn rửa mặt nhà tắm",
            "giặt là hấp áo vest chăn ga ngoài tiệm",
            "mua hộp khăn giấy rút và túi rác tự phân hủy",
            "thay bóng đèn điện hành lang ban công bị cháy",
        ],
    },
    "housing.utilities": {
        "train": [
            "đóng hóa đơn tiền điện sinh hoạt t10",
            "thanh toán tiền điện hàng tháng qua app ngân hàng",
            "trả tiền điện lực evn kỳ này",
            "tiền điện tháng mười hai hộ gia đình",
            "công ty cấp nước gửi hóa đơn tiền nước tháng",
            "đóng tiền nước máy chung cư tháng mới",
            "thanh toán cước nước sinh hoạt sawaco kỳ này",
            "gia hạn gói internet cáp quang fpt sáu tháng",
            "đóng cước wifi internet fpt hàng tháng",
            "thanh toán cước truyền hình và mạng fpt",
            "đóng tiền mạng viễn thông vnpt gia đình",
            "trả cước internet cáp quang viettel tại nhà",
            "đóng cước điện thoại trả sau viettel tháng này",
            "nạp tiền điện thoại trả trước viettel",
            "nạp thẻ cào điện thoại mobifone qua ví",
            "đăng ký gói data 4g vinaphone dùng cả tháng",
            "mua gói cước 5g tốc độ cao mobifone",
            "gia hạn gói cước di động sim data hằng tháng",
            "đổi bình gas an toàn saigon petro nấu ăn",
            "gọi đại lý giao bình gas petrolimex tận nhà",
            "tiền điện nước wifi phòng trọ tháng này",
            "chia sẻ tiền điện nước internet tháng vừa rồi",
            "đóng tiền truyền hình cáp k cộng hàng tháng",
            "tien dien thang nay qua app ngan hang",
            "dong tien nuoc sinh hoat chung cu",
            "cuoc wifi mang cap quang fpt thang",
            "nap the dien thoai tra truoc viettel",
            "gia han goi data 4g mobifone thang",
            "hoa don dien luc evn ky thanh toan",
            "doi binh ga nau an saigon petro",
            "tien dien t10 t12 phong tro sinh vien",
            "cuoc vien thong di dong tra sau vinaphone",
        ],
        "val": [
            "thanh toán hóa đơn điện lực evn tháng mười hai",
            "đóng tiền cấp nước sinh hoạt định kỳ",
            "gia hạn hợp đồng cáp quang internet vnpt",
            "nạp tiền gia hạn gói 4g tốc độ cao viettel",
            "đổi bình ga saigon petro cho bếp gia đình",
            "trả tiền điện nước mạng wifi chung cư",
            "nạp thẻ cào điện thoại vinaphone trả trước",
        ],
    },
    "health.hospital": {
        "train": [
            "đi khám răng định kỳ ở phòng khám nha khoa",
            "nha khoa lấy cao răng và kiểm tra sâu răng",
            "chữa tủy răng hàm và bọc răng sứ thẩm mỹ",
            "đóng tiền niềng răng định kỳ hàng tháng",
            "đi nhổ răng sữa cho bé tại phòng khám nha",
            "khám tổng quát sức khỏe định kỳ bệnh viện đa khoa",
            "đóng viện phí xét nghiệm tổng quát bệnh viện",
            "khám chuyên khoa nội tiết phòng khám tư",
            "khám da liễu soi da điều trị dị ứng",
            "khám tai mũi họng nội soi vòm họng bác sĩ",
            "khám nhi cho bé tại bệnh viện nhi đồng",
            "siêu âm thai và khám định kỳ bệnh viện từ dũ",
            "xét nghiệm công thức máu tổng quát tại diag",
            "chụp phim x quang cột sống tại bệnh viện",
            "tiêm vắc xin phòng cúm mùa trung tâm vnvc",
            "tiêm mũi nhắc vắc xin viêm gan b tại vnvc",
            "khám mắt kiểm tra thị lực tại bệnh viện mắt",
            "đo độ cận và thay tròng kính chống ánh sáng xanh",
            "cắt gọng kính cận mới tại cửa hàng kính mắt",
            "đóng phí hội viên phòng tập thể hình citigym",
            "gia hạn gói tập gym tập tạ hàng tháng",
            "đóng học phí lớp tập yoga trị liệu hàng tuần",
            "mua thẻ bơi tháng rèn luyện thể lực sức khỏe",
            "tập vật lý trị liệu phục hồi chức năng vai gáy",
            "khám sức khỏe tổng quát gói vip vinmec",
            "kham tong quat dinh ky phong kham tu nhan",
            "nho rang sau lay cao rang nha khoa",
            "do do can cat trong kinh mat moi",
            "xet nghiem mau sieu am o bung medlatec",
            "tiem phong vac xin cum mua vnvc",
            "dong the tap gym yoga thang nay",
            "vien phi kham chuyen khoa benh vien da khoa",
            "kham sk dinh ky tai benh vien",
        ],
        "val": [
            "đi lấy cao răng và trám răng ở nha khoa",
            "khám sức khỏe tổng quát bệnh viện đại học y",
            "làm xét nghiệm máu định kỳ tại phòng khám diag",
            "đo độ cận và cắt tròng kính mắt mới",
            "tiêm vắc xin phòng bệnh tại trung tâm vnvc",
            "đóng thẻ hội viên tập gym và bơi lội tháng",
            "nộp viện phí nội soi dạ dày tại bệnh viện",
        ],
    },
    "education": {
        "train": [
            "đóng học phí kỳ mới trường đại học",
            "nộp tiền học phí tín chỉ học kỳ hai",
            "đóng tiền học thêm toán văn anh buổi tối",
            "trả học phí thuê gia sư dạy kèm tại nhà",
            "đăng ký khóa học tiếng anh giao tiếp trung tâm",
            "đóng tiền khóa luyện thi chứng chỉ ielts cấp tốc",
            "đóng lệ phí đăng ký dự thi chứng chỉ toeic",
            "mua khóa học lập trình backend trên udemy",
            "gia hạn gói học chứng chỉ phân tích dữ liệu coursera",
            "gia hạn ứng dụng luyện phát âm tiếng anh elsa",
            "đóng phí tài khoản học ngoại ngữ duolingo theo năm",
            "mua bộ sách giáo khoa và sách tham khảo lớp mới",
            "mua sách phát triển bản thân tại nhà sách fahasa",
            "đặt mua sách ngoại văn tiểu thuyết trên tiki",
            "mua sách chuyên môn lập trình tại nhã nam",
            "mua giáo trình ôn thi chứng chỉ hành nghề",
            "mua từ điển anh việt và sách luyện ngữ pháp",
            "mua vở kẻ ngang tập giấy a4 và bút bi",
            "mua đồ dùng văn phòng phẩm học tập đầu năm học",
            "tiền in ấn đóng cuốn tài liệu bài giảng môn học",
            "photo tài liệu giáo trình ôn tập kỳ thi cuối kỳ",
            "đóng tiền học lớp tiếng trung giao tiếp hsk",
            "đăng ký khóa luyện thi tiếng nhật jlpt",
            "dong tien hoc phi hoc ky dai hoc",
            "nop le phi thi chung chi ielts toeic",
            "mua sach giao trinh tai nha sach fahasa",
            "dang ky khoa hoc lap trinh thiet ke online",
            "mua vo ghi but bi do dung van phong pham",
            "in an photo tai lieu on thi cuoi ky",
            "dong hp khoa hoc tieng anh giao tiep",
            "dong tien hoc them cho ban than buoi toi",
        ],
        "val": [
            "nộp học phí học kỳ mới đại học chính quy",
            "đăng ký lớp luyện thi chứng chỉ tiếng anh ielts",
            "mua giáo trình đại học và sách kỹ năng ở fahasa",
            "mua sổ tay vở ghi và bút viết văn phòng phẩm",
            "thanh toán khóa học lập trình python trên coursera",
            "tiền in ấn tài liệu ôn tập trước kỳ thi",
            "đóng tiền học lớp tiếng nhật sơ cấp buổi tối",
        ],
    },
    "shopping.general": {
        "train": [
            "thanh toán đơn hàng mua sắm trên shopee",
            "nhận bưu kiện ship cod từ shopee express",
            "đặt mua đồ gia dụng nhỏ trên sàn lazada",
            "chốt đơn mỹ phẩm trên livestream tiktok shop",
            "thanh toán giỏ hàng tiêu dùng trên tiki",
            "mua mỹ phẩm chăm sóc da tại cửa hàng hasaki",
            "mua sữa rửa mặt và kem dưỡng ẩm ở guardian",
            "mua nước tẩy trang và bông tẩy trang watsons",
            "mua kem chống nắng hằng ngày và son dưỡng môi",
            "mua dầu gội đầu dầu xả và sữa tắm gội",
            "mua bàn chải đánh răng và kem đánh răng",
            "mua dao cạo râu lăn khử mùi đồ cá nhân",
            "mua đồ lặt vặt tiêu dùng tại cửa hàng circle k",
            "ghé cửa hàng tiện lợi gs25 mua đồ dùng cá nhân",
            "mua sắm đồ dùng gia đình tại siêu thị aeon mall",
            "sắm đồ tiêu dùng cá nhân ở lotte mart cuối tuần",
            "mua vali kéo du lịch và túi đựng phụ kiện",
            "mua bình giữ nhiệt ly giữ nhiệt cá nhân",
            "mua tinh dầu thơm và nến thơm trang trí phòng",
            "mua ô dù che mưa và áo mưa cá nhân",
            "mua phụ kiện trang trí sinh hoạt cá nhân shopee",
            "mua gương để bàn và hộp đựng mỹ phẩm cá nhân",
            "mua kem duong am sua rua mat hasaki",
            "dat don hang my pham tren tiktok shop",
            "thanh toan don hang ship cod lazada",
            "mua dau goi sua tam kem danh rang",
            "mua do dung ca nhan cua hang tien loi",
            "sam do tieu dung ca nhan sieu thi aeon",
            "don mua sam online san thuong mai dien tu",
        ],
        "val": [
            "nhận đơn hàng mua sắm ship cod từ lazada",
            "mua kem chống nắng và nước tẩy trang ở hasaki",
            "mua dầu gội sữa tắm bàn chải ở siêu thị aeon",
            "ghé cửa hàng circle k mua đồ dùng lặt vặt",
            "thanh toán giỏ hàng mỹ phẩm trên tiktok shop",
            "mua bình giữ nhiệt và đồ cá nhân trên shopee",
            "mua sữa rửa mặt và serum dưỡng da guardian",
        ],
    },
    "food.drinks": {
        "train": [
            "uống ly cà phê sữa đá buổi sáng",
            "gọi ly cà phê đen đá không đường tỉnh táo",
            "uống bạc xỉu nóng thơm ngon buổi sáng",
            "mua ly cà phê muối huế mang đi làm",
            "uống cà phê cốt dừa cộng cà phê",
            "gọi cà phê phin sữa đá highlands coffee",
            "mua trà sen vàng và trà thạch đào highlands",
            "uống trà sữa ô long kem cheese phúc long",
            "đặt trà vải lài và trà đào phúc long",
            "uống trà hạt sen macchiato the coffee house",
            "gọi cà phê americano đá starbucks",
            "uống trà sữa bơ già và cà phê katinat",
            "mua trà ô long nhài sữa phê la",
            "mua trà sữa trân châu đường đen gong cha",
            "đặt ly trà sữa trân châu kem trứng tocotoco",
            "mua kem tươi và trà chanh chanh leo mixue",
            "uống hồng trà kem sữa koi thé buổi chiều",
            "uống cà phê trung nguyên legend buổi sáng",
            "mua ly trà dâu tằm pha lê giải khát",
            "uống trà mãng cầu xiêm mát lạnh buổi trưa",
            "uống nước ép ổi hồng và nước ép dưa hấu",
            "mua ly sinh tố bơ sầu riêng sữa đặc",
            "gọi ly sinh tố xoài chanh dây mát lạnh",
            "mua cốc nước mía ép quất vỉa hè",
            "uống nước dừa xiêm tươi ướp lạnh",
            "mua chai nước khoáng thiên nhiên lavie",
            "mua chai nước tinh khiết aquafina uống dọc đường",
            "mua lốc nước ngọt coca cola giải khát",
            "mua lon nước tăng lực redbull tỉnh táo",
            "uống trà chanh giã tay mát lạnh cùng bạn",
            "gọi cacao sữa đá và matcha latte kem tươi",
            "uong ca phe sua da buoi sang",
            "mua tra sua tran chau duong den",
            "order tra dao cam sa highlands coffee",
            "mua chai nuoc suoi lavie uong giai khat",
            "uong nuoc ep cam sinh to bo buoi chieu",
            "cf sua da bac xiu quan quen",
            "ts phuc long tra sua gong cha",
            "cf sáng cùng đồng nghiệp văn phòng",
            "cà phê sữa đá mang đi cùng bạn đồng nghiệp",
            "cf den da khong duong buoi sang",
            "mua cf sua da dau gio lam",
        ],
        "val": [
            "mua ly trà sen vàng và cà phê sữa highlands",
            "uống trà sữa ô long kem phô mai phúc long",
            "mua hai chai nước khoáng tinh khiết lavie",
            "uống cà phê muối và bạc xỉu đá buổi sáng",
            "gọi sinh tố bơ xoài và nước ép ổi tươi",
            "mua trà đào cam sả the coffee house chiều nay",
            "uống matcha đá xay và trà dâu tằm giải nhiệt",
        ],
    },
    "other": {
        "train": [
            "lệ phí chứng thực sao y bản chính giấy tờ",
            "phí công chứng hợp đồng mua bán tại văn phòng",
            "phí dịch thuật công chứng hồ sơ xin visa",
            "lệ phí cấp đổi căn cước công dân gắn chip",
            "nộp lệ phí làm mới hộ chiếu trực tuyến",
            "lệ phí đổi giấy phép lái xe hạng b2",
            "phí trích lục giấy tờ hộ tịch tại ủy ban",
            "in ấn photocopy hồ sơ giấy tờ hành chính",
            "phí gửi thư bảo đảm bưu phẩm qua bưu điện",
            "gửi chuyển phát nhanh hồ sơ tài liệu vnpost",
            "đánh thêm chìa khóa nhà chìa khóa xe dự phòng",
            "gọi thợ mở khóa sửa ổ khóa cửa phòng bị kẹt",
            "đóng góp quỹ từ thiện ủng hộ đồng bào vùng lũ",
            "quyên góp tiền hỗ trợ chương trình thiện nguyện",
            "đóng tiền quỹ phòng ban công ty hằng tháng",
            "góp tiền quỹ lớp họp mặt cuối năm",
            "tiền tip bồi dưỡng nhân viên giao hàng lắp đặt",
            "khoản chi tiêu vặt phát sinh đột xuất khác",
            "chi phí linh tinh ngoài kế hoạch chưa phân loại",
            "phi cong chung sao y giay to hanh chinh",
            "le phi cap doi can cuoc giay phep lai xe",
            "phi gui buu pham chuyen phat buu dien",
            "quyen gop tu thien ung ho dong bao",
            "đóng tiền quỹ phòng quy lớp cơ quan",
            "chi phí phat sinh khac ngoai du kien",
            "photocopy ho so cong chung giay to ca nhan",
            "nộp tiền phạt vi phạm hành chính giao thông",
            "phí chuyển phát hồ sơ tài liệu chuyển phát nhanh",
            "đóng tiền lệ phí làm thẻ căn cước hộ chiếu mới",
            "tiền đánh rơi mất ví tiền lẻ phát sinh ngoài ý muốn",
            "chi phí bồi dưỡng nhân viên vận chuyển hỗ trợ",
            "phí gửi hành lý ký gửi tủ đồ công cộng",
            "nop phi giay to sao y cong chung hanh chinh",
            "chi phi lat vat phat sinh khac chua phan loai",
            "dong tien phat hanh chinh vi pham giao thong",
        ],
        "val": [
            "nộp phí công chứng hợp đồng và sao y giấy tờ",
            "lệ phí làm lại căn cước và giấy phép lái xe",
            "tiền gửi bưu phẩm tài liệu qua bưu điện",
            "đóng tiền quỹ phòng công ty và quỹ từ thiện",
            "tiền bồi dưỡng tip nhân viên vận chuyển lắp đặt",
            "chi phí đánh chìa khóa dự phòng và photocopy",
        ],
    },
    # Light reinforcement on frequently confused / boundary categories
    "food.groceries": {
        "train": [
            "đi chợ mua rau cải cà chua thịt ba chỉ nấu cơm",
            "mua gạo thơm st25 trứng gà ta ở siêu thị winmart",
            "mua cá thu tươi tôm sú về nấu canh bách hóa xanh",
            "mua thịt bò thăn nấm kim châm và đậu phụ coopmart",
            "sắm trái cây hoa quả tươi cam táo nho ngoài chợ",
            "mua nước mắm dầu ăn hạt nêm gia vị bếp",
            "di cho sang mua thit heo ca tuoi rau cu",
            "sieu thi bach hoa xanh mua thuc pham nau an",
        ],
        "val": [
            "đi chợ đầu mối mua thịt cá rau tươi nấu tối",
            "mua gạo st25 dầu ăn nước mắm ở siêu thị winmart",
        ],
    },
    "shopping.clothes": {
        "train": [
            "mua đôi dép lê đi trong nhà và đôi sandal",
            "mua chân váy xếp ly công sở mặc đi làm",
            "mua áo khoác gió chống nắng và quần tây âu",
            "sắm áo thun cotton và quần short mặc nhà",
            "mua dep le chan vay ao so mi uniqlo",
            "mua bộ đồ thể thao tập cầu lông chạy bộ",
            "mua áo quần tập thể thao cầu lông gym",
            "đặt áo khoác dù chống nắng thời trang nam nữ",
            "mua áo len cardigan và quần jeans ống suông",
            "mua giày sneaker thể thao và tất vớ cotton",
            "dat mua ao khoac gio thoi trang mua dong",
            "mua quan tay ao so mi vay cong so",
        ],
        "val": [
            "mua đôi dép lê và quần short mặc ở nhà",
            "mua chân váy công sở và áo sơ mi trắng",
        ],
    },
    "shopping.electronics": {
        "train": [
            "mua ổ cứng di động ssd sao lưu dữ liệu",
            "mua sợi cáp hdmi nối màn hình máy tính",
            "mua tai nghe chụp tai chống ồn không dây",
            "mua sạc nhanh gan và cáp usb type c anker",
            "mua chuot khong day ban phim co the gioi di dong",
            "mua củ sạc nhanh pd type c iphone chính hãng",
            "mua bàn là bàn ủi hơi nước cầm tay điện máy xanh",
            "mua cu sac nhanh cap sac iphone anker chinh hang",
        ],
        "val": [
            "mua cáp chuyển đổi hdmi và ổ cứng ssd di động",
            "sắm tai nghe bluetooth chống ồn ở điện máy xanh",
        ],
    },
    "health.medicine": {
        "train": [
            "mua thuốc dị ứng thời tiết viêm mũi tại hiệu thuốc",
            "mua chai xịt mũi nước biển sâu nhà thuốc long châu",
            "mua men vi sinh tiêu hóa đường ruột pharmacity",
            "mua thuốc ho siro thảo dược và viên ngậm đau họng",
            "mua thuoc cam cum men tieu hoa nha thuoc an khang",
        ],
        "val": [
            "ghé nhà thuốc long châu mua xịt mũi và thuốc dị ứng",
            "mua men vi sinh và vitamin c ở pharmacity",
        ],
    },
    "transport.maintenance": {
        "train": [
            "đưa ô tô vào gara kiểm tra bảo dưỡng định kỳ",
            "thay dầu nhớt máy lọc nhớt lọc gió xe máy",
            "sửa phanh xe thay má phanh trước tại tiệm sửa xe",
            "kiem tra dinh ky bao duong gara o to xe may",
            "sửa chân chống nghiêng thay bóng đèn pha xi nhan xe máy",
            "thay bóng đèn hậu xi nhan sửa công tắc đề xe máy",
            "sua chan chong thay bong den xi nhan xe may",
        ],
        "val": [
            "đem xe ô tô đi bảo dưỡng kiểm tra định kỳ tại gara",
        ],
    },
    "transport.public": {
        "train": [
            "mua vé tàu điện trên cao tuyến metro đi làm",
            "nạp tiền tài khoản thu phí tự động vetc epass",
            "mua ve xe buyt ve tau dien metro",
            "đặt vé tàu hỏa khứ hồi về quê nghỉ lễ",
            "mua vé tàu hỏa giường nằm đi du lịch",
        ],
        "val": [
            "mua vé tàu điện metro và nạp thẻ cầu đường epass",
        ],
    },
    "income.salary": {
        "train": [
            "công ty chuyển khoản trả lương tháng chính thức",
            "payroll salary chuyển khoản lương nhân viên tháng",
            "nhận lương thực nhận kỳ cuối tháng từ công ty",
        ],
        "val": [
            "nhận chuyển khoản payroll lương tháng chính thức",
        ],
    },
    "income.bonus": {
        "train": [
            "nhận phụ cấp chức vụ và chuyên cần hàng tháng",
            "lĩnh tiền phụ cấp ăn trưa đi lại công ty chuyển khoản",
            "thưởng hiệu suất quý và phụ cấp trách nhiệm",
            "nhan phu cap an trua chuyen can hang thang",
        ],
        "val": [
            "nhận tiền phụ cấp chuyên cần và ăn trưa tháng này",
        ],
    },
    "income.other": {
        "train": [
            "nhận lại tiền đặt cọc thuê phòng trọ cũ",
            "hoàn lại tiền đặt cọc vỏ bình nước tinh khiết",
            "thu hồi tiền cọc dịch vụ sự kiện trước đây",
            "nhan lai tien coc binh nuoc dat coc",
        ],
        "val": [
            "thu hồi lại tiền đặt cọc thuê thiết bị cũ",
        ],
    },
}

AUG_OOD_POOLS: dict[str, dict[str, list[str]]] = {
    "c_english_gibberish_code_fragments": {
        "train": [
            # English everyday & workplace chatter (including financial/food/tech homonym words)
            "good morning everyone have a great productive day",
            "please check the deployment status on staging server",
            "can you send me the updated architecture slide deck",
            "let us schedule a quick coffee chat tomorrow afternoon",
            "sorry i could not join the call earlier today",
            "how is your weekend going with family and friends",
            "remember to update the unit tests before merging",
            "this pull request fixes the layout overflow on small screens",
            "please verify the sha256 checksum after building release",
            "we need to review the quarterly roadmap next monday",
            "could you share your screen during the design walkthrough",
            "lunch meeting is moved from twelve to one pm",
            "the network latency looks much faster after the patch",
            "thank you for your feedback on the interface mockup",
            "check your inbox for the calendar invitation link",
            "order of operations in this parser is deterministic",
            "budget extra time for regression testing before shipping",
            "pay close attention to edge cases in null safety",
            "account synchronization finished without any conflicts",
            "health check endpoint returned status ok in two milliseconds",
            "transferring large binary files over local wifi network",
            "book a conference room on the third floor for demo",
            "water the balcony plants before leaving for work",
            "ticket number four eighty two is ready for verification",
            "do not forget to commit local changes safely",
            "happy new year wishing everybody peace and happiness",
            "congratulations on shipping the new mobile release",
            "weather forecast predicts heavy rain later this evening",
            "let me double check the configuration yaml file",
            "everything looks clean zero analyzer warnings found",
            # Mixed Vietnamese/English tech & office chat
            "ok bro check lại nhánh code mới giúp mình nhé",
            "deploy bản build mới lên server staging bị lỗi rồi",
            "fix xong bug responsive trên màn hình nhỏ chưa bạn",
            "ping nhẹ qua slack khi nào họp daily standup nha",
            "merge pull request xong rồi chạy lại bộ test nhé",
            "app mobile đang sync dữ liệu nền hơi chậm một chút",
            "team backend mới cập nhật schema api v2 lên notion",
            "check log docker container xem tại sao bị restart",
            "push commit lên repository cẩn thận kẻo dính conflict",
            "review giúp mình đoạn parser tiếng việt này với",
            "link thiết kế figma mới mình đã ghim trên nhóm chat",
            "build release apk xong chưa gửi file qua telegram đi",
            "server redis bị timeout kết nối từ sáng tới giờ",
            "chốt lịch sprint planning chiều nay lúc ba giờ nha",
            "test case này chạy pass xanh hết rồi quá đỉnh",
            # URLs, file paths & CLI/code fragments
            "https://github.com/flutter/flutter/issues/12345",
            "https://pub.dev/packages/flutter_bloc/example",
            "http://127.0.0.1:5000/api/v1/status",
            "https://docs.python.org/3/library/pathlib.html",
            "https://firebase.google.com/docs/firestore/security",
            "lib/features/financial_ai/data/inference/fasttext_classifier.dart",
            "tools/financial_ai/evaluate_all_models.py",
            "assets/models/vn_financial_fasttext_v1_meta.json",
            "def normalize_text(raw: str) -> str: return raw.strip()",
            "for idx, row in enumerate(records): total += len(row)",
            "class TransactionState extends Equatable { const TransactionState(); }",
            "final result = items.where((item) => item.isReady).toList();",
            "const sum = numbers.reduce((prev, curr) => prev + curr, 0);",
            "SELECT user_id, email FROM accounts WHERE verified = true;",
            "INSERT INTO audit_logs (action, created_at) VALUES ('login', NOW());",
            "flutter analyze --fatal-infos --fatal-warnings --no-pub",
            "flutter test --no-pub --timeout 60s test/unit/",
            "python -u tools/financial_ai/train.py",
            "git status --short && git diff --stat HEAD",
            "docker compose logs -f --tail=100 api-worker",
            "kubectl describe pod financial-worker-7d9f8b",
            "npm run build && npm run test:coverage",
            "import 'dart:convert'; import 'dart:typed_data';",
            "try { await runTask(); } catch (err) { rethrow; }",
            "curl -H 'Accept: application/json' https://api.service.local/ping",
            # Gibberish, keyboard mashes & alphanumeric random tokens
            "asdfghjkl qwertyuiop zxcvbnm",
            "qazwsx edcrfv tgbyhn ujmikolp",
            "poiuytrewq lkjhgfdsa mnbvcxz",
            "zzzzxxxxccccvvvvbbbbnnnnmmmm",
            "blablabla yadayada foobar bazqux",
            "wibble wobble snickerdoodle flibbertigibbet",
            "lorem ipsum dolor sit amet consectetur",
            "xkcd99 a1b2c3d4 e5f6g7h8",
            "abc123 xyz789 qwe456 asd321",
            "hehehe hahaha hihihi huhuhu",
            "trololol bruh lmao ggwp ezpz",
            "ref_8839201 tx_004912 id_99210",
            "uuid 550e8400 e29b 41d4 a716 446655440000",
            "ver 3.27.0 build 45 arm64 release",
            "sha256 602462570be9b70c138835ebf525ecf1",
            "token xyz981203 bearer abcdef123456",
            # Short 1-4 word non-financial Vietnamese conversational fragments
            "chờ một chút nhé",
            "tới nơi rồi nè",
            "sắp xong việc chưa",
            "hôm nay bận quá đi",
            "để mai rồi tính",
            "nghe cũng hợp lý đấy",
            "thôi đi ngủ sớm nha",
            "chào cả nhà buổi sáng",
            "cảm ơn bạn rất nhiều nhé",
            "nhắn lại sau giúp mình",
            "từ từ làm cho chắc",
            "đang trên đường về nhà",
            "bấm nhầm nút rồi bạn ơi",
            "chưa thấy phản hồi gì",
            "không có vấn đề gì cả",
            "vâng ạ em hiểu rồi",
            "đồng ý chốt thế nhé",
            "alo nghe rõ không vậy",
            "tạm biệt mọi người nha",
            "mệt quá nghỉ ngơi thôi",
            "ok để mình xem lại",
            "hình như chưa đúng lắm",
            "cứ làm tiếp đi bạn",
            "chúc bạn ngủ ngon nhé",
            "gặp lại bạn sau nha",
            "có gì nhắn mình nhé",
            "xong xuôi hết cả rồi",
            "đợi thêm vài phút nữa",
            "trời ơi nóng quá đi",
            "buồn ngủ ríu cả mắt",
            "toilavietnam",
            "khong biet gi het",
            "cho ti nhe ban oi",
            "toi noi chua vay",
            "lam xong chua ban",
            "ok nhe chao ban",
            "chờ lát nha bạn",
            "đợi mình một chút nha",
            "tí nữa nhắn lại nha",
            "nói chuyện tiếp sau nhé",
            "đã về tới nhà chưa vậy",
            "làm việc tiếp đi nha",
            "chờ thêm chút nữa nha",
            "cho mot lat nhe",
            "doi ti minh nhan lai",
            "ve nha nghi ngoi som nha",
            "ngu ngon nha ca nha",
            "toi noi roi ne ban oi",
            "chieu nay troi mua to sap co gio lon",
            "hom nay thoi tiet mat me de chiu qua",
            "phat bieu gop y cuoc hop tong ket cuoi nam",
            "ghi chu cong viec hop giao ban dau tuan",
            "qwerty123 asdf456 zxcv789",
            "xyz99 foo_bar_baz ping_pong",
            "null undefined NaN Infinity",
            "status_code 200 latency 4ms ok",
            "lorem ipsum dolor sit amet",
            "test123 hello world foo bar",
            "check env PATH PYTHONPATH LANG",
            "json parse error unexpected token",
            "branch merge rebase cherry pick",
            "buoi sang tot lanh chao moi nguoi",
            "cam on nhieu hen gap lai sau nha",
            "chuc cuoi tuan vui ve hanh phuc",
        ],
        "val": [
            "please attach the release notes to the pull request",
            "could you verify if the staging database migration succeeded",
            "happy friday wishing everyone a restful weekend ahead",
            "check your email for the updated zoom meeting link",
            "order of fields in json payload does not matter",
            "budget extra margin for network retries in client code",
            "check giúp mình pipeline ci trên github actions nha",
            "fix xong lỗi dark mode chưa để team qa test lại",
            "https://api.example.org/v2/users/profile?include=roles",
            "SELECT count(*) FROM user_sessions WHERE expired_at IS NULL;",
            "final sorted = entries.toList()..sort((a, b) => a.compareTo(b));",
            "git checkout -b fix/ui-padding-overflow",
            "qwerty zxcvbnm poiuyt lkjhgf",
            "flibber flabber zizzle wombat",
            "ref_491028 ver_2.1.4 hash_99ab",
            "chờ mình một lát nữa nhé",
            "đang kẹt ở ngoài đường chút",
            "tối nay nói chuyện sau nha",
            "ok cảm ơn cậu nhiều lắm",
            "bấm lộn rồi bỏ qua đi",
        ],
    },
    "a_chatter_homonyms": {
        "train": [
            "đứng đợi ở tiền sảnh tòa nhà văn phòng",
            "bác sĩ khuyên người rối loạn tiền đình nghỉ ngơi",
            "tiền vệ đội tuyển chuyền bóng rất thông minh",
            "lắng nghe chia sẻ từ các anh chị tiền bối",
            "hỏi thăm sức khỏe bác lương mới về hưu",
            "ngã tư đường lương thế vinh rất đông xe",
            "uống nước lọc ấm mỗi sáng rất tốt cho sức khỏe",
            "nước sông mùa mưa dâng lên khá cao",
            "trời nóng bức cả phòng nghỉ giải lao uống nước",
            "dung lượng pin điện thoại chỉ còn mười lăm phần trăm",
            "cách ăn nói khéo léo và ăn mặc lịch sự",
            "chụp góc này lên hình rất ăn ảnh luôn",
            "rửa sạch mấy cái lọ thủy tinh đựng gia vị",
            "cắm lọ hoa ly thơm ngát giữa bàn tiếp khách",
            "ngồi ở tiền sảnh khách sạn chờ đoàn khách tới",
            "dung doi o tien sanh khach san cho ban",
            "pin laptop con hai muoi phan tram thoi",
            "ca nha nghi giai lao uong nuoc loc mat",
        ],
        "val": [
            "đợi anh ở khu vực tiền sảnh sảnh chính khách sạn",
            "bác lương cạnh nhà sáng nào cũng tập thể dục",
            "điện thoại sắp hết pin chỉ còn năm phần trăm",
            "uống hai ly nước lọc mát sau khi chạy bộ",
        ],
    },
    "b_non_financial_lifeos": {
        "train": [
            "tạo lịch hẹn khám mắt định kỳ sáng thứ tư",
            "đặt lịch hẹn nha khoa kiểm tra răng chiều thứ năm",
            "nhắc lịch đóng tiền điện trước ngày cuối tháng",
            "nhắc lịch đóng học phí cho con vào đầu tuần sau",
            "tạo nhắc nhở bảo dưỡng thay nhớt xe ở mốc hai vạn km",
            "cập nhật công tơ mét odo xe vision đạt hai mươi lăm nghìn km",
            "ghi nhật ký uống bốn trăm ml nước lọc sau tập thể thao",
            "nhắc uống hai viên vitamin tổng hợp sau bữa ăn trưa",
            "đặt báo thức sáu giờ sáng mai dậy chạy bộ công viên",
            "tạo danh sách đi chợ mua rau cải cà chua thịt cá",
            "ghi chú danh sách đồ dùng cần chuẩn bị cho chuyến đi",
            "lưu ghi chú mật khẩu wifi phòng họp tầng hai",
            "tao lich hen kham rang nha khoa chieu thu hai",
            "nhac uong thuoc bo mat luc chin gio toi nay",
            "cap nhat odo xe may air blade 19000 km",
            "uong them ba tram ml nuoc loc tinh khiet",
            "nhắc lịch đóng tiền điện lực trước cuối tuần này",
            "tạo nhắc nhở đóng tiền điện trước thứ sáu",
            "lên lịch khám răng định kỳ ở nha khoa tuần tới",
            "đặt lịch hẹn khám mắt tổng quát sáng thứ ba",
            "nhắc lịch kiểm tra sức khỏe định kỳ bệnh viện",
            "tạo lịch hẹn cắt tóc gội đầu chiều thứ bảy",
            "cài nhắc nhở đóng cước internet trước ngày gia hạn",
            "lưu việc cần làm thanh toán tiền nước vào thứ hai",
            "nhắc uống thuốc bổ mắt sau bữa cơm tối",
            "đặt báo thức sáu giờ rưỡi sáng thứ hai",
            "tạo việc cần làm dọn dẹp phòng cuối tuần",
            "nhắc kiểm tra hạn bảo hiểm xe máy cuối tháng",
            "nhắc bảo dưỡng thay nhớt xe khi đủ hai vạn km",
            "dat lich hen kham nha khoa sang thu nam",
            "tao nhac nho dong tien nuoc dien truoc han",
            "nhac lich dong hoc phi ky moi dau tuan sau",
            "len lich kham benh tong quat phong kham cuoi tuan",
            "cai bao thuc bay gio sang mai di lam",
            "nhac toi dong tien mang wifi truoc thu bay",
        ],
        "val": [
            "tạo lịch hẹn khám răng định kỳ ở phòng khám tuần sau",
            "nhắc lịch khám mắt kiểm tra thị lực vào sáng thứ sáu",
            "nhắc đóng tiền điện lực trước thứ bảy tuần này",
            "ghi nhật ký uống ba trăm ml nước lọc buổi sáng",
        ],
    },
    "d_negated_hypothetical_balance_otp": {
        "train": [
            "đừng ghi nhận khoản ăn sáng 45k này vào sổ",
            "không lưu giao dịch chuyển khoản 300k vừa nói",
            "hủy bỏ bút toán mua cà phê 50k vừa tạo nhầm",
            "xóa giúp tôi khoản chi 200k mới nhập sai",
            "bỏ qua khoản mua đồ 150k không ghi vào chi tiêu",
            "tôi định tháng tới mua chiếc xe máy điện 30 triệu",
            "dự định năm sau đổi chiếc laptop mới khoảng 25 triệu",
            "nếu mua cái máy lọc không khí 6 triệu thì có ổn không",
            "có nên chi 10 triệu đăng ký khóa học này không nhỉ",
            "số dư tài khoản ngân hàng mbbank hiện còn bao nhiêu",
            "trong ví điện tử momo hiện giờ còn mấy trăm nghìn",
            "tổng chi tiêu ăn uống từ đầu tháng đến nay bao nhiêu",
            "mã otp xác thực giao dịch ngân hàng là 592817",
            "mã pin thẻ atm mới cấp của bạn là 718293",
            "tuyệt đối không cung cấp mã xác nhận otp 401928",
            "dung ghi khoan chi 100k nay vao so nhe",
            "du dinh mua dien thoai moi tam 18 trieu",
            "ma otp xac nhan dang nhap cua quy khach la 839201",
        ],
        "val": [
            "đừng ghi khoản mua sách 120k vừa đọc nhầm vào sổ",
            "dự định tháng sau mua tủ lạnh mới khoảng 12 triệu",
            "số dư khả dụng trong tài khoản techcombank còn bao nhiêu",
            "mã otp kích hoạt ví điện tử của bạn là 920184",
        ],
    },
}

AUG_TRAIN_WRAPPERS = [
    ("aug_tr_bare_acc", "{item}", False),
    ("aug_tr_bare_noacc", "{item}", True),
    ("aug_tr_w1", "trả tiền {item} {amt}", False),
    ("aug_tr_w2", "đóng {item} {amt}", False),
    ("aug_tr_w3", "chi {amt} cho {item}", False),
    ("aug_tr_w4", "thanh toán {item} {amt}", False),
    ("aug_tr_w5", "mới {item} hết {amt}", False),
    ("aug_tr_w6", "{item} {amt}", True),
]

AUG_VAL_WRAPPERS = [
    ("aug_va_bare_acc", "{item}", False),
    ("aug_va_bare_noacc", "{item}", True),
    ("aug_va_w1", "mới chi {amt} {item}", False),
    ("aug_va_w2", "trả {item} hết {amt}", False),
]

AMOUNTS = ["35k", "50k", "85 nghìn", "120k", "250k", "450k", "1tr2", "2tr5", "4tr"]


def _read_jsonl(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def _write_jsonl(path: Path, rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")


def _write_fasttext(path: Path, rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for r in rows:
            fh.write(f"__label__{r['label']} {r['normalized_text']}\n")


def main() -> None:
    rng = random.Random(20261126)

    # 1. Load frozen held-out test sets (READ-ONLY)
    fin_test = _read_jsonl(DATA_DIR / "test.jsonl")
    ood_test = _read_jsonl(DATA_DIR / "ood_financial_test.jsonl")
    hard_v2 = _read_jsonl(DATA_DIR / "hard_v2_test.jsonl")
    ms_ood_test = _read_jsonl(DATA_DIR / "ood_money_split_test.jsonl")
    held_out_all = fin_test + ood_test + hard_v2
    held_out_indexed = index_target_rows(held_out_all)

    forbidden_norms: set[str] = {
        r["normalized_text"] for r in held_out_all + ms_ood_test if r.get("normalized_text")
    }
    forbidden_asc: set[str] = {strip_vn_accents(n) for n in forbidden_norms}

    # 2. Load base non-augmented train/val rows (so script is 100% idempotent)
    base_fin_tr = [r for r in _read_jsonl(DATA_DIR / "train.jsonl") if not str(r.get("template_id", "")).startswith("aug_")]
    base_fin_va = [r for r in _read_jsonl(DATA_DIR / "val.jsonl") if not str(r.get("template_id", "")).startswith("aug_")]
    base_ood_tr = [r for r in _read_jsonl(DATA_DIR / "ood_financial_train.jsonl") if not str(r.get("template_id", "")).startswith("aug_")]
    base_ood_va = [r for r in _read_jsonl(DATA_DIR / "ood_financial_val.jsonl") if not str(r.get("template_id", "")).startswith("aug_")]

    seen_id_norms: set[str] = {
        r["normalized_text"] for r in base_fin_tr + base_fin_va
    }
    seen_ood_norms: set[str] = {
        r["normalized_text"] for r in base_ood_tr + base_ood_va
    }
    # Never collide ID <-> OOD across any split
    all_base_ood_norms = seen_ood_norms | {r["normalized_text"] for r in ood_test if r.get("normalized_text")}
    all_base_id_norms = seen_id_norms | {r["normalized_text"] for r in fin_test if r.get("normalized_text")}

    aug_id_rows: dict[str, list[dict[str, str]]] = {"train": [], "val": []}
    aug_ood_rows: dict[str, list[dict[str, str]]] = {"train": [], "val": []}

    # 3. Generate ID augmentations
    for label, splits in AUG_ID_POOLS.items():
        if label not in SEMANTIC_LABELS:
            raise ValueError(f"Invalid label: {label}")
        for split in ("train", "val"):
            wrappers = AUG_TRAIN_WRAPPERS if split == "train" else AUG_VAL_WRAPPERS
            for phrase in splits[split]:
                picked_wrappers = (
                    [wrappers[0], wrappers[1], *rng.sample(wrappers[2:], k=3)]
                    if split == "train"
                    else wrappers
                )
                for tid, tpl, noacc in picked_wrappers:
                    raw = tpl.format(item=phrase, amt=rng.choice(AMOUNTS))
                    if noacc:
                        raw = strip_vn_accents(raw)
                    norm = normalize_for_classifier(raw)
                    if len(norm) < 2:
                        continue
                    asc = strip_vn_accents(norm)
                    if (
                        norm in seen_id_norms
                        or norm in all_base_ood_norms
                        or norm in forbidden_norms
                        or asc in forbidden_asc
                    ):
                        continue
                    # Check near-duplicate vs held_out_all before accepting
                    cand_row = {
                        "label": label,
                        "raw_text": raw,
                        "normalized_text": norm,
                        "template_id": tid,
                        "style": "aug_unaccented" if noacc else "aug_accented",
                    }
                    if find_near_duplicates([cand_row], held_out_all, token_jaccard_thresh=0.78, char4_jaccard_thresh=0.80, preindexed_targets=held_out_indexed):
                        continue
                    seen_id_norms.add(norm)
                    aug_id_rows[split].append(cand_row)

    # 4. Generate OOD augmentations
    ood_wrappers_tr = [("aug_ood_tr_bare", "{item}", False), ("aug_ood_tr_noacc", "{item}", True)]
    ood_wrappers_va = [("aug_ood_va_bare", "{item}", False), ("aug_ood_va_noacc", "{item}", True)]

    for stratum, splits in AUG_OOD_POOLS.items():
        for split in ("train", "val"):
            wrappers = ood_wrappers_tr if split == "train" else ood_wrappers_va
            for phrase in splits[split]:
                for tid, tpl, noacc in wrappers:
                    if stratum == "c_english_gibberish_code_fragments" and noacc and strip_vn_accents(phrase) == phrase:
                        continue
                    raw = strip_vn_accents(phrase) if noacc else phrase
                    norm = normalize_for_classifier(raw)
                    if len(norm) < 2:
                        continue
                    asc = strip_vn_accents(norm)
                    if (
                        norm in seen_ood_norms
                        or norm in seen_id_norms
                        or norm in all_base_id_norms
                        or norm in forbidden_norms
                        or asc in forbidden_asc
                    ):
                        continue
                    cand_row = {
                        "split": split,
                        "stratum": stratum,
                        "label": OOD_LABEL,
                        "template_id": f"{tid}_{stratum[:4]}",
                        "raw_text": raw,
                        "normalized_text": norm,
                        "style": "aug_ood_unaccented" if noacc else "aug_ood_accented",
                    }
                    if find_near_duplicates([cand_row], held_out_all, token_jaccard_thresh=0.78, char4_jaccard_thresh=0.80, preindexed_targets=held_out_indexed):
                        continue
                    seen_ood_norms.add(norm)
                    aug_ood_rows[split].append(cand_row)

    # 5. Merge and export train/val JSONL + fasttext.txt (leaving all test splits untouched!)
    final_fin_tr = base_fin_tr + aug_id_rows["train"]
    final_fin_va = base_fin_va + aug_id_rows["val"]
    final_ood_tr = base_ood_tr + aug_ood_rows["train"]
    final_ood_va = base_ood_va + aug_ood_rows["val"]

    _write_jsonl(DATA_DIR / "train.jsonl", final_fin_tr)
    _write_jsonl(DATA_DIR / "val.jsonl", final_fin_va)
    _write_fasttext(DATA_DIR / "train.fasttext.txt", final_fin_tr)
    _write_fasttext(DATA_DIR / "val.fasttext.txt", final_fin_va)

    _write_jsonl(DATA_DIR / "ood_financial_train.jsonl", final_ood_tr)
    _write_jsonl(DATA_DIR / "ood_financial_val.jsonl", final_ood_va)

    # Update dataset_stats.json preserving test stats
    stats = json.loads((DATA_DIR / "dataset_stats.json").read_text(encoding="utf-8"))
    for sp, items in [("train", final_fin_tr), ("val", final_fin_va)]:
        counts = Counter(x["label"] for x in items)
        stats[sp] = {
            "count": len(items),
            "unique_templates": len({x["template_id"] for x in items}),
            "num_classes": len(counts),
            "min_per_class": min(counts.values()),
            "max_per_class": max(counts.values()),
        }
    (DATA_DIR / "dataset_stats.json").write_text(
        json.dumps(stats, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(
        f"Augmented ID: train +{len(aug_id_rows['train'])} -> {len(final_fin_tr)} | "
        f"val +{len(aug_id_rows['val'])} -> {len(final_fin_va)}"
    )
    print(
        f"Augmented OOD: train +{len(aug_ood_rows['train'])} -> {len(final_ood_tr)} | "
        f"val +{len(aug_ood_rows['val'])} -> {len(final_ood_va)}"
    )
    print(f"OOD train strata: {dict(sorted(Counter(r['stratum'] for r in final_ood_tr).items()))}")
    print(f"ID train weak counts: { {c: sum(1 for r in final_fin_tr if r['label']==c) for c in ['housing.housework','housing.utilities','health.hospital','education','shopping.general','food.drinks','other']} }")


if __name__ == "__main__":
    main()
