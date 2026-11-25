# LifeOS Super App — Báo Cáo Kiểm Thử Hiển Thị & Golden Visual QA (Visual QA Report)

**Bộ kiểm thử:** `test/widget/ux_usability_and_visual_qa_test.dart`, `test/widget/ux_golden_qa_test.dart`, `test/widget/top_toast_and_pro_max_redesign_test.dart`
**Thư mục ảnh đối chiếu:**
- Trước nâng cấp (commit baseline `3e11941`): `docs/ux/screenshots/before/` (`5` ảnh)
- Sau nâng cấp: `docs/ux/screenshots/after/` (`8` ảnh)
- Golden Regression chuẩn CI: `test/goldens/ux_01..08_*.png` (`8` ảnh — đã kiểm định khớp tuyệt đối 100% không dùng `--update-goldens`)

---

## 1. Ma Trận Kiểm Thử Đa Màn Hình & Môi Trường (Section 24)

| # | Cấu hình màn hình & ngữ cảnh | Độ phân giải | Cỡ chữ | Chủ đề | Đệm / Bàn phím | Màn hình kiểm tra | RenderFlex Overflow | Ngoại lệ | Kết quả |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Siêu hẹp (`320dp`) | `320 × 640` | `1.0x` | Light | Safe Area 0 | Today, Quick Hub (`+`), Finance, Notifications | **0** | **0** | **PASS** |
| 2 | Siêu hẹp + Chữ lớn + Tương phản cao | `320 × 640` | `1.25x` | High Contrast Light | — | Offline/Sync-Failed Banner + 8 Trust UX Badges | **0** | **0** | **PASS** |
| 3 | Android hẹp chuẩn + Chữ lớn | `360 × 800` | `1.25x` | Light | — | Today, Quick Hub (`+`), Finance, Notifications | **0** *(đã phát hiện & sửa lỗi `2.5px` tại `finance_page.dart:4228`)* | **0** | **PASS** |
| 4 | Android hẹp + 24 màn hình (chống cắt chữ & xếp dọc 1 từ/dòng) | `360 × 800` | `1.12x` | Light | — | 4 tab chính + 20 route tiện ích + Drawer | **0** | **0** | **PASS** |
| 5 | iPhone chuẩn Dark + Safe Area | `390 × 844` | `1.0x` | Dark | Top `44` / Bottom `34` | Today, Quick Hub (`+`), Finance, Notifications | **0** | **0** | **PASS** |
| 6 | Pixel High Contrast + Chữ lớn | `412 × 915` | `1.15x` | High Contrast Light | — | Today, Quick Hub (`+`), Finance, Notifications | **0** | **0** | **PASS** |
| 7 | Điện thoại rộng + HC Dark + Bàn phím mở | `480 × 854` | `1.0x` | High Contrast Dark | Keyboard `280px` | Today, Finance, Notifications | **0** | **0** | **PASS** |
| 8 | Máy tính bảng (`NavigationRail`) | `900 × 1200` | `1.0x` | Light | — | Today (Rail), Finance, Notifications | **0** | **0** | **PASS** |

---

## 2. Danh Sách 8 Ảnh Golden Regression Đã Kiểm Duyệt Trực Quan

| STT | File Golden (`test/goldens/` & `docs/ux/screenshots/after/`) | Màn hình & Cấu hình | Ghi nhận kiểm tra trực quan |
|---:|---|---|---|
| 1 | `ux_01_today_light.png` | `TodayPage` Light (`390×844`) | Thanh dock dưới giữ nút `+` chính giữa + 4 icon phẳng 2D Duotone; phụ đề theo nhịp ngày gọn gàng; pill `Ví cá nhân · Riêng tư` không bọc 2 dòng; nút mắt mở rộng `44×44dp`; toàn bộ Hero CTA nằm trọn trên dock. |
| 2 | `ux_02_today_dark.png` | `TodayPage` Dark (`390×844`) | Nền Slate dịu mắt (`#161B22` / `#202731`), xanh điểm nhấn `#19C23E` rõ ràng, icon 2D cân đối, không chói gắt. |
| 3 | `ux_03_quick_create_hub.png` | `QuickCreateHubSheet` (`390×844`) | Thanh nhập tự nhiên + nút `Nói` xanh `#0B7A2A` tương phản cao, đủ 6 ô Bento + 3 chip `Chuyển ví`, `Thêm nhắc nhở`, `Chi phí xe` + cụm Đối soát & Lưu trữ không tràn. |
| 4 | `ux_04_finance_light.png` | `FinancePage` Light (`390×844`) | Huy hiệu `Cá nhân · Riêng tư` rõ ràng phía trên thẻ ví; nút `Tự động` / `Báo cáo` bọc `Wrap` chống tràn `1.25x`; thanh tab pill cân đối. |
| 5 | `ux_05_omni_search_grouped.png` | `OmniCommandPaletteSheet` (`390×844`) | Tìm `"thay nhot"` trả thẳng nhóm `Tính năng` → `Xe cộ & Bảo dưỡng` có tiêu đề nhóm và bộ đếm rõ ràng. |
| 6 | `ux_06_notifications_4tier.png` | `ActivityNotificationsPage` (`390×844`) | Phân nhóm theo loại, hiển thị huy hiệu 4 tầng ưu tiên + nút `Hoãn` và `Ẩn` rõ ràng. |
| 7 | `ux_07_today_high_contrast_large.png` | `TodayPage` High Contrast + `1.25x` (`360×800`) | Đường viền đậm rõ, chữ tương phản AAA, không có bất kỳ vùng cắt chữ hay đè lên dock nào. |
| 8 | `ux_08_onboarding_ftue.png` | `OnboardingPrivacyPage` (`390×844`) | Nút `Bỏ qua` ở góc phải trên, 6 chip chọn nhu cầu quan tâm sạch sẽ, không còn mã mời hay avatar giả. |

---

## 3. Lỗi Giao Diện Thực Tế Phát Hiện & Đã Sửa Trong Quá Trình Visual QA

1. **Tràn `2.5px` trên `FinancePage` ở `360dp @ 1.25x` (`finance_page.dart:4228`):** `Row` chứa `'✨ Tự động'` và `'📊 Báo cáo'` tràn `2.5px` → chuyển sang `Wrap(spacing: 4, runSpacing: 4)` → `0px` tràn.
2. **Thanh tiêu đề phụ `LifeOsTopBrandHeader` (`lifeos_design_system.dart:972`):** `Spacer()` chia đôi chiều rộng còn lại khiến nút `Ghi giao dịch` bị ép ở `1.25x` → chuyển sang `MainAxisAlignment.end` khi không có `subtitle`.
3. **Ngăn kéo `LifeOsLogoSideDrawer` (`lifeos_logo_side_drawer.dart:620`):** Khi tôn trọng OS `1.12x` text scale, phần chrome cố định chiếm `678/800px` chỉ chừa `121px` cho danh sách → đưa thẻ hồ sơ và Motion Studio vào vùng cuộn `ListView` + gom footer thành 1 hàng duy nhất → danh sách có `> 460px` thoáng đãng.
4. **Chiều cao Hero Card `TodayPage` (`today_page.dart:1850`):** Pill phạm vi mới + phụ đề đẩy nút `Nói ghi nhanh` và `Chi tiết` sát thanh dock ở `360×800 @ 1.12x` → gộp pill phạm vi và avatar stack cùng hàng `Wrap` gọn + đặt `Gợi ý phù hợp` ngay sau `Việc cần chú ý` → toàn bộ Hero CTA nằm trọn trên dock.
