# Nghiên Cứu Sâu Hành Vi Người Dùng Từ Các Siêu Ứng Dụng Lớn & Kiến Trúc Kết Hợp Gemini AI

**Dự án:** Life OS Super App (`vn.lifeos.app`)  
**Phiên bản kiến trúc:** Hybrid Local FastText + Connected Gemini 2.5 + Behavioral Habit Engine  
**Nguyên tắc cốt lõi:** Offline-First (`< 5ms`) · Zero-Friction Thumb Ergonomics · Quyền riêng tư tuyệt đối · Không phụ thuộc máy chủ bắt buộc

---

## 1. Tổng Hợp Nghiên Cứu Hành Vi & Vi Tương Tác (Micro-Interactions) Từ Các Ứng Dụng Hàng Đầu

Người dùng mở một siêu ứng dụng quản lý đời sống — tài chính — lịch trình trung bình **4–8 lần/ngày**, nhưng mỗi phiên tương tác chỉ kéo dài **5–15 giây** (khi đang đứng tính tiền cà phê, vừa nhận lương, đang họp hoặc đi chợ). Nếu một thao tác đòi hỏi quá **3 chạm** hoặc bắt người dùng tự phân loại *"đây là Lịch hẹn, Việc làm hay Chi tiêu?"* trước khi gõ, tỷ lệ bỏ cuộc tăng vọt trên 60%.

Bảng dưới đây đúc kết các cơ chế tâm lý hành vi đã được kiểm chứng từ những ứng dụng lớn và cách kết hợp trực tiếp vào **Life OS**:

| Nhóm Ứng Dụng Tham Chiếu | Hành Vi Thực Tế Của Người Dùng | Cơ Chế Tối Ưu Hóa Thao Tác | Ứng Dụng Trực Tiếp Vào Life OS |
| :--- | :--- | :--- | :--- |
| **MoMo · ZaloPay · Grab** *(Siêu ứng dụng Việt Nam)* | Thao tác bằng **1 ngón cái**, lặp lại cùng một nhóm chi tiêu theo khung giờ cố định trong ngày (sáng ăn phở/cà phê, trưa cơm văn phòng, chiều đổ xăng, tối đi chợ). | **1. Gợi ý theo nhịp sinh học (Circadian Contextual Chips)** theo 4 khung giờ.<br>**2. Xếp hạng thói quen `RFM` (Recency × Frequency)** đẩy cửa hàng/khoản chi hay dùng lên đầu.<br>**3. Đệm số `000` thông minh** cho tiền Việt (`35` → `35.000 ₫`). | Nâng cấp `UserBehaviorPrefs` lưu bộ nhớ thói quen (`HabitShortcut`) kết hợp tần suất & độ mới; hiển thị gợi ý đúng khung giờ ngay trên `TodayPage` và nút `+`. |
| **Revolut · Apple Wallet · Money Lover** *(Fintech chuẩn quốc tế & VN)* | Lo lắng tiêu lố ngân sách vào cuối tháng; ngại bấm lưu nhanh vì sợ nhập nhầm số tiền hoặc sai ví. | **1. Nhịp chi tiêu an toàn mỗi ngày (Safe-to-Spend Daily Pace)** thay vì chỉ báo tổng tháng.<br>**2. Xem trước tức thì (`< 10ms` Live Preview)** ngay khi đang gõ.<br>**3. Nút `Hoàn tác` (1-Tap Undo)** trên thanh thông báo đỉnh màn hình. | Mọi thao tác lưu nhanh 1 chạm từ `+` hoặc gợi ý thói quen đều kèm nút **`Hoàn tác`** trên `LifeOsTopToast` (gọi `TransactionReverseSubmitted` tức thì) và tự nhớ ví thanh toán gần nhất. |
| **Todoist · TickTick · Linear · Notion** *(Năng suất & Quản lý công việc)* | Khi nảy ra ý định (*"Chiều mai 15h họp dự án, nhắc mua sữa tươi, sáng ăn phở 55k"*), người dùng suy nghĩ bằng **một câu tự nhiên**, không muốn mở 3 màn hình khác nhau. | **Thanh Lệnh Đa Năng (Unified Omni-Command Bar)**: Gõ **1 câu duy nhất**, hệ thống tự nhận diện đa ý định (Thu chi · Chia tiền · Lịch hẹn · Việc cần làm · Giỏ đi chợ), bóc tách ngày giờ tương đối (`sáng mai`, `15h`, `tối nay`) và mức ưu tiên (`!gấp`). | Xây dựng `SmartOmniIntentParser` chạy tức thì trên máy kết hợp sâu với **Gemini AI** để bóc tách câu đơn lẫn câu ghép đa tác vụ ngay trong `QuickCreateHubSheet` (`+`) và `FinancialAiAssistantPage`. |
| **Splitwise · Tricount** *(Chia tiền nhóm & Gia đình)* | Sau bữa ăn nhóm hoặc hóa đơn điện nước chung, muốn chia đều hoặc chia theo người ngay lập tức mà không cần bấm máy tính. | Nhận diện mẫu câu `"ăn lẩu 600k chia 4 người"` → tự chia nguyên đơn vị `VND` (không sai số dấu phẩy động) và gắn vào không gian Gia đình/Nhóm. | Tích hợp luồng `groupBillSplit` trực tiếp vào bộ điều phối đa năng và bản nháp Gemini để xác nhận 1 chạm. |

