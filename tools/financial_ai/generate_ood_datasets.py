"""Generates strictly disjoint, multi-stratum OOD datasets for BOTH LifeOS local AI models.

Outputs in `tools/financial_ai/datasets/`:
- `ood_financial_train.jsonl`, `ood_financial_val.jsonl`, `ood_financial_test.jsonl`
- `ood_money_split_train.jsonl`, `ood_money_split_val.jsonl`, `ood_money_split_test.jsonl`

Anti-Leakage Guarantees:
- 0% normalized text overlap across train / val / test within OOD splits.
- 0% template_id overlap across train / val / test within OOD splits.
- 0% normalized text overlap against each model's in-domain train / val / test splits.
- Covers both accented and unaccented Vietnamese across 5 realistic OOD strata:
  (a) Everyday chatter, weather, traffic, greetings, news, and tricky homonyms
  (b) Non-financial LifeOS domain commands (calendar, alarms, medicine reminders, hydration ml, ODO km, grocery lists, notes)
  (c) English chatter, mixed slang, gibberish, code snippets, short 1-3 word fragments
  (d) Negated, hypothetical, balance-inquiry, and OTP/PIN utterances
  (e) [Money Split AI ONLY] Single-person transactions from Financial AI's matching split
"""

from __future__ import annotations

import json
import random
from collections import Counter
from pathlib import Path

from feature_spec import normalize_for_classifier, strip_vn_accents

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "datasets"

OOD_TRAIN_WRAPPERS: list[tuple[str, str]] = [
    ("ood_tr_w1", "{item}"),
    ("ood_tr_w2", "nhắn nhẹ {item}"),
    ("ood_tr_w3", "mình mới bảo {item}"),
    ("ood_tr_w4", "này bạn ơi {item}"),
    ("ood_tr_w5", "cậu ơi {item}"),
]

OOD_VAL_WRAPPERS: list[tuple[str, str]] = [
    ("ood_va_w1", "{item}"),
    ("ood_va_w2", "tiện nhắc {item}"),
    ("ood_va_w3", "hình như {item}"),
]

OOD_TEST_WRAPPERS: list[tuple[str, str]] = [
    ("ood_te_w1", "{item}"),
    ("ood_te_w2", "nghe nói {item}"),
    ("ood_te_w3", "vừa thấy {item}"),
]

