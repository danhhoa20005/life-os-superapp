import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/lifeos_brand_colors.dart';
import '../../../../core/utils/privacy_mask_formatter.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../models/motion_sample_ui_spec.dart';

/// Builds the first 33 interactive samples (`#01`–`#33`) of the LifeOS Motion Gallery
/// covering Groups 1–4:
/// 1. `navigationMaterial` (`#01`–`#08`)
/// 2. `springPhysicsGestures` (`#09`–`#17`)
/// 3. `microInteractionsButtons` (`#18`–`#25`)
/// 4. `cardsBentoCarousels` (`#26`–`#33`)
List<MotionSampleSpec> buildMotionSamplesPart1() {
  return <MotionSampleSpec>[
    // ═══════════════════════════════════════════════════════════════════════════
    // GROUP 1 — Material Navigation & Container Transitions (#01–#08)
    // ═══════════════════════════════════════════════════════════════════════════
    MotionSampleSpec(
      number: 1,
      id: 'nav_open_container_card',
      category: MotionSampleCategory.navigationMaterial,
      titleVi: 'Biến đổi Thẻ sang Chi tiết',
      uxPurposeVi:
          'Mở rộng liền mạch thẻ ngân sách thành trang phân tích chi tiết giữ nguyên ngữ cảnh không gian.',
      tokenSummary: 'LifeOsOpenContainer · medium (300ms) · FadeThrough',
      upstreamRef: 'flutter/packages · animations (OpenContainer)',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample01OpenContainerCard(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 2,
      id: 'nav_open_container_fab',
      category: MotionSampleCategory.navigationMaterial,
      titleVi: 'Nút Ngọc mở Trình soạn nhanh',
      uxPurposeVi:
          'Biến nút hành động nổi (+) thành khung ghi chép giao dịch tức thì mà không đứt mạch thị giác.',
      tokenSummary: 'LifeOsOpenContainer · medium (300ms) · FAB Morph',
      upstreamRef: 'flutter/packages · animations (OpenContainer FAB)',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample02OpenContainerFab(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 3,
      id: 'nav_shared_axis_x',
      category: MotionSampleCategory.navigationMaterial,
      titleVi: 'Trục chung Ngang (3 bước)',
      uxPurposeVi:
          'Dẫn dắt luồng thiết lập kế hoạch 3 bước tiến và lùi theo trục ngang nhất quán.',
      tokenSummary:
          'LifeOsMaterialContentSwitcher · SharedAxis.horizontal · 300ms',
      upstreamRef: 'flutter/packages · animations (SharedAxisTransition X)',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample03SharedAxisX(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 4,
      id: 'nav_shared_axis_y',
      category: MotionSampleCategory.navigationMaterial,
      titleVi: 'Trục chung Dọc (Phân cấp)',
      uxPurposeVi:
          'Chuyển đổi mượt theo chiều dọc giữa tổng quan năm, quý và danh mục con.',
      tokenSummary:
          'LifeOsMaterialContentSwitcher · SharedAxis.vertical · 300ms',
      upstreamRef: 'flutter/packages · animations (SharedAxisTransition Y)',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample04SharedAxisY(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 5,
      id: 'nav_shared_axis_z',
      category: MotionSampleCategory.navigationMaterial,
      titleVi: 'Trục chung Chiều sâu Z',
      uxPurposeVi:
          'Phóng sâu từ cụm thư mục tài sản vào chi tiết sổ tiết kiệm với cảm giác lớp không gian.',
      tokenSummary: 'LifeOsMaterialContentSwitcher · SharedAxis.scaled · 300ms',
      upstreamRef: 'flutter/packages · animations (SharedAxisTransition Z)',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample05SharedAxisZ(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 6,
      id: 'nav_fade_through',
      category: MotionSampleCategory.navigationMaterial,
      titleVi: 'Chuyển cảnh Tan xuyên (Fade Through)',
      uxPurposeVi:
          'Đổi bộ lọc ngang hàng (Chi tiêu · Lịch hẹn · Sức khỏe) sạch gọn không gây trượt ngang rối mắt.',
      tokenSummary: 'FadeThroughTransition · standard (220ms)',
      upstreamRef: 'flutter/packages · animations (FadeThroughTransition)',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample06FadeThrough(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 7,
      id: 'nav_fade_scale_modal',
      category: MotionSampleCategory.navigationMaterial,
      titleVi: 'Hộp thoại Kính nổi (Fade Scale)',
      uxPurposeVi:
          'Hiển thị và thu gọn bảng xác nhận nhanh ngay tại tâm chú ý mà không che khuất toàn màn hình.',
      tokenSummary: 'FadeScaleTransition · standard (220ms) / exitFast (140ms)',
      upstreamRef: 'flutter/packages · animations (FadeScaleTransition)',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample07FadeScaleModal(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 8,
      id: 'nav_hero_arc_shuttle',
      category: MotionSampleCategory.navigationMaterial,
      titleVi: 'Quỹ đạo Cung tròn (Arc Tween)',
      uxPurposeVi:
          'Di chuyển vật phẩm chọn từ góc danh sách về giỏ tổng hợp theo đường cong tự nhiên thay vì đường thẳng cứng.',
      tokenSummary: 'MaterialRectArcTween · emphasizedCurve · panel (340ms)',
      upstreamRef: 'flutter/flutter · MaterialRectArcTween',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample08HeroArcShuttle(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),

    // ═══════════════════════════════════════════════════════════════════════════
    // GROUP 2 — Spring Physics & Gesture Continuity (#09–#17)
    // ═══════════════════════════════════════════════════════════════════════════
    MotionSampleSpec(
      number: 9,
      id: 'phys_1d_spring_lab',
      category: MotionSampleCategory.springPhysicsGestures,
      titleVi: 'Phòng thí nghiệm Lò xo 1D',
      uxPurposeVi:
          'So sánh trực quan độ nảy và hệ số tắt dần (ζ) của 4 cấu hình lò xo chuẩn LifeOS.',
      tokenSummary: 'press · snappy · bouncy · sheetSnap (SpringController)',
      upstreamRef: 'flutter/physics · SpringSimulation',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample09Spring1DLab(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 10,
      id: 'phys_2d_free_throw',
      category: MotionSampleCategory.springPhysicsGestures,
      titleVi: 'Ném tự do 2D bảo toàn vận tốc',
      uxPurposeVi:
          'Kéo và vẩy viên ngọc theo mọi hướng; lò xo 2D bắt trọn vận tốc ngón tay để hồi tâm mượt mà.',
      tokenSummary: 'LifeOsSpring2DController · gestureThrowSpring (k:260)',
      upstreamRef: 'rautrices/flutter_physics · 2D SpringSimulation',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample10FreeThrow2D(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 11,
      id: 'phys_retarget_chase',
      category: MotionSampleCategory.springPhysicsGestures,
      titleVi: 'Đổi đích giữa chừng liên tục C¹',
      uxPurposeVi:
          'Bấm chuyển Trái · Giữa · Phải ngay khi đang bay mà không bao giờ khựng hoặc giật vận tốc về 0.',
      tokenSummary: 'LifeOsSpringController · C¹ velocity continuity',
      upstreamRef: 'rautrices/flutter_physics · Mid-Flight Retarget',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample11RetargetChase(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 12,
      id: 'phys_animated_box',
      category: MotionSampleCategory.springPhysicsGestures,
      titleVi: 'Khung biến hình Vật lý liên tục',
      uxPurposeVi:
          'Đổi kích thước, bo góc và sắc thái thẻ bằng mô phỏng lò xo mượt mà khi đổi chế độ xem.',
      tokenSummary: 'LifeOsPhysicsAnimatedBox · snappySpring (k:500, c:42.5)',
      upstreamRef: 'rautrices/flutter_physics · AContainer',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample12PhysicsAnimatedBox(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 13,
      id: 'phys_magnetic_corners',
      category: MotionSampleCategory.springPhysicsGestures,
      titleVi: 'Hút nam châm 4 góc theo đà vẩy',
      uxPurposeVi:
          'Dự phóng điểm rơi theo vận tốc vẩy tay (lookahead 0.18s) để hút thẻ nổi về đúng góc mong muốn.',
      tokenSummary: 'projectNearestDetent · LifeOsSpring2DController',
      upstreamRef: 'Apple PiP Corner Snap · projectNearestDetent',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample13MagneticCorners(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 14,
      id: 'phys_swipe_decision_card',
      category: MotionSampleCategory.springPhysicsGestures,
      titleVi: 'Thẻ gạt Duyệt / Bỏ qua có lò xo',
      uxPurposeVi:
          'Gạt ngang để phân loại nhanh giao dịch chờ duyệt với góc nghiêng và màu ngữ nghĩa theo biên độ kéo.',
      tokenSummary: 'gestureThrowSpring · RotateZ + Semantic Blend',
      upstreamRef: 'Physics Card Triage · LifeOsSpringController',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample14SwipeDecisionCard(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 15,
      id: 'phys_rubber_band_pull',
      category: MotionSampleCategory.springPhysicsGestures,
      titleVi: 'Lực cản Dây thun Hyperbolic',
      uxPurposeVi:
          'Tạo cảm giác đàn hồi vật lý tự nhiên khi kéo vượt biên danh sách hoặc thanh trượt.',
      tokenSummary: 'rubberBandClamp (0.55) · sheetSnapSpring',
      upstreamRef: 'michalwachowicz/smooth_sheets · Rubber-Band Math',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample15RubberBandPull(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 16,
      id: 'phys_spring_rope_chain',
      category: MotionSampleCategory.springPhysicsGestures,
      titleVi: 'Chuỗi 5 nút Lò xo liên kết',
      uxPurposeVi:
          'Mô phỏng truyền sóng đàn hồi qua chuỗi 5 mắt xích khi kéo hoặc gẩy điểm neo đầu.',
      tokenSummary: 'CustomPainter · Coupled 5-Node Spring Chain',
      upstreamRef: 'Flutter Canvas Physics · Harmonic Chain',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample16SpringRopeChain(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 17,
      id: 'phys_scrub_dock_capsule',
      category: MotionSampleCategory.springPhysicsGestures,
      titleVi: 'Viên nang Kính trượt co giãn',
      uxPurposeVi:
          'Trượt ngón tay dọc thanh điều hướng với hiệu ứng giọt nước giãn nhẹ theo vận tốc kéo.',
      tokenSummary: 'snappySpring · Velocity Stretch Capsule',
      upstreamRef: 'LifeOS LiquidGlassSlidingDock · iOS 26 Capsule',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample17ScrubDockCapsule(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),

    // ═══════════════════════════════════════════════════════════════════════════
    // GROUP 3 — Micro-Interactions & Tactile Controls (#18–#25)
    // ═══════════════════════════════════════════════════════════════════════════
    MotionSampleSpec(
      number: 18,
      id: 'micro_pressable_squish',
      category: MotionSampleCategory.microInteractionsButtons,
      titleVi: 'Nút nhấn Đàn hồi giữ chuẩn 48dp',
      uxPurposeVi:
          'Phản hồi xúc giác tức thì (0.97x–0.98x) nhưng vùng chạm ngoài luôn giữ nguyên tối thiểu 48×48dp.',
      tokenSummary: 'LifeOsPressable · pressSpring (k:600, c:43) · 48dp',
      upstreamRef: 'LifeOS Core · LifeOsPressable',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample18PressableSquish(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 19,
      id: 'micro_morphing_cta',
      category: MotionSampleCategory.microInteractionsButtons,
      titleVi: 'Nút hành động Biến hình 3 trạng thái',
      uxPurposeVi:
          'Chuyển mượt từ Xác nhận sang Xử lý rồi Đã lưu một lần duy nhất nhờ khóa chống lặp hiệu ứng.',
      tokenSummary: 'LifeOsOneShotEffectTracker · standard (220ms)',
      upstreamRef: 'LifeOS Core · LifeOsOneShotEffectTracker',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample19MorphingCta(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 20,
      id: 'micro_shimmer_sweep',
      category: MotionSampleCategory.microInteractionsButtons,
      titleVi: 'Vệt sáng Kim loại hữu hạn',
      uxPurposeVi:
          'Quét ánh sáng lướt nhẹ đúng 1 nhịp khi chạm hoặc làm mới mà không treo vòng lặp nền.',
      tokenSummary: 'lifeOsShimmer · 900ms finite pass (0 infinite loop)',
      upstreamRef: 'gskinner/flutter_animate · ShimmerEffect',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample20ShimmerSweep(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 21,
      id: 'micro_icon_morph_toggle',
      category: MotionSampleCategory.microInteractionsButtons,
      titleVi: 'Xoay mũi tên & Đổi mắt Bảo mật',
      uxPurposeVi:
          'Che mặc định mã định danh nhạy cảm bằng PrivacyMaskFormatter đến khi chủ động nhấn mở.',
      tokenSummary: 'AnimatedRotation + AnimatedSwitcher · micro (160ms)',
      upstreamRef: 'LifeOS Security · PrivacyMaskFormatter',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample21IconMorphToggle(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 22,
      id: 'micro_segmented_pill',
      category: MotionSampleCategory.microInteractionsButtons,
      titleVi: 'Thanh phân đoạn Trượt lò xo',
      uxPurposeVi:
          'Chuyển đổi mượt giữa Ngày · Tuần · Tháng bằng viên nang nền trượt theo vật lý snappySpring.',
      tokenSummary: 'LifeOsSpringController · snappySpring (k:500, c:42.5)',
      upstreamRef: 'UI/UX Pro Max · Segmented Pill Trough',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample22SegmentedPill(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 23,
      id: 'micro_physics_switch_chip',
      category: MotionSampleCategory.microInteractionsButtons,
      titleVi: 'Công tắc Vật lý & Chip lọc nảy nhẹ',
      uxPurposeVi:
          'Bật tắt trích quỹ tự động và chọn nhãn danh mục với phản hồi lò xo kèm biểu tượng rõ nghĩa.',
      tokenSummary: 'snappySpring + pressSpring · WCAG Icon + Text',
      upstreamRef: 'Material 3 Expressive · Physics Switch & Chip',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample23PhysicsSwitchChip(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 24,
      id: 'micro_error_shake',
      category: MotionSampleCategory.microInteractionsButtons,
      titleVi: 'Rung cảnh báo Nhập sai mã',
      uxPurposeVi:
          'Phản hồi rung ngang ngắn gọn kèm nhãn lỗi rõ ràng khi nhập sai mã PIN xác thực.',
      tokenSummary: 'lifeOsErrorShake · ShakeEffect (340ms, 5Hz, ±6px)',
      upstreamRef: 'gskinner/flutter_animate · ShakeEffect',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample24ErrorShake(speedFactor: speedFactor, replaySeed: replaySeed),
    ),
    MotionSampleSpec(
      number: 25,
      id: 'micro_hold_radial_confirm',
      category: MotionSampleCategory.microInteractionsButtons,
      titleVi: 'Nhấn giữ Vòng tròn Xác nhận',
      uxPurposeVi:
          'Ngăn thao tác nhầm cho lệnh quan trọng bằng vòng tiến độ nhấn giữ tự thu hồi nếu thả sớm.',
      tokenSummary: 'CustomPainter Radial Ring · 650ms hold / exitStandard',
      upstreamRef: 'Fintech Safety UX · Hold-to-Confirm Ring',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample25HoldRadialConfirm(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),

    // ═══════════════════════════════════════════════════════════════════════════
    // GROUP 4 — Cards, Bento Surfaces & 3D Carousels (#26–#33)
    // ═══════════════════════════════════════════════════════════════════════════
    MotionSampleSpec(
      number: 26,
      id: 'card_3d_tilt_wallet',
      category: MotionSampleCategory.cardsBentoCarousels,
      titleVi: 'Thẻ Ví nghiêng Phối cảnh 3D',
      uxPurposeVi:
          'Nghiêng thẻ tài khoản theo ngón tay kéo kèm ánh kim dịch chuyển như thẻ vật lý thật.',
      tokenSummary: 'Matrix4 perspective (0.0012) · Spring return',
      upstreamRef: 'Apple Wallet / Revolut · 3D Perspective Card',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample26TiltWalletCard(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 27,
      id: 'card_perspective_carousel',
      category: MotionSampleCategory.cardsBentoCarousels,
      titleVi: 'Băng chuyền Thẻ phối cảnh 3D',
      uxPurposeVi:
          'Vuốt duyệt các hũ tài chính với tỷ lệ cuộn liên tục tạo chiều sâu tự nhiên.',
      tokenSummary: 'LifeOsPerspectiveCarousel · scrollRatio [-1..+1]',
      upstreamRef: 'gskinnerTeam/flutter_custom_carousel',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample27PerspectiveCarousel(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 28,
      id: 'card_wallet_fan_deck',
      category: MotionSampleCategory.cardsBentoCarousels,
      titleVi: 'Xếp chồng Thẻ quạt Apple Wallet',
      uxPurposeVi:
          'Xếp gọn 3 thẻ thanh toán trong một khung; chạm thẻ bất kỳ để rút mượt lên vị trí đầu.',
      tokenSummary: 'Stacked Fan Deck · medium (300ms) · emphasizedCurve',
      upstreamRef: 'Apple Wallet · Stacked Card Deck',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample28WalletFanDeck(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 29,
      id: 'card_parallax_bento',
      category: MotionSampleCategory.cardsBentoCarousels,
      titleVi: 'Thẻ Bento Đa lớp Thị sai (Parallax)',
      uxPurposeVi:
          'Tách tiền cảnh, trung cảnh và hậu cảnh dịch chuyển khác tốc độ tạo chiều sâu không gian tinh tế.',
      tokenSummary: '3-Layer Depth Parallax · gestureThrowSpring',
      upstreamRef: 'gskinnerTeam/flutter_vignettes · Parallax Card',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample29ParallaxBento(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 30,
      id: 'card_3d_flip_180',
      category: MotionSampleCategory.cardsBentoCarousels,
      titleVi: 'Lật thẻ 180° Mặt trước / Mã QR',
      uxPurposeVi:
          'Lật mặt thẻ ngân hàng sang mặt sau chứa mã đối soát bảo mật mà không rời khỏi khung hiện tại.',
      tokenSummary: 'Matrix4.rotateY(π) · medium (300ms) · Front/Back swap',
      upstreamRef: '3D Card Flip · Matrix4 Perspective',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample30CardFlip180(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 31,
      id: 'card_expandable_bento',
      category: MotionSampleCategory.cardsBentoCarousels,
      titleVi: 'Ô Bento Mở rộng Chi tiết mượt',
      uxPurposeVi:
          'Giữ gọn chỉ số chính trên thẻ và chỉ trượt mở phần giải thích chi tiết khi người dùng cần xem.',
      tokenSummary: 'LifeOsAnimatedVisibility · standard (220ms) · Zero jump',
      upstreamRef: 'LifeOS Core · LifeOsAnimatedVisibility',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample31ExpandableBento(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 32,
      id: 'card_metallic_sheen_sweep',
      category: MotionSampleCategory.cardsBentoCarousels,
      titleVi: 'Viền Ánh kim Phản quang theo tay kéo',
      uxPurposeVi:
          'Tái hiện viền kính kim loại bắt sáng động theo góc chạm trên thẻ hạng thành viên cao cấp.',
      tokenSummary: 'Specular Rim CustomPainter · Pointer Angle Sweep',
      upstreamRef: 'Apple Liquid Glass · Specular Metallic Rim',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample32MetallicSheenSweep(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
    MotionSampleSpec(
      number: 33,
      id: 'card_mint_wave_canvas',
      category: MotionSampleCategory.cardsBentoCarousels,
      titleVi: 'Nền Sóng Ngọc Ánh sáng Phòng thu',
      uxPurposeVi:
          'Tạo lớp nền khúc xạ dịu mắt thích ứng Sáng và Tối để các thẻ kính nổi bật chiều sâu tự nhiên.',
      tokenSummary: 'LifeOsMintWaveCanvas + TammySemanticColors (Light/Dark)',
      upstreamRef: 'LifeOS BrandKit 1.0 · Daylight Mint Wave',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample33MintWaveCanvas(
            speedFactor: speedFactor,
            replaySeed: replaySeed,
          ),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Stage & Typography Helpers (Overflow-safe at 360x800 @ 112%–125%)
// ─────────────────────────────────────────────────────────────────────────────

Duration _scaledDuration(
  LifeOsMotionPreferences motion,
  Duration base,
  double speedFactor, {
  Duration? reduced,
}) {
  final resolved = motion.resolveDuration(base, reduced: reduced);
  if (resolved == Duration.zero) return Duration.zero;
  final clampedSpeed = speedFactor.clamp(0.2, 3.0);
  return Duration(
    milliseconds: math.max(
      16,
      (resolved.inMilliseconds / clampedSpeed).round(),
    ),
  );
}

TextStyle _tabularStyle({
  required Color color,
  double fontSize = 13,
  FontWeight fontWeight = FontWeight.w700,
  double? letterSpacing,
  double height = 1.2,
}) {
  return TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    height: height,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );
}

class _SampleStage extends StatelessWidget {
  final Widget child;
  final double height;
  final EdgeInsetsGeometry padding;

  const _SampleStage({
    required this.child,
    this.height = 156,
    this.padding = const EdgeInsets.all(10),
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveHeight = constraints.hasBoundedHeight
            ? math.min(height, constraints.maxHeight)
            : height;
        return Container(
          width: double.infinity,
          height: effectiveHeight,
          padding: padding,
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border, width: 0.9),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
    );
  }
}

class _CompactActionChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? activeColor;

  const _CompactActionChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final accent = activeColor ?? c.primary;
    final bg = selected ? accent : c.surface;
    final fg = selected ? c.onPrimary : c.textPrimary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 30, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? accent : c.border, width: 0.9),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 13.5, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #01 — LifeOsOpenContainer Card-to-Detail Morph
// ═════════════════════════════════════════════════════════════════════════════
class _Sample01OpenContainerCard extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample01OpenContainerCard({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample01OpenContainerCard> createState() =>
      _Sample01OpenContainerCardState();
}

class _Sample01OpenContainerCardState
    extends State<_Sample01OpenContainerCard> {
  static const List<(String period, String amount, double ratio)> _periods =
      <(String, String, double)>[
        ('Tháng 11/2026', '12.450.000 ₫', 0.68),
        ('Tháng 10/2026', '10.920.000 ₫', 0.59),
        ('Tháng 09/2026', '13.180.000 ₫', 0.74),
      ];

  int _periodIdx = 0;
  int _openCount = 0;

  @override
  void didUpdateWidget(covariant _Sample01OpenContainerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      setState(() => _periodIdx = (_periodIdx + 1) % _periods.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final item = _periods[_periodIdx];

    return _SampleStage(
      height: 152,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Chạm thẻ để mở trang chi tiết (${_openCount}x)',
                    style: _tabularStyle(
                      color: c.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _CompactActionChip(
                label: 'Đổi kỳ',
                icon: Icons.calendar_today_rounded,
                onTap: () => setState(
                  () => _periodIdx = (_periodIdx + 1) % _periods.length,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LifeOsOpenContainer<void>(
              closedColor: c.surface,
              openColor: c.background,
              closedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.border),
              ),
              onClosed: (_) {
                if (mounted) setState(() => _openCount++);
              },
              closedBuilder: (ctx, openContainer) {
                return InkWell(
                  onTap: openContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.primarySubtle,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_rounded,
                            color: c.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  'Ngân sách Gia đình · ${item.$1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: c.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                LifeOsTruthfulNumericText(
                                  formattedValue: item.$2,
                                  style: _tabularStyle(
                                    color: c.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: c.primarySubtle,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'Mở',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.primary,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.open_in_full_rounded,
                                size: 12,
                                color: c.primary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              openBuilder: (ctx, closeContainer) {
                final detailColors = TammySemanticColors.of(ctx);
                return Scaffold(
                  backgroundColor: detailColors.background,
                  appBar: AppBar(
                    backgroundColor: detailColors.surface,
                    leading: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Đóng',
                      onPressed: () => closeContainer(),
                    ),
                    title: Text('Chi tiết Ngân sách · ${item.$1}'),
                  ),
                  body: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: detailColors.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: detailColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Tổng chi đã xác nhận',
                                  style: TextStyle(
                                    color: detailColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item.$2,
                                  style: _tabularStyle(
                                    color: detailColors.textPrimary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                LifeOsAnimatedProgressBar(
                                  progressRatio: item.$3,
                                  color: detailColors.primary,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => closeContainer(),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Thu về thẻ ban đầu'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #02 — LifeOsOpenContainer Jewel/FAB-to-Composer Morph
// ═════════════════════════════════════════════════════════════════════════════
class _Sample02OpenContainerFab extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample02OpenContainerFab({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample02OpenContainerFab> createState() =>
      _Sample02OpenContainerFabState();
}

class _Sample02OpenContainerFabState extends State<_Sample02OpenContainerFab> {
  static const List<(String title, String amount, IconData icon)> _presets =
      <(String, String, IconData)>[
        ('Cà phê sáng', '45.000 ₫', Icons.coffee_rounded),
        ('Đổ xăng xe', '90.000 ₫', Icons.local_gas_station_rounded),
        ('Siêu thị rau củ', '215.000 ₫', Icons.shopping_basket_rounded),
      ];

  int _selectedIdx = 0;

  @override
  void didUpdateWidget(covariant _Sample02OpenContainerFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      setState(() => _selectedIdx = (_selectedIdx + 1) % _presets.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final current = _presets[_selectedIdx];

    return _SampleStage(
      height: 172,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(current.$3, size: 16, color: c.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Khoản ghi gần nhất',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      current.$1,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    LifeOsTruthfulNumericText(
                      formattedValue: current.$2,
                      style: _tabularStyle(
                        color: c.primary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              LifeOsOpenContainer<int>(
                closedColor: LifeOSBrandColors.primary,
                openColor: c.background,
                closedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onClosed: (picked) {
                  if (picked != null && mounted) {
                    setState(() => _selectedIdx = picked);
                  }
                },
                closedBuilder: (ctx, openContainer) {
                  return InkWell(
                    onTap: openContainer,
                    child: const SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  );
                },
                openBuilder: (ctx, closeContainer) {
                  final sc = TammySemanticColors.of(ctx);
                  return Scaffold(
                    backgroundColor: sc.background,
                    appBar: AppBar(
                      backgroundColor: sc.surface,
                      leading: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => closeContainer(),
                      ),
                      title: const Text('Ghi nhanh khoản chi'),
                    ),
                    body: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (
                              var i = 0;
                              i < _presets.length;
                              i++
                            ) ...<Widget>[
                              ListTile(
                                tileColor: sc.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: sc.border),
                                ),
                                leading: Icon(
                                  _presets[i].$3,
                                  color: sc.primary,
                                ),
                                title: Text(_presets[i].$1),
                                trailing: Text(
                                  _presets[i].$2,
                                  style: _tabularStyle(
                                    color: sc.textPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                                onTap: () => closeContainer(returnValue: i),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Soạn mới',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #03 — LifeOsMaterialContentSwitcher (SharedAxis.horizontal Stepper 3 bước)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample03SharedAxisX extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample03SharedAxisX({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample03SharedAxisX> createState() => _Sample03SharedAxisXState();
}

class _Sample03SharedAxisXState extends State<_Sample03SharedAxisX> {
  static const List<(String stepTitle, String detail, IconData icon)> _steps =
      <(String, String, IconData)>[
        (
          'Bước 1 · Chọn hạn mức',
          'Thiết lập 8.500.000 ₫ cho sinh hoạt',
          Icons.tune_rounded,
        ),
        (
          'Bước 2 · Ngưỡng nhắc',
          'Báo sớm khi chạm 80% ngân sách',
          Icons.notifications_active_outlined,
        ),
        (
          'Bước 3 · Sẵn sàng',
          'Đồng bộ tức thì cho cả gia đình',
          Icons.verified_rounded,
        ),
      ];

  int _step = 0;
  bool _reverse = false;

  void _goTo(int next) {
    if (next == _step) return;
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() {
      _reverse = next < _step;
      _step = next.clamp(0, _steps.length - 1);
    });
  }

  @override
  void didUpdateWidget(covariant _Sample03SharedAxisX oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _goTo((_step + 1) % _steps.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final dur = _scaledDuration(
      motion,
      LifeOsMotionTokens.medium,
      widget.speedFactor,
    );
    final item = _steps[_step];

    return _SampleStage(
      height: 154,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (var i = 0; i < _steps.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _CompactActionChip(
                    label: 'Bước ${i + 1}',
                    selected: _step == i,
                    onTap: () => _goTo(i),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LifeOsMaterialContentSwitcher(
              sharedAxis: LifeOsSharedAxis.horizontal,
              reverse: _reverse,
              duration: dur,
              child: Container(
                key: ValueKey<int>(_step),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.primarySubtle,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(item.$3, color: c.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              item.$1,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.$2,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Bước tiếp',
                      onPressed: () => _goTo((_step + 1) % _steps.length),
                      icon: Icon(
                        Icons.arrow_forward_rounded,
                        color: c.primary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #04 — LifeOsMaterialContentSwitcher (SharedAxis.vertical Drill-Down)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample04SharedAxisY extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample04SharedAxisY({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample04SharedAxisY> createState() => _Sample04SharedAxisYState();
}

class _Sample04SharedAxisYState extends State<_Sample04SharedAxisY> {
  static const List<(String level, String title, String metric)> _levels =
      <(String, String, String)>[
        ('Cấp 1 · Năm', 'Tổng quan Tài chính 2026', '148.200.000 ₫'),
        ('Cấp 2 · Quý', 'Chi tiêu Quý IV / 2026', '36.450.000 ₫'),
        ('Cấp 3 · Nhóm', 'Hóa đơn Điện & Nước sạch', '2.180.000 ₫'),
      ];

  int _depth = 0;
  bool _reverse = false;

  void _setDepth(int next) {
    if (next == _depth) return;
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() {
      _reverse = next < _depth;
      _depth = next.clamp(0, _levels.length - 1);
    });
  }

  @override
  void didUpdateWidget(covariant _Sample04SharedAxisY oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _setDepth((_depth + 1) % _levels.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final dur = _scaledDuration(
      motion,
      LifeOsMotionTokens.medium,
      widget.speedFactor,
    );
    final info = _levels[_depth];

    return _SampleStage(
      height: 154,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Phân cấp dọc: ${info.$1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
              _CompactActionChip(
                label: 'Lên cấp',
                icon: Icons.keyboard_arrow_up_rounded,
                onTap: () =>
                    _setDepth(_depth > 0 ? _depth - 1 : _levels.length - 1),
              ),
              const SizedBox(width: 6),
              _CompactActionChip(
                label: 'Đi sâu',
                icon: Icons.keyboard_arrow_down_rounded,
                selected: true,
                onTap: () => _setDepth((_depth + 1) % _levels.length),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LifeOsMaterialContentSwitcher(
              sharedAxis: LifeOsSharedAxis.vertical,
              reverse: _reverse,
              duration: dur,
              child: InkWell(
                key: ValueKey<int>(_depth),
                borderRadius: BorderRadius.circular(13),
                onTap: () => _setDepth((_depth + 1) % _levels.length),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.layers_rounded, color: c.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                info.$2,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                info.$3,
                                style: _tabularStyle(
                                  color: c.primary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #05 — LifeOsMaterialContentSwitcher (SharedAxis.scaled Z-Depth Zoom)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample05SharedAxisZ extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample05SharedAxisZ({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample05SharedAxisZ> createState() => _Sample05SharedAxisZState();
}

class _Sample05SharedAxisZState extends State<_Sample05SharedAxisZ> {
  static const List<(String badge, String title, String sub, IconData icon)>
  _layers = <(String, String, String, IconData)>[
    (
      'Lớp Z0',
      'Két Tài sản Gia đình',
      '3 danh mục đang bảo vệ',
      Icons.folder_special_rounded,
    ),
    (
      'Lớp Z1',
      'Sổ Tiết kiệm Kỳ hạn 12T',
      'Lãi suất 5,8%/năm · Đáo hạn T12',
      Icons.savings_rounded,
    ),
    (
      'Lớp Z2',
      'Chứng chỉ Xác thực AES-256',
      'Mã định danh đã khóa an toàn',
      Icons.shield_rounded,
    ),
  ];

  int _layer = 0;
  bool _reverse = false;

  void _zoomTo(int next) {
    if (next == _layer) return;
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() {
      _reverse = next < _layer;
      _layer = next.clamp(0, _layers.length - 1);
    });
  }

  @override
  void didUpdateWidget(covariant _Sample05SharedAxisZ oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _zoomTo((_layer + 1) % _layers.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final dur = _scaledDuration(
      motion,
      LifeOsMotionTokens.medium,
      widget.speedFactor,
    );
    final current = _layers[_layer];

    return _SampleStage(
      height: 154,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _CompactActionChip(
                  label: 'Thu lùi',
                  icon: Icons.zoom_out_rounded,
                  onTap: () =>
                      _zoomTo(_layer > 0 ? _layer - 1 : _layers.length - 1),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactActionChip(
                  label: 'Phóng sâu',
                  icon: Icons.zoom_in_rounded,
                  selected: true,
                  onTap: () => _zoomTo((_layer + 1) % _layers.length),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    current.$1,
                    style: _tabularStyle(color: c.primary, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LifeOsMaterialContentSwitcher(
              sharedAxis: LifeOsSharedAxis.scaled,
              reverse: _reverse,
              duration: dur,
              child: InkWell(
                key: ValueKey<int>(_layer),
                borderRadius: BorderRadius.circular(13),
                onTap: () => _zoomTo((_layer + 1) % _layers.length),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.primarySubtle,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(current.$4, color: c.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                current.$2,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                current.$3,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #06 — FadeThroughTransition Tab/Filter Cross-Switch
// ═════════════════════════════════════════════════════════════════════════════
class _Sample06FadeThrough extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample06FadeThrough({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample06FadeThrough> createState() => _Sample06FadeThroughState();
}

class _Sample06FadeThroughState extends State<_Sample06FadeThrough> {
  static const List<(String tab, String headline, String value, IconData icon)>
  _tabs = <(String, String, String, IconData)>[
    (
      'Chi tiêu',
      'Hạn mức ăn uống tuần này',
      '1.240.000 ₫',
      Icons.receipt_long_rounded,
    ),
    (
      'Lịch hẹn',
      'Khám sức khỏe định kỳ sáng T7',
      '08:30 · Hoàn tất',
      Icons.event_available_rounded,
    ),
    (
      'Sức khỏe',
      'Mục tiêu vận động mỗi ngày',
      '7.850 bước',
      Icons.favorite_rounded,
    ),
  ];

  int _tabIdx = 0;

  @override
  void didUpdateWidget(covariant _Sample06FadeThrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      setState(() => _tabIdx = (_tabIdx + 1) % _tabs.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final dur = _scaledDuration(
      motion,
      LifeOsMotionTokens.standard,
      widget.speedFactor,
    );
    final active = _tabs[_tabIdx];

    return _SampleStage(
      height: 154,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (var i = 0; i < _tabs.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _CompactActionChip(
                    label: _tabs[i].$1,
                    selected: _tabIdx == i,
                    onTap: () {
                      motion.selectionHaptic();
                      setState(() => _tabIdx = i);
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LifeOsMaterialContentSwitcher(
              sharedAxis: null,
              duration: dur,
              child: Container(
                key: ValueKey<int>(_tabIdx),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(active.$4, color: c.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              active.$2,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: c.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              active.$3,
                              style: _tabularStyle(
                                color: c.textPrimary,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #07 — FadeScaleTransition Glass Popup Toggle
// ═════════════════════════════════════════════════════════════════════════════
class _Sample07FadeScaleModal extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample07FadeScaleModal({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample07FadeScaleModal> createState() =>
      _Sample07FadeScaleModalState();
}

class _Sample07FadeScaleModalState extends State<_Sample07FadeScaleModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: LifeOsMotionTokens.standard,
      reverseDuration: LifeOsMotionTokens.exitFast,
    );
  }

  void _toggle() {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    _ctrl.duration = _scaledDuration(
      motion,
      LifeOsMotionTokens.standard,
      widget.speedFactor,
    );
    _ctrl.reverseDuration = _scaledDuration(
      motion,
      LifeOsMotionTokens.exitFast,
      widget.speedFactor,
    );
    setState(() => _open = !_open);
    if (!TickerMode.valuesOf(context).enabled || motion.isMotionOff) {
      _ctrl.value = _open ? 1.0 : 0.0;
      return;
    }
    if (_open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  void didUpdateWidget(covariant _Sample07FadeScaleModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _toggle();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return _SampleStage(
      height: 154,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(
            alignment: Alignment.topCenter,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _open
                          ? 'Đang mở hộp kính xác nhận'
                          : 'Nhấn nút để bật hộp thoại kính',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _CompactActionChip(
                  label: _open ? 'Thu gọn' : 'Mở hộp kính',
                  icon: _open
                      ? Icons.close_fullscreen_rounded
                      : Icons.open_in_new_rounded,
                  selected: _open,
                  onTap: _toggle,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 34),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                if (_ctrl.isDismissed && !_open) {
                  return Center(
                    child: OutlinedButton.icon(
                      onPressed: _toggle,
                      icon: const Icon(Icons.lock_outline_rounded, size: 16),
                      label: const Text('Bật xác nhận Khóa thẻ'),
                    ),
                  );
                }
                if (motion.isReducedMotion) {
                  return FadeTransition(opacity: _ctrl, child: child);
                }
                return FadeScaleTransition(animation: _ctrl, child: child);
              },
              child: LiquidGlassSurface(
                material: LiquidGlassMaterial.card,
                borderRadius: 14,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.verified_user_rounded,
                      color: c.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tạm khóa thanh toán trực tuyến?',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CompactActionChip(
                      label: 'Đồng ý',
                      selected: true,
                      onTap: _toggle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #08 — Curved Arc Trajectory (MaterialRectArcTween Interactive Shuttle)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample08HeroArcShuttle extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample08HeroArcShuttle({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample08HeroArcShuttle> createState() =>
      _Sample08HeroArcShuttleState();
}

class _Sample08HeroArcShuttleState extends State<_Sample08HeroArcShuttle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _atTarget = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: LifeOsMotionTokens.panel,
    );
  }

  void _shuttle() {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    _ctrl.duration = _scaledDuration(
      motion,
      LifeOsMotionTokens.panel,
      widget.speedFactor,
    );
    setState(() => _atTarget = !_atTarget);
    if (!TickerMode.valuesOf(context).enabled || motion.isMotionOff) {
      _ctrl.value = _atTarget ? 1.0 : 0.0;
      return;
    }
    if (_atTarget) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  void didUpdateWidget(covariant _Sample08HeroArcShuttle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _shuttle();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return _SampleStage(
      height: 156,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _shuttle,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            const beginRect = Rect.fromLTWH(6, 6, 44, 44);
            final endWidth = math.min(148.0, math.max(96.0, w * 0.50));
            final endRect = Rect.fromLTWH(
              math.max(6.0, w - endWidth - 6.0),
              math.max(6.0, h - 48.0),
              endWidth,
              42,
            );
            final arcTween = MaterialRectArcTween(
              begin: beginRect,
              end: endRect,
            );

            return AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final curvedT = motion.isReducedMotion
                    ? _ctrl.value
                    : LifeOsMotionTokens.emphasizedCurve.transform(_ctrl.value);
                final currentRect = motion.isReducedMotion
                    ? (_atTarget ? endRect : beginRect)
                    : arcTween.lerp(curvedT);

                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ArcTrajectoryGuidePainter(
                          arcTween: arcTween,
                          color: c.primary.withValues(alpha: 0.26),
                          anchorBorder: c.border,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: _CompactActionChip(
                        label: _atTarget ? 'Trả về A' : 'Bay tới B',
                        icon: Icons.swap_calls_rounded,
                        selected: _atTarget,
                        onTap: _shuttle,
                      ),
                    ),
                    Positioned.fromRect(
                      rect: currentRect,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: LifeOSBrandColors.appIconBgGradient,
                          ),
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: c.primary.withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.savings_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              if (curvedT > 0.45 ||
                                  (motion.isReducedMotion &&
                                      _atTarget)) ...<Widget>[
                                const SizedBox(width: 6),
                                Text(
                                  'Hũ Vàng +500K',
                                  style: _tabularStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ArcTrajectoryGuidePainter extends CustomPainter {
  final MaterialRectArcTween arcTween;
  final Color color;
  final Color anchorBorder;

  const _ArcTrajectoryGuidePainter({
    required this.arcTween,
    required this.color,
    required this.anchorBorder,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final b = arcTween.begin;
    final e = arcTween.end;
    if (b == null || e == null) return;

    final socketPaint = Paint()
      ..color = anchorBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(b, const Radius.circular(12)),
      socketPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(e, const Radius.circular(12)),
      socketPaint,
    );

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const steps = 16;
    for (var i = 1; i < steps; i++) {
      final r = arcTween.lerp(i / steps);
      canvas.drawCircle(r.center, 2.1, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcTrajectoryGuidePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.anchorBorder != anchorBorder;
}

// ═════════════════════════════════════════════════════════════════════════════
// #09 — 1D Spring Lab (press / snappy / bouncy / sheetSnap)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample09Spring1DLab extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample09Spring1DLab({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample09Spring1DLab> createState() => _Sample09Spring1DLabState();
}

class _Sample09Spring1DLabState extends State<_Sample09Spring1DLab>
    with SingleTickerProviderStateMixin {
  static const List<(String name, SpringDescription spring)> _presets =
      <(String, SpringDescription)>[
        ('Press', LifeOsMotionTokens.pressSpring),
        ('Snappy', LifeOsMotionTokens.snappySpring),
        ('Bouncy', LifeOsMotionTokens.bouncySpring),
        ('Sheet', LifeOsMotionTokens.sheetSnapSpring),
      ];

  late final LifeOsSpringController _ctrl;
  int _presetIdx = 2;
  bool _atRight = false;

  @override
  void initState() {
    super.initState();
    _ctrl = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: _presets[_presetIdx].$2,
    );
  }

  void _fire({int? newPresetIdx}) {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    if (newPresetIdx != null) {
      _presetIdx = newPresetIdx;
    }
    _atRight = !_atRight;
    _ctrl.spring = _presets[_presetIdx].$2;
    _ctrl.animateTo(
      _atRight ? 1.0 : 0.0,
      springOverride: _presets[_presetIdx].$2,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _Sample09Spring1DLab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _fire();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final selected = _presets[_presetIdx];
    final zeta = LifeOsMotionTokens.dampingRatioOf(selected.$2);

    return _SampleStage(
      height: 158,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (var i = 0; i < _presets.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: _CompactActionChip(
                    label: _presets[i].$1,
                    selected: _presetIdx == i,
                    onTap: () => _fire(newPresetIdx: i),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'k=${selected.$2.stiffness.toStringAsFixed(0)} · c=${selected.$2.damping.toStringAsFixed(1)} · ζ=${zeta.toStringAsFixed(2)}',
                    style: _tabularStyle(
                      color: c.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _CompactActionChip(
                label: 'Bắn thử',
                icon: Icons.bolt_rounded,
                onTap: _fire,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _fire,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: c.border),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const puckSize = 32.0;
                    final travel = math.max(
                      12.0,
                      constraints.maxWidth - puckSize - 16.0,
                    );
                    return AnimatedBuilder(
                      animation: _ctrl,
                      builder: (context, _) {
                        final rawX = 8.0 + (_ctrl.value * travel);
                        final clampedX = rawX
                            .clamp(
                              0.0,
                              math.max(0.0, constraints.maxWidth - puckSize),
                            )
                            .toDouble();
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: <Widget>[
                            Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: c.separator,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            Positioned(
                              left: 8.0 + travel + puckSize / 2,
                              top: 8,
                              bottom: 8,
                              child: Container(
                                width: 1.5,
                                color: c.primary.withValues(alpha: 0.35),
                              ),
                            ),
                            Positioned(
                              left: clampedX,
                              child: Container(
                                width: puckSize,
                                height: puckSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c.primary,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: c.primary.withValues(alpha: 0.30),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #10 — 2D Free-Throw Draggable Puck (LifeOsSpring2DController)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample10FreeThrow2D extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample10FreeThrow2D({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample10FreeThrow2D> createState() => _Sample10FreeThrow2DState();
}

class _Sample10FreeThrow2DState extends State<_Sample10FreeThrow2D>
    with TickerProviderStateMixin {
  late final LifeOsSpring2DController _ctrl;
  double _lastSpeedPx = 0.0;

  @override
  void initState() {
    super.initState();
    _ctrl = LifeOsSpring2DController(
      vsync: this,
      spring: LifeOsMotionTokens.gestureThrowSpring,
    );
  }

  void _impulseThrow() {
    final motion = LifeOsMotionScope.read(context);
    motion.lightHaptic();
    _lastSpeedPx = 920.0;
    _ctrl.jumpTo(const Offset(52, -24));
    _ctrl.animateTo(
      Offset.zero,
      velocityPxPerSec: const Offset(-680, 420),
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _Sample10FreeThrow2D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _impulseThrow();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return _SampleStage(
      height: 156,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxDx = math.max(24.0, constraints.maxWidth * 0.40);
          final maxDy = math.max(18.0, constraints.maxHeight * 0.34);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _impulseThrow,
            onPanStart: (_) => _ctrl.stop(),
            onPanUpdate: (d) {
              final next = _ctrl.value + d.delta;
              _ctrl.jumpTo(
                Offset(
                  next.dx.clamp(-maxDx, maxDx),
                  next.dy.clamp(-maxDy, maxDy),
                ),
              );
            },
            onPanEnd: (d) {
              final v = d.velocity.pixelsPerSecond;
              setState(() => _lastSpeedPx = v.distance);
              _ctrl.animateTo(
                Offset.zero,
                velocityPxPerSec: v,
                motion: motion,
                tickersEnabled: TickerMode.valuesOf(context).enabled,
                timeDilationFactor: widget.speedFactor,
              );
            },
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final offset = motion.resolveOffset(_ctrl.value);
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TetherLinePainter(
                          offset: offset,
                          color: c.primary.withValues(alpha: 0.28),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      top: 2,
                      right: 4,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Kéo & vẩy tự do 2D (chạm để thử)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_lastSpeedPx.round()} px/s',
                            style: _tabularStyle(
                              color: c.primary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.translate(
                      offset: offset,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: LifeOSBrandColors.appIconBgGradient,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: c.primary.withValues(alpha: 0.32),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.open_with_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TetherLinePainter extends CustomPainter {
  final Offset offset;
  final Color color;

  const _TetherLinePainter({required this.offset, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final target = center + offset;
    canvas.drawCircle(
      center,
      5,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawLine(
      center,
      target,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TetherLinePainter oldDelegate) =>
      oldDelegate.offset != offset || oldDelegate.color != color;
}

// ═════════════════════════════════════════════════════════════════════════════
// #11 — Mid-Flight Retargeting Chase (Trái · Giữa · Phải, C¹ Velocity)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample11RetargetChase extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample11RetargetChase({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample11RetargetChase> createState() => _Sample11RetargetChaseState();
}

class _Sample11RetargetChaseState extends State<_Sample11RetargetChase>
    with SingleTickerProviderStateMixin {
  static const List<(String label, double pos)> _targets = <(String, double)>[
    ('Trái', -1.0),
    ('Giữa', 0.0),
    ('Phải', 1.0),
  ];

  late final LifeOsSpringController _ctrl;
  int _targetIdx = 1;

  @override
  void initState() {
    super.initState();
    _ctrl = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: LifeOsMotionTokens.gestureThrowSpring,
    );
  }

  void _retarget(int index) {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    setState(() => _targetIdx = index);
    _ctrl.animateTo(
      _targets[index].$2,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  void didUpdateWidget(covariant _Sample11RetargetChase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _retarget((_targetIdx + 1) % _targets.length);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return _SampleStage(
      height: 154,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (var i = 0; i < _targets.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _CompactActionChip(
                    label: _targets[i].$1,
                    selected: _targetIdx == i,
                    onTap: () => _retarget(i),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: c.border),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final halfSpan = math.max(
                    16.0,
                    (constraints.maxWidth - 44.0) / 2.0,
                  );
                  return AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      final dx = (_ctrl.value * halfSpan).clamp(
                        -halfSpan,
                        halfSpan,
                      );
                      return Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List<Widget>.generate(3, (i) {
                              final active = _targetIdx == i;
                              return GestureDetector(
                                onTap: () => _retarget(i),
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: active
                                        ? c.primary.withValues(alpha: 0.28)
                                        : c.separator,
                                    border: Border.all(
                                      color: active ? c.primary : c.border,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          Transform.translate(
                            offset: Offset(dx, 0),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: c.primary,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    _ctrl.velocity.abs().toStringAsFixed(1),
                                    style: _tabularStyle(
                                      color: c.onPrimary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #12 — LifeOsPhysicsAnimatedBox Morphing Container
// ═════════════════════════════════════════════════════════════════════════════
class _Sample12PhysicsAnimatedBox extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample12PhysicsAnimatedBox({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample12PhysicsAnimatedBox> createState() =>
      _Sample12PhysicsAnimatedBoxState();
}

class _Sample12PhysicsAnimatedBoxState
    extends State<_Sample12PhysicsAnimatedBox> {
  int _mode = 0;

  void _cycle([int? target]) {
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() => _mode = target ?? ((_mode + 1) % 3));
  }

  @override
  void didUpdateWidget(covariant _Sample12PhysicsAnimatedBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _cycle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    const labels = <String>['Viên nang', 'Thẻ vuông', 'Thanh rộng'];

    return _SampleStage(
      height: 156,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (var i = 0; i < labels.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _CompactActionChip(
                    label: labels[i],
                    selected: _mode == i,
                    onTap: () => _cycle(i),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final maxH = constraints.maxHeight;
                final (
                  double w,
                  double h,
                  double r,
                  Color col,
                  String txt,
                ) = switch (_mode) {
                  0 => (
                    math.min(138.0, maxW * 0.56),
                    math.min(46.0, maxH * 0.54),
                    99.0,
                    c.primary,
                    '2.450.000 ₫',
                  ),
                  1 => (
                    math.min(116.0, maxW * 0.48),
                    math.min(82.0, maxH * 0.88),
                    20.0,
                    c.secondary,
                    'Tiết kiệm 72%',
                  ),
                  _ => (
                    math.max(120.0, maxW - 8.0),
                    math.min(62.0, maxH * 0.72),
                    14.0,
                    LifeOSBrandColors.forest,
                    'Đã đồng bộ Sổ Gia đình',
                  ),
                };

                return Center(
                  child: GestureDetector(
                    onTap: _cycle,
                    child: LifeOsPhysicsAnimatedBox(
                      width: w,
                      height: h,
                      borderRadius: r,
                      color: col,
                      spring: LifeOsMotionTokens.bouncySpring,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          txt,
                          style: _tabularStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #13 — Magnetic 4-Corner Snap (projectNearestDetent)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample13MagneticCorners extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample13MagneticCorners({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample13MagneticCorners> createState() =>
      _Sample13MagneticCornersState();
}

class _Sample13MagneticCornersState extends State<_Sample13MagneticCorners>
    with TickerProviderStateMixin {
  late final LifeOsSpring2DController _ctrl;
  int _cornerIdx = 0; // 0: TL, 1: TR, 2: BR, 3: BL
  double _spanX = 80.0;
  double _spanY = 34.0;
  bool _initializedCorner = false;

  @override
  void initState() {
    super.initState();
    _ctrl = LifeOsSpring2DController(
      vsync: this,
      spring: LifeOsMotionTokens.snappySpring,
    );
  }

  Offset _cornerOffset(int idx, double sx, double sy) {
    return switch (idx % 4) {
      0 => Offset(-sx, -sy),
      1 => Offset(sx, -sy),
      2 => Offset(sx, sy),
      _ => Offset(-sx, sy),
    };
  }

  void _snapToCorner(int idx, {Offset? velocity}) {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    _cornerIdx = idx % 4;
    _ctrl.animateTo(
      _cornerOffset(_cornerIdx, _spanX, _spanY),
      velocityPxPerSec: velocity,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _Sample13MagneticCorners oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _snapToCorner((_cornerIdx + 1) % 4);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    const cornerNames = <String>[
      'Trái-Trên',
      'Phải-Trên',
      'Phải-Dưới',
      'Trái-Dưới',
    ];

    return _SampleStage(
      height: 158,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _spanX = math.max(24.0, (constraints.maxWidth - 88.0) / 2.0);
          _spanY = math.max(16.0, (constraints.maxHeight - 54.0) / 2.0);
          if (!_initializedCorner) {
            _initializedCorner = true;
            _ctrl.jumpTo(_cornerOffset(_cornerIdx, _spanX, _spanY));
          }

          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              for (var i = 0; i < 4; i++)
                Transform.translate(
                  offset: _cornerOffset(i, _spanX, _spanY),
                  child: GestureDetector(
                    onTap: () => _snapToCorner(i),
                    child: Container(
                      width: 68,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _cornerIdx == i
                            ? c.primarySubtle
                            : c.surface.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: _cornerIdx == i ? c.primary : c.border,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            cornerNames[i],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Text(
                'Vẩy thẻ về 4 góc nam châm',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  return Transform.translate(
                    offset: _ctrl.value,
                    child: GestureDetector(
                      onTap: () => _snapToCorner((_cornerIdx + 1) % 4),
                      onPanStart: (_) => _ctrl.stop(),
                      onPanUpdate: (d) => _ctrl.addDelta(d.delta),
                      onPanEnd: (d) {
                        final v = d.velocity.pixelsPerSecond;
                        final snapX = LifeOsMotionTokens.projectNearestDetent(
                          current: _ctrl.value.dx,
                          velocityPerSec: v.dx,
                          detents: <double>[-_spanX, _spanX],
                        );
                        final snapY = LifeOsMotionTokens.projectNearestDetent(
                          current: _ctrl.value.dy,
                          velocityPerSec: v.dy,
                          detents: <double>[-_spanY, _spanY],
                        );
                        final nextIdx = snapY < 0
                            ? (snapX < 0 ? 0 : 1)
                            : (snapX >= 0 ? 2 : 3);
                        _snapToCorner(nextIdx, velocity: v);
                      },
                      child: Container(
                        width: 72,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c.primary,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: c.primary.withValues(alpha: 0.30),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.picture_in_picture_alt_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'PiP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #14 — Swipeable Decision Card (Duyệt / Bỏ qua + Spring Settle)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample14SwipeDecisionCard extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample14SwipeDecisionCard({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample14SwipeDecisionCard> createState() =>
      _Sample14SwipeDecisionCardState();
}

class _Sample14SwipeDecisionCardState extends State<_Sample14SwipeDecisionCard>
    with SingleTickerProviderStateMixin {
  static const List<(String title, String amount)> _bills = <(String, String)>[
    ('Hóa đơn Điện EVN', '680.000 ₫'),
    ('Phí Quản lý Căn hộ', '850.000 ₫'),
    ('Internet Cáp quang', '240.000 ₫'),
  ];

  late final LifeOsSpringController _dxCtrl;
  int _billIdx = 0;
  String _lastDecision = 'Kéo ngang hoặc bấm Duyệt';

  @override
  void initState() {
    super.initState();
    _dxCtrl = LifeOsSpringController(
      vsync: this,
      spring: LifeOsMotionTokens.gestureThrowSpring,
      tolerance: LifeOsMotionTokens.pixelSpringTolerance,
    );
  }

  void _commitDecision(bool approved) {
    final motion = LifeOsMotionScope.read(context);
    motion.lightHaptic();
    setState(() {
      _billIdx = (_billIdx + 1) % _bills.length;
      _lastDecision = approved ? 'Đã duyệt thanh toán' : 'Đã tạm hoãn';
    });
    _dxCtrl.jumpTo(approved ? -26.0 : 26.0);
    _dxCtrl.animateTo(
      0.0,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  void didUpdateWidget(covariant _Sample14SwipeDecisionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _commitDecision(true);
    }
  }

  @override
  void dispose() {
    _dxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final bill = _bills[_billIdx];

    return _SampleStage(
      height: 158,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _lastDecision,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
              _CompactActionChip(
                label: 'Bỏ qua',
                icon: Icons.close_rounded,
                activeColor: c.warning,
                onTap: () => _commitDecision(false),
              ),
              const SizedBox(width: 6),
              _CompactActionChip(
                label: 'Duyệt',
                icon: Icons.check_rounded,
                selected: true,
                onTap: () => _commitDecision(true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GestureDetector(
              onHorizontalDragStart: (_) => _dxCtrl.stop(),
              onHorizontalDragUpdate: (d) => _dxCtrl.jumpTo(
                (_dxCtrl.value + d.delta.dx).clamp(-120.0, 120.0),
              ),
              onHorizontalDragEnd: (d) {
                final vx = d.velocity.pixelsPerSecond.dx;
                if (_dxCtrl.value > 58 || vx > 650) {
                  _commitDecision(true);
                } else if (_dxCtrl.value < -58 || vx < -650) {
                  _commitDecision(false);
                } else {
                  _dxCtrl.animateTo(
                    0.0,
                    velocity: vx,
                    motion: motion,
                    tickersEnabled: TickerMode.valuesOf(context).enabled,
                    timeDilationFactor: widget.speedFactor,
                  );
                }
              },
              child: AnimatedBuilder(
                animation: _dxCtrl,
                builder: (context, _) {
                  final dx = motion.isReducedMotion ? 0.0 : _dxCtrl.value;
                  final ratio = (dx / 90.0).clamp(-1.0, 1.0);
                  final tint = ratio >= 0
                      ? Color.lerp(c.surface, c.successSubtle, ratio.abs())!
                      : Color.lerp(c.surface, c.warningSubtle, ratio.abs())!;

                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: Transform.rotate(
                      angle: motion.isReducedMotion ? 0.0 : ratio * 0.09,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: tint,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: ratio.abs() > 0.25
                                ? (ratio > 0 ? c.success : c.warning)
                                : c.border,
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              ratio < -0.2
                                  ? Icons.schedule_rounded
                                  : Icons.receipt_rounded,
                              color: ratio < -0.2 ? c.warning : c.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      bill.$1,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      bill.$2,
                                      style: _tabularStyle(
                                        color: c.primary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Icon(
                              Icons.swipe_rounded,
                              size: 18,
                              color: c.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #15 — Hyperbolic Rubber-Band Over-Drag (LifeOsMotionTokens.rubberBandClamp)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample15RubberBandPull extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample15RubberBandPull({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample15RubberBandPull> createState() =>
      _Sample15RubberBandPullState();
}

class _Sample15RubberBandPullState extends State<_Sample15RubberBandPull>
    with SingleTickerProviderStateMixin {
  late final LifeOsSpringController _ctrl;
  double _rawInput = 0.0;

  @override
  void initState() {
    super.initState();
    _ctrl = LifeOsSpringController(
      vsync: this,
      spring: LifeOsMotionTokens.sheetSnapSpring,
      tolerance: LifeOsMotionTokens.pixelSpringTolerance,
    );
  }

  void _demoStretch() {
    final motion = LifeOsMotionScope.read(context);
    motion.lightHaptic();
    _rawInput = 120.0;
    final resisted = LifeOsMotionTokens.rubberBandClamp(
      _rawInput,
      min: -24.0,
      max: 24.0,
      viewportExtent: 140.0,
      resistance: 0.55,
    );
    _ctrl.jumpTo(resisted);
    _ctrl.animateTo(
      0.0,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _Sample15RubberBandPull oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _demoStretch();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return _SampleStage(
      height: 154,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Thô: ${_rawInput.toStringAsFixed(0)}px · Sau cản: ${_ctrl.value.toStringAsFixed(1)}px',
                      style: _tabularStyle(
                        color: c.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: _CompactActionChip(
                  label: 'Kéo vượt biên',
                  icon: Icons.compare_arrows_rounded,
                  onTap: _demoStretch,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _demoStretch,
                  onHorizontalDragStart: (_) {
                    _ctrl.stop();
                    _rawInput = _ctrl.value;
                  },
                  onHorizontalDragUpdate: (d) {
                    _rawInput += d.delta.dx;
                    final clamped = LifeOsMotionTokens.rubberBandClamp(
                      _rawInput,
                      min: -24.0,
                      max: 24.0,
                      viewportExtent: constraints.maxWidth,
                      resistance: 0.55,
                    );
                    _ctrl.jumpTo(clamped);
                    setState(() {});
                  },
                  onHorizontalDragEnd: (d) {
                    _rawInput = 0.0;
                    _ctrl.animateTo(
                      0.0,
                      velocity: d.velocity.pixelsPerSecond.dx * 0.35,
                      motion: motion,
                      tickersEnabled: TickerMode.valuesOf(context).enabled,
                      timeDilationFactor: widget.speedFactor,
                    );
                    setState(() {});
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: c.border),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (context, _) {
                        final dx = motion.isReducedMotion ? 0.0 : _ctrl.value;
                        final stretch =
                            1.0 + (dx.abs() / 240.0).clamp(0.0, 0.22);
                        return Transform.translate(
                          offset: Offset(dx, 0),
                          child: Transform.scale(
                            scaleX: motion.isReducedMotion ? 1.0 : stretch,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.primarySubtle,
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(color: c.primary),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        Icons.drag_indicator_rounded,
                                        size: 16,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Kéo căng dây thun',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: c.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #16 — Multi-Node Spring Hanging Chain (5-Node CustomPainter)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample16SpringRopeChain extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample16SpringRopeChain({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample16SpringRopeChain> createState() =>
      _Sample16SpringRopeChainState();
}

class _Sample16SpringRopeChainState extends State<_Sample16SpringRopeChain>
    with TickerProviderStateMixin {
  late final List<LifeOsSpringController> _nodeY;

  @override
  void initState() {
    super.initState();
    _nodeY = List<LifeOsSpringController>.generate(5, (i) {
      return LifeOsSpringController(
        vsync: this,
        spring: SpringDescription(
          mass: 1.0 + i * 0.22,
          stiffness: 360.0 - i * 32.0,
          damping: 20.0 + i * 2.4,
        ),
        tolerance: LifeOsMotionTokens.pixelSpringTolerance,
      );
    });
  }

  void _pluck([double peakDy = 28.0]) {
    final motion = LifeOsMotionScope.read(context);
    motion.lightHaptic();
    final tickers = TickerMode.valuesOf(context).enabled;
    for (var i = 0; i < _nodeY.length; i++) {
      final weight = 1.0 - (i - 2).abs() * 0.25;
      _nodeY[i].jumpTo(peakDy * weight);
      _nodeY[i].animateTo(
        0.0,
        velocity: -220.0 * weight,
        motion: motion,
        tickersEnabled: tickers,
        timeDilationFactor: widget.speedFactor,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _Sample16SpringRopeChain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _pluck();
    }
  }

  @override
  void dispose() {
    for (final ctrl in _nodeY) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return _SampleStage(
      height: 154,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pluck(28.0),
        onPanUpdate: (d) {
          final box = context.findRenderObject() as RenderBox?;
          final w = (box != null && box.hasSize) ? box.size.width : 280.0;
          final focus = ((d.localPosition.dx / w) * 4.0).clamp(0.0, 4.0);
          final dy = (d.localPosition.dy - 78.0).clamp(-34.0, 34.0);
          for (var i = 0; i < _nodeY.length; i++) {
            final dist = (i - focus).abs();
            final factor = (1.0 - dist * 0.28).clamp(0.15, 1.0);
            _nodeY[i].jumpTo(dy * factor);
          }
        },
        onPanEnd: (d) {
          final vy = d.velocity.pixelsPerSecond.dy;
          final tickers = TickerMode.valuesOf(context).enabled;
          for (var i = 0; i < _nodeY.length; i++) {
            _nodeY[i].animateTo(
              0.0,
              velocity: vy * (1.0 - i * 0.12),
              motion: motion,
              tickersEnabled: tickers,
              timeDilationFactor: widget.speedFactor,
            );
          }
        },
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 4,
              top: 2,
              right: 4,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Chạm hoặc kéo gẩy chuỗi 5 nút lò xo',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  _CompactActionChip(
                    label: 'Gẩy dây',
                    icon: Icons.waves_rounded,
                    onTap: () => _pluck(-28.0),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              top: 28,
              child: AnimatedBuilder(
                animation: Listenable.merge(_nodeY),
                builder: (context, _) {
                  final offsets = List<double>.generate(
                    _nodeY.length,
                    (i) => motion.isReducedMotion ? 0.0 : _nodeY[i].value,
                  );
                  return CustomPaint(
                    painter: _SpringRopePainter(
                      nodeOffsetsY: offsets,
                      primary: c.primary,
                      accent: LifeOSBrandColors.primaryLight,
                      anchorColor: c.border,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpringRopePainter extends CustomPainter {
  final List<double> nodeOffsetsY;
  final Color primary;
  final Color accent;
  final Color anchorColor;

  const _SpringRopePainter({
    required this.nodeOffsetsY,
    required this.primary,
    required this.accent,
    required this.anchorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * 0.52;
    final leftPin = Offset(14, midY);
    final rightPin = Offset(size.width - 14, midY);
    final span = rightPin.dx - leftPin.dx;

    final pts = <Offset>[
      leftPin,
      for (var i = 0; i < nodeOffsetsY.length; i++)
        Offset(
          leftPin.dx + span * ((i + 1) / (nodeOffsetsY.length + 1)),
          midY + nodeOffsetsY[i],
        ),
      rightPin,
    ];

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final mid = Offset(
        (pts[i].dx + pts[i + 1].dx) / 2,
        (pts[i].dy + pts[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = primary.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(leftPin, 4.5, Paint()..color = anchorColor);
    canvas.drawCircle(rightPin, 4.5, Paint()..color = anchorColor);

    for (var i = 1; i < pts.length - 1; i++) {
      canvas.drawCircle(pts[i], 9.5, Paint()..color = primary);
      canvas.drawCircle(
        pts[i] - const Offset(2.2, 2.2),
        3.2,
        Paint()..color = accent.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpringRopePainter oldDelegate) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// #17 — Scrubbing Liquid Capsule (Velocity Stretch)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample17ScrubDockCapsule extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample17ScrubDockCapsule({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample17ScrubDockCapsule> createState() =>
      _Sample17ScrubDockCapsuleState();
}

class _Sample17ScrubDockCapsuleState extends State<_Sample17ScrubDockCapsule>
    with TickerProviderStateMixin {
  static const List<(String label, IconData icon)> _items =
      <(String, IconData)>[
        ('Hôm nay', Icons.wb_sunny_outlined),
        ('Thu chi', Icons.account_balance_wallet_outlined),
        ('Lịch', Icons.calendar_month_outlined),
        ('Tài sản', Icons.pie_chart_outline_rounded),
      ];

  late final LifeOsSpringController _slotCtrl;
  late final LifeOsSpringController _stretchCtrl;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _slotCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: LifeOsMotionTokens.snappySpring,
    );
    _stretchCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: LifeOsMotionTokens.pressSpring,
    );
  }

  void _selectSlot(int idx) {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    final tickers = TickerMode.valuesOf(context).enabled;
    setState(() => _selected = idx.clamp(0, _items.length - 1));
    _stretchCtrl.jumpTo(12.0);
    _stretchCtrl.animateTo(
      0.0,
      motion: motion,
      tickersEnabled: tickers,
      timeDilationFactor: widget.speedFactor,
    );
    _slotCtrl.animateTo(
      _selected.toDouble(),
      motion: motion,
      tickersEnabled: tickers,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  void didUpdateWidget(covariant _Sample17ScrubDockCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _selectSlot((_selected + 1) % _items.length);
    }
  }

  @override
  void dispose() {
    _slotCtrl.dispose();
    _stretchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return _SampleStage(
      height: 148,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Trượt ngón tay ngang thanh dock · Đang chọn: ${_items[_selected].$1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final slotW = constraints.maxWidth / _items.length;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) {
                  final rawSlot = ((d.localPosition.dx / slotW) - 0.5).clamp(
                    0.0,
                    (_items.length - 1).toDouble(),
                  );
                  _slotCtrl.jumpTo(rawSlot);
                  _stretchCtrl.jumpTo(
                    (d.delta.dx.abs() * 1.8).clamp(0.0, 18.0),
                  );
                  final nearest = rawSlot.round();
                  if (nearest != _selected) {
                    motion.selectionHaptic();
                    setState(() => _selected = nearest);
                  }
                },
                onHorizontalDragEnd: (d) {
                  final tickers = TickerMode.valuesOf(context).enabled;
                  _stretchCtrl.animateTo(
                    0.0,
                    motion: motion,
                    tickersEnabled: tickers,
                    timeDilationFactor: widget.speedFactor,
                  );
                  _slotCtrl.animateTo(
                    _selected.toDouble(),
                    motion: motion,
                    tickersEnabled: tickers,
                    timeDilationFactor: widget.speedFactor,
                  );
                },
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: c.border),
                  ),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      AnimatedBuilder(
                        animation: Listenable.merge(<Listenable>[
                          _slotCtrl,
                          _stretchCtrl,
                        ]),
                        builder: (context, _) {
                          final extra = motion.isReducedMotion
                              ? 0.0
                              : _stretchCtrl.value;
                          final pillW = math.max(24.0, slotW - 8.0 + extra);
                          final left =
                              (_slotCtrl.value * slotW + 4.0 - extra / 2)
                                  .clamp(
                                    4.0,
                                    math.max(
                                      4.0,
                                      constraints.maxWidth - pillW - 4.0,
                                    ),
                                  )
                                  .toDouble();
                          return Positioned(
                            left: left,
                            top: 5,
                            bottom: 5,
                            width: pillW,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.primarySubtle,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: c.primary.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Row(
                        children: <Widget>[
                          for (var i = 0; i < _items.length; i++)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _selectSlot(i),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Icon(
                                          _items[i].$2,
                                          size: 19,
                                          color: _selected == i
                                              ? c.primary
                                              : c.textSecondary,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _items[i].$1,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: _selected == i
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: _selected == i
                                                ? c.primary
                                                : c.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #18 — LifeOsPressable Tactile Squish (Outer 48dp Hit Target Preserved)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample18PressableSquish extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample18PressableSquish({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample18PressableSquish> createState() =>
      _Sample18PressableSquishState();
}

class _Sample18PressableSquishState extends State<_Sample18PressableSquish> {
  int _count = 12;

  @override
  void didUpdateWidget(covariant _Sample18PressableSquish oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      setState(() => _count++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return _SampleStage(
      height: 148,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Khung chạm chuẩn 48dp không bị co nhỏ khi nhấn',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              LifeOsTruthfulNumericText(
                formattedValue: '$_count lần',
                style: _tabularStyle(color: c.primary, fontSize: 14),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: c.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: LifeOsPressable(
                    pressedScale: LifeOsMotionTokens.pressedScaleCompact,
                    haptic: LifeOsPressHaptic.light,
                    semanticsLabel: 'Ghi nhận tương tác chuẩn 48dp',
                    onPressed: () => setState(() => _count++),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.primary,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.touch_app_rounded,
                              color: c.onPrimary,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Nhấn đàn hồi (+1)',
                              style: TextStyle(
                                color: c.onPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              LifeOsPressable(
                pressedScale: LifeOsMotionTokens.pressedScaleCompact,
                semanticsLabel: 'Đặt lại bộ đếm',
                onPressed: () => setState(() => _count = 0),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: c.border),
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: c.textPrimary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #19 — Morphing Action Button (Xác nhận -> Xử lý -> Đã lưu + OneShotTracker)
// ═════════════════════════════════════════════════════════════════════════════
enum _CtaPhase { idle, processing, saved }

class _Sample19MorphingCta extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample19MorphingCta({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample19MorphingCta> createState() => _Sample19MorphingCtaState();
}

class _Sample19MorphingCtaState extends State<_Sample19MorphingCta>
    with SingleTickerProviderStateMixin {
  final LifeOsOneShotEffectTracker _tracker = LifeOsOneShotEffectTracker();
  late final AnimationController _processCtrl;
  _CtaPhase _phase = _CtaPhase.idle;
  int _txSeq = 1;
  String _note = 'Sẵn sàng lưu mã tx_01';

  String get _currentKey => 'tx_${_txSeq.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _processCtrl =
        AnimationController(vsync: this, duration: LifeOsMotionTokens.medium)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              final isFresh = _tracker.consumeOnce(_currentKey);
              setState(() {
                _phase = _CtaPhase.saved;
                _note = isFresh
                    ? 'Đã lưu $_currentKey (hiệu ứng 1 lần)'
                    : 'Bỏ qua lặp lại mã $_currentKey';
              });
            }
          });
  }

  void _triggerSubmit() {
    if (_phase == _CtaPhase.processing) return;
    final motion = LifeOsMotionScope.read(context);
    if (_tracker.hasConsumed(_currentKey)) {
      motion.selectionHaptic();
      setState(() {
        _phase = _CtaPhase.saved;
        _note = 'Chặn phát lại hiệu ứng trùng $_currentKey';
      });
      return;
    }
    motion.lightHaptic();
    final dur = _scaledDuration(
      motion,
      LifeOsMotionTokens.medium,
      widget.speedFactor,
    );
    if (dur == Duration.zero || !TickerMode.valuesOf(context).enabled) {
      _tracker.consumeOnce(_currentKey);
      setState(() {
        _phase = _CtaPhase.saved;
        _note = 'Đã lưu $_currentKey tức thì';
      });
      return;
    }
    setState(() {
      _phase = _CtaPhase.processing;
      _note = 'Đang xác thực $_currentKey...';
    });
    _processCtrl.duration = dur;
    _processCtrl.forward(from: 0.0);
  }

  void _newTransaction() {
    _processCtrl.stop();
    setState(() {
      _txSeq++;
      _phase = _CtaPhase.idle;
      _note = 'Sẵn sàng lưu mã $_currentKey';
    });
  }

  @override
  void didUpdateWidget(covariant _Sample19MorphingCta oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      if (_phase == _CtaPhase.saved) {
        _newTransaction();
      } else {
        _triggerSubmit();
      }
    }
  }

  @override
  void dispose() {
    _processCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final dur = _scaledDuration(
      motion,
      LifeOsMotionTokens.standard,
      widget.speedFactor,
    );

    final (Color bg, IconData icon, String label) = switch (_phase) {
      _CtaPhase.idle => (c.primary, Icons.send_rounded, 'Xác nhận'),
      _CtaPhase.processing => (c.secondary, Icons.sync_rounded, 'Đang xử lý'),
      _CtaPhase.saved => (c.success, Icons.check_circle_rounded, 'Đã lưu'),
    };

    return _SampleStage(
      height: 152,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _note,
                    style: _tabularStyle(
                      color: c.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _CompactActionChip(
                label: 'Mã mới',
                icon: Icons.add_rounded,
                onTap: _newTransaction,
              ),
            ],
          ),
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final targetW = switch (_phase) {
                  _CtaPhase.idle => math.min(184.0, constraints.maxWidth),
                  _CtaPhase.processing => math.min(146.0, constraints.maxWidth),
                  _CtaPhase.saved => math.min(164.0, constraints.maxWidth),
                };
                return AnimatedContainer(
                  duration: dur,
                  curve: LifeOsMotionTokens.emphasizedCurve,
                  width: targetW,
                  height: 48,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(
                      _phase == _CtaPhase.processing ? 99 : 14,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: _triggerSubmit,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: _scaledDuration(
                            motion,
                            LifeOsMotionTokens.micro,
                            widget.speedFactor,
                          ),
                          child: FittedBox(
                            key: ValueKey<_CtaPhase>(_phase),
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(icon, color: Colors.white, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #20 — Specular Shimmer Sweep (Finite 1-Pass lifeOsShimmer, Zero Idle Ticker)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample20ShimmerSweep extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample20ShimmerSweep({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample20ShimmerSweep> createState() => _Sample20ShimmerSweepState();
}

class _Sample20ShimmerSweepState extends State<_Sample20ShimmerSweep> {
  int _sweepTrigger = 0;

  void _sweep() {
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() => _sweepTrigger++);
  }

  @override
  void didUpdateWidget(covariant _Sample20ShimmerSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _sweep();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final sweepDur = _scaledDuration(
      motion,
      const Duration(milliseconds: 900),
      widget.speedFactor,
    );

    Widget badgeCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[LifeOSBrandColors.forest, LifeOSBrandColors.primary],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'Hạng Ngọc Lục Bảo · Đã xác thực',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Đã quét ánh kim: $_sweepTrigger nhịp hữu hạn',
                    style: _tabularStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (_sweepTrigger > 0 && sweepDur > Duration.zero) {
      badgeCard = KeyedSubtree(
        key: ValueKey<int>(_sweepTrigger),
        child: badgeCard.lifeOsShimmer(
          context: context,
          active: true,
          duration: sweepDur,
        ),
      );
    }

    return _SampleStage(
      height: 148,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Chạm thẻ để quét đúng 1 nhịp sáng',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _CompactActionChip(
                label: 'Quét sáng',
                icon: Icons.flare_rounded,
                selected: _sweepTrigger > 0,
                onTap: _sweep,
              ),
            ],
          ),
          GestureDetector(onTap: _sweep, child: badgeCard),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #21 — Rotating Chevron & Privacy Mask Eye Swap
// ═════════════════════════════════════════════════════════════════════════════
class _Sample21IconMorphToggle extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample21IconMorphToggle({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample21IconMorphToggle> createState() =>
      _Sample21IconMorphToggleState();
}

class _Sample21IconMorphToggleState extends State<_Sample21IconMorphToggle> {
  static const String _rawInvite = 'FAM-8K2P9Q';
  static const String _rawPhone = '0912345678';

  bool _revealed = false;
  bool _chevronOpen = false;

  @override
  void didUpdateWidget(covariant _Sample21IconMorphToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      setState(() {
        _revealed = !_revealed;
        _chevronOpen = !_chevronOpen;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final dur = _scaledDuration(
      motion,
      LifeOsMotionTokens.micro,
      widget.speedFactor,
    );

    final inviteDisplay = _revealed
        ? _rawInvite
        : PrivacyMaskFormatter.maskCode(_rawInvite);
    final phoneDisplay = _revealed
        ? _rawPhone
        : PrivacyMaskFormatter.maskPhone(_rawPhone);

    return _SampleStage(
      height: 152,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.shield_outlined, color: c.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Mã mời nhóm: $inviteDisplay',
                          style: _tabularStyle(
                            color: c.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Liên hệ: $phoneDisplay',
                          style: _tabularStyle(
                            color: c.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _revealed ? 'Ẩn mã' : 'Hiện mã',
                  onPressed: () {
                    motion.selectionHaptic();
                    setState(() => _revealed = !_revealed);
                  },
                  icon: AnimatedSwitcher(
                    duration: dur,
                    child: Icon(
                      _revealed
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_outlined,
                      key: ValueKey<bool>(_revealed),
                      color: _revealed ? c.primary : c.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () {
              motion.selectionHaptic();
              setState(() => _chevronOpen = !_chevronOpen);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _chevronOpen
                            ? 'Đang mở ghi chú: Tự động che mặc định theo chuẩn bảo mật'
                            : 'Nhấn xoay mũi tên xem quy tắc bảo mật',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: motion.isReducedMotion
                        ? 0.0
                        : (_chevronOpen ? 0.5 : 0.0),
                    duration: dur,
                    curve: LifeOsMotionTokens.standardCurve,
                    child: Icon(
                      _chevronOpen && motion.isReducedMotion
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: c.primary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #22 — Spring Segmented Pill Track (snappySpring)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample22SegmentedPill extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample22SegmentedPill({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample22SegmentedPill> createState() => _Sample22SegmentedPillState();
}

class _Sample22SegmentedPillState extends State<_Sample22SegmentedPill>
    with SingleTickerProviderStateMixin {
  static const List<(String label, String amount)> _segments =
      <(String, String)>[
        ('Ngày', '320.000 ₫'),
        ('Tuần', '2.150.000 ₫'),
        ('Tháng', '8.940.000 ₫'),
      ];

  late final LifeOsSpringController _ctrl;
  int _idx = 1;

  @override
  void initState() {
    super.initState();
    _ctrl = LifeOsSpringController(
      vsync: this,
      initialValue: 1.0,
      spring: LifeOsMotionTokens.snappySpring,
    );
  }

  void _pick(int next) {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    setState(() => _idx = next);
    _ctrl.animateTo(
      next.toDouble(),
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  void didUpdateWidget(covariant _Sample22SegmentedPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _pick((_idx + 1) % _segments.length);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return _SampleStage(
      height: 148,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final segW = (constraints.maxWidth - 8.0) / _segments.length;
              return Container(
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: c.separator,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Stack(
                  children: <Widget>[
                    AnimatedBuilder(
                      animation: _ctrl,
                      builder: (context, _) {
                        final left = (_ctrl.value * segW)
                            .clamp(
                              0.0,
                              math.max(0.0, segW * (_segments.length - 1)),
                            )
                            .toDouble();
                        return Positioned(
                          left: left,
                          top: 0,
                          bottom: 0,
                          width: segW,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Row(
                      children: <Widget>[
                        for (var i = 0; i < _segments.length; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _pick(i),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _segments[i].$1,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: _idx == i
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: _idx == i
                                          ? c.primary
                                          : c.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Tổng chi theo ${_segments[_idx].$1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                LifeOsTruthfulNumericText(
                  formattedValue: _segments[_idx].$2,
                  style: _tabularStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #23 — Physics Switch Thumb & Filter Chip Pop
// ═════════════════════════════════════════════════════════════════════════════
class _Sample23PhysicsSwitchChip extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample23PhysicsSwitchChip({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample23PhysicsSwitchChip> createState() =>
      _Sample23PhysicsSwitchChipState();
}

class _Sample23PhysicsSwitchChipState extends State<_Sample23PhysicsSwitchChip>
    with SingleTickerProviderStateMixin {
  static const List<(String label, IconData icon)> _chips =
      <(String, IconData)>[
        ('Ăn uống', Icons.restaurant_rounded),
        ('Nhà cửa', Icons.home_outlined),
        ('Tiết kiệm', Icons.savings_outlined),
      ];

  late final LifeOsSpringController _switchCtrl;
  bool _autoSave = true;
  final Set<int> _activeChips = <int>{0, 2};

  @override
  void initState() {
    super.initState();
    _switchCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: 1.0,
      spring: LifeOsMotionTokens.snappySpring,
    );
  }

  void _toggleSwitch() {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    setState(() => _autoSave = !_autoSave);
    _switchCtrl.animateTo(
      _autoSave ? 1.0 : 0.0,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  void didUpdateWidget(covariant _Sample23PhysicsSwitchChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _toggleSwitch();
    }
  }

  @override
  void dispose() {
    _switchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return _SampleStage(
      height: 152,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleSwitch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    _autoSave
                        ? Icons.bolt_rounded
                        : Icons.pause_circle_outline_rounded,
                    color: _autoSave ? c.primary : c.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _autoSave
                            ? 'Trích quỹ tự động: Đang bật'
                            : 'Trích quỹ tự động: Tạm tắt',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _switchCtrl,
                    builder: (context, _) {
                      final t = _switchCtrl.value.clamp(0.0, 1.0);
                      final travel =
                          _switchCtrl.isAnimating && !motion.isReducedMotion
                          ? 5.0
                          : 0.0;
                      final thumbW = 22.0 + travel;
                      final left = 3.0 + t * (48.0 - thumbW - 6.0);
                      return Container(
                        width: 48,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color.lerp(c.separator, c.primary, t),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Stack(
                          children: <Widget>[
                            Positioned(
                              left: left,
                              top: 3,
                              width: thumbW,
                              height: 22,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: <Widget>[
              for (var i = 0; i < _chips.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: LifeOsPressable(
                    pressedScale: LifeOsMotionTokens.pressedScaleCompact,
                    onPressed: () {
                      setState(() {
                        if (_activeChips.contains(i)) {
                          _activeChips.remove(i);
                        } else {
                          _activeChips.add(i);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: _scaledDuration(
                        motion,
                        LifeOsMotionTokens.micro,
                        widget.speedFactor,
                      ),
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: _activeChips.contains(i)
                            ? c.primarySubtle
                            : c.surface,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: _activeChips.contains(i)
                              ? c.primary
                              : c.border,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              _activeChips.contains(i)
                                  ? Icons.check_circle_rounded
                                  : _chips[i].$2,
                              size: 14,
                              color: _activeChips.contains(i)
                                  ? c.primary
                                  : c.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _chips[i].$1,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _activeChips.contains(i)
                                    ? c.primary
                                    : c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #24 — Validation Error Shake (lifeOsErrorShake / ShakeEffect)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample24ErrorShake extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample24ErrorShake({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample24ErrorShake> createState() => _Sample24ErrorShakeState();
}

class _Sample24ErrorShakeState extends State<_Sample24ErrorShake> {
  int _shakeTrigger = 0;
  bool _hasError = false;

  void _triggerWrongPin() {
    LifeOsMotionScope.read(context).mediumHaptic();
    setState(() {
      _hasError = true;
      _shakeTrigger++;
    });
  }

  void _triggerValidPin() {
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() => _hasError = false);
  }

  @override
  void didUpdateWidget(covariant _Sample24ErrorShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _triggerWrongPin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    final pinBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _hasError ? c.errorSubtle : c.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _hasError ? c.error : c.border, width: 1.2),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            _hasError
                ? Icons.error_outline_rounded
                : Icons.verified_user_outlined,
            color: _hasError ? c.error : c.success,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _hasError
                    ? 'Mã PIN chưa khớp (lần $_shakeTrigger) · Vui lòng thử lại'
                    : 'Mã khóa Két Bảo mật: • • • • (Hợp lệ)',
                style: _tabularStyle(
                  color: _hasError ? c.error : c.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    ).lifeOsErrorShake(context: context, triggerCount: _shakeTrigger);

    return _SampleStage(
      height: 148,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          pinBox,
          Row(
            children: <Widget>[
              Expanded(
                child: _CompactActionChip(
                  label: 'Thử sai mã',
                  icon: Icons.gpp_bad_outlined,
                  selected: _hasError,
                  activeColor: c.error,
                  onTap: _triggerWrongPin,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactActionChip(
                  label: 'Nhập đúng',
                  icon: Icons.check_rounded,
                  selected: !_hasError,
                  onTap: _triggerValidPin,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #25 — Long-Press Radial Hold-to-Confirm Ring (CustomPainter)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample25HoldRadialConfirm extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample25HoldRadialConfirm({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample25HoldRadialConfirm> createState() =>
      _Sample25HoldRadialConfirmState();
}

class _Sample25HoldRadialConfirmState extends State<_Sample25HoldRadialConfirm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 650),
          reverseDuration: LifeOsMotionTokens.exitStandard,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            LifeOsMotionScope.read(context).mediumHaptic();
            setState(() => _confirmed = true);
          }
        });
  }

  void _startHold() {
    if (_confirmed) return;
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    final dur = _scaledDuration(
      motion,
      const Duration(milliseconds: 650),
      widget.speedFactor,
      reduced: const Duration(milliseconds: 220),
    );
    if (dur == Duration.zero || !TickerMode.valuesOf(context).enabled) {
      _ctrl.value = 1.0;
      setState(() => _confirmed = true);
      return;
    }
    _ctrl.duration = dur;
    _ctrl.forward();
  }

  void _cancelHold() {
    if (_confirmed) return;
    if (_ctrl.value < 1.0) {
      _ctrl.reverse();
    }
  }

  void _reset() {
    _ctrl.value = 0.0;
    setState(() => _confirmed = false);
  }

  @override
  void didUpdateWidget(covariant _Sample25HoldRadialConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      if (_confirmed) {
        _reset();
      } else {
        _ctrl.value = 1.0;
        setState(() => _confirmed = true);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return _SampleStage(
      height: 152,
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTapDown: (_) => _startHold(),
            onTapUp: (_) => _cancelHold(),
            onTapCancel: _cancelHold,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return SizedBox(
                  width: 68,
                  height: 68,
                  child: CustomPaint(
                    painter: _RadialHoldRingPainter(
                      progress: _ctrl.value,
                      trackColor: c.separator,
                      ringColor: _confirmed ? c.success : c.primary,
                    ),
                    child: Center(
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _confirmed ? c.success : c.primarySubtle,
                        ),
                        child: Icon(
                          _confirmed
                              ? Icons.check_rounded
                              : Icons.fingerprint_rounded,
                          color: _confirmed ? Colors.white : c.primary,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _confirmed
                        ? 'Đã xác nhận tất toán sổ!'
                        : 'Nhấn & giữ nút vân tay',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => Text(
                    'Tiến độ giữ: ${(_ctrl.value * 100).round()}%',
                    style: _tabularStyle(
                      color: _confirmed ? c.success : c.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (_confirmed)
                  _CompactActionChip(
                    label: 'Đặt lại',
                    icon: Icons.replay_rounded,
                    onTap: _reset,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RadialHoldRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color ringColor;

  const _RadialHoldRingPainter({
    required this.progress,
    required this.trackColor,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 4.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );

    if (progress > 0.0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadialHoldRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.ringColor != ringColor;
}

// ═════════════════════════════════════════════════════════════════════════════
// #26 — 3D Perspective Tilt Wallet Card (Matrix4..setEntry(3,2,0.0012))
// ═════════════════════════════════════════════════════════════════════════════
class _Sample26TiltWalletCard extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample26TiltWalletCard({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample26TiltWalletCard> createState() =>
      _Sample26TiltWalletCardState();
}

class _Sample26TiltWalletCardState extends State<_Sample26TiltWalletCard>
    with TickerProviderStateMixin {
  late final LifeOsSpring2DController _tiltCtrl;

  @override
  void initState() {
    super.initState();
    _tiltCtrl = LifeOsSpring2DController(
      vsync: this,
      spring: LifeOsMotionTokens.snappySpring,
      tolerance: LifeOsMotionTokens.springTolerance,
    );
  }

  void _demoTilt() {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    _tiltCtrl.jumpTo(const Offset(0.18, -0.14));
    _tiltCtrl.animateTo(
      Offset.zero,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  void didUpdateWidget(covariant _Sample26TiltWalletCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _demoTilt();
    }
  }

  @override
  void dispose() {
    _tiltCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final maskedCard = PrivacyMaskFormatter.maskCode('970412348899');

    return _SampleStage(
      height: 158,
      child: GestureDetector(
        onTap: _demoTilt,
        onPanUpdate: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize) {
            final nx = ((d.localPosition.dx / box.size.width) - 0.5) * 2.0;
            final ny = ((d.localPosition.dy / box.size.height) - 0.5) * 2.0;
            _tiltCtrl.jumpTo(
              Offset(
                (nx * 0.22).clamp(-0.26, 0.26),
                (-ny * 0.20).clamp(-0.24, 0.24),
              ),
            );
          }
        },
        onPanEnd: (_) {
          _tiltCtrl.animateTo(
            Offset.zero,
            motion: motion,
            tickersEnabled: TickerMode.valuesOf(context).enabled,
            timeDilationFactor: widget.speedFactor,
          );
        },
        child: Center(
          child: AnimatedBuilder(
            animation: _tiltCtrl,
            builder: (context, _) {
              final ry = motion.isReducedMotion ? 0.0 : _tiltCtrl.value.dx;
              final rx = motion.isReducedMotion ? 0.0 : _tiltCtrl.value.dy;
              final matrix = Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(rx)
                ..rotateY(ry);

              return Transform(
                alignment: Alignment.center,
                transform: matrix,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment(-0.8 + ry * 2.0, -0.9 + rx * 2.0),
                      end: const Alignment(0.9, 0.9),
                      colors: const <Color>[
                        LifeOSBrandColors.forest,
                        LifeOSBrandColors.primary,
                        Color(0xFF159943),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: LifeOSBrandColors.primary.withValues(
                          alpha: 0.28,
                        ),
                        blurRadius: 14,
                        offset: Offset(-ry * 18, 6 + rx * 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 28,
                            height: 20,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCD34D),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Ví Chính LifeOS · Đã xác thực',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '24.680.000 ₫',
                          style: _tabularStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              maskedCard,
                              style: _tabularStyle(
                                color: Colors.white.withValues(alpha: 0.84),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            'Kéo nghiêng 3D',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.80),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #27 — LifeOsPerspectiveCarousel (scrollRatio 3D Carousel)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample27PerspectiveCarousel extends StatelessWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample27PerspectiveCarousel({
    required this.speedFactor,
    required this.replaySeed,
  });

  static const List<(String name, String balance, Color color, IconData icon)>
  _jars = <(String, String, Color, IconData)>[
    ('Quỹ Dự phòng', '45.000.000 ₫', Color(0xFF0B7A2A), Icons.shield_rounded),
    ('Tổ ấm & Nhà cửa', '120.000.000 ₫', Color(0xFF1D4ED8), Icons.home_rounded),
    ('Quỹ Giáo dục', '32.500.000 ₫', Color(0xFF6D28D9), Icons.school_rounded),
    (
      'Trải nghiệm Gia đình',
      '14.800.000 ₫',
      Color(0xFFB45309),
      Icons.flight_takeoff_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final initial = (replaySeed - 1).abs() % _jars.length;

    return _SampleStage(
      height: 158,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LifeOsPerspectiveCarousel(
        key: ValueKey<int>(replaySeed),
        height: 136,
        viewportFraction: 0.80,
        initialIndex: initial,
        children: <Widget>[
          for (final jar in _jars)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: jar.$3,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(jar.$4, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            jar.$1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      jar.$2,
                      style: _tabularStyle(
                        color: Colors.white,
                        fontSize: 18.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'Vuốt ngang xem hũ kế tiếp',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #28 — Stacked Apple Wallet Fan Deck (3 Cards, Tap Brings to Front)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample28WalletFanDeck extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample28WalletFanDeck({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample28WalletFanDeck> createState() => _Sample28WalletFanDeckState();
}

class _Sample28WalletFanDeckState extends State<_Sample28WalletFanDeck> {
  static const List<(String id, String title, String amount, Color bg)> _cards =
      <(String, String, String, Color)>[
        ('cash', 'Ví Tiền mặt Gia đình', '4.250.000 ₫', Color(0xFF0B7A2A)),
        ('bank', 'Ngân hàng Lương chính', '18.900.000 ₫', Color(0xFF1E3A8A)),
        ('save', 'Thẻ Tiết kiệm Linh hoạt', '52.000.000 ₫', Color(0xFF1F2937)),
      ];

  final List<int> _order = <int>[0, 1, 2]; // index 0 is front card

  void _promoteCard(int cardIdIndex) {
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() {
      if (_order.first == cardIdIndex) {
        final first = _order.removeAt(0);
        _order.add(first);
      } else {
        _order.remove(cardIdIndex);
        _order.insert(0, cardIdIndex);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _Sample28WalletFanDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _promoteCard(_order.last);
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final dur = _scaledDuration(
      motion,
      LifeOsMotionTokens.medium,
      widget.speedFactor,
    );

    return _SampleStage(
      height: 162,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          for (var depth = _order.length - 1; depth >= 0; depth--)
            Builder(
              builder: (context) {
                final cardIdx = _order[depth];
                final card = _cards[cardIdx];
                final topOffset = depth == 0 ? 34.0 : (depth == 1 ? 17.0 : 2.0);
                final scale = motion.isReducedMotion
                    ? 1.0
                    : (1.0 - depth * 0.055);

                return AnimatedPositioned(
                  key: ValueKey<String>(card.$1),
                  duration: dur,
                  curve: LifeOsMotionTokens.emphasizedCurve,
                  top: topOffset,
                  left: 4,
                  right: 4,
                  height: 102,
                  child: AnimatedScale(
                    duration: dur,
                    curve: LifeOsMotionTokens.emphasizedCurve,
                    scale: scale,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () => _promoteCard(cardIdx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: card.$4,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      card.$2,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.touch_app_outlined,
                                  color: Colors.white70,
                                  size: 15,
                                ),
                              ],
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                card.$3,
                                style: _tabularStyle(
                                  color: Colors.white,
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #29 — Multi-Layer Parallax Bento Card (flutter_vignettes Port)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample29ParallaxBento extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample29ParallaxBento({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample29ParallaxBento> createState() => _Sample29ParallaxBentoState();
}

class _Sample29ParallaxBentoState extends State<_Sample29ParallaxBento>
    with TickerProviderStateMixin {
  late final LifeOsSpring2DController _parallaxCtrl;
  int _presetAngle = 0;

  @override
  void initState() {
    super.initState();
    _parallaxCtrl = LifeOsSpring2DController(
      vsync: this,
      spring: LifeOsMotionTokens.gestureThrowSpring,
      tolerance: LifeOsMotionTokens.springTolerance,
    );
  }

  void _shiftGaze() {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    _presetAngle = (_presetAngle + 1) % 3;
    final target = switch (_presetAngle) {
      1 => const Offset(-1.0, -0.5),
      2 => const Offset(1.0, 0.4),
      _ => Offset.zero,
    };
    _parallaxCtrl.animateTo(
      target,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  void didUpdateWidget(covariant _Sample29ParallaxBento oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _shiftGaze();
    }
  }

  @override
  void dispose() {
    _parallaxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _SampleStage(
      height: 156,
      padding: EdgeInsets.zero,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _shiftGaze,
        onPanUpdate: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize) {
            final nx = ((d.localPosition.dx / box.size.width) - 0.5) * 2.0;
            final ny = ((d.localPosition.dy / box.size.height) - 0.5) * 2.0;
            _parallaxCtrl.jumpTo(
              Offset(nx.clamp(-1.0, 1.0), ny.clamp(-1.0, 1.0)),
            );
          }
        },
        onPanEnd: (_) {
          _parallaxCtrl.animateTo(
            Offset.zero,
            motion: motion,
            tickersEnabled: TickerMode.valuesOf(context).enabled,
            timeDilationFactor: widget.speedFactor,
          );
        },
        child: AnimatedBuilder(
          animation: _parallaxCtrl,
          builder: (context, _) {
            final p = motion.isReducedMotion
                ? Offset.zero
                : _parallaxCtrl.value;
            return Stack(
              children: <Widget>[
                // Layer 1: Far Background Hills & Sun (0.35x)
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(p.dx * -8, p.dy * -5),
                    child: CustomPaint(
                      painter: _ParallaxHillsPainter(isDark: isDark),
                    ),
                  ),
                ),
                // Layer 2: Midground Brand Symbol Emblem (0.75x)
                Positioned(
                  right: 18 + p.dx * -15,
                  top: 22 + p.dy * -10,
                  child: const Opacity(
                    opacity: 0.9,
                    child: LifeOsLeafMark(size: 46, borderRadius: 14),
                  ),
                ),
                // Layer 3: Foreground Crisp Bento Readout (+1.1x)
                Positioned(
                  left: 14 + p.dx * 8,
                  bottom: 14 + p.dy * 6,
                  right: 76,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Hành trình Tự do Tài chính',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Đạt 78,4% kế hoạch năm',
                          style: _tabularStyle(
                            color: c.textPrimary,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ParallaxHillsPainter extends CustomPainter {
  final bool isDark;

  const _ParallaxHillsPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final bgRect = Offset.zero & size;
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const <Color>[Color(0xFF15271E), Color(0xFF1E293B)]
              : const <Color>[Color(0xFFECFDF3), Color(0xFFE0F2FE)],
        ).createShader(bgRect),
    );

    canvas.drawCircle(
      Offset(size.width * 0.24, size.height * 0.30),
      26,
      Paint()
        ..color = const Color(
          0xFF34D399,
        ).withValues(alpha: isDark ? 0.18 : 0.28),
    );

    final hill = Path()
      ..moveTo(-20, size.height)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.48,
        size.width + 20,
        size.height * 0.78,
      )
      ..lineTo(size.width + 20, size.height)
      ..close();
    canvas.drawPath(
      hill,
      Paint()
        ..color = const Color(
          0xFF10B981,
        ).withValues(alpha: isDark ? 0.16 : 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _ParallaxHillsPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

// ═════════════════════════════════════════════════════════════════════════════
// #30 — 180° 3D Card Flip (Matrix4.rotateY Front Wallet <-> Back Masked QR)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample30CardFlip180 extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample30CardFlip180({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample30CardFlip180> createState() => _Sample30CardFlip180State();
}

class _Sample30CardFlip180State extends State<_Sample30CardFlip180>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: LifeOsMotionTokens.medium,
    );
  }

  void _flip() {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    _ctrl.duration = _scaledDuration(
      motion,
      LifeOsMotionTokens.medium,
      widget.speedFactor,
    );
    setState(() => _showBack = !_showBack);
    if (!TickerMode.valuesOf(context).enabled || motion.isMotionOff) {
      _ctrl.value = _showBack ? 1.0 : 0.0;
      return;
    }
    if (_showBack) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  void didUpdateWidget(covariant _Sample30CardFlip180 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _flip();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final maskedQrRef = PrivacyMaskFormatter.maskCode('VNQR982341');

    return _SampleStage(
      height: 156,
      child: GestureDetector(
        onTap: _flip,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = LifeOsMotionTokens.emphasizedCurve.transform(_ctrl.value);
            if (motion.isReducedMotion) {
              return _showBack
                  ? _buildBackFace(c, maskedQrRef)
                  : _buildFrontFace(c);
            }

            final angle = t * math.pi;
            final isBackVisible = angle >= (math.pi / 2);
            final matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle);

            return Transform(
              alignment: Alignment.center,
              transform: matrix,
              child: isBackVisible
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _buildBackFace(c, maskedQrRef),
                    )
                  : _buildFrontFace(c),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFrontFace(TammySemanticColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LifeOSBrandColors.forest,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.credit_card_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Mặt trước · Thẻ Thanh toán Chung',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _CompactActionChip(
                label: 'Lật QR',
                icon: Icons.flip_camera_android_rounded,
                onTap: _flip,
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '15.400.000 ₫',
              style: _tabularStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackFace(TammySemanticColors c, String maskedQrRef) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: c.primary, width: 1.2),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.primarySubtle,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.qr_code_2_rounded, color: c.primary, size: 38),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Mặt sau · Mã QR Nhận tiền',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Mã tham chiếu: $maskedQrRef',
                    style: _tabularStyle(
                      color: c.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _CompactActionChip(label: 'Mặt trước', selected: true, onTap: _flip),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #31 — Expandable Bento Metric Tile (LifeOsAnimatedVisibility)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample31ExpandableBento extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample31ExpandableBento({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample31ExpandableBento> createState() =>
      _Sample31ExpandableBentoState();
}

class _Sample31ExpandableBentoState extends State<_Sample31ExpandableBento> {
  bool _expanded = false;

  void _toggle() {
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() => _expanded = !_expanded);
  }

  @override
  void didUpdateWidget(covariant _Sample31ExpandableBento oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _toggle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final dur = _scaledDuration(
      motion,
      LifeOsMotionTokens.standard,
      widget.speedFactor,
    );

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 136, maxHeight: 172),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _toggle,
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.primarySubtle,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.insights_rounded,
                    color: c.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Tổng chi Tuần này',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                          ),
                        ),
                        Text(
                          '1.840.000 ₫',
                          style: _tabularStyle(
                            color: c.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _CompactActionChip(
                  label: _expanded ? 'Ẩn bớt' : 'Chi tiết',
                  selected: _expanded,
                  onTap: _toggle,
                ),
              ],
            ),
          ),
          LifeOsAnimatedVisibility(
            visible: _expanded,
            duration: dur,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  _buildMetricPill(c, 'Ăn uống 42%'),
                  _buildMetricPill(c, 'Di chuyển 28%'),
                  _buildMetricPill(c, 'Hóa đơn 30%'),
                ],
              ),
            ),
          ),
          if (!_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LifeOsAnimatedProgressBar(
                progressRatio: 0.62,
                color: c.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(TammySemanticColors c, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.border),
      ),
      child: Text(
        text,
        style: _tabularStyle(
          color: c.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// #32 — Drag-Driven Specular Metallic Rim Sweep
// ═════════════════════════════════════════════════════════════════════════════
class _Sample32MetallicSheenSweep extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample32MetallicSheenSweep({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample32MetallicSheenSweep> createState() =>
      _Sample32MetallicSheenSweepState();
}

class _Sample32MetallicSheenSweepState
    extends State<_Sample32MetallicSheenSweep>
    with SingleTickerProviderStateMixin {
  late final LifeOsSpringController _angleCtrl;

  @override
  void initState() {
    super.initState();
    _angleCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: 0.25,
      spring: LifeOsMotionTokens.snappySpring,
    );
  }

  void _stepAngle() {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    final next = (_angleCtrl.value + 0.35) % 1.0;
    _angleCtrl.animateTo(
      next,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  void didUpdateWidget(covariant _Sample32MetallicSheenSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _stepAngle();
    }
  }

  @override
  void dispose() {
    _angleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);

    return _SampleStage(
      height: 152,
      child: GestureDetector(
        onTap: _stepAngle,
        onHorizontalDragUpdate: (d) {
          final box = context.findRenderObject() as RenderBox?;
          final w = (box != null && box.hasSize) ? box.size.width : 280.0;
          _angleCtrl.jumpTo((d.localPosition.dx / w).clamp(0.0, 1.0));
        },
        child: AnimatedBuilder(
          animation: _angleCtrl,
          builder: (context, _) {
            final pos = motion.isReducedMotion ? 0.35 : _angleCtrl.value;
            return CustomPaint(
              foregroundPainter: _MetallicRimSweepPainter(sweepFraction: pos),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Row(
                      children: <Widget>[
                        Icon(
                          Icons.workspace_premium_rounded,
                          color: Color(0xFF6EE7B7),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Thẻ Kim loại Obsidian · Viền phản quang',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Kéo ngang để xoay góc phản chiếu ánh sáng',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.76),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(pos * 360).round()}°',
                          style: _tabularStyle(
                            color: const Color(0xFF6EE7B7),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MetallicRimSweepPainter extends CustomPainter {
  final double sweepFraction;

  const _MetallicRimSweepPainter({required this.sweepFraction});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.0);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(15));
    final angle = sweepFraction * math.pi * 2;

    // Specular surface sheen band
    canvas.save();
    canvas.clipRRect(rrect);
    final sheenX = -size.width * 0.25 + sweepFraction * (size.width * 1.5);
    final sheenRect = Rect.fromLTWH(sheenX - 44, 0, 88, size.height);
    canvas.drawRect(
      sheenRect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.0),
            const Color(0xFFA7F3D0).withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(sheenRect),
    );
    canvas.restore();

    // Directional metallic rim
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          transform: GradientRotation(angle),
          colors: const <Color>[
            Color(0x22FFFFFF),
            Color(0xFF6EE7B7),
            Color(0xFFFFFFFF),
            Color(0x22FFFFFF),
          ],
          stops: const <double>[0.0, 0.45, 0.52, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _MetallicRimSweepPainter oldDelegate) =>
      oldDelegate.sweepFraction != sweepFraction;
}

// ═════════════════════════════════════════════════════════════════════════════
// #33 — Daylight Studio Mint Wave Surface (TammySemanticColors Light/Dark)
// ═════════════════════════════════════════════════════════════════════════════
class _Sample33MintWaveCanvas extends StatefulWidget {
  final double speedFactor;
  final int replaySeed;

  const _Sample33MintWaveCanvas({
    required this.speedFactor,
    required this.replaySeed,
  });

  @override
  State<_Sample33MintWaveCanvas> createState() =>
      _Sample33MintWaveCanvasState();
}

class _Sample33MintWaveCanvasState extends State<_Sample33MintWaveCanvas> {
  // 0 = Follow Theme, 1 = Preview Daylight, 2 = Preview True Dark
  int _paletteMode = 0;

  void _cycleMode([int? mode]) {
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() => _paletteMode = mode ?? ((_paletteMode + 1) % 3));
  }

  @override
  void didUpdateWidget(covariant _Sample33MintWaveCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replaySeed != widget.replaySeed) {
      _cycleMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hostBrightness = Theme.of(context).brightness;
    final previewDark = switch (_paletteMode) {
      1 => false,
      2 => true,
      _ => hostBrightness == Brightness.dark,
    };
    final semantic = previewDark
        ? TammySemanticColors.dark
        : TammySemanticColors.light;

    final baseTheme = previewDark ? ThemeData.dark() : ThemeData.light();
    final scopedTheme = baseTheme.copyWith(
      extensions: <ThemeExtension<dynamic>>[semantic],
    );

    return Theme(
      data: scopedTheme,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 156,
          width: double.infinity,
          child: LifeOsMintWaveCanvas(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: semantic.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _CompactActionChip(
                          label: 'Hệ thống',
                          selected: _paletteMode == 0,
                          onTap: () => _cycleMode(0),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: _CompactActionChip(
                          label: 'Phòng Sáng',
                          selected: _paletteMode == 1,
                          onTap: () => _cycleMode(1),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: _CompactActionChip(
                          label: 'Phòng Tối',
                          selected: _paletteMode == 2,
                          onTap: () => _cycleMode(2),
                        ),
                      ),
                    ],
                  ),
                  LiquidGlassSurface(
                    material: LiquidGlassMaterial.mintHero,
                    borderRadius: 14,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    onTap: _cycleMode,
                    child: Row(
                      children: <Widget>[
                        LifeOsSymbolMark(
                          size: 28,
                          variant: previewDark
                              ? LifeOsSymbolVariant.white
                              : LifeOsSymbolVariant.color,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  previewDark
                                      ? 'Nền Sóng Ngọc · Chế độ Tối dịu mắt'
                                      : 'Nền Sóng Ngọc · Ánh sáng Ban ngày',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: semantic.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Chạm để đổi sắc độ khúc xạ nền kính',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: semantic.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
