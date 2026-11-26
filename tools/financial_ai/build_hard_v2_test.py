"""Builds the frozen hard_v2_test.jsonl benchmark BEFORE any training augmentation.

Covers realistic Vietnamese phrasings targeting weak categories and OOD Stratum C:
- No-diacritics, teencode & abbreviations ("tiền điện t11", "đóng hp", "kham rang", "giup viec theo gio")
- Brand names (EVN, Sawaco, FPT, Viettel, Vinmec, Long Châu, Highlands, Phúc Long, bTaskee, Shopee, etc.)
- Mixed Vietnamese/English, typos, and ASR-style homophone errors
- Hard OOD Stratum C (English sentences, code/URL fragments, gibberish, random digits) + Strata A/B/D

Verifies 0% normalized text collision against all existing train/val/test/OOD splits.
"""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path

from feature_spec import OOD_LABEL, SEMANTIC_LABELS, normalize_for_classifier

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "datasets"
OUT_PATH = DATA_DIR / "hard_v2_test.jsonl"

HARD_ID_CASES: dict[str, list[tuple[str, str]]] = {
    "housing.housework": [
        ("giup viec theo gio btaskee 220k", "no_diacritics_brand"),
        ("thue co giup viec don nha cuoi tuan 250k", "accented_sentence"),
        ("don phong theo gio 180k", "no_diacritics"),
        ("giúp ziệc theo h dọn bếp 200k", "typo_teencode"),
        ("vs may lanh phong ngu 300k", "teencode_no_diacritics"),
        ("vệ sinh điều hòa hai cục 350k", "accented_phrase"),
        ("mua nuoc giat omo matic 165k", "no_diacritics_brand"),
        ("nuoc rua chen sunlight 45k", "no_diacritics_brand"),
        ("rữa chén bát và nước lau sàn 95k", "asr_typo"),
        ("mua tui dung rac cuon lon 35k", "no_diacritics"),
        ("nước tẩy rửa bồn cầu duck 52k", "accented_brand"),
        ("sua ong nuoc bon rua chen 280k", "asr_typo_no_diacritics"),
        ("thợ sửa vòi nước rò rỉ nhà tắm 190k", "accented_phrase"),
        ("mua choi lau nha lock and lock 320k", "no_diacritics_brand"),
        ("bot giat ariel cua ngang 189k", "no_diacritics_brand"),
        ("giặt ủi chăn ga gối đệm 140k", "accented_phrase"),
        ("book lịch dọn nhà btaskee cuối tuần 260k", "mixed_vi_en_brand"),
        ("mua giay ve sinh cuon pulppy 88k", "no_diacritics_brand"),
        ("thay bóng đèn led phòng khách 75k", "accented_phrase"),
        ("phí thu gom rác dân lập tháng 11 50k", "accented_phrase"),
        ("mua nuoc xa vai comfort tui lon 155k", "no_diacritics_brand"),
        ("vệ sinh lồng máy giặt cửa trước 450k", "accented_phrase"),
        ("mua màng bọc thực phẩm và khăn lau bếp 65k", "accented_phrase"),
        ("giat rem cua so phong khach 300k", "no_diacritics"),
        ("mua viên tẩy lồng giặt nhật bản 85k", "accented_phrase"),
    ],
    "housing.utilities": [
        ("tiền điện t11 890k", "teencode_abbrev"),
        ("tien dien t11 evn 950k", "teencode_brand"),
        ("đóng tiền điện lực evn hcm 1tr15", "accented_brand"),
        ("tien nuoc sawaco thang 11 165k", "no_diacritics_brand"),
        ("hóa đơn cấp nước sawaco 140k", "accented_brand"),
        ("cuoc internet fpt t11 265k", "teencode_brand"),
        ("đóng tiền mạng fpt telecom 290k", "accented_brand"),
        ("nap 4g viettel 90k", "no_diacritics_brand"),
        ("gia han goi cuoc data 5g viettel t11 120k", "teencode_no_diacritics_brand"),
        ("cuoc cap quang vnpt gia dinh 230k", "no_diacritics_brand"),
        ("nap card dien thoai mobifone 100k", "no_diacritics_brand"),
        ("nap card dt vinaphone 50k", "teencode_brand"),
        ("tiền điên tháng này tăng quá 1tr4", "asr_typo"),
        ("đổi bình ga petrolimex bếp nấu 430k", "asr_variant_brand"),
        ("pay bill dien nuoc nha tro 720k", "mixed_vi_en"),
        ("topup data viettel myviettel 70k", "mixed_vi_en_brand"),
        ("tiền nước máy sinh hoạt khu phố 110k", "accented_phrase"),
        ("cước trả sau di động vnpt 185k", "accented_brand"),
        ("hóa đơn điện nước tháng mười một 820k", "spoken_style"),
        ("dong tien wifi phong tro 150k", "no_diacritics"),
        ("thanh toan hoa don evn qua momo 640k", "no_diacritics_brand"),
        ("cước truyền hình cáp fpt play 130k", "accented_brand"),
        ("nạp tiền sim data mobi 125k", "teencode_brand"),
    ],
    "health.hospital": [
        ("kham rang 400k", "no_diacritics"),
        ("khám răn sâu nha khoa 500k", "asr_typo"),
        ("khám tổng quát vinmec 2tr5", "accented_brand"),
        ("kham suc khoe tong quat vinmec 1tr8", "no_diacritics_brand"),
        ("vien phi benh vien cho ray 1tr2", "no_diacritics_brand"),
        ("đóng viện phí nội trú bệnh viện bạch mai 3tr4", "accented_brand"),
        ("tiêm vắc xin cúm vnvc 356k", "accented_brand"),
        ("tiem vacxin hpv vnvc 1tr79", "no_diacritics_brand"),
        ("lấy cao răng đánh bóng nha khoa kim 300k", "accented_brand"),
        ("nho rang khon phong kham nha khoa kim 1tr5", "no_diacritics_brand"),
        ("xét nghiệm máu sinh hóa medlatec 480k", "accented_brand"),
        ("siêu âm ổ bụng phòng khám đa khoa 350k", "accented_phrase"),
        ("đo khúc xạ cắt gọng kính cận 850k", "accented_phrase"),
        ("do mat cat kinh can 600k", "no_diacritics"),
        ("gia hạn thẻ tập gym california 1tr2", "accented_brand"),
        ("dong tien tap yoga thang 11 750k", "no_diacritics"),
        ("book lịch checkup sức khỏe vinmec 2tr2", "mixed_vi_en_brand"),
        ("khám nội soi tai mũi họng vinmec 380k", "accented_brand"),
        ("trám răng thẩm mỹ nha khoa paris 450k", "accented_brand"),
        ("tap pilates phuc hoi cot song 900k", "no_diacritics"),
        ("kham da lieu tri mun phong kham 550k", "no_diacritics"),
        ("chup mri khop goi benh vien 2tr1", "no_diacritics"),
    ],
    "education": [
        ("đóng hp 3tr5", "teencode_abbrev"),
        ("dong hp hoc ky moi 4tr2", "teencode_no_diacritics"),
        ("dong hoc phi dai hoc tin chi 5tr8", "no_diacritics"),
        ("đóng tiền học phí tiếng anh ielts 4tr5", "accented_phrase"),
        ("mua sách kỹ năng nhà sách fahasa 245k", "accented_brand"),
        ("mua sac fahasa cho em 180k", "asr_typo_brand"),
        ("dang ky khoa hoc udemy react 299k", "no_diacritics_brand"),
        ("thanh toán khóa học data coursera 1tr1", "accented_brand"),
        ("lệ phí thi chứng chỉ toeic iig 1tr5", "accented_phrase"),
        ("thi thu ielts british council 500k", "no_diacritics"),
        ("mua vpp vo but bi thien long 95k", "teencode_brand"),
        ("mua văn phòng phẩm sổ tay bút highlight 120k", "accented_phrase"),
        ("gia hạn app học ngoại ngữ elsa speak 390k", "mixed_vi_en_brand"),
        ("mua giao trinh on thi dai hoc 160k", "no_diacritics"),
        ("đón học phí lớp luyện thi 1tr2", "asr_typo"),
        ("tuition fee khóa học lập trình python 2tr4", "mixed_vi_en"),
        ("in ấn tài liệu giáo trình học tập 65k", "accented_phrase"),
        ("mua tu dien tieng nhat nha sach phuong nam 310k", "no_diacritics_brand"),
        ("học thêm toán lý hóa thầy hùng 800k", "accented_phrase"),
        ("nâng cấp gói học duolingo super 220k", "accented_brand"),
        ("mua sách kinh tế alpha books 195k", "accented_brand"),
    ],
    "shopping.general": [
        ("đặt đơn shopee mall 340k", "accented_brand"),
        ("ship cod don hang shopee 215k", "no_diacritics_brand"),
        ("chốt đơn tiktok shop kem chống nắng 280k", "accented_brand"),
        ("tra tien don hang lazada 390k", "no_diacritics_brand"),
        ("mua mỹ phẩm tẩy trang hasaki 310k", "accented_brand"),
        ("ghe guardian mua sua rua mat 195k", "no_diacritics_brand"),
        ("mua đồ tiêu dùng cá nhân siêu thị aeon 480k", "accented_brand"),
        ("shopping mall aeon mua do ca nhan 520k", "mixed_vi_en_brand"),
        ("ghé circle k mua đồ lặt vặt 75k", "accented_brand"),
        ("mua do vat dung ca nhan gs25 68k", "no_diacritics_brand"),
        ("mua dầu gội đầu sữa tắm watsons 290k", "accented_brand"),
        ("don tiki now giao hang nhanh 240k", "no_diacritics_brand"),
        ("mua kem đánh răng bàn chải điện 450k", "accented_phrase"),
        ("sắm vali kéo du lịch cá nhân 950k", "accented_phrase"),
        ("mua son dưỡng môi nước hoa hồng 360k", "accented_phrase"),
        ("chốt đơn mua sắm online sàn tmđt 410k", "teencode_abbrev"),
        ("mua bình giữ nhiệt lock lock 330k", "accented_brand"),
        ("mua bông tẩy trang và sữa dưỡng thể 185k", "accented_phrase"),
        ("thanh toan gio hang shopee pay 260k", "no_diacritics_brand"),
        ("sắm đồ cá nhân siêu thị lotte mart 430k", "accented_brand"),
        ("mua nến thơm tinh dầu phòng 220k", "accented_phrase"),
    ],
    "food.drinks": [
        ("cf sữa đá highlands 55k", "teencode_brand"),
        ("uong ca phe highlands coffee 65k", "no_diacritics_brand"),
        ("trà sữa phúc long size l 62k", "accented_brand"),
        ("ts phuc long kem cheese 58k", "teencode_brand"),
        ("order trà đào cam sả the coffee house 55k", "mixed_vi_en_brand"),
        ("mua ly katinat trà sữa ô long 60k", "accented_brand"),
        ("uong ca fê muối huế 35k", "asr_typo"),
        ("cà phê starbucks cold brew 95k", "accented_brand"),
        ("mua tra sua gong cha tran chau 68k", "no_diacritics_brand"),
        ("phê la ô long nhài sữa 54k", "accented_brand"),
        ("kem và trà hoa quả mixue 35k", "accented_brand"),
        ("uống bạc xỉu đá sài gòn 38k", "accented_phrase"),
        ("mua nước suối lavie chai nhỏ 15k", "accented_brand"),
        ("nuoc ep cam tuoi khong duong 40k", "no_diacritics"),
        ("sinh tố bơ dừa sáp 45k", "accented_phrase"),
        ("tra chanh gia tay pho co 25k", "no_diacritics"),
        ("cf trung nguyên legend đen đá 42k", "teencode_brand"),
        ("coffee date cuối tuần katina 115k", "mixed_vi_en_typo"),
        ("mua hai chai nước khoáng aquafina 20k", "accented_brand"),
        ("uống matcha đá xay kem tươi 65k", "accented_phrase"),
        ("nước dừa tươi xiêm xanh 30k", "accented_phrase"),
        ("gọi ly trà vải hoa hồng 49k", "accented_phrase"),
    ],
    "other": [
        ("công chứng giấy tờ sao y bản chính 80k", "accented_phrase"),
        ("phi cong chung ho so nha dat 150k", "no_diacritics"),
        ("lệ phí làm lại căn cước công dân 70k", "accented_phrase"),
        ("photocopy in tai lieu giay to 35k", "no_diacritics"),
        ("đánh lại chìa khóa xe dự phòng 60k", "accented_phrase"),
        ("phi gui buu pham chuyen phat nhanh buu dien 55k", "no_diacritics"),
        ("quyên góp quỹ từ thiện đồng bào miền trung 300k", "accented_phrase"),
        ("đóng tiền quỹ phòng công ty tháng 11 100k", "accented_phrase"),
        ("tiền tip bồi dưỡng nhân viên giao lắp 50k", "accented_phrase"),
        ("lệ phí cấp đổi bằng lái xe sở gtvt 135k", "accented_phrase"),
        ("trích lục giấy khai sinh ủy ban phường 40k", "accented_phrase"),
        ("chi phi phat sinh ngoai du kien khac 200k", "no_diacritics"),
        ("dịch thuật công chứng hồ sơ du học 420k", "accented_phrase"),
        ("thuê thợ mở khóa cửa phòng 180k", "accented_phrase"),
        ("khoản chi lặt vặt phát sinh khác 90k", "accented_phrase"),
    ],
    # Representative hard phrasings across remaining major categories
    "food.meals": [
        ("an sang bun bo hue gio heo 55k", "no_diacritics"),
        ("đặt cơm trưa grabfood văn phòng 65k", "accented_brand"),
        ("bánh mì thịt nướng chả lụa 28k", "accented_phrase"),
        ("an toi lau bo nhung dam voi ban 380k", "no_diacritics"),
        ("gà rán kfc combo trưa 99k", "accented_brand"),
    ],
    "food.groceries": [
        ("di cho mua thit heo rau muong 145k", "no_diacritics"),
        ("mua trứng gà ta gạo thơm winmart 230k", "accented_brand"),
        ("bách hóa xanh mua cá hồi tươi rau củ 290k", "accented_brand"),
        ("mua gia vị nước mắm dầu ăn coopmart 175k", "accented_brand"),
    ],
    "transport.fuel": [
        ("do xang a95 cay xang petrolimex 80k", "no_diacritics_brand"),
        ("đổ xăn đầy bình xe lead 75k", "asr_typo"),
        ("sạc pin trạm vinfast xe điện 60k", "accented_brand"),
    ],
    "transport.ride_hailing": [
        ("book grabcar ra san bay tan son nhat 185k", "mixed_vi_en_brand"),
        ("đi taxi điện xanh sm về nhà 95k", "accented_brand"),
        ("đặt xe ôm công nghệ bebike đi làm 42k", "accented_brand"),
    ],
    "transport.public": [
        ("nap tien tai khoan thu phi epass 300k", "no_diacritics_brand"),
        ("gửi xe máy hầm tòa nhà 10k", "accented_phrase"),
        ("di tau dien metro ben thanh suoi tien 20k", "no_diacritics_brand"),
    ],
    "transport.maintenance": [
        ("thay nhớt xe honda vision head 185k", "accented_brand"),
        ("bao duong sua xe thay bugi loc gio 320k", "no_diacritics"),
        ("vá lốp không săm dọc đường 40k", "accented_phrase"),
    ],
    "housing.rent": [
        ("dong tien tro thang 11 3tr5", "no_diacritics"),
        ("chuyển khoản tiền thuê căn hộ vinhomes 9tr5", "accented_brand"),
        ("phí quản lý vận hành chung cư 680k", "accented_phrase"),
    ],
    "shopping.clothes": [
        ("mua áo sơ mi uniqlo công sở 599k", "accented_brand"),
        ("sam giay sneaker bitis hunter 850k", "no_diacritics_brand"),
    ],
    "shopping.electronics": [
        ("mua sac du phong anker tgdd 690k", "no_diacritics_brand"),
        ("điện máy xanh mua nồi chiên không dầu 1tr9", "accented_brand"),
    ],
    "health.medicine": [
        ("mua vi thuoc cam sot o long chau 115k", "no_diacritics_brand"),
        ("ghé pharmacity mua vitamin c panadol 98k", "accented_brand"),
    ],
    "entertainment": [
        ("mua vé xem phim rạp cgv cuối tuần 210k", "accented_brand"),
        ("thuê sân cầu lông pickleball tối thứ năm 240k", "accented_phrase"),
    ],
    "subscriptions": [
        ("gia hạn gói netflix tháng 260k", "accented_brand"),
        ("thanh toan spotify premium thang 11 59k", "no_diacritics_brand"),
        ("mua gói icloud plus 50gb 19k", "accented_brand"),
    ],
    "family": [
        ("mua bỉm tã sữa bột em bé con cưng 680k", "accented_brand"),
        ("chuyen khoan bieu bo me o que tien sinh hoat 4tr", "no_diacritics"),
    ],
    "gifts": [
        ("đi phong bì mừng đám cưới đồng nghiệp 1tr", "accented_phrase"),
        ("mua hoa và bánh kem tặng sinh nhật bạn 380k", "accented_phrase"),
    ],
    "debt.interest": [
        ("dong tien tra gop hang thang fe credit 1tr45", "no_diacritics_brand"),
        ("dong tien gop dien thoai home credit 1tr1", "no_diacritics_brand"),
    ],
    "bank.fee": [
        ("tru phi thong bao bien dong sms banking 11k", "no_diacritics"),
        ("phí thường niên thẻ tín dụng quốc tế 499k", "accented_phrase"),
    ],
    "income.salary": [
        ("nhan luong t11 cong ty chuyen khoan 21tr", "teencode_no_diacritics"),
        ("vietcombank bao co luong chinh thuc 24tr5", "no_diacritics_brand"),
    ],
    "income.bonus": [
        ("nhận thưởng kpi quý bốn công ty 6tr", "accented_phrase"),
        ("nhan tien thuong du an vuot kpi 4tr5", "no_diacritics"),
    ],
    "income.freelance": [
        ("nhận thù lao thiết kế web freelance 5tr", "accented_phrase"),
        ("khach thanh toan tien day kem gia su tieng anh 2tr4", "no_diacritics"),
    ],
    "income.business": [
        ("doanh thu don hang shopee doi soat ve vi 7tr2", "no_diacritics_brand"),
        ("nhan tien thu ho cod giao hang nhanh 3tr8", "no_diacritics_brand"),
    ],
    "income.interest": [
        ("nhan lai gui tiet kiem ky han ngan hang 1tr4", "no_diacritics"),
        ("co tuc tien mat chung khoan ve tai khoan 2tr1", "no_diacritics"),
    ],
    "income.gift": [
        ("được ông bà lì xì mừng tuổi đầu năm 1tr", "accented_phrase"),
        ("bo me gui cho minh tien tieu vat 2tr", "no_diacritics"),
    ],
    "income.other": [
        ("bán thanh lý màn hình máy tính cũ 1tr8", "accented_phrase"),
        ("ban chia bill an trua chuyen tra lai minh 120k", "no_diacritics"),
    ],
}