---

## 2. Kiến Trúc Kết Hợp Kép: Offline AI Trên Máy + Liên Kết Gemini AI

Để vừa giữ trọn nguyên tắc **100% hoạt động không cần Internet, 0ms độ trễ, không tốn phí bắt buộc**, vừa khai phóng sức mạnh hiểu ngôn ngữ tự nhiên sâu sắc của mô hình ngôn ngữ lớn khi có mạng và được người dùng cho phép, Life OS áp dụng **Kiến Trúc Trí Tuệ Kép 2 Tầng (Dual-Tier Hybrid Intelligence)**:

```text
Người dùng nhập câu / Giọng nói / Hóa đơn / Câu hỏi tài chính
                              │
                              ▼
     ┌─────────────────────────────────────────────────┐
     │ TẦNG 1: TRÊN THIẾT BỊ (OFFLINE-FIRST · < 5ms)   │
     │ • SmartOmniIntentParser (Thu chi/Lịch/Việc/Chợ) │
     │ • FastText VN Classifier (.ftq INT8, 548 KB)    │
     │ • Personalization & UserBehaviorPrefs (RFM)     │
     └────────────────────────┬────────────────────────┘
                              │
            ┌─────────────────┴─────────────────┐
            │ Đã bật Gemini AI & Có kết nối?    │
            └───────┬───────────────────┬───────┘
          Không /   │                   │ Có (hoặc bấm "✨ Phân tích sâu Gemini")
          Offline   ▼                   ▼
     ┌──────────────────────┐  ┌──────────────────────────────────────────┐
     │ Trả kết quả tức thì  │  │ TẦNG 2: GEMINI AI CONNECTOR (OPT-IN)     │
     │ 100% trên máy        │  │ • Khóa API lưu trong Android Keystore    │
     │ (Không lộ dữ liệu)   │  │ • Bộ lọc ẩn SĐT / Số TK / Email (PII)    │
     └──────────┬───────────┘  │ • Gemini 2.5 Flash Structured JSON       │
                │              │ • Bóc tách đa tác vụ + Lời khuyên thông  │
                │              │   minh dựa trên nhịp chi tiêu thực tế    │
                │              └────────────────────┬─────────────────────┘
                │                                   │ (Nếu lỗi mạng / hết hạn mức:
                │                                   │  tự động lùi về Tầng 1 êm ái)
                └─────────────────┬─────────────────┘
                                  ▼
         ┌─────────────────────────────────────────────────┐
         │ XEM TRƯỚC ĐA TÁC VỤ & XÁC NHẬN AN TOÀN 1 CHẠM   │
         │ • Thẻ Giao dịch → TransactionRepository         │
         │ • Thẻ Lịch hẹn  → CalendarBloc / DeviceCalendar │
         │ • Thẻ Việc làm  → TaskBloc                      │
         │ • Thẻ Đi chợ    → DailyLifeBloc                 │
         │ • Ghi nhớ thói quen RFM + Hỗ trợ Hoàn tác ngay  │
         └─────────────────────────────────────────────────┘
```