# Stratum (a): Everyday Vietnamese chatter, weather, traffic, greetings, news, tricky homonyms
STRATUM_A: dict[str, list[str]] = {
    "train": [
        "hôm nay trời nắng đẹp dịu nhẹ quá",
        "dự báo thời tiết cuối tuần có gió mùa đông bắc",
        "ngoài trời mưa rào rả rích từ sáng sớm",
        "chúc cả nhà buổi sáng tràn đầy năng lượng",
        "chúc mừng sinh nhật bạn nhiều niềm vui bình an",
        "ngã tư hàng xanh giờ tan tầm kẹt xe kéo dài",
        "đường nguyễn trãi chiều nay đông đúc xe cộ",
        "cầu sài gòn buổi chiều gió thổi mát rượi",
        "bạn minh lương mới chuyển về khu chung cư bên cạnh",
        "nhà văn hóa nằm trên phố lương ngọc quyến",
        "gặp thầy lương ở hành lang khoa công nghệ",
        "đi ngang qua ngã tư nguyễn lương bằng giờ cao điểm",
        "nghỉ giải lao mười lăm phút giữa hai tiết học",
        "hôm nay cả phòng nghỉ giải lao uống nước lọc",
        "tín hiệu đầu dây bên kia hơi bị rè tiếng",
        "nối lại đầu dây mạng cáp bị đứt ngoài hành lang",
        "trời nóng bức nhớ uống nước lọc cho mát người",
        "buổi sáng uống nước lọc ấm rất tốt cho cổ họng",
        "bạn ấy ăn nói rất lịch sự và khéo léo",
        "hai đứa làm việc ăn ý với nhau từng chi tiết",
        "hôm nay mặc bộ đồ này lên hình ăn ảnh ghê",
        "mặc đồ chỉnh tề lịch sự trước khi vào phòng họp",
        "buổi sáng chạy bộ ba vòng quanh hồ hoàn kiếm",
        "tối nay cả team chạy deadline kịp tiến độ giao hàng",
        "xem bóng đá trực tiếp trận chung kết tối nay",
        "cuối tuần đá bóng giao hữu trên sân cỏ gần nhà",
        "bản tin thời sự buổi tối đưa tin tình hình giao thông",
        "nghe podcast tin tức công nghệ trên đường đi làm",
        "kẹt xe cứng ngắc đoạn đường trường chinh lúc năm giờ",
        "sắp xếp sáu lọ gia vị thủy tinh gọn gàng trên kệ bếp",
        "cắm lọ hoa cúc vàng đặt ngay bàn phòng khách",
        "rửa sạch mấy cái lọ thủy tinh đựng gia vị trong bếp",
        "pin điện thoại chỉ còn ba mươi phần trăm thôi",
        "dung lượng ổ cứng máy tính còn hai mươi phần trăm",
        "chia sẻ bài viết hay lên nhóm cộng đồng kỹ sư",
        "chia sẻ kinh nghiệm học ngoại ngữ cho người mới",
        "trả lời tin nhắn khách hàng trên trang fanpage",
        "trả bài kiểm tra môn toán cho học sinh lớp tám",
        "góp ý chân thành cho bản thiết kế giao diện mới",
        "chóng mặt rối loạn tiền đình khi thay đổi thời tiết",
        "đợi bạn ở tiền sảnh tầng trệt tòa nhà văn phòng",
        "cầu thủ tiền vệ trung tâm chuyền bóng rất chuẩn xác",
        "gặp các anh chị tiền bối trong ngành chia sẻ nghề nghiệp",
        "trà dư tửu hậu ngồi kể chuyện ngày xưa vui vẻ",
        "nước sông hồng mùa này dâng cao hơn tháng trước",
        "nước mưa đọng lại trên sân thượng sau cơn bão",
        "tầm nhìn xa bị hạn chế do sương mù dày đặc",
        "không khí buổi sớm trong lành mát mẻ dễ chịu",
        "chờ thang máy hơi lâu vào giờ cao điểm buổi sáng",
        "cảm ơn anh chị đã hỗ trợ nhiệt tình suốt tuần qua",
        "hẹn cuối tuần rảnh rỗi tụ tập trò chuyện hàn huyên",
        "bầu trời hoàng hôn chiều nay nhuộm sắc cam rực rỡ",
        "đèn đường trên đại lộ thăng long bật sáng từ sáu giờ",
        "làm việc này luôn cho kịp tiến độ buổi chiều",
        "chiều nay đi lượn một vòng quanh hồ tây hóng gió",
        "mấy luống rau cải ngoài ban công lớn nhanh thật",
        "nói thật luôn là mình quên mất lịch hẹn hôm qua",
    ],
    "val": [
        "thời tiết ngày mai nắng ráo thích hợp dã ngoại",
        "chiều nay mây đen kéo đến báo hiệu sắp mưa to",
        "đoạn cầu vượt ngã tư sở kẹt xe suốt nửa tiếng",
        "đi dạo trên đường lương thế vinh vào buổi tối mát",
        "công viên cạnh phố lương văn can rất nhiều cây xanh",
        "giờ giải lao trưa mọi người ra ban công hít thở",
        "đầu dây điện thoại bên kia nghe tiếng gió thổi mạnh",
        "nhớ uống nước lọc đều đặn mỗi ngày kẻo khô họng",
        "cách ăn nói nhẹ nhàng giúp cuộc trao đổi thuận lợi",
        "chiều mát chạy bộ dọc bờ kênh rất sảng khoái",
        "rủ nhau xem bóng đá ngoại hạng anh tối thứ bảy",
        "thời lượng pin laptop giảm xuống mười lăm phần trăm",
        "lau chùi mấy cái lọ đựng hạt khô trong tủ bếp",
        "chia sẻ tài liệu hướng dẫn cài đặt lên nhóm chat",
        "phát biểu góp ý tại buổi họp tổng kết cuối tháng",
        "ngồi chờ ở khu vực tiền sảnh khách sạn đón đoàn",
        "buổi tối ngồi đọc báo cập nhật tin tức thế giới",
        "chúc bạn một tuần mới làm việc thật suôn sẻ nhé",
    ],
    "test": [
        "bầu trời sáng nay nhiều mây và gió thổi mát rượi",
        "dự báo thời tiết khu vực miền nam chiều có mưa dông",
        "ngã tư thủ đức kẹt xe kéo dài sau cơn mưa lớn",
        "kẹt xe kẹt cứng trên tuyến đường lê văn lương",
        "tòa nhà bưu điện nằm góc đường lương định của",
        "hỏi thăm bác lương hàng xóm mới chuyển từ quê lên",
        "cả lớp nghỉ giải lao mười phút trước ca thực hành",
        "báo hiệu hết giờ giải lao mọi người quay lại chỗ ngồi",
        "alo đầu dây bên kia nói to lên chút giúp mình",
        "kiểm tra lại đầu dây cắm mạng xem có lỏng không",
        "uống nước lọc mát lạnh sau khi đi ngoài nắng về",
        "bình nước lọc trong phòng làm việc vừa hết nước rồi",
        "anh ấy ăn nói điềm đạm nên ai cũng quý mến",
        "chọn trang phục ăn mặc đơn giản mà gọn gàng",
        "sáng chủ nhật chạy bộ năm vòng công viên thống nhất",
        "hẹn anh em tối nay xem bóng đá đội tuyển quốc gia",
        "tin tức giao thông buổi sáng cảnh báo ngập úng cục bộ",
        "chúc ngủ ngon mơ đẹp hẹn sáng mai gặp lại nhé",
        "báo pin yếu còn mười phần trăm cần cắm sạc ngay",
        "rửa sạch mấy lọ thủy tinh để đựng gia vị nấu ăn",
        "chia sẻ đường dẫn tài liệu học tập cho cả lớp",
        "trả lời bình luận thắc mắc của thành viên diễn đàn",
        "bác sĩ dặn dò người bị tiền đình nên ngủ đủ giấc",
        "bàn trà phòng khách bày sẵn ấm chén tiếp khách quý",
        "chuyến tàu điện chạy êm ru qua khu đô thị mới",
        "đường phố lên đèn lung linh vào buổi tối cuối tuần",
        "tắc đường ngay vòng xoay nên tới trễ mười phút",
        "mùa thu lá vàng rơi đầy dọc con đường rợp bóng cây",
    ],
}