HARD_OOD_CASES: dict[str, list[str]] = {
    "c_english_gibberish_code_fragments": [
        # English sentences (including tricky domain words like order/pay/account/budget/update)
        "please update the quarterly budget report before five pm",
        "did you receive my email about the deployment schedule",
        "can you review this pull request and approve the merge",
        "good morning team let us sync on the sprint backlog today",
        "the weather in saigon looks rainy all afternoon",
        "sorry i missed your call earlier i was commuting home",
        "happy birthday wishing you joy success and good health",
        "remember to push your local commits before shutting down",
        "could you check why the login endpoint returned 401 unauthorized",
        "let us grab lunch together after the architecture review",
        "please verify the checksum of the downloaded archive file",
        "our mobile build pipeline passed all integration checks",
        "thank you for sharing the meeting notes in the channel",
        "where did we save the design tokens specification document",
        "have a relaxing sunday evening with your loved ones",
        # Mixed Vietnamese / English tech & social chatter
        "ok bro check lại ticket jira giúp mình nhé",
        "deploy bản staging lên cloud run bị timeout rồi",
        "fix xong lỗi layout overflow ở màn hình 360x800 chưa",
        "ping nhẹ team qa vào test regression nhánh mới nha",
        "push commit lên git repo đi rồi anh review cho",
        "app build release apk chạy mượt trên android 14 lắm",
        "sáng nay standup meeting dời sang 9h30 nha mọi người",
        "link figma mockup mới đã gắn trong notion rồi đó",
        "server log báo connection refused tới redis cache",
        "rebase nhánh feature với main cẩn thận kẻo conflict",
        # Code fragments & URLs
        "https://github.com/lifeos-app/mobile/pull/1842",
        "http://localhost:8080/api/v2/healthz?verbose=true",
        "https://pub.dev/packages/flutter_bloc/versions/9.1.0",
        "final filtered = items.where((x) => x.isValid).toList();",
        "flutter test --no-pub --timeout 60s test/unit/",
        "python -u tools/financial_ai/evaluate_all_models.py",
        "git log --oneline -n 10 --graph --decorate",
        "SELECT id, category_key FROM ledger_entries ORDER BY created_at DESC;",
        "const total = rows.reduce((acc, cur) => acc + cur.weight, 0);",
        "docker build -t lifeos-worker:latest -f Dockerfile .",
        "import 'package:flutter/foundation.dart';",
        "curl -s https://api.example.com/v1/status | jq .",
        # Gibberish & random tokens
        "zxqwk plmokn ijnuhb ygvtfc",
        "qwertyuiop asdfghjkl zxcvbnm",
        "blorp zizzle frazzle wombat",
        "mnbvcxz lkjhgfdsa poiuytrewq",
        "ttttt yyyyy uuuuu iiiii",
        "xyz123 abc987 qwe456 rty789",
        "kakaka hohoho hihihi hahaha",
        "aabbcc ddeeff gghhii jjkkll",
        # Random digits / IDs / timestamps
        "948271 003918 552104",
        "ref 948271 id 003918",
        "build 2026-11-26 14:30:00",
        "sdt 0909123456 zalo",
        "ver 3.27.1-rc2 hash 482910",
        "100 200 300 400",
        # Short conversational fragments (non-financial)
        "ok để xem lại đã",
        "chắc vậy rồi đó",
        "ừ đúng rồi bạn",
        "rồi xong hết chưa",
        "tới liền đây chờ tí",
        "alo nghe rõ không bạn",
        "cảm ơn nhiều lắm nha",
        "tạm biệt hẹn gặp lại",
        "vâng ạ em biết rồi",
        "không có gì đâu nha",
    ],
    "a_chatter_homonyms": [
        "kẹt xe ở ngã tư hàng xanh lâu ghê luôn",
        "hom nay troi mat me thich hop di dao cong vien",
        "bac luong nha ben canh moi di ha noi ve",
        "doi ban o tien sanh toa nha bitexco",
        "uong coc nuoc loc am moi sang tot cho co hong",
        "cau thu tien ve ghi ban dep mat phut bu gio",
        "pin dien thoai con hai muoi phan tram thoi",
        "cả lớp nghỉ giải lao mười phút giữa giờ",
        "chia se tai lieu on tap len nhom lop di",
        "tra bai kiem tra toan cho hoc sinh lop chin",
        "bị rối loạn tiền đình nên hay chóng mặt",
        "nước sông hương chiều nay dâng nhẹ sau mưa",
    ],
    "b_non_financial_lifeos": [
        "tạo lịch họp khách hàng lúc 10 giờ sáng mai",
        "dat lich hen kham rang chieu thu bay tuan sau",
        "bật chuông báo thức năm giờ ba mươi sáng mai",
        "dat bao thuc bay gio sang cac ngay trong tuan",
        "nhắc uống hai viên vitamin tổng hợp sau bữa ăn tối",
        "nhac uong thuoc bo mat luc tam gio toi nay",
        "đã uống 400 ml nước lọc tinh khiết buổi chiều",
        "uong them 350ml nuoc am sau khi tap the duc",
        "cập nhật odo xe máy vision đạt 18.500 km",
        "ghi so cong to met o to 42000 km",
        "ghi chú mật khẩu wifi phòng họp tầng năm",
        "tao viec can lam gui bao cao tuan truoc thu sau",
        "nhac khoa cua so tat den truoc khi di ngu",
        "danh sách đi chợ cần mua hành ngò gừng sả tỏi",
        "tạo ghi chú ý tưởng nâng cấp màn hình trang chủ",
    ],
    "d_negated_hypothetical_balance_otp": [
        "đừng ghi khoản ăn tối 180k vừa nói nhé",
        "dung luu giao dich mua cafe 45k nay vao so",
        "không tính khoản chi 120k này vào báo cáo",
        "hủy bút toán chuyển khoản 500k vừa tạo nhầm",
        "xoa giup toi giao dich 250k vua nhap sai",
        "tôi định tháng sau mua xe máy điện 32 triệu",
        "du dinh cuoi nam doi dien thoai moi tam 20 cu",
        "nếu chi 8 triệu học khóa dữ liệu thì có nên không",
        "co nen mua laptop gaming 28 trieu luc nay khong",
        "số dư khả dụng trong tài khoản vietcombank còn bao nhiêu",
        "trong vi tien mat hien gio con 3 trieu ruoi",
        "tổng chi tiêu ăn uống tháng này bao nhiêu rồi",
        "ma otp xac thuc giao dich 500k la 619284 khong chia se",
        "mã pin thẻ atm mới của quý khách là 405912",
        "tuyệt đối giữ bí mật mã xác thực otp 738291",
    ],
}


