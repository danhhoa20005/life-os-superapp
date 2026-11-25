# LifeOS Super App — Design System 2.0 (`LifeOS — Tammy × Apple`)

Hệ thống thiết kế thống nhất trên toàn ứng dụng (`lib/app/theme/`, `lib/core/widgets/lifeos_design_system.dart`, `lib/core/widgets/trust_ux_widgets.dart`, `lib/core/widgets/smart_form_inputs.dart`, `lib/core/widgets/status_widgets.dart`), bảo toàn bản sắc thương hiệu xanh ngọc LifeOS, nút `+` trung tâm và bộ 32 icon phẳng 2D Duotone.

---

## 1. Bảng Màu Ngữ Nghĩa & Tương Phản WCAG 2.2 AA (`lib/app/theme/app_colors.dart`)

| Token | Light Mode | Tỷ lệ tương phản (Light) | Dark Mode | Tỷ lệ tương phản (Dark) | Mục đích |
|---|---|---:|---|---:|---|
| `primary` / `onPrimary` | `#0B7A2A` / `#FFFFFF` | **5.44 : 1** (Pass AA) | `#19C23E` / `#04260E` | **9.5+ : 1** (Pass AAA) | Hành động chính, điểm nhấn thương hiệu |
| `primarySubtle` | `#ECFDF3` | `#0B7A2A` trên `#ECFDF3`: **5.2 : 1** | `#163524` | `#19C23E` trên `#163524`: **6.4 : 1** | Nền huy hiệu tích cực, chip chọn |
| `background` | `#F6F8FA` | — | `#161B22` (luminance > 0.006) | — | Nền canvas dịu mắt (không đen tuyền gây chói) |
| `surface` | `#FFFFFF` | — | `#202731` (luminance > 0.015) | — | Thẻ nổi, bottom sheet, hộp thoại |
| `textPrimary` | `#0F172A` | **17.4 : 1** trên `#FFFFFF` | `#F8FAFC` | **14.3 : 1** trên `#202731` | Tiêu đề, số tiền, nội dung chính |
| `textSecondary` | `#5B6777` | **5.75 : 1** trên `#FFFFFF` | `#CBD5E1` | **9.6 : 1** trên `#202731` | Phụ đề, thời gian, mô tả phụ |
| `warning` / `warningSubtle` | `#B45309` / `#FEF3C7` | **5.02 : 1** trên `#FFFFFF` | `#FBBF24` / `#3B2D12` | **8.8 : 1** trên `#202731` | Chờ xác nhận, đang đồng bộ, cần kiểm tra |
| `error` / `errorSubtle` | `#DC2626` / `#FEE2E2` | **4.83 : 1** trên `#FFFFFF` | `#F87171` / `#3D1D1E` | **5.8 : 1** trên `#202731` | Lỗi đồng bộ, tranh chấp, hành động hủy |
| **High Contrast** | `highContrastLight` | Tăng viền đậm + `textSecondary` ≥ 7:1 | `highContrastDark` | Tăng viền sáng + chữ AAA | Bật tự động theo OS hoặc công tắc trong bảng `Aa` |

---

## 2. Hệ Thống Khoảng Cách & Bo Góc (`lib/app/theme/app_spacing.dart`)

- **Lưới chuẩn 4pt đầy đủ:** `4` (`xxs`), `8` (`xs`), `12` (`sm`), `16` (`md`), `20` (`lg`), `24` (`xl`), `32` (`xxl`), `40` (`xl2`), `48` (`xxxl`).
- **Bo góc nhất quán:** `radiusSm = 8`, `radiusMd = 12`, `radiusLg = 16`, `radiusXl = 24`, `radiusPill = 999`.
- **Công thái học chạm:** `minHitTarget = 48.0`, `buttonHeightM = 48.0`, `buttonHeightL = 52.0`, `inputHeight = 50.0`.
- **Breakpoint đáp ứng:** Mobile `< 840dp` (Floating Liquid Glass Dock với nút `+` ở chính giữa); Tablet `≥ 840dp` (`NavigationRail`, tối đa `maxContentWidth = 1000dp`).

---

## 3. Phân Cấp Chữ (`lib/app/theme/app_typography.dart`)

| Cấp độ | Style | Kích thước / Trọng lượng | Tabular Figures |
|---|---|---|---|
| **Display** | `displaySmall` | `32px / w800` | Bật (`FontFeature.tabularFigures()`) |
| **Headline** | `headlineMedium` | `25px / w800` | Bật |
| **Title** | `titleLarge / Medium / Small` | `19 / 16 / 14.5px / w700–w800` | Bật |
| **Body** | `bodyLarge / Medium / Small` | `16 / 14.5 / 13.2px / w500` | Hỗ trợ khi hiển thị số |
| **Label & Caption** | `labelLarge / Medium / Small` | `14 / 12.8 / 12px / w600–w700` | Bật trên `labelLarge` / `labelSmall` |
| **Financial Number** | `AppTypography.financialNumber(...)` | Tùy ngữ cảnh / `w800` | **Bắt buộc bật** để mọi chữ số VND căn thẳng cột không rung |

---

## 4. Thư Viện Component Chuẩn Hóa & Trạng Thái

| Nhóm Component | Triển khai chuẩn trong LifeOS | Trạng thái hỗ trợ |
|---|---|---|
| **App Bar & Navigation** | `LifeOsTopBrandHeader`, `LiquidGlassSlidingDock` (`+` trung tâm), `NavigationRail` | Default, Selected, Pressed, High Contrast, Keyboard Focus |
| **Buttons & FAB** | `LifeOsPrimaryCtaButton`, `FilledButton`, `OutlinedButton`, `IconButton` (≥48dp), `LiquidGlassJewelButton` | Default, Pressed, Disabled, Loading (chống double-tap), Focus |
| **Smart Form Inputs** | `LifeOsVndSmartAmountField`, `LifeOsRelativeDateTimePicker`, `TextField` chuẩn M3 | Default, Focused, Suggestions, Inline Validation Error, Draft Restored |
| **Search & Filter** | `OmniCommandPaletteSheet` (debounced + grouped + recent chips), `ChoiceChip`, `FilterChip` | Empty, Typing, Grouped Hits, Zero-Result Recovery |
| **Financial Trust & Status** | `FinancialTrustStatusBadge` (8 trạng thái), `DataVisibilityBadge`, `SemanticStatusBadge`, `CloudSyncIndicator`, `LifeOsOfflineSyncBanner` | Icon + Nhãn tiếng Việt + Viền + `Semantics` (không bao giờ chỉ dựa vào màu) |
| **Cards & Lists** | `ProHeroGradientCard`, `ProWalletCreditCard`, `ProFintechStatementTile`, `LifeOsSoftCard`, `LifeOsResponsiveIconGrid` | Loading Skeleton, Empty CTA, Content, Error Retry, Offline |
| **Feedback & Overlays** | `LifeOsTopToast` (đỉnh màn hình + `Hoàn tác`), `LiquidGlassSheetFrame`, `showDestructiveConfirmDialog`, `showLifeOsJustInTimePermissionRationale` | Info, Success, Warning, Error, Reduced Motion |
| **Biểu đồ & Icon** | `ProDonutChart` (`CustomPainter`), `ProCashflowPulseCard`, 32 Nano Banana Flat 2D Duotone Icons (`assets/icons/`) | Có `Semantics` đọc cho trình đọc màn hình |
