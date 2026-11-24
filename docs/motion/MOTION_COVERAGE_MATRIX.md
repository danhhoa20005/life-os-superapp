# Danh Sách Màn Hình Cải Thiện, Ma Trận 66 Mẫu Gallery & Kiểm Toán Bản Quyền (`v3.21.0+37`)

## 1. Danh Sách Màn Hình Thực Tế Được Nâng Cấp Chuyển Động (Không Thay Đổi Nghiệp Vụ)

| # | Màn hình / Thành phần | File triển khai | Hạng mục nâng cấp chuyển động | Hỗ trợ Light / Dark & Reduce Motion |
|---|---|---|---|---|
| 1 | **Thanh điều hướng dưới & Khung Adaptive Shell** | `lib/app/app_router.dart`, `lib/core/widgets/liquid_glass.dart` | Nâng cấp viên nang `LiquidGlassSlidingDock` sang `SpringSimulation` (`snappySpring`, $\zeta = 0.950$) bảo toàn vận tốc vuốt ngang `onHorizontalDragEnd` và đổi hướng giữa chừng (`NAV-02`). Đăng ký route `/motion-gallery`. | Khi bật Reduce Motion: nhảy mờ `100 ms` (`0 ms` khi tắt), tắt biến dạng giọt lỏng. |
| 2 | **Hệ thống Thu gọn `"Chi tiết"` & Cài đặt Giao diện** | `lib/core/widgets/lifeos_design_system.dart` | Chuyển toàn bộ `LifeOsDetailsDiscloseSection` sang `LifeOsAnimatedVisibility` (`AnimatedSize` + `AnimatedOpacity` + `IgnorePointer` + `ExcludeSemantics`). Bổ sung bộ chọn đủ 4 chế độ `LifeOsMotionMode` và nút mở **Motion Studio (66 mẫu)** trong `showLifeOsAppearanceSheet`. | Chiều cao đóng/mở mượt ở chế độ thường; hạ về fade ngắn / tức thì khi Reduce Motion. |
| 3 | **Biểu đồ Tài chính & Dòng tiền** | `lib/core/widgets/pro_max_widgets.dart` | Nội suy mượt góc mở lát `ProDonutChart` và chiều cao cột `ProCashflowPulseCard` (`0%` overshoot); điều phối phản hồi rung qua `LifeOsMotionScope.read(context).selectionHaptic()`. | Chuyển trạng thái tức thì khi tắt hiệu ứng; tắt rung khi `isMotionOff` hoặc tắt haptic. |
| 4 | **Ngăn kéo Biểu trưng cạnh trái (Side Drawer)** | `lib/core/widgets/lifeos_logo_side_drawer.dart` | Nâng cấp chuyển động trượt ngăn kéo tôn trọng `LifeOsMotionScope` và bổ sung lối tắt trực tiếp vào **Motion Studio · 66 mẫu**. | Tự động chuyển từ `SlideTransition` sang `FadeTransition` / `0 ms` khi Reduce Motion. |
| 5 | **Khởi động & Xác thực (Splash / Login / Register)** | `lib/features/authentication/presentation/pages/splash_page.dart`, `auth_pages.dart` | `SplashPage` đọc trực tiếp `LifeOsMotionScope`; nút đăng nhập/đăng ký dùng lò xo `LifeOsPressable`; khung form rung cảnh báo 1 lần (`.lifeOsErrorShake` của `flutter_animate` + `LifeOsOneShotEffectTracker`) khi sai thông tin mà không phát lại khi rebuild. | Rung cảnh báo tự động tắt khi bật Reduce Motion, chỉ giữ thông báo văn bản rõ ràng. |
| 6 | **Thu âm Giọng nói Thông minh (Voice AI Sheet)** | `lib/core/widgets/voice_smart_capture_sheet.dart` | Tách luồng biên độ âm thanh sang `ValueNotifier<double> _rmsNotifier` nối thẳng `RepaintBoundary` + `CustomPaint(_VoiceMicHaloPainter)` — đạt **0 lần `setState` toàn bảng / frame** và **0 sự kiện gửi vào BLoC / frame**. | Tắt vòng sóng dao động khi bật Reduce Motion, giữ chấm trạng thái tĩnh rõ ràng. |
| 7 | **Đối soát Ngân hàng Tự động & Báo cáo Tài chính** | `lib/features/transactions/presentation/pages/auto_tx_and_report_pages.dart` | Tích hợp hoạt ảnh vector timeline `LifeOsLottieAnimation` (`lifeos_wallet_sync_radar.json`, 1 nhịp hữu hạn) trên trạng thái rỗng chờ đối soát; bọc chuyển đổi kỳ báo cáo `Tuần / Tháng / Năm` bằng `LifeOsMaterialContentSwitcher` (`FadeThroughTransition`). | Lottie đóng băng ở khung ổn định `0.85` khi Reduce Motion; đổi kỳ báo cáo không trượt ngang. |
| 8 | **Danh bạ Tiện ích (Tab Menu) & Trung tâm Cài đặt** | `lib/features/daily_life/presentation/pages/super_app_directory_page.dart`, `lib/features/notifications/presentation/pages/activity_and_settings_pages.dart` | Bổ sung ô tiện ích **Motion Studio** trong danh mục Menu và dòng **Motion Studio & Hiệu ứng (`66 mẫu`)** trong mục Giao diện & Quyền riêng tư của Cài đặt. | Đồng bộ hoàn toàn bảng màu Sáng/Tối và cỡ chữ lớn `112%–125%`. |
| 9 | **Motion Design Studio & Living Gallery (`/motion-gallery`)** | `lib/features/motion_gallery/` | Trạm thử nghiệm trực quan **66 mẫu chuyển động tương tác thật** chia 8 nhóm chức năng, điều khiển bởi `MotionGalleryBloc` (`0%` Cubit), hỗ trợ tua chậm `0.25x / 0.5x / 1.0x`, đổi Sáng/Tối, bật/tắt Reduce Motion tại chỗ và mở Sân khấu lớn (`showLifeOsSpringSheet`). | Ảo hóa `SliverList.builder` 60/120 FPS; kiểm tra trực tiếp chế độ Reduce Motion ngay trên 66 mẫu. |