# Stratum (b): Non-financial LifeOS domain commands (calendar, alarms, medicine, hydration ml, ODO km, grocery lists, notes)
STRATUM_B: dict[str, list[str]] = {
    "train": [
        "tạo lịch họp giao ban sản phẩm lúc chín giờ sáng thứ hai",
        "đặt lịch hẹn gặp bác sĩ nha khoa vào chiều thứ năm",
        "dời cuộc họp kiểm thử phần mềm sang ba giờ chiều mai",
        "nhắc lịch phỏng vấn ứng viên phòng họp tầng bốn",
        "thêm sự kiện sinh nhật mẹ vào lịch cuối tuần này",
        "hẹn báo thức lúc năm giờ ba mươi sáng dậy chạy bộ",
        "đặt chuông báo thức bảy giờ kém mười lăm đi làm",
        "bật báo thức gọi dậy lúc sáu giờ sáng mỗi ngày",
        "tắt báo thức cuối tuần để ngủ bù thêm một chút",
        "nhắc uống hai viên vitamin tổng hợp sau bữa ăn sáng",
        "đặt lịch uống một viên thuốc bổ mắt vào buổi tối",
        "nhắc uống thuốc dị ứng lúc tám giờ tối trước khi ngủ",
        "ghi nhận đã uống một viên canxi sau bữa cơm trưa",
        "đã uống ba trăm ml nước lọc tinh khiết buổi sáng",
        "ghi nhật ký uống bốn trăm năm mươi ml nước sau tập gym",
        "nhắc uống hai trăm năm mươi ml nước mỗi hai tiếng",
        "cộng thêm năm trăm ml nước ấm vào mục tiêu hôm nay",
        "cập nhật odo xe máy honda đạt mười hai nghìn km",
        "nhắc kiểm tra odo xe tay ga khi chạm mốc hai vạn km",
        "ghi số công tơ mét ô tô hiện tại ba mươi lăm nghìn km",
        "nhắc bảo dưỡng định kỳ xe vision ở mốc mười lăm nghìn cây số",
        "tạo danh sách đi chợ tuần này gồm hành lá tỏi ớt chanh",
        "ghi chú đồ cần mua ở bếp dầu hào nước tương tiêu xay",
        "nhắc thêm cà rốt khoai tây vào danh sách đi chợ chiều nay",
        "danh sách vật dụng dã ngoại cần chuẩn bị lều bạt đèn pin",
        "ghi chú ý tưởng cải tiến màn hình trang chủ ứng dụng",
        "lưu ghi chú mật khẩu wifi phòng họp tầng ba là lifeos",
        "tạo việc cần làm hoàn thiện tài liệu kiến trúc trước thứ sáu",
        "nhắc gọi điện hỏi thăm sức khỏe ông bà nội tối nay",
        "tạo công việc dọn dẹp bàn làm việc sạch sẽ cuối ngày",
        "nhắc khóa cửa sổ tắt bình nóng lạnh trước khi đi ngủ",
        "đánh dấu đã hoàn thành nhiệm vụ kiểm tra sao lưu dữ liệu",
        "thêm nhắc nhở tưới cây ban công vào bảy giờ tối nay",
        "đặt lịch hẹn cắt tóc vào sáng chủ nhật tuần tới",
        "ghi chú danh sách sách hay muốn tìm đọc trong tháng này",
        "cập nhật quãng đường di chuyển hôm nay là mười tám km",
        "nhắc kiểm tra áp suất lốp xe máy ở mốc tám nghìn km",
        "nhắc uống thuốc dạ dày trước bữa ăn trưa ba mươi phút",
        "lưu lại số đo chiều cao cân nặng định kỳ tháng này",
        "đặt nhắc nhở nghỉ mắt thư giãn sau mỗi bốn mươi lăm phút",
    ],
    "val": [
        "tạo lịch họp thiết kế giao diện lúc mười giờ sáng mai",
        "nhắc lịch khám mắt định kỳ sáng thứ bảy tại phòng khám",
        "đặt báo thức sáu giờ mười lăm phút sáng mai dậy sớm",
        "hẹn chuông đồng hồ tám giờ tối nhắc đọc sách",
        "nhắc uống một viên omega sau bữa cơm tối nay",
        "ghi nhận uống thuốc cảm theo đơn buổi chiều lúc hai giờ",
        "ghi nhật ký uống ba trăm năm mươi ml nước khoáng mát",
        "uống thêm hai trăm ml nước lọc sau giờ họp căng thẳng",
        "cập nhật odo xe wave đạt hai mươi mốt nghìn km",
        "nhắc bảo dưỡng lọc gió xe máy ở mốc mười sáu nghìn km",
        "danh sách đi chợ cần mua rau muống cải ngọt gừng sả",
        "ghi chú danh sách món đồ mang theo chuyến công tác",
        "tạo việc cần làm gửi báo cáo tổng kết cho trưởng nhóm",
        "ghi chú ý tưởng tối ưu tốc độ khởi động ứng dụng",
        "nhắc gọi điện chúc mừng sinh nhật cô giáo cũ tối mai",
    ],
    "test": [
        "đặt lịch họp nhóm kỹ thuật lúc mười bốn giờ chiều thứ tư",
        "thêm cuộc hẹn ăn tối giao lưu cùng bạn cũ tối thứ bảy",
        "dời lịch trình buổi thuyết trình sang sáng thứ hai tuần sau",
        "đặt báo thức năm giờ bốn mươi lăm sáng mai ra sân bay",
        "bật chuông báo thức bảy giờ sáng các ngày trong tuần",
        "nhắc uống hai viên thuốc bổ gan sau bữa ăn tối",
        "đặt lịch uống thuốc kháng sinh sáng trưa chiều đúng giờ",
        "ghi nhận đã uống bốn trăm ml nước tinh khiết buổi chiều",
        "cộng ba trăm ml nước ấm vừa uống vào nhật ký sức khỏe",
        "nhắc uống đủ hai nghìn ml nước lọc mỗi ngày",
        "cập nhật số odo xe máy vision hiện tại mười bốn nghìn km",
        "thay nhớt định kỳ xe tay ga khi công tơ mét chạm mười tám nghìn km",
        "ghi nhận odo ô tô gia đình đã đi bốn mươi nghìn km",
        "danh sách đi chợ ngày mai cần mua hành ngò cà chua đậu hũ",
        "ghi chú danh sách gia vị hết trong tủ bếp cần bổ sung",
        "nhắc mua thêm giấy lau tay khi ghé cửa hàng tiện lợi",
        "tạo ghi chú tóm tắt nội dung cuộc họp sáng nay",
        "tạo việc cần làm kiểm tra lại toàn bộ tài liệu bàn giao",
        "nhắc tắt điều hòa và khóa cửa ban công trước lúc ra khỏi nhà",
        "ghi chú số điện thoại bác bảo vệ chung cư để liên hệ khi cần",
        "đặt lịch hẹn bảo hành máy lọc nước định kỳ vào sáng chủ nhật",
        "nhắc tập giãn cơ cổ vai gáy lúc mười lăm giờ chiều",
        "lưu danh sách bài hát yêu thích vào sổ tay cá nhân",
        "tạo nhắc nhở kiểm tra hạn đăng kiểm xe vào tháng tới",
    ],
}