def _load_existing_norms() -> set[str]:
    existing: set[str] = set()
    for fname in [
        "train.jsonl",
        "val.jsonl",
        "test.jsonl",
        "ood_financial_train.jsonl",
        "ood_financial_val.jsonl",
        "ood_financial_test.jsonl",
    ]:
        path = DATA_DIR / fname
        if not path.exists():
            continue
        with path.open("r", encoding="utf-8") as fh:
            for line in fh:
                obj = json.loads(line)
                norm = str(obj.get("normalized_text") or "").strip()
                if norm:
                    existing.add(norm)
    return existing


def main() -> None:
    valid_labels = set(SEMANTIC_LABELS)
    existing_norms = _load_existing_norms()

    rows: list[dict[str, str]] = []
    seen_hard_norms: set[str] = set()
    collisions: list[str] = []

    for label, entries in HARD_ID_CASES.items():
        if label not in valid_labels:
            raise ValueError(f"Unknown semantic label: {label}")
        for idx, (raw, style) in enumerate(entries, start=1):
            norm = normalize_for_classifier(raw)
            if len(norm) < 2:
                raise ValueError(f"Normalized text too short for ID sample: {raw!r} -> {norm!r}")
            if norm in existing_norms:
                collisions.append(f"ID collision with existing dataset: {norm!r} (raw={raw!r})")
                continue
            if norm in seen_hard_norms:
                collisions.append(f"Duplicate norm inside hard_v2_test: {norm!r}")
                continue
            seen_hard_norms.add(norm)
            rows.append(
                {
                    "split": "hard_v2_test",
                    "stratum": "in_domain",
                    "label": label,
                    "template_id": f"hard_v2_id_{label}_{idx}",
                    "raw_text": raw,
                    "normalized_text": norm,
                    "style": style,
                }
            )

    for stratum, entries in HARD_OOD_CASES.items():
        for idx, raw in enumerate(entries, start=1):
            norm = normalize_for_classifier(raw)
            if norm in existing_norms:
                collisions.append(f"OOD collision with existing dataset: {norm!r} (raw={raw!r})")
                continue
            if norm and norm in seen_hard_norms:
                collisions.append(f"Duplicate OOD norm inside hard_v2_test: {norm!r}")
                continue
            if norm:
                seen_hard_norms.add(norm)
            rows.append(
                {
                    "split": "hard_v2_test",
                    "stratum": stratum,
                    "label": OOD_LABEL,
                    "template_id": f"hard_v2_ood_{stratum}_{idx}",
                    "raw_text": raw,
                    "normalized_text": norm,
                    "style": "hard_ood",
                }
            )

    if collisions:
        raise RuntimeError("Collisions found while building hard_v2_test.jsonl:\n" + "\n".join(collisions))

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8", newline="\n") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")

    sha256_hex = hashlib.sha256(OUT_PATH.read_bytes()).hexdigest()
    id_count = sum(1 for r in rows if r["label"] != OOD_LABEL)
    ood_count = sum(1 for r in rows if r["label"] == OOD_LABEL)
    cat_counts = Counter(r["label"] for r in rows if r["label"] != OOD_LABEL)
    stratum_counts = Counter(r["stratum"] for r in rows if r["label"] == OOD_LABEL)

    print(f"Wrote frozen {OUT_PATH} ({len(rows)} rows: {id_count} ID, {ood_count} OOD)")
    print(f"hard_v2_test.jsonl SHA-256: {sha256_hex}")
    print(f"ID per-category counts: {dict(sorted(cat_counts.items()))}")
    print(f"OOD per-stratum counts: {dict(sorted(stratum_counts.items()))}")


if __name__ == "__main__":
    main()