---

## 2. Danh Mục 66 Mẫu Chuyển Động Theo 8 Nhóm Chức Năng

1. **Nhóm 1 — Điều hướng Material Motion (`#01`–`#08`, 8 mẫu):** `OpenContainer` Card-to-Detail, `OpenContainer` Jewel-to-Composer, `SharedAxis` X/Y/Z, `FadeThrough`, `FadeScale`, `MaterialRectArcTween` Hero Shuttle.
2. **Nhóm 2 — Vật lý Lò xo & Cử chỉ (`#09`–`#17`, 9 mẫu):** Phòng thí nghiệm 4 lò xo 1D, Ném tự do 2D bảo toàn vận tốc, Đổi đích giữa chừng liên tục $C^1$, `LifeOsPhysicsAnimatedBox`, Hút nam châm 4 góc theo đà vẩy, Thẻ gạt Duyệt/Bỏ qua, Dây thun Hyperbolic Rubber-Band, Chuỗi 5 mắt xích lò xo, Viên nang trượt co giãn.
3. **Nhóm 3 — Vi tương tác & Nút bấm (`#18`–`#25`, 8 mẫu):** `LifeOsPressable` 48dp, Nút biến hình 3 trạng thái (`LifeOsOneShotEffectTracker`), Vệt sáng Shimmer (`flutter_animate`), Xoay chevron & Mắt bảo mật (`PrivacyMaskFormatter`), Thanh phân đoạn lò xo, Công tắc vật lý, Rung cảnh báo lỗi (`ShakeEffect`), Vòng nhấn giữ xác nhận.
4. **Nhóm 4 — Thẻ, Bento & Băng chuyền (`#26`–`#33`, 8 mẫu):** Thẻ Ví nghiêng 3D, `LifeOsPerspectiveCarousel` (`scrollRatio`), Xếp chồng quạt Apple Wallet, Bento thị sai 3 lớp, Lật thẻ 180° Ví/QR, Bento mở rộng mượt, Viền ánh kim theo góc kéo, Nền sóng ngọc phòng thu.
5. **Nhóm 5 — Danh sách & Vũ đạo Cuộn (`#34`–`#41`, 8 mẫu):** Stagger có rào chắn `LifeOsStableListRegistry` (`<= 5` dòng vs chặn đồng bộ hàng loạt), Header kính thu gọn theo cuộn, Vuốt sao kê Duyệt/Hoàn tác, Nâng thẻ ưu tiên, Biến hình Bento 2 cột <-> 1 cột, Thanh tiến độ theo cuộn, `LifeOsStaleWhileRevalidate` Skeleton, `AnimatedList` chèn/xóa mượt.
6. **Nhóm 6 — Bottom Sheet, Hộp thoại & Tiết lộ (`#42`–`#49`, 8 mẫu):** `LifeOsSpringBottomSheet` đa nấc `42%/72%/92%`, Chuyển giao cuộn-kéo Sheet, Thu nhỏ lớp nền `0.94` kiểu iOS, Stepper `SharedAxis` nội bộ Sheet, Màng sóng Bezier đàn hồi (`GooeyEdge`), Mở rộng `"Chi tiết"` không giật, `LifeOsTopToast` chống lặp burst `1200ms`, Hộp thoại `FadeScaleTransition`.
7. **Nhóm 7 — Biểu đồ, Bộ đếm & Trung thực Tài chính (`#50`–`#57`, 8 mẫu):** Donut biến hình `chartMorphSpring` (`0%` overshoot), Cột dòng tiền 7 ngày + đường ngắm chạm, Sparkline vẽ theo `PathMetric` + đường phẳng khi `Delta = 0`, `LifeOsTruthfulNumericText` (không đếm giả từ 0), Thanh trượt mô phỏng FIRE, Ba vòng đồng tâm 6 Hũ, Vòng đếm Pomodoro, Thanh ngân sách trung thực khi vượt `118%`.
8. **Nhóm 8 — GLSL Shader, Lottie, Sprite Sheet, Particle & Linh vật (`#58`–`#66`, 9 mẫu):** GLSL `liquid_caustics.frag`, GLSL `holographic_foil.frag`, Vầng sóng âm Voice `ValueNotifier`, Lottie dấu kiểm one-shot, Lottie Radar đổi màu Light/Dark, Đối chiếu minh bạch **Ảnh 3D tĩnh Nano Banana vs Sprite 8-frame RGBA chạy thật**, Pháo hạt `LifeOsParticleBurst`, Linh vật tương tác 5 trạng thái `"Mầm Ngọc"`, Sóng nước Lottie + dòng chảy Marching Ants.