# Stratum (c): English chatter, mixed slang, random gibberish, code snippets, short 1-3 word fragments
STRATUM_C: dict[str, list[str]] = {
    "train": [
        "hello good morning my friend",
        "how is the weather over there today",
        "please send me the project slides before noon",
        "see you in the conference room at three",
        "thank you so much for your quick reply",
        "have a wonderful weekend with your family",
        "let us schedule a sync call tomorrow morning",
        "happy anniversary wishing you all the best",
        "nice to meet you again after a long time",
        "could you check the pull request on github",
        "good night everyone talk to you tomorrow",
        "what time does the presentation start today",
        "ok bro check tin nhắn trên slack nhé",
        "fix bug giao diện xong rồi nghỉ ngơi thôi",
        "deploy bản build mới lên staging lúc nào vậy",
        "ping nhẹ mình qua zalo khi bạn rảnh nha",
        "review code giúp mình nhánh feature mới nhé",
        "server log báo timeout kết nối database rồi",
        "loading màn hình hơi chậm cần tối ưu thêm",
        "merge commit vào branch chính cẩn thận conflict",
        "test case này chạy pass hết rồi đỉnh quá",
        "update tài liệu spec lên notion cho cả team",
        "asdf jkl zxcv bnm qwer",
        "qwerty uiop ghjkl vbnm",
        "zzzz xxxx cccc vvvv bbbb",
        "lorem ipsum dolor sit amet",
        "foobar bazqux blahblah yadayada",
        "hahaha hihihi huhuhu kekeke",
        "xyzw abcd efgh ijkl mnop",
        "ptqrst uvwxyz mnbvcx lkjhgf",
        "def compute_metrics(items): return len(items)",
        "for item in records: print(item.strip())",
        "select id name from users where active",
        "const sum = values.reduce((a, b) => a + b)",
        "git status --short && git diff --check",
        "flutter analyze --fatal-infos --no-pub",
        "import json from pathlib import Path",
        "class UserProfile(BaseModel): name: str",
        "return Response(status=200, media_type='json')",
        "kubectl get pods -n production-cluster",
        "alo alo",
        "ok nhé",
        "cảm ơn bạn",
        "chào buổi sáng",
        "vâng ạ",
        "tạm biệt",
        "được rồi",
        "nghe rõ",
        "ừ đúng rồi",
        "không sao đâu",
        "hẹn gặp lại",
        "chúc ngủ ngon",
        "rất vui",
        "tuyệt vời",
        "bình thường thôi",
        "chờ chút nhé",
        "xong rồi nha",
        "mọi thứ ổn",
        "xin chào",
        "tốt quá rồi",
        "who is calling right now",
        "let me check my schedule first",
        "the sunset is gorgeous tonight",
        "happy birthday to my colleague",
        "python -m unittest discover",
        "mvn clean package -DskipTests",
        "sudo systemctl restart nginx",
        "try catch finally return null",
        "qqqwww eeeerrr tttyyy uuu",
        "zxcvbnm asdfghjkl qwertyuiop",
        "kaka hoho hehe xoxo",
        "mình đi đây",
        "nhớ rồi nha",
        "đợi xíu đi",
        "vào việc thôi",
        "tuyệt đối ổn",
        "hợp lý quá",
        "không cần đâu",
        "chỉ hỏi vậy thôi",
        "đùa chút thôi",
        "mình chờ chút nữa",
        "đợi lát nữa nhé",
        "cho hỏi chút xíu",
        "cho mình xin phép",
        "làm luôn cho nóng",
        "hợp ý nhất luôn",
        "tuyệt vời nhất rồi",
        "chốt vậy luôn nhé",
        "đợi một tẹo nha",
        "xem qua một lát",
    ],
    "val": [
        "good afternoon hope everything goes smoothly",
        "please share the meeting link in our chat",
        "let me know when you arrive at the lobby",
        "awesome work on the design prototype",
        "happy new year filled with joy and health",
        "check giúp mình pull request mới tạo nha bro",
        "build apk release chạy mượt không bị crash",
        "màn hình bị lag nhẹ khi cuộn danh sách dài",
        "push nhánh code lên git repo trước giờ nghỉ",
        "qazwsx edcrfv tgbyhn ujmik",
        "blabla bloobloo zyxwvutsrq",
        "mnbvcx zlkjhg fdsapoiuyt",
        "async def fetch_data(url): return await get(url)",
        "docker compose up -d --build postgres",
        "final result = items.where((e) => e.isValid)",
        "chào buổi trưa",
        "ổn áp rồi",
        "cứ thế nhé",
        "nhất trí luôn",
        "không vấn đề",
        "tới nơi chưa",
        "chờ một lát",
        "biết rồi ạ",
    ],
    "test": [
        "hello there how was your morning commute",
        "the sky looks clear and sunny this afternoon",
        "could you remind me about tomorrow standup time",
        "thanks a lot for helping me debug that issue",
        "wishing everyone a peaceful and productive day",
        "let us catch up over video call next friday",
        "just checking if the microphone audio is clear",
        "sorry for the late response i was in a meeting",
        "okela bro tối nay mình check kỹ lại log nhé",
        "deploy hotfix xong hết lỗi rồi yên tâm đi",
        "chờ xíu app đang sync dữ liệu offline về máy",
        "debug mãi mới ra nguyên nhân lỗi null pointer",
        "team backend vừa cập nhật endpoint api mới",
        "poiuyt lkjhgf mnbvcx asdfgh",
        "xxxyyy zzzwww qqqppp rrrttt",
        "gibberish random tokens alpha beta gamma",
        "flubber wibble wobble snickerdoodle",
        "while idx < len(rows): idx += 1",
        "curl -X GET https://api.example.com/health",
        "export default function AppHeader() { return null }",
        "npm run lint && npm run test:unit",
        "pip install --no-cache-dir -r requirements.txt",
        "alo nghe không",
        "đồng ý nha",
        "chào buổi tối",
        "cảm ơn nhiều",
        "tạm ổn rồi",
        "lát gọi lại",
        "hẹn ngày mai",
        "không có gì",
        "quá chuẩn luôn",
        "rõ ràng rồi",
        "tiếp tục nhé",
        "đợi tẹo nha",
        "xin lỗi nhé",
    ],
}

