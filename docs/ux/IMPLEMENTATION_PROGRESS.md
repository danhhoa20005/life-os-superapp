# LifeOS Super App — Nhật Ký Tiến Độ Triển Khai UI/UX & Human Behavior Engineering

**Nhánh làm việc:** `agy/v3.27.0-upgrade`
**Baseline đối chiếu:** `v3.26.0+44` (`4bc371e`) & nhánh kỹ thuật `v3.27.0+45` (`3e11941`)
**Ngày cập nhật:** 25/11/2026
**Nguyên tắc bảo toàn:** Giữ nguyên 100% nút `+` ở giữa thanh điều hướng dưới (`LiquidGlassSlidingDock`), nút `Menu` 1 chạm trên thanh đỉnh, 32 icon Nano Banana Flat 2D Duotone (`assets/icons/`), toàn bộ kiến trúc `flutter_bloc` (không `Cubit`), không `.showSnackBar(`, không `TextOverflow` trong `lib/`, thuần Dart ở `domain/` và `lib/core/behavior/{behavior_domain,behavior_engine}.dart`.

---

## 1. Tiến Độ Theo Từng Wave Thực Thi

| Wave | Phạm vi & Vai trò thực thi | Commit / Bằng chứng | Trạng thái |
|---|---|---|---|
| **Wave 0 — Audit & Baseline** | 2 luồng kiểm toán song song chỉ đọc (`architect` + `research`) rà soát toàn bộ kiến trúc IA, Behavior Engine, Quick Create, Forms, Search, FTUE, Permissions, Trust UX, Notifications, Design System & Accessibility; chụp 5 ảnh baseline trước thay đổi (`docs/ux/screenshots/before/01..05_*.png`) tại commit `3e11941`. | `docs/ux/UX_MASTER_AUDIT.md`, `docs/ux/screenshots/before/` | **DONE** |
| **Wave 1A — Quick Create, Smart Forms, Drafts & Global Search 2.0** | Worktree độc lập (`developer` subagent `d6386ddb`): triển khai `LocalDraftStore` phân vùng theo `userId` & tự xóa khi đăng xuất; `LifeOsVndSmartAmountField` (chip gợi ý không tự ghi đè + dòng xác nhận dạng tabular); `LifeOsRelativeDateTimePicker` (5 mốc thời gian + giải nghĩa tường minh); `QuickCreateHubSheet` 3 chế độ đủ 10 thao tác + form chia tiền thủ công + khóa chống double-tap bằng `operationId` duy nhất; `VietnameseSearchMatcher` + `GlobalSearchAndCommandEngine` + `OmniCommandPaletteSheet` với từ điển đồng nghĩa 2 chiều, phân nhóm theo miền dữ liệu, lịch sử tìm kiếm lưu/xóa theo tài khoản, debounce 120ms & RBAC nghiêm ngặt. | Commit `e1b42e2`, `test/unit/v327_ux_forms_drafts_search_test.dart` | **DONE & INTEGRATED** |
| **Wave 1B — Behavior Engine 2.0 & Adaptive Dashboard** | Worktree độc lập (`developer` subagent `20b053f7`): tách lớp `lib/core/behavior/` (`behavior_domain.dart`, `behavior_engine.dart` thuần Dart, `local_behavior_store.dart` phân vùng theo `userId` + `UxMetricsTracker`); công thức xếp hạng 7 yếu tố chuẩn hóa (`TimeRelevance`, `Frequency`, `Recency`, `Context`, `Urgency`, `Habit`, `DismissalPenalty`); trung bình giờ tròn qua nửa đêm (circular mean); nâng cấp `UserBehaviorPrefs` phân tách toàn bộ khóa theo `userId`; nâng cấp `TodayPage` với phụ đề theo nhịp ngày, nhãn đồng bộ trung thực (`Lưu cục bộ an toàn`), pill phạm vi riêng tư, thẻ FTUE `Bắt đầu trong 10 giây`, thẻ `Gợi ý phù hợp` minh bạch có nút `Ẩn` & bảng `Tùy chỉnh` (bật/tắt, đổi nhu cầu, đặt lại dữ liệu hành vi). | Commit `1e27fec`, `test/unit/user_behavior_engine_v2_test.dart`, `test/unit/user_behavior_ux_test.dart` | **DONE & INTEGRATED** |
| **Wave 1C — FTUE, JIT Permissions, 8-State Trust UX, 4-Tier Notifications, Design System 2.0 & Sanitization** | Worktree độc lập (`developer` subagent `68d31be7`): gỡ bỏ toàn bộ xin quyền hàng loạt khi khởi động; chuẩn hóa Just-in-Time 4-part Rationale (`LifeOsPermissionsPopup`); nâng cấp `OnboardingPrivacyPage` có nút `Bỏ qua` lưu theo `userId` + 6 chip nhu cầu + xóa dữ liệu giả (`GD-F7K9M2`, avatar giả, tab `Calendar`); gỡ luồng `VerifyOtpPage`/`ResetPasswordPage` giả mạo; xây dựng bộ 8 trạng thái `FinancialTrustStatusBadge` + `DataVisibilityBadge` + `LifeOsOfflineSyncBanner` áp dụng cho `FinancePage`, `AutoTransactionReviewPage`, `FamilyPage`, `ProFintechStatementTile`; nâng cấp `SmartInboxEngine` 4 tầng + dedup chuẩn + Quiet Hours qua đêm + Daily Digest + Category opt-in/out + Snooze đa mức lưu bền vững theo `userId`; nâng cấp bảng màu WCAG 2.2 AA/AAA (`#0B7A2A`, `#B45309`, Dark `onPrimary #021608` trên `#19C23E`), High Contrast Light/Dark + nút bật trong `Aa`, bảo toàn OS `textScaler >= 1.0`, `minHitTarget = 48dp`, `xl2 = 40dp`, dọn sạch 45+ điểm lộ raw exception. | Commit `dedcdfc`, `test/widget/permissions_popup_test.dart`, `test/unit/v327_trust_ux_notifications_ftue_test.dart` | **DONE & INTEGRATED** |
| **Wave 2 — Integration Polish, Multi-Viewport Visual QA, Usability & Golden Suite** | Lead tích hợp và kiểm chứng chéo toàn repo: (1) Nối `LocalDraftStore.clearAllInMemoryCaches()` vào `AuthBloc` khi đăng xuất; (2) Sửa cuộn `LifeOsLogoSideDrawer` để cỡ chữ lớn `112%` giữ vùng cuộn menu `> 460px`; (3) Sửa tràn `2.5px` ở `finance_page.dart:4228` (`Row` → `Wrap`) và `LifeOsTopBrandHeader` `Spacer()` khi `subtitle == null`; (4) Tinh gọn bố cục `TodayPage` để toàn bộ Hero CTA nằm trọn trên thanh dock và thẻ tiện ích dưới không bị đẩy khuất sau tiêu đề khi cuộn; (5) Viết mới `test/widget/ux_usability_and_visual_qa_test.dart` (4 nhóm persona + 8 cấu hình màn hình `320dp`–`900dp`) và `test/widget/ux_golden_qa_test.dart` (`8` ảnh Golden Regression); (6) Hoàn thiện bộ `18/18` tài liệu `docs/ux/` và đối chiếu `5` ảnh BEFORE vs `8` ảnh AFTER. | Commit Wave 2 trên `agy/v3.27.0-upgrade`, `docs/ux/` (`18` file + `13` ảnh) | **DONE** |

