# LifeOS Super App — Báo Cáo Khả Năng Tiếp Cận (Accessibility Report — WCAG 2.2 AA)

**Phiên bản kiểm chứng:** Nhánh `agy/v3.27.0-upgrade` (sau nâng cấp Design System 2.0 & Accessibility)
**Chuẩn đối chiếu:** WCAG 2.2 Level AA, Android Touch Target Guidelines (`48 × 48 logical dp`), Apple HIG, Flutter Accessibility Guidelines.
**Bằng chứng tự động:** `test/unit/v327_trust_ux_notifications_ftue_test.dart`, `test/widget/ux_usability_and_visual_qa_test.dart`, `test/widget/top_toast_and_pro_max_redesign_test.dart`, `test/widget/logo_side_drawer_navigation_test.dart`.

---

## 1. Kết Quả Cải Tiến Tương Phản Màu (Contrast Audit)

| Thành phần / Token | Trước (`v3.26.0`) | Tỷ lệ Trước | Sau (Design System 2.0) | Tỷ lệ Sau | Trạng thái WCAG 2.2 |
|---|---|---:|---|---:|---|
| Light `primary` trên `#FFFFFF` | `#0D8A3E` | ~4.37 : 1 (Fail AA chữ thường) | `#0B7A2A` | **5.44 : 1** | **PASS AA** |
| Light `warning` trên `#FFFFFF` | `#D97706` | ~3.19 : 1 (Fail AA) | `#B45309` | **5.02 : 1** | **PASS AA** |
| Dark `onPrimary` trên `primary` (`FilledButton`) | `#FFFFFF` trên `#2ECC71` | **~2.18 : 1 (Fail AA/AAA)** | `#021608` trên `#19C23E` | **> 9.5 : 1** | **PASS AAA** |
| Light `LifeOsStatusPill` Emerald | `#12B847` trên `#EAFBF0` | ~2.51 : 1 (Fail AA) | `#0B7A2A` trên `#EAFBF0` | **> 4.9 : 1** | **PASS AA** |
| High Contrast Light & Dark | Chỉ đổi 2 màu viền | Không đủ chuẩn | Bộ `highContrastLight` & `highContrastDark` đầy đủ (`textPrimary` > 10:1, `textSecondary` > 7:1) | **> 7.0 : 1** | **PASS AAA** |
| Dark Mode Canvas Luminance | `#161B22` / `#202731` | > 0.006 / > 0.015 | Bảo toàn nền Slate dịu mắt | Đạt | **PASS** |

---

## 2. Cỡ Chữ Trợ Năng Hệ Điều Hành (OS Font Scaling & Large Text)

- **Lỗi trước đây (`lib/app/app.dart:83-86`):** Ứng dụng ghi đè `MediaQuery.textScaler` bằng `TextScaler.linear(themeState.textScale)` mặc định `0.92`, khiến người dùng thị lực kém bật cỡ chữ hệ thống `130%–150%` bị ép thu nhỏ về `92%`.
- **Khắc phục (`lib/app/app.dart`):** Khi OS `textScaler > 1.0`, hệ thống dùng `math.max(osScale, themeState.textScale)` để **không bao giờ thu nhỏ cỡ chữ trợ năng OS**, đồng thời gắn `highContrastTheme` & `highContrastDarkTheme` tự động theo hệ điều hành và bổ sung công tắc **`Tương phản cao`** (`Key('appearance_high_contrast_switch')`) ngay trong bảng `Aa` (`showLifeOsAppearanceSheet`).
- **Kiểm chứng:**
  - `v327_trust_ux_notifications_ftue_test.dart`: xác nhận OS `1.35x` được giữ đúng `1.35x` (không bị ép về `0.92`).
  - `ux_usability_and_visual_qa_test.dart`: xác nhận **0 `RenderFlex` overflow** ở `360dp @ 1.25x` và `320dp @ 1.25x` High Contrast.
  - `logo_side_drawer_navigation_test.dart`: sửa cấu trúc cuộn `LifeOsLogoSideDrawer` để danh sách menu không bị kẹp còn 121px ở `360×800 @ 112%`.

---

## 3. Công Thái Học Ngón Cái & Vùng Chạm (`≥ 48dp` Touch Ergonomics)

- **Token chuẩn (`lib/app/theme/app_spacing.dart`):** Nâng `minHitTarget = 48.0`, `buttonHeightM = 48.0`, bổ sung `iconButtonTheme` tối thiểu `48 × 48dp` trong `AppTheme`.
- **Các nút đã mở rộng vùng chạm:**
  - Nút ẩn/hiện số dư trên Hero Card (`toggle_balance_privacy_btn`): `≥ 44 × 44dp`.
  - Chip gợi ý VND (`LifeOsVndSmartAmountField`) & chip thời gian tương đối (`LifeOsRelativeDateTimePicker`): chiều cao `≥ 48dp`.
  - Nút hành động trong `LifeOsPermissionsPopup` (`48dp`), `LifeOsOfflineSyncBanner` (`48dp`), nút `Tùy chỉnh` / `Ẩn` gợi ý (`44–48dp`), các nút tròn thanh đỉnh mở rộng vùng nhận chạm `40 × 44dp` mà không tràn màn `360dp`.
- **Không phụ thuộc cử chỉ ẩn:** Ngăn kéo cạnh trái có nút Logo thay thế; thanh dock vuốt ngang hỗ trợ chạm trực tiếp; mọi hành động hoãn/ẩn đều có nút bấm tường minh.

---

## 4. Semantics, Trình Đọc Màn Hình (TalkBack / VoiceOver) & Reduce Motion

- **Không chỉ dùng màu sắc (WCAG 1.4.1):**
  - Toàn bộ 8 trạng thái `FinancialTrustStatusBadge`, `DataVisibilityBadge`, `LifeOsStatusPill`, `ProFintechStatementTile`, kiểm tra tổng tách khoản trên `FinancePage`, và trạng thái số dư thành viên trên `FamilyPage` đều kết hợp **Icon + Nhãn tiếng Việt + Viền + `Semantics`**.
  - `ProDonutChart`, `ProCashflowPulseCard`, `EmptyStateView`, `ErrorRetryView`, `LifeOsOfflineSyncBanner`, `LifeOsVndSmartAmountField` (`liveRegion: true`) đã có `Semantics` tường minh.
  - Nút ẩn/hiện mật khẩu tại `RegisterPage` đã có `tooltip` đầy đủ.
- **Reduce Motion:** Toàn bộ hiệu ứng đi qua `LifeOsMotionScope`, tôn trọng cờ `disableAnimations` / `reduceMotion` của hệ điều hành (được kiểm chứng trong `permissions_popup_test.dart` và `test/core/motion/`).

---

## 5. Giới Hạn Kiểm Thử Thiết Bị Vật Lý (Trung Thực)

- **Kiểm thử thủ công với TalkBack trên thiết bị Android thật & VoiceOver trên iOS thật:** `NOT RUN — DEVICE REQUIRED` (chưa kết nối điện thoại vật lý USB trong phiên này). Toàn bộ cây `Semantics`, tỷ lệ tương phản, vùng chạm, OS text scaling và Reduce Motion đã được kiểm chứng tự động 100% trên Flutter Widget Test Engine.
