# LifeOS Super App — Kế Hoạch & Kết Quả Kiểm Thử Khả Năng Sử Dụng (Usability Test Plan)

> **Minh bạch phương pháp:** Các kịch bản dưới đây được thực thi bằng **Automated Task-Based Widget Usability Tests** (`test/widget/ux_usability_and_visual_qa_test.dart`, `test/unit/v327_ux_forms_drafts_search_test.dart`, `test/unit/user_behavior_engine_v2_test.dart`, `test/unit/v327_trust_ux_notifications_ftue_test.dart`).
> **Nghiên cứu người dùng có người tham gia thật & chỉ số SUS:** **`NOT_MEASURED`** *(chưa tuyển người tham gia thật trong phiên kỹ thuật này; không coi kiểm thử tự động là nghiên cứu người dùng thực tế)*.

---

## 1. Ma Trận 4 Nhóm Kịch Bản Kiểm Thử (Section 23)

| Nhóm | Kịch bản kiểm thử | File kiểm thử tự động | Trạng thái tự động |
|---|---|---|---|
| **1. Người mới** | Khởi động lần đầu vào Onboarding gọn nhẹ, KHÔNG bật popup xin quyền Android hàng loạt | `ux_usability_and_visual_qa_test.dart` (Persona 1) & `permissions_popup_test.dart` | **PASS** |
| **1. Người mới** | Chọn nhu cầu quan tâm & bấm `Bỏ qua` (lưu trạng thái bỏ qua theo từng `userId`) | `ux_usability_and_visual_qa_test.dart` & `v327_trust_ux_notifications_ftue_test.dart` | **PASS** |
| **1. Người mới** | Xem thẻ hướng dẫn thao tác đầu tiên (`Bắt đầu trong 10 giây`), tìm cách ghi khoản chi đầu tiên & ẩn gợi ý | `user_behavior_ux_test.dart` | **PASS** |
| **1. Người mới** | Ẩn số dư 1 chạm (`•••••••• ₫`) với phản hồi Top Toast | `ux_usability_and_visual_qa_test.dart` & `top_toast_and_pro_max_redesign_test.dart` | **PASS** |
| **1. Người mới** | Tìm chức năng xe cộ (`thay nhot`) và bảo mật/quyền riêng tư (`mat khau`) qua Global Search | `ux_usability_and_visual_qa_test.dart` & `v327_ux_forms_drafts_search_test.dart` | **PASS** |
| **2. Thường xuyên** | Ghi nhanh khoản chi bằng chip gợi ý không tự ghi đè (`35` → `35.000 ₫`) + xem dòng xác nhận số tiền | `ux_usability_and_visual_qa_test.dart` (Persona 2) & `v327_ux_forms_drafts_search_test.dart` | **PASS** |
| **2. Thường xuyên** | Gõ câu tự nhiên đa tác vụ (`Ăn sáng 35k, đổ xăng 70k và nhắc tôi họp vào 14h`) có xem trước & bật/tắt từng nháp | `v327_ux_forms_drafts_search_test.dart` | **PASS** |
| **2. Thường xuyên** | Tìm giao dịch cũ (`pho`), chia tiền thủ công từ `+ → Chia tiền nhóm`, mở thu âm 1 chạm | `ux_usability_and_visual_qa_test.dart` & `smart_voice_auto_endpoint_and_confirm_test.dart` | **PASS** |
| **2. Thường xuyên** | Tạo việc làm / nhắc nhở bằng chip thời gian tương đối (`Hôm nay`, `Ngày mai`, `Cuối tuần`, `15 phút nữa`, `Thứ Hai tuần sau`) | `v327_ux_forms_drafts_search_test.dart` | **PASS** |
| **3. Gia đình** | Phân biệt rõ `Cá nhân · Riêng tư` trên ví cá nhân vs `Gia đình · Chia sẻ` trên không gian gia đình | `ux_usability_and_visual_qa_test.dart` (Persona 3) | **PASS** |
| **3. Gia đình** | Hiển thị chính xác toàn bộ 8 trạng thái `FinancialTrustStatusBadge` và 9 trạng thái chi quỹ chung | `v327_trust_ux_notifications_ftue_test.dart` | **PASS** |
| **3. Gia đình** | RBAC Global Search: dữ liệu riêng tư của thành viên khác không bao giờ lộ trong tìm kiếm | `v327_ux_forms_drafts_search_test.dart` | **PASS** |
| **4. Bất thường** | **Bấm nút lưu liên tục (Double-tap):** chỉ tạo đúng **1** giao dịch (0 trùng lặp) | `ux_usability_and_visual_qa_test.dart` & `v327_ux_forms_drafts_search_test.dart` | **PASS** |
| **4. Bất thường** | **Nhập sai dữ liệu / Lỗi BLoC:** hiện lỗi nội tuyến rõ ràng, giữ mở sheet & không mất dữ liệu vừa nhập | `v327_ux_forms_drafts_search_test.dart` | **PASS** |
| **4. Bất thường** | **Đổi tài khoản / Quay lại giữa chừng:** bản nháp `LocalDraftStore` & dữ liệu hành vi phân vùng tuyệt đối theo `userId` | `ux_usability_and_visual_qa_test.dart`, `v327_ux_forms_drafts_search_test.dart`, `user_behavior_engine_v2_test.dart` | **PASS** |
| **4. Bất thường** | **Từ chối cấp quyền Just-in-Time:** các tính năng còn lại tiếp tục hoạt động bình thường | `ux_usability_and_visual_qa_test.dart` & `permissions_popup_test.dart` | **PASS** |
| **4. Bất thường** | **Mất mạng / Đồng bộ thất bại:** hiển thị `LifeOsOfflineSyncBanner` + nút `Thử đồng bộ lại` | `ux_usability_and_visual_qa_test.dart` & `v327_trust_ux_notifications_ftue_test.dart` | **PASS** |

---

## 2. Giao Thức Đề Xuất Cho Nghiên Cứu Người Dùng Thật (Trong Giai Đoạn Beta)

Khi có người dùng thật (tối thiểu 5–8 người đại diện 4 nhóm: Sinh viên, Nhân viên văn phòng, Gia đình, Người lớn tuổi):
1. Giao 8 tác vụ thực tế không gợi ý đường đi (*Think-Aloud Protocol*) trên thiết bị Android thực tế.
2. Ghi nhận riêng: tỷ lệ hoàn thành (`Task Success Rate`), lượt chạm đầu tiên đúng (`First-click Success`), thời gian hoàn thành (`Time on Task`), điểm ngập ngừng/lỗi thao tác và thang điểm `SUS` chuẩn 10 câu hỏi.
3. Hiệu chỉnh trọng số `RecommendationEngine` từ dữ liệu chấp nhận/ẩn thực tế (opt-in) sau tối thiểu 2 tuần sử dụng.
