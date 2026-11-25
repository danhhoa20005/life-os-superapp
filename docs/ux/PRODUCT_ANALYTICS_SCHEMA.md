# LifeOS Super App — Product Analytics & Privacy-Safe UX Metrics Schema

**Nguyên tắc cốt lõi:** Chỉ đo các chỉ số phản ánh **giá trị thực sự và mức độ dễ dùng** (task completion, friction, error recovery), **100% xử lý cục bộ trên thiết bị**, **tuyệt đối không thu thập PII hoặc nội dung tài chính**, và **opt-in rõ ràng** nếu về sau người dùng đồng ý chia sẻ ẩn danh.

---

## 1. Chính Sách Dữ Liệu & Phạm Vi Lưu Giữ

| Thuộc tính | Quy định bắt buộc trong LifeOS |
|---|---|
| **Nơi lưu trữ** | Cục bộ trên thiết bị qua `NativeSecureVaultBridge` (`LocalBehaviorStore` / `UxMetricsTracker`), mã hóa AES-256-GCM trên Android Keystore. |
| **Phân vùng** | Riêng biệt theo `userId` (`__u_<uid>`); xóa sạch RAM cache khi đăng xuất. |
| **Chính sách lưu giữ (Retention)** | Cửa sổ trượt tối đa `200` sự kiện hành vi cấu trúc gần nhất + bộ đếm tổng hợp cục bộ; người dùng có nút **`Đặt lại dữ liệu hành vi`** xóa tức thì 100%. |
| **Gửi ra máy chủ ngoài** | **TẮT MẶC ĐỊNH (0 byte gửi ra ngoài).** Không gửi bất kỳ dữ liệu tài chính, ghi chú, tài liệu, transcript hay sức khỏe lên analytics server. |
| **Phát sự kiện trong `build()`** | **CẤM TUYỆT ĐỐI.** Chỉ phát sự kiện từ hành động tương tác thực tế của người dùng hoặc hoàn tất luồng nghiệp vụ. |

---

## 2. Schema Chỉ Số UX Đầy Đủ (`schemaVersion: 2`)

| Tên chỉ số | Công thức / Đơn vị | Mục đích đánh giá UX | Trạng thái đo hiện tại |
|---|---|---|---|
| **Task Success Rate** | `taskSuccessCount / (taskSuccessCount + taskFailureCount)` | Tỷ lệ hoàn thành tác vụ chính không gặp lỗi chặn | Đo tự động trong widget usability test; dữ liệu người dùng thật: `NOT_MEASURED` |
| **Time on Task** | `durationMs` (ms) từ lúc mở luồng đến khi BLoC xác nhận | Tốc độ hoàn thành tác vụ nhanh | Đo tự động bằng stopwatch trong test; dữ liệu người dùng thật: `NOT_MEASURED` |
| **First-click Success** | Tỷ lệ chọn đúng lối vào ngay chạm đầu tiên | Đánh giá độ rõ ràng của IA và nhãn tiếng Việt | Đo tự động theo kịch bản persona; dữ liệu người dùng thật: `NOT_MEASURED` |
| **First-time-to-value (FTV)** | Thời gian từ kết thúc FTUE đến giao dịch/lịch đầu tiên | Hiệu quả Onboarding & First-Action Tip | Theo dõi cục bộ `UxMetricsTracker`; dữ liệu người dùng thật: `NOT_MEASURED` |
| **Average Steps per Task** | Số lần chạm trung bình (`stepCount`) cho mỗi tác vụ | Kiểm chứng mục tiêu 1–3 chạm | Đo tĩnh + kiểm thử tự động trong `USER_JOURNEY_MAPS.md` |
| **Form Abandonment Rate** | `formAbandonCount / formOpenCount` | Phát hiện form rườm rà hoặc mất bản nháp | Bộ đếm cục bộ `UxMetricsTracker` |
| **Input Error Rate** | `validationErrorCount / formSubmitCount` | Phát hiện lỗi định dạng VND / ngày giờ | Bộ đếm cục bộ `UxMetricsTracker` |
| **Undo Rate** | `undoCount / financialCreateCount` | Theo dõi mức độ nhập nhầm và giá trị nút Hoàn tác | Bộ đếm cục bộ `UxMetricsTracker` |
| **Search Success Rate** | `searchResultSelected / searchPerformed` | Độ chính xác tìm kiếm & từ điển đồng nghĩa | Bộ đếm cục bộ `UxMetricsTracker` |
| **Zero-result Search Rate** | `zeroResultSearchCount / searchPerformed` | Phát hiện từ khóa người Việt còn thiếu đồng nghĩa | Bộ đếm cục bộ `UxMetricsTracker` |
| **Recommendation Acceptance Rate** | `recommendationAccepted / recommendationShown` | Đánh giá độ hữu ích thực sự của gợi ý ngữ cảnh | Bộ đếm cục bộ `UxMetricsTracker` |
| **Recommendation Dismissal Rate** | `recommendationDismissed / recommendationShown` | Giảm gợi ý gây nhiễu bằng `DismissalPenalty` | Bộ đếm cục bộ `UxMetricsTracker` |
| **Notification Opt-out Rate** | Số danh mục bị tắt / tổng số danh mục thông báo | Phát hiện nhóm thông báo gây phiền | Tính cục bộ từ `NotificationExperiencePrefs` |
| **Accessibility Defect Count** | Số lỗi tương phản / vùng chạm < 48dp / thiếu Semantics / overflow | Bảo đảm WCAG 2.2 AA & công thái học | Đo tự động bằng bộ kiểm thử Accessibility & Multi-Viewport |
| **System Usability Scale (SUS)** | Thang 0–100 từ bảng hỏi 10 câu trên người tham gia thật | Chuẩn hóa cảm nhận dễ sử dụng toàn cục | **`NOT_MEASURED`** *(chưa có nghiên cứu người dùng thật)* |
| **Crash-free Sessions** | Tỷ lệ phiên không crash | Độ ổn định production | **`NOT_MEASURED`** *(chưa phát hành telemetry production)* |

---

## 3. Khẳng Định Chống Lạm Dụng Chỉ Số (Anti-Vanity-Metric Rule)

LifeOS **không bao giờ** coi số lần mở app cao hay thời gian ở lại màn hình lâu là thành công. Một ứng dụng quản lý đời sống xuất sắc giúp người dùng **hoàn thành việc trong 5–15 giây và quay lại cuộc sống thực**.
