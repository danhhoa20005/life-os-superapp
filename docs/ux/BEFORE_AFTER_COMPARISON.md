# LifeOS Super App — So Sánh Trước & Sau Nâng Cấp UI/UX (Before vs After Comparison)

**Baseline Trước:** Commit `3e11941` (`v3.27.0+45` kế thừa UX từ `v3.26.0+44`), ảnh lưu tại `docs/ux/screenshots/before/`.
**Phiên Bản Sau:** Nhánh `agy/v3.27.0-upgrade` sau 3 luồng nâng cấp UI/UX & Human Behavior Engineering + Visual QA, ảnh lưu tại `docs/ux/screenshots/after/`.

---

## 1. Bảng Đối Chiếu Toàn Diện Trước → Sau

| Hạng mục | Trước Nâng Cấp (`docs/ux/screenshots/before/`) | Sau Nâng Cấp (`docs/ux/screenshots/after/`) | Bằng chứng kiểm chứng |
|---|---|---|---|
| **Thanh điều hướng & Icon** | Nút `+` ở giữa thanh dock, 32 icon 2D Duotone, nút `Menu` 1 chạm trên đỉnh | **Bảo toàn 100%** nút `+` trung tâm, 32 icon 2D phẳng & `Menu` 1 chạm; mở rộng vùng chạm tiện ích đỉnh & sửa cuộn Drawer ở cỡ chữ lớn | `ux_01_today_light.png`, `top_toast_and_pro_max_redesign_test.dart` |
| **Behavior Engine & Dashboard (`TodayPage`)** | `UserBehaviorPrefs` rò khóa quyền & giọng nói giữa tài khoản; lỗi trung bình giờ qua đêm (`23h+1h=12h`); chưa có gợi ý theo ngữ cảnh, tắt/đặt lại hành vi hay FTUE tip; báo `'Đang đồng bộ'` dù chưa kết nối | Kiến trúc tách lớp `lib/core/behavior/` (Domain + Engine 7 yếu tố chuẩn hóa + `LocalBehaviorStore` theo `userId` + `UxMetricsTracker`); thẻ `Gợi ý phù hợp` có giải thích, nút `Ẩn` (DismissalPenalty), sheet `Tùy chỉnh` (bật/tắt, đổi nhu cầu, đặt lại); thẻ FTUE `Bắt đầu trong 10 giây`; nhãn trung thực `'Lưu cục bộ an toàn'` & `'Ví cá nhân · Riêng tư'` | `ux_01_today_light.png`, `user_behavior_engine_v2_test.dart`, `user_behavior_ux_test.dart` |
| **Quick Create Hub (`+`) & Forms** | Thiếu `Chuyển ví`, `Nhắc nhở`, `Chi phí xe`; `Chia tiền nhóm` mở nhầm thu âm; double-tap tạo 2 GD trùng; đóng sheet trước khi BLoC lưu gây mất bản nháp; bàn phím số không nhập được `35k`/`1tr2`; thiếu chip `Cuối tuần`, `15 phút nữa`, `Thứ Hai tuần sau` | Hub 3 chế độ đầy đủ 10 thao tác + form chia tiền thủ công; `LifeOsVndSmartAmountField` (chip gợi ý không tự ghi đè + dòng `"Số tiền sẽ lưu"` dạng tabular); `LifeOsRelativeDateTimePicker` (5 mốc + giải nghĩa tường minh); `LocalDraftStore` mã hóa theo `userId`; chống double-tap bằng `operationId` duy nhất & chờ BLoC xác nhận | `ux_03_quick_create_hub.png`, `v327_ux_forms_drafts_search_test.dart`, `ux_usability_and_visual_qa_test.dart` |
| **Global Search (`🔍`)** | Không hiểu `thay nhớt`, `tiền nhà`, `mật khẩu`, `chia bill`, `tiền điện` <-> `evn`; danh sách phẳng không nhóm; không có lịch sử tìm kiếm / nút xóa | 9 nhóm từ đồng nghĩa 2 chiều, phân nhóm theo loại (`SearchDomainKind.labelVi`), lưu & xóa lịch sử tìm kiếm theo từng tài khoản, debounce `120ms`, lọc RBAC nghiêm ngặt trên cả `dailySnap` | `ux_05_omni_search_grouped.png`, `v327_ux_forms_drafts_search_test.dart` |
| **FTUE Onboarding & Xin Quyền** | Bật popup xin nhiều quyền Android & FCM ngay khi khởi động; Onboarding chứa mã mời giả `GD-F7K9M2`, avatar giả, tab `'Calendar'`, không có nút `Bỏ qua`, không chọn nhu cầu; `VerifyOtpPage`/`ResetPasswordPage` giả mạo thành công | **0 popup xin quyền khi khởi động**; hộp thoại Just-in-Time Rationale giải thích đủ 4 câu hỏi; Onboarding ngắn có nút `Bỏ qua` theo tài khoản & 6 chip chọn nhu cầu; xóa toàn bộ dữ liệu giả và luồng đặt lại mật khẩu giả | `ux_08_onboarding_ftue.png`, `permissions_popup_test.dart`, `v327_trust_ux_notifications_ftue_test.dart` |
| **Financial Trust UX & Lỗi** | Gộp 6 trạng thái chi quỹ thành `CHỜ DUYỆT`; hardcode `'Khớp mẫu · Chờ duyệt'`; GD đã đảo vẫn hiện tick xanh verified; lộ 45+ raw exception `$e`/`err.toString()` | Bộ 8 `FinancialTrustStatusBadge` (icon + nhãn + viền + Semantics) phủ đủ giao dịch, duyệt tự động, quỹ 9 trạng thái và gia đình; GD đảo hiện biểu tượng hoàn tác + `'Đã đảo bút toán'`; **0 raw exception** rò ra UI; thêm `DataVisibilityBadge` & `LifeOsOfflineSyncBanner` | `ux_04_finance_light.png`, `v327_trust_ux_notifications_ftue_test.dart` |
| **Notification Experience Engine** | 3 tầng ưu tiên, `dedupKey` gắn `$idx` lỗi dedup, mất trạng thái đọc/hoãn khi thoát màn, không có Giờ yên lặng / Tóm tắt ngày / Bật tắt từng loại | 4 tầng (`Khẩn cấp`, `Đúng giờ`, `Cần xử lý`, `Thông tin`), dedup ổn định, phân nhóm theo loại, lưu bền vững theo `userId`, Hoãn 4 mức (`15p`/`1h`/`Tối nay`/`Ngày mai`), Giờ yên lặng qua đêm (`22:00–07:00`), Tóm tắt hằng ngày & bật/tắt theo danh mục | `ux_06_notifications_4tier.png`, `v327_trust_ux_notifications_ftue_test.dart` |
| **Design System 2.0 & Accessibility** | Nút chính Dark mode chữ trắng trên `#2ECC71` chỉ **2.18:1** (Fail AA); Light primary `#0D8A3E` (4.37:1); ép OS text scale xuống `0.92`; thiếu `40dp` spacing & `48dp` hit target; không có High Contrast trong `Aa` | Primary Light `#0B7A2A` (**5.44:1**), Warning `#B45309` (**5.02:1**), Dark `onPrimary` `#021608` trên `#19C23E` (**> 9.5:1 AAA**); bảo toàn OS `textScaler >= 1.0`; thêm `xl2 = 40dp`, `minHitTarget = 48dp`, bảng High Contrast hoàn chỉnh & công tắc ngay trong `Aa` | `ux_02_today_dark.png`, `ux_07_today_high_contrast_large.png`, `v327_trust_ux_notifications_ftue_test.dart` |

---

## 2. Ảnh Đối Chiếu Trực Tiếp Trong Repository

- **Trước (`3e11941`):**
  - `docs/ux/screenshots/before/01_today_light.png`
  - `docs/ux/screenshots/before/02_today_dark.png`
  - `docs/ux/screenshots/before/03_quick_create_hub.png`
  - `docs/ux/screenshots/before/04_finance_light.png`
  - `docs/ux/screenshots/before/05_onboarding_ftue.png`
- **Sau (Nâng cấp UX 2.0):**
  - `docs/ux/screenshots/after/ux_01_today_light.png`
  - `docs/ux/screenshots/after/ux_02_today_dark.png`
  - `docs/ux/screenshots/after/ux_03_quick_create_hub.png`
  - `docs/ux/screenshots/after/ux_04_finance_light.png`
  - `docs/ux/screenshots/after/ux_05_omni_search_grouped.png`
  - `docs/ux/screenshots/after/ux_06_notifications_4tier.png`
  - `docs/ux/screenshots/after/ux_07_today_high_contrast_large.png`
  - `docs/ux/screenshots/after/ux_08_onboarding_ftue.png`