# Stratum (d): Negated, hypothetical, balance-inquiry, and OTP/PIN utterances
STRATUM_D: dict[str, list[str]] = {
    "train": [
        "đừng ghi khoản ăn trưa 50k vào sổ nhé",
        "đừng ghi nhận giao dịch mua cà phê 35k này",
        "không lưu khoản chi mua sách 120k hôm nay",
        "tôi không mua gì hết trong ngày hôm nay",
        "hôm nay chưa chi tiêu phát sinh khoản nào cả",
        "hủy giao dịch 250k vừa nhập nhầm lúc nãy",
        "xóa bút toán chuyển tiền 500k vừa rồi giúp tôi",
        "bỏ qua khoản chi 80k vừa đọc nhầm nhé",
        "không tính khoản ăn tối 300k này vào chi tiêu",
        "tôi định mua chiếc xe máy mới giá 35 triệu",
        "dự định tháng tới sẽ đổi điện thoại 20 triệu",
        "nếu mua cái laptop 25tr thì có hợp lý không",
        "có nên mua máy ảnh 18 triệu lúc này không nhỉ",
        "đang cân nhắc mua bộ bàn ghế 8 triệu vào cuối năm",
        "giả sử mỗi tháng tiết kiệm được 5 triệu thì sao",
        "tính sang năm sửa lại phòng ngủ hết tầm 15 triệu",
        "mua đôi giày thể thao giá 2tr có đắt quá không",
        "số dư hiện tại trong tài khoản còn bao nhiêu",
        "kiểm tra giúp tôi ví tiền mặt còn bao nhiêu tiền",
        "trong tài khoản ngân hàng hiện còn 4 triệu đồng",
        "hiện còn 3tr5 trong ví tiền mặt dự phòng",
        "tổng chi tiêu từ đầu tháng đến nay bao nhiêu rồi",
        "cho xem báo cáo tổng thu chi tuần vừa qua",
        "hạn mức chi tiêu an toàn hôm nay còn bao nhiêu",
        "mã otp xác thực giao dịch của quý khách là 482910",
        "mã otp giao dịch 500k là 739104 không chia sẻ",
        "mã pin thẻ thanh toán của bạn là 194820",
        "mã xác nhận đăng nhập một lần otp là 605312",
        "tuyệt đối không cung cấp mã otp 884210 cho người lạ",
        "mật khẩu xác thực bảo mật tài khoản là 918273",
        "không ghi khoản đổ xăng 70k vào danh sách chi",
        "chưa có giao dịch mua sắm nào phát sinh sáng nay",
        "ước gì có tiền đi du lịch châu âu 50 triệu",
        "nếu tháng sau nhận thưởng 10tr thì sẽ để dành",
        "số dư trong tài khoản ngân hàng còn lại bao nhiêu tiền",
        "ví điện tử hiện còn lại mấy trăm nghìn",
        "trong sổ tiết kiệm hiện giờ còn lại bao nhiêu",
        "tôi định mua chiếc tivi màn hình phẳng 12 triệu",
        "đang cân nhắc mua chiếc tủ lạnh mới 10 triệu",
        "nếu sắm chiếc đồng hồ thông minh 6 triệu thì sao",
        "dự định mua chiếc ghế công thái học 4 triệu",
        "có nên mua chiếc tai nghe chống ồn 5 triệu không",
    ],
    "val": [
        "đừng ghi khoản mua nước ép 40k vừa nói nhé",
        "không lưu giao dịch nháp 150k này vào hệ thống",
        "hủy bỏ giao dịch vừa tạo 300k lúc nãy",
        "tôi không hề chi khoản nào vào chiều qua cả",
        "dự định cuối năm mua tivi mới khoảng 14 triệu",
        "nếu chi 6 triệu học khóa thiết kế có nên không",
        "có nên đổi xe tay ga 40 triệu trong tháng này không",
        "trong thẻ ngân hàng hiện tại còn 7 triệu đồng",
        "tổng số dư tất cả các ví còn lại bao nhiêu",
        "xem giúp tổng chi ăn uống tháng này bao nhiêu",
        "mã otp kích hoạt thẻ của bạn là 551920",
        "vui lòng nhập mã pin bảo mật 304918 để xác thực",
    ],
    "test": [
        "đừng ghi khoản ăn phở 55k vừa rồi vào báo cáo",
        "không lưu giao dịch chuyển khoản 400k nháp này",
        "tôi không mua đồ gì trên mạng hôm nay cả",
        "chưa phát sinh bất kỳ khoản thu chi nào hôm nay",
        "hủy giao dịch 180k mới nhập sai số tiền",
        "xóa giúp tôi bút toán 90k vừa ghi nhầm",
        "bỏ qua khoản mua trà sữa 45k không ghi sổ",
        "tôi định mua chiếc xe đạp thể thao 12 triệu",
        "nếu mua chiếc đồng hồ 7 triệu thì có phí quá không",
        "có nên chi 30 triệu nâng cấp máy tính làm việc không",
        "đang dự tính tháng sau đi du lịch nhật bản 25 triệu",
        "giả sử chi tiêu tối giản 6 triệu một tháng xem sao",
        "số dư tài khoản tiết kiệm còn bao nhiêu tiền",
        "trong tài khoản chính hiện đang còn 12 triệu đồng",
        "còn 1tr8 trong ví tiền mặt từ tuần trước",
        "tổng thu nhập tháng này tính đến hôm nay bao nhiêu",
        "hạn mức chi ngày hôm nay còn lại bao nhiêu nữa",
        "mã otp của quý khách là 482910 hiệu lực năm phút",
        "mã xác thực giao dịch otp ngân hàng là 829104",
        "mã pin thẻ atm mới cấp của bạn là 617283",
        "tuyệt đối giữ bí mật mã otp 394812 với mọi người",
        "lệnh hủy bỏ bản nháp giao dịch 600k vừa rồi",
        "không tính khoản dự kiến 2 triệu vào sổ chi tiêu",
        "hỏi thăm giá vé máy bay tết khoảng 4 triệu có đắt không",
    ],
}