### 2.1. Bảo Mật & Quyền Riêng Tư Chuẩn Ngân Hàng
1. **Lưu trữ khóa API bằng phần cứng (`NativeSecureVaultBridge`):** Khóa Gemini API của người dùng chỉ lưu trong **Android Keystore (`AES-256-GCM`)** cục bộ trên máy, truyền qua HTTP header `x-goog-api-key` (không bao giờ gắn vào URL query hay lưu lên Cloud Firestore, không bao giờ ghi ra log).
2. **Lá chắn ẩn danh dữ liệu nhạy cảm (`GeminiPrivacySanitizer`):** Trước khi gửi văn bản lên Gemini (khi bật chế độ *Ẩn thông tin cá nhân*), hệ thống tự động che số điện thoại Việt Nam, địa chỉ email, mã CCCD và chuỗi số tài khoản ngân hàng dài (`8–19` chữ số không đi kèm đơn vị tiền tệ) thành `[ẨN_BẢO_MẬT]`.
3. **Số tiền nguyên tuyệt đối (`int amountMinor`):** Gemini chỉ đóng vai trò hiểu ngữ nghĩa và trả về JSON cấu trúc chặt; toàn bộ phép tính số dư, ngân sách và chia hóa đơn đều được kiểm chứng lại ở tầng Domain bằng số nguyên `int`.

---

## 3. Các Điểm Chạm Giao Diện Được Nâng Cấp Đồng Bộ

1. **Nút `+` Trung Tâm (`QuickCreateHubSheet` — Thanh Lệnh Đa Năng):**
   - Hỗ trợ gõ **một câu bất kỳ** cho cả **Chi tiêu, Thu nhập, Lịch hẹn, Việc cần làm, Đi chợ** với thẻ xem trước đổi màu theo ngữ nghĩa ngay khi gõ.
   - Hiển thị **Gợi ý theo khung giờ thực tế** (Sáng / Trưa / Chiều / Tối) trộn cùng **Thói quen hay dùng gần đây (`RFM`)**.
   - Nút **`Hoàn tác`** ngay trên thông báo sau khi lưu nhanh để người dùng thao tác 1 chạm không chút đắn đo.
   - Nút chuyển tiếp sang **Phân tích sâu Gemini AI** khi gặp câu ghép dài hoặc hóa đơn nhiều món.

2. **Trang chủ `Hôm nay` (`TodayPage` — Nhịp Sống Thông Minh):**
   - Bổ sung dải **Gợi ý nhanh theo giờ & thói quen** gọn gàng, không tràn dòng, giúp ghi lại bữa sáng/cà phê/lịch họp chỉ bằng 1 chạm hoặc mở trợ lý Gemini AI.

3. **Trợ lý AI & Liên kết Gemini (`FinancialAiAssistantPage` & `FinancialAiSettingsPage`):**
   - Trang **Cài đặt AI (`/financial-ai-settings`)**: Thẻ **Liên kết Gemini AI** cho phép nhập khóa API (ẩn/hiện an toàn), chọn mô hình (`Gemini 2.5 Flash` tốc độ cao hoặc `Gemini 2.5 Pro` suy luận sâu), bật/tắt lá chắn ẩn thông tin nhạy cảm, và bấm **Kiểm tra kết nối** trực tiếp.
   - Trang **Trợ lý AI (`/financial-ai`)**: Chế độ kết hợp thông minh vừa bóc tách các khoản Thu/Chi chuẩn xác, vừa bóc tách thêm **Lịch hẹn, Việc cần làm, Món đi chợ** và hiển thị **Góc nhìn cố vấn Gemini** từ chính câu nói tự nhiên của người dùng, cho phép bấm lưu từng mục hoặc lưu tất cả trong 1 chạm.