---

## 2. Bảng Đối Chiếu Đóng 12 Hạng Mục Kiểm Toán (`UX-001` → `UX-012`)

| Mã Audit | Mức độ | Trạng thái | File triển khai chính | Kiểm thử xác minh |
|---|---|---|---|---|
| **UX-001** | P0 | **RESOLVED** | `daily_life_repository_impl.dart`, `pro_utilities_repository_impl.dart`, `document_vault_repository_impl.dart`, `daily_life_bloc.dart` | `v327_trust_ux_notifications_ftue_test.dart` |
| **UX-002** | P0 | **RESOLVED** | `trust_ux_widgets.dart`, `finance_page.dart`, `auto_tx_and_report_pages.dart`, `pro_max_widgets.dart`, `family_page.dart` | `v327_trust_ux_notifications_ftue_test.dart`, `ux_usability_and_visual_qa_test.dart` |
| **UX-003** | P0 | **RESOLVED** | `quick_create_hub_sheet.dart`, `local_draft_store.dart`, `auth_bloc.dart` | `v327_ux_forms_drafts_search_test.dart`, `ux_usability_and_visual_qa_test.dart` |
| **UX-004** | P0 | **RESOLVED** | `app_colors.dart`, `app_theme.dart`, `lifeos_design_system.dart` | `v327_trust_ux_notifications_ftue_test.dart`, `ux_golden_qa_test.dart` |
| **UX-005** | P0 | **RESOLVED** | `auth_pages.dart` (`VerifyOtpPage`, `ResetPasswordPage`) | `v327_trust_ux_notifications_ftue_test.dart` |
| **UX-006** | P1 | **RESOLVED** | `app_router.dart`, `notification_ingestion_bloc.dart`, `lifeos_permissions_popup.dart`, `auth_pages.dart` (`OnboardingPrivacyPage`) | `permissions_popup_test.dart`, `v327_trust_ux_notifications_ftue_test.dart`, `ux_usability_and_visual_qa_test.dart` |
| **UX-007** | P1 | **RESOLVED** | `lib/core/behavior/*`, `user_behavior_prefs.dart`, `today_page.dart` | `user_behavior_engine_v2_test.dart`, `user_behavior_ux_test.dart` |
| **UX-008** | P1 | **RESOLVED** | `quick_create_hub_sheet.dart`, `smart_form_inputs.dart` | `v327_ux_forms_drafts_search_test.dart`, `ux_usability_and_visual_qa_test.dart` |
| **UX-009** | P1 | **RESOLVED** | `vietnamese_search_matcher.dart`, `global_search_and_command_engine.dart`, `omni_command_palette_sheet.dart` | `v327_ux_forms_drafts_search_test.dart`, `ux_usability_and_visual_qa_test.dart` |
| **UX-010** | P1 | **RESOLVED** | `smart_inbox_engine.dart`, `activity_and_settings_pages.dart` | `v327_trust_ux_notifications_ftue_test.dart`, `ux_golden_qa_test.dart` |
| **UX-011** | P2 | **RESOLVED** | `app.dart`, `app_spacing.dart`, `app_typography.dart`, `lifeos_logo_side_drawer.dart`, `lifeos_design_system.dart`, `status_widgets.dart` | `v327_trust_ux_notifications_ftue_test.dart`, `logo_side_drawer_navigation_test.dart`, `ux_usability_and_visual_qa_test.dart` |
| **UX-012** | P2 | **RESOLVED** | `family_page.dart`, `finance_page.dart`, `today_page.dart`, `status_widgets.dart`, `auth_pages.dart` | `top_toast_and_pro_max_redesign_test.dart`, `user_behavior_ux_test.dart`, `ux_usability_and_visual_qa_test.dart` |

---

## 3. Hạng Mục Chưa Thực Hiện / Cần Phần Cứng Hoặc Nghiên Cứu Ngoài

- **Kiểm thử thủ công TalkBack / VoiceOver trên thiết bị Android/iOS vật lý:** `NOT RUN — DEVICE REQUIRED`.
- **Nghiên cứu người dùng thực tế (5–8 người tham gia) & chấm điểm thang đo SUS:** `NOT_MEASURED` (kế hoạch kiểm chứng thực địa đã ghi rõ trong `docs/ux/USABILITY_TEST_PLAN.md`).
- **Số liệu Crash-Free Sessions & Retention Production:** `NOT_MEASURED` (chưa phát hành production và không tự động đẩy git/release khi chưa được người dùng ủy quyền).