# Disjoint single-person transfers & income/expense near-OOD specifically for Money Split AI Stratum (e)
EXTRA_SINGLE_PERSON_NEAR_OOD: dict[str, list[str]] = {
    "train": [
        "chuyển khoản 2 triệu cho mẹ ăn tiêu tháng này",
        "nhận lương tháng này 20 triệu qua ngân hàng",
        "ăn phở bò tái chín sáng nay 55k",
        "đổ xăng xe máy 70k cây xăng gần nhà",
        "rút tiền mặt tại cây atm 1 triệu đồng",
        "chuyển 3 triệu từ mbbank sang tài khoản tiết kiệm",
        "mua thuốc cảm cúm ở nhà thuốc hết 95k",
        "thanh toán hóa đơn tiền điện lực 850k",
        "đặt ly trà sữa trân châu 45k uống buổi chiều",
        "mua chiếc áo sơ mi đi làm 399k",
        "đóng học phí khóa tiếng anh cá nhân 4 triệu",
        "đi taxi từ văn phòng về nhà hết 110k",
        "đóng tiền thuê phòng trọ tháng này cho chủ nhà 3tr2",
        "trả góp chiếc tủ lạnh điện máy xanh mỗi tháng 1tr2",
        "nhận lại tiền cọc phòng trọ cũ 2 triệu",
        "mua vé xem phim rạp cgv đi xem một mình 95k",
        "trả bớt khoản vay cá nhân cho người quen 1tr5",
        "chuyển khoản biếu gia đình ở quê 3 triệu",
        "gửi tiền về quê phụng dưỡng mẹ 2tr",
        "mua thịt cá rau ở siêu thị winmart 350k",
        "mua cá hồi tươi ở coopmart về nấu cơm 280k",
        "đi chợ mua đồ ăn trưa một mình 90k",
        "mới nhận lương tháng mười chuyển khoản 18 triệu",
        "lương tháng này vừa về tài khoản 22 triệu đồng",
        "được công ty trả thưởng quý 5 triệu đồng",
        "đóng hóa đơn tiền điện tháng này 950k",
        "đi siêu thị bách hóa xanh mua đồ hết 420k",
        "thanh toán tiền nước và internet 450k",
        "mua đồ tiêu dùng ở lotte mart 680k",
        "chuyển khoản trả tiền thuê nhà hàng tháng 4 triệu",
        "đóng tiền trả góp xe máy hàng tháng 2tr5",
        "gửi tiền mặt cho mẹ đi chợ 1 triệu",
        "ăn phở gà ta buổi sáng một mình 45k",
        "uống trà sữa một mình buổi chiều 55k",
        "đặt cơm trưa văn phòng tự ăn 40k",
        "mua sắm quần áo cuối tuần tự chi 750k",
        "mua sữa bỉm cho bé ở nhà hết 420k",
        "gửi tiền biếu bố mẹ cuối tháng 3 triệu",
        "đóng học phí cho con đầu năm học 2tr8",
        "mua tã giấy và sữa bột cho em bé 650k",
        "chuyển khoản tiền học thêm cho con gái 1tr2",
        "mua đồ dùng bếp gia đình 290k",
        "mới nhận tiền lương công ty chuyển về thẻ 17 triệu",
        "lương cứng tháng tư vừa về ví ngân hàng 16 triệu",
        "được kế toán chuyển lương định kỳ 19 triệu",
        "vừa lĩnh tiền lương cuối tháng qua bidv 21 triệu",
        "thu nhập lương hàng tháng đã cộng vào tài khoản 23 triệu",
        "lương thưởng quý này mới nhận được 14 triệu đồng",
        "ghé nhà thuốc tây mua vỉ thuốc cảm và khẩu trang 65k",
        "ra hiệu thuốc mua chai nước muối sinh lý và thuốc ho 75k",
        "mua hộp vitamin c và thuốc hạ sốt tại quầy thuốc 110k",
        "ghé tiệm thuốc pharmacity mua thuốc đau đầu 50k",
    ],
    "val": [
        "chuyển khoản 1tr5 gửi biếu bố ở quê",
        "nhận lương chuyển khoản tháng này 18 triệu",
        "ăn cơm tấm sườn chả buổi trưa 50k",
        "đổ đầy bình xăng xe vision 75k",
        "thanh toán tiền mạng internet tháng này 250k",
        "mua vé xem phim cuối tuần một mình 110k",
    ],
    "test": [
        "chuyển khoản 2 triệu cho mẹ",
        "nhận lương tháng này 20 triệu",
        "ăn phở bò 55k",
        "đổ xăng 70k",
        "rút tiền mặt atm 500k",
        "chuyển 5 triệu từ vcb sang tài khoản tiết kiệm của tôi",
        "mua chai nước ép cam buổi trưa 35k",
        "thanh toán cước điện thoại di động 120k",
        "đóng tiền thuê phòng trọ cá nhân 3tr5",
        "mua sạc dự phòng anker 650k",
    ],
}