---

## 3. Kiểm Toán Tài Nguyên & Giấy Phép (Asset & License Governance)

Chi tiết máy đọc được lưu đầy đủ tại [asset-manifest.json](file:///g:/superapp/examples/asset-manifest.json):

| Tài nguyên / Thư viện | Đường dẫn / Gói | Phân loại kỹ thuật | Giấy phép |
|---|---|---|---|
| `animations` (`^2.2.0`) | `pubspec.yaml` | Thư viện Material Motion chính thức của Google Flutter | `BSD-3-Clause` |
| `flutter_animate` (`^4.5.2`) + `flutter_shaders` | `pubspec.yaml` | Thư viện hiệu ứng thành phần & GLSL Shader | `BSD-3-Clause` |
| `lottie` (`^3.8.2`) | `pubspec.yaml` | Trình phát vector timeline Bodymovin thuần Dart | `MIT` |
| `mascot_leafy_guardian.jpg` | `assets/motion/` | **Ảnh 3D tĩnh** chân dung Mầm Ngọc (Nano Banana) | First-Party Original |
| `banner_motion_studio_3d.jpg` | `assets/motion/` | **Ảnh 3D tĩnh** điêu khắc động học (Nano Banana) | First-Party Original |
| `ic_motion_physics_3d.jpg` | `assets/motion/` | **Ảnh 3D tĩnh** icon con lắc pha lê (Nano Banana) | First-Party Original |
| `coin_spin_spritesheet.png` | `assets/motion/` | **Hoạt ảnh chạy thật** — Sprite sheet 8 khung hình RGBA (`1024×128`) | First-Party Original (`MIT`) |
| `lifeos_*.json` (4 file) | `assets/lottie/` | **Hoạt ảnh chạy thật** — Vector keyframe Bodymovin JSON v5.7.4 | First-Party Original (`MIT`) |
| `liquid_caustics.frag`, `holographic_foil.frag` | `shaders/` | **Hoạt ảnh chạy thật** — GLSL Fragment Shaders (`#version 460 core`) | First-Party Original (`MIT`) |