SPLIT_CONTAMINATION_TOKENS = (
    "chia hoa don",
    "chia bill",
    "chia deu",
    "cua doi",
    "campuchia",
    "gop von",
    "phan tram",
    "50 30 20",
    "6 lo",
    "6 hu",
    "tat toan cong no",
    "ung ho bua",
    "ung truoc",
    "khoan chi chung",
)


def _load_norm_set(path: Path, field: str = "normalized_text") -> set[str]:
    out: set[str] = set()
    if not path.exists():
        return out
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            obj = json.loads(line)
            val = obj.get(field) or obj.get("normalized") or ""
            if val:
                out.add(val)
    return out


def _emit_stratum_rows(
    rng: random.Random,
    stratum: str,
    split: str,
    phrases: list[str],
    wrappers: list[tuple[str, str]],
    seen_norms: set[str],
    forbidden_norms: set[str],
    allow_wrappers: bool = True,
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for phrase in phrases:
        # 1. Bare accented & unaccented
        candidates: list[tuple[str, str, str]] = [
            (f"{split}_{stratum}_bare_acc", phrase, "accented_short"),
        ]
        no_acc = strip_vn_accents(phrase)
        if no_acc != phrase:
            candidates.append((f"{split}_{stratum}_bare_noacc", no_acc, "unaccented_short"))

        # 2. Wrapped accented & unaccented (for Vietnamese strata a, b, d)
        if allow_wrappers:
            non_bare = [(tid, tpl) for tid, tpl in wrappers if tpl != "{item}"]
            picked = (
                rng.sample(non_bare, k=min(3, len(non_bare)))
                if split == "train"
                else non_bare[:1]
            )
            for tid, tpl in picked:
                sent = tpl.format(item=phrase)
                candidates.append((f"{tid}_{stratum}_acc", sent, "accented_sentence"))
                if split == "train" or rng.random() < 0.70:
                    sent_no = strip_vn_accents(sent)
                    candidates.append(
                        (f"{tid}_{stratum}_noacc", sent_no, "unaccented_sentence")
                    )

        for tid, raw_text, style in candidates:
            norm = normalize_for_classifier(raw_text)
            if len(norm) < 2:
                continue
            if norm in seen_norms or norm in forbidden_norms:
                continue
            seen_norms.add(norm)
            rows.append(
                {
                    "split": split,
                    "stratum": stratum,
                    "label": "__ood__",
                    "template_id": tid,
                    "raw_text": raw_text,
                    "normalized_text": norm,
                    "style": style,
                }
            )
    return rows


def _sample_near_ood_from_financial(
    rng: random.Random,
    fin_split: str,
    target_split: str,
    max_samples: int,
    seen_norms: set[str],
    forbidden_norms: set[str],
) -> list[dict[str, str]]:
    src_path = DATA_DIR / f"{fin_split}.jsonl"
    pool: list[dict[str, str]] = []
    with src_path.open("r", encoding="utf-8") as fh:
        for line in fh:
            obj = json.loads(line)
            raw = obj["raw_text"]
            norm = obj["normalized_text"]
            asc_raw = strip_vn_accents(raw)
            asc_norm = strip_vn_accents(norm)
            if any(tok in asc_raw or tok in asc_norm for tok in SPLIT_CONTAMINATION_TOKENS):
                continue
            if norm in seen_norms or norm in forbidden_norms:
                continue
            pool.append(obj)

    rng.shuffle(pool)
    rows: list[dict[str, str]] = []
    for obj in pool:
        if len(rows) >= max_samples:
            break
        norm = obj["normalized_text"]
        if norm in seen_norms or norm in forbidden_norms:
            continue
        seen_norms.add(norm)
        rows.append(
            {
                "split": target_split,
                "stratum": "e_single_person_near_ood",
                "label": "__ood__",
                "template_id": f"{target_split}_nearood_{obj['template_id']}",
                "raw_text": obj["raw_text"],
                "normalized_text": norm,
                "style": obj.get("style", "single_person_tx"),
            }
        )
    return rows


def _write_and_verify(
    prefix: str,
    by_split: dict[str, list[dict[str, str]]],
    in_domain_norms: set[str],
) -> None:
    norm_sets: dict[str, set[str]] = {}
    tpl_sets: dict[str, set[str]] = {}

    for split in ("train", "val", "test"):
        items = by_split[split]
        out_path = DATA_DIR / f"{prefix}_{split}.jsonl"
        with out_path.open("w", encoding="utf-8", newline="\n") as fh:
            for item in items:
                fh.write(json.dumps(item, ensure_ascii=False) + "\n")
        norm_sets[split] = {r["normalized_text"] for r in items}
        tpl_sets[split] = {r["template_id"] for r in items}

    # Strict anti-leakage assertions
    assert norm_sets["train"].isdisjoint(norm_sets["val"]), f"{prefix}: norm leakage train <-> val"
    assert norm_sets["train"].isdisjoint(norm_sets["test"]), f"{prefix}: norm leakage train <-> test"
    assert norm_sets["val"].isdisjoint(norm_sets["test"]), f"{prefix}: norm leakage val <-> test"

    assert tpl_sets["train"].isdisjoint(tpl_sets["val"]), f"{prefix}: template leakage train <-> val"
    assert tpl_sets["train"].isdisjoint(tpl_sets["test"]), f"{prefix}: template leakage train <-> test"
    assert tpl_sets["val"].isdisjoint(tpl_sets["test"]), f"{prefix}: template leakage val <-> test"

    for split in ("train", "val", "test"):
        overlap_id = norm_sets[split] & in_domain_norms
        assert not overlap_id, f"{prefix}_{split}: {len(overlap_id)} collisions with in-domain: {list(overlap_id)[:5]}"

    for split in ("train", "val", "test"):
        strata_counts = Counter(r["stratum"] for r in by_split[split])
        print(
            f"[{prefix}_{split}] total={len(by_split[split])} | strata={dict(sorted(strata_counts.items()))}"
        )


def main() -> None:
    rng = random.Random(20261125)
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    fin_in_domain = (
        _load_norm_set(DATA_DIR / "train.jsonl")
        | _load_norm_set(DATA_DIR / "val.jsonl")
        | _load_norm_set(DATA_DIR / "test.jsonl")
    )
    split_in_domain = (
        _load_norm_set(DATA_DIR / "money_split_train.jsonl")
        | _load_norm_set(DATA_DIR / "money_split_val.jsonl")
        | _load_norm_set(DATA_DIR / "money_split_test.jsonl")
    )

    wrappers_by_split = {
        "train": OOD_TRAIN_WRAPPERS,
        "val": OOD_VAL_WRAPPERS,
        "test": OOD_TEST_WRAPPERS,
    }

    # 1. Financial AI OOD datasets (Strata a, b, c, d)
    fin_seen: set[str] = set()
    fin_by_split: dict[str, list[dict[str, str]]] = {"train": [], "val": [], "test": []}
    for split in ("train", "val", "test"):
        w = wrappers_by_split[split]
        fin_by_split[split].extend(
            _emit_stratum_rows(rng, "a_chatter_homonyms", split, STRATUM_A[split], w, fin_seen, fin_in_domain, True)
        )
        fin_by_split[split].extend(
            _emit_stratum_rows(rng, "b_non_financial_lifeos", split, STRATUM_B[split], w, fin_seen, fin_in_domain, True)
        )
        fin_by_split[split].extend(
            _emit_stratum_rows(rng, "c_english_gibberish_code_fragments", split, STRATUM_C[split], w, fin_seen, fin_in_domain, False)
        )
        fin_by_split[split].extend(
            _emit_stratum_rows(rng, "d_negated_hypothetical_balance_otp", split, STRATUM_D[split], w, fin_seen, fin_in_domain, True)
        )

    _write_and_verify("ood_financial", fin_by_split, fin_in_domain)

    # 2. Money Split AI OOD datasets (Strata a, b, c, d + e single-person near-OOD)
    ms_seen: set[str] = set()
    ms_by_split: dict[str, list[dict[str, str]]] = {"train": [], "val": [], "test": []}
    near_ood_caps = {"train": 420, "val": 60, "test": 90}
    for split in ("train", "val", "test"):
        w = wrappers_by_split[split]
        ms_by_split[split].extend(
            _emit_stratum_rows(rng, "a_chatter_homonyms", split, STRATUM_A[split], w, ms_seen, split_in_domain, True)
        )
        ms_by_split[split].extend(
            _emit_stratum_rows(rng, "b_non_financial_lifeos", split, STRATUM_B[split], w, ms_seen, split_in_domain, True)
        )
        ms_by_split[split].extend(
            _emit_stratum_rows(rng, "c_english_gibberish_code_fragments", split, STRATUM_C[split], w, ms_seen, split_in_domain, False)
        )
        ms_by_split[split].extend(
            _emit_stratum_rows(rng, "d_negated_hypothetical_balance_otp", split, STRATUM_D[split], w, ms_seen, split_in_domain, True)
        )
        # Disjoint explicit single-person transfers/expenses + sampled split-matched rows from datasets/{split}.jsonl
        ms_by_split[split].extend(
            _emit_stratum_rows(rng, "e_single_person_near_ood", split, EXTRA_SINGLE_PERSON_NEAR_OOD[split], w, ms_seen, split_in_domain, False)
        )
        ms_by_split[split].extend(
            _sample_near_ood_from_financial(
                rng,
                fin_split=split,
                target_split=split,
                max_samples=near_ood_caps[split],
                seen_norms=ms_seen,
                forbidden_norms=split_in_domain,
            )
        )

    _write_and_verify("ood_money_split", ms_by_split, split_in_domain)


if __name__ == "__main__":
    main()
