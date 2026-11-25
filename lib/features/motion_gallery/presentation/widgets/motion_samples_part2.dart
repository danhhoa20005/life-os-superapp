import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/lifeos_brand_colors.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../models/motion_sample_ui_spec.dart';

Duration _scaledDuration(
  BuildContext context,
  Duration base,
  double speedFactor,
) {
  final motion = LifeOsMotionScope.of(context);
  final resolved = motion.resolveDuration(base);
  if (resolved == Duration.zero) return Duration.zero;
  final ms = (resolved.inMilliseconds / speedFactor.clamp(0.2, 2.5)).round();
  return Duration(milliseconds: math.max(16, ms));
}

Widget _sampleChipButton({
  Key? buttonKey,
  required BuildContext context,
  required String label,
  IconData? icon,
  required VoidCallback onTap,
  bool primary = false,
}) {
  final c = TammySemanticColors.of(context);
  final bg = primary ? c.primary : c.surfaceRaised;
  final fg = primary ? Colors.white : c.textPrimary;
  final border = primary ? c.primary : c.border;

  return LifeOsPressable(
    key: buttonKey,
    pressedScale: LifeOsMotionTokens.pressedScaleCompact,
    onPressed: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 0.9),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14.5, color: fg),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Builds Groups 5–8 (`#34`–`#66`, 33 interactive samples) for the LifeOS Motion Gallery.
List<MotionSampleSpec> buildMotionSamplesPart2() {
  return <MotionSampleSpec>[
    // ══════════════════════════════════════════════════════════════════════════
    // NHÓM 5 — listsStaggerChoreography (#34–#41, 8 mẫu)
    // ══════════════════════════════════════════════════════════════════════════
    MotionSampleSpec(
      number: 34,
      id: 'list_guarded_stagger',
      category: MotionSampleCategory.listsStaggerChoreography,
      titleVi: 'Danh sách Stagger có rào chắn TX-05',
      uxPurposeVi:
          'Dòng mới lẻ đi vào mượt (30ms/mục), còn đồng bộ hàng loạt (>5 mục) tự bỏ qua stagger để không giật cuộn.',
      tokenSummary:
          'LifeOsStableListRegistry · staggerStep 30ms · maxStaggeredItems 5',
      upstreamRef: 'LifeOS TX-05 Guarded List Choreography',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample34GuardedStagger(
            key: ValueKey<String>('s34_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 35,
      id: 'list_collapsing_glass_header',
      category: MotionSampleCategory.listsStaggerChoreography,
      titleVi: 'Tiêu đề Kính thu gọn theo nhịp cuộn',
      uxPurposeVi:
          'Thu gọn chiều cao thanh tổng quan ví theo vị trí cuộn thực để nhường không gian đọc sổ giao dịch.',
      tokenSummary: 'ScrollController offset lerp · FontFeature.tabularFigures',
      upstreamRef: 'Apple HIG Large Title Scroll-Coupled Collapse',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample35CollapsingHeader(
            key: ValueKey<String>('s35_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 36,
      id: 'list_swipe_statement_row',
      category: MotionSampleCategory.listsStaggerChoreography,
      titleVi: 'Kéo ngang duyệt sao kê có ngưỡng Haptic',
      uxPurposeVi:
          'Kéo sang phải để khớp giao dịch hoặc sang trái để hoàn tác với phản hồi xúc giác đúng ngưỡng 64px.',
      tokenSummary:
          'gestureThrowSpring (k:260, c:26, ζ=0.806) · selectionHaptic',
      upstreamRef: 'iOS Mail / Revolut Statement Swipe Action',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample36SwipeStatementRow(
            key: ValueKey<String>('s36_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 37,
      id: 'list_priority_lift_card',
      category: MotionSampleCategory.listsStaggerChoreography,
      titleVi: 'Nâng độ nổi lò xo cho thẻ việc ưu tiên',
      uxPurposeVi:
          'Nhấn chọn việc cần làm làm tăng độ nổi bóng đổ và viền sáng tức thì mà không dịch chuyển bố cục xung quanh.',
      tokenSummary: 'snappySpring (k:500, c:42.5, ζ=0.950) · 3-tier elevation',
      upstreamRef: 'Linear / Things 3 Tactile Task Elevation',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample37PriorityLiftCard(
            key: ValueKey<String>('s37_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 38,
      id: 'list_bento_grid_morph',
      category: MotionSampleCategory.listsStaggerChoreography,
      titleVi: 'Biến hình Lưới Bento 2 cột sang Danh sách gọn',
      uxPurposeVi:
          'Chuyển đổi mượt giữa chế độ xem thẻ Bento 2 cột và danh sách 1 cột theo mật độ thông tin người dùng chọn.',
      tokenSummary: 'AnimatedSize (300ms emphasizedCurve) + AnimatedSwitcher',
      upstreamRef: 'UI/UX Pro Max Adaptive Bento Morph',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample38BentoGridMorph(
            key: ValueKey<String>('s38_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 39,
      id: 'list_scroll_progress_adapter',
      category: MotionSampleCategory.listsStaggerChoreography,
      titleVi: 'Thanh tiến độ đọc sổ theo vị trí cuộn',
      uxPurposeVi:
          'Hiển thị chính xác tỷ lệ đã kiểm tra của bảng đối soát tài chính dài mà không phát sinh sự kiện BLoC mỗi khung hình.',
      tokenSummary: 'ScrollController metrics -> 0..100% tabularFigures',
      upstreamRef: 'Scroll-Driven Progress Adapter Pattern',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample39ScrollProgressAdapter(
            key: ValueKey<String>('s39_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 40,
      id: 'list_stale_while_revalidate',
      category: MotionSampleCategory.listsStaggerChoreography,
      titleVi: 'Stale-While-Revalidate & Skeleton hữu hạn',
      uxPurposeVi:
          'Giữ nguyên số dư đã lưu đệm khi đồng bộ ngầm; chỉ hiện khung xương khi tải lần đầu chưa có dữ liệu.',
      tokenSummary: 'LifeOsStaleWhileRevalidate + LifeOsSkeletonBox',
      upstreamRef: 'LifeOS Section 6.1 #6 SWR Loading Policy',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample40StaleWhileRevalidate(
            key: ValueKey<String>('s40_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 41,
      id: 'list_animated_diff_ledger',
      category: MotionSampleCategory.listsStaggerChoreography,
      titleVi: 'Chèn & xóa dòng giao dịch không nháy danh sách',
      uxPurposeVi:
          'Chỉ dòng vừa thêm hoặc xóa co giãn mượt trong AnimatedList, giữ cố định các dòng còn lại trên màn hình.',
      tokenSummary: 'AnimatedList · standard 220ms enter / exitFast 140ms',
      upstreamRef: 'Flutter AnimatedList Diff Choreography',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample41AnimatedDiffLedger(
            key: ValueKey<String>('s41_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),

    // ══════════════════════════════════════════════════════════════════════════
    // NHÓM 6 — sheetsDialogsDisclosures (#42–#49, 8 mẫu)
    // ══════════════════════════════════════════════════════════════════════════
    MotionSampleSpec(
      number: 42,
      id: 'sheet_multi_detent_spring',
      category: MotionSampleCategory.sheetsDialogsDisclosures,
      titleVi: 'Bottom Sheet đa nấc lò xo 42% · 72% · 92%',
      uxPurposeVi:
          'Hỗ trợ kéo tay có lực cản dây thun và dự đoán nấc dừng theo vận tốc vuốt với độ vọt lố 0%.',
      tokenSummary:
          'LifeOsSpringBottomSheet · sheetSnapSpring (ζ=1.003) · lookahead 0.18s',
      upstreamRef: 'fujidaiti/smooth_sheets Multi-Detent Port',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample42MultiDetentSpring(
            key: ValueKey<String>('s42_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 43,
      id: 'sheet_nested_scroll_handoff',
      category: MotionSampleCategory.sheetsDialogsDisclosures,
      titleVi: 'Chuyển giao mượt giữa Cuộn nội dung và Kéo Sheet',
      uxPurposeVi:
          'Khi danh sách chạm đỉnh (offset = 0), thao tác kéo xuống lập tức truyền vận tốc sang thu gọn tấm Sheet.',
      tokenSummary:
          'Nested Scroll Handoff · sheetSnapSpring · normalizeVelocity',
      upstreamRef: 'smooth_sheets / iOS Sheet Scroll Handoff',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample43NestedScrollHandoff(
            key: ValueKey<String>('s43_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 44,
      id: 'sheet_ios_scale_back',
      category: MotionSampleCategory.sheetsDialogsDisclosures,
      titleVi: 'Thu nhỏ lớp nền 0.94 kiểu thẻ xếp chồng iOS',
      uxPurposeVi:
          'Lớp trang gốc lùi nhẹ về sau (scale 0.94) khi tấm chi tiết nổi lên để tạo chiều sâu không gian rõ ràng.',
      tokenSummary: 'sheetSnapSpring (ζ=1.003) · background scale 1.0 -> 0.94',
      upstreamRef: 'Apple HIG Stacked Modal Card Presentation',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample44IosScaleBack(
            key: ValueKey<String>('s44_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 45,
      id: 'sheet_paged_shared_axis',
      category: MotionSampleCategory.sheetsDialogsDisclosures,
      titleVi: 'Luồng nhiều bước SharedAxis bên trong Sheet',
      uxPurposeVi:
          'Chuyển tiếp tiến/lùi giữa các bước chia tiền nhóm ngay trong một tấm Sheet mà không mở chồng nhiều popup.',
      tokenSummary:
          'LifeOsMaterialContentSwitcher · SharedAxisTransition.horizontal',
      upstreamRef: 'Material Motion Shared Axis Stepper (animations ^2.2.0)',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample45PagedSharedAxis(
            key: ValueKey<String>('s45_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 46,
      id: 'sheet_gooey_bezier_edge',
      category: MotionSampleCategory.sheetsDialogsDisclosures,
      titleVi: 'Màng sóng Bezier đàn hồi khi kéo cạnh',
      uxPurposeVi:
          'Đường cong Bezier biến dạng theo ngón tay và bật về trạng thái phẳng bằng lò xo đàn hồi giàu cảm xúc.',
      tokenSummary:
          'CustomPainter Quadratic/Cubic Bezier + bouncySpring (ζ=0.616)',
      upstreamRef: 'gskinner/flutter_vignettes Gooey Edge Port',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample46GooeyBezierEdge(
            key: ValueKey<String>('s46_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 47,
      id: 'sheet_progressive_disclosure',
      category: MotionSampleCategory.sheetsDialogsDisclosures,
      titleVi: 'Tiết lộ tuần tự mục Chi tiết không giật khung',
      uxPurposeVi:
          'Ẩn thông số phụ sau nút Chi tiết để thẻ giao dịch thoáng sạch, đồng thời loại bỏ vùng chạm ẩn khi đóng.',
      tokenSummary:
          'LifeOsDetailsDiscloseSection + LifeOsAnimatedVisibility (220ms)',
      upstreamRef: 'LifeOS Progressive Disclosure & ExcludeSemantics',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample47ProgressiveDisclosure(
            key: ValueKey<String>('s47_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 48,
      id: 'sheet_dynamic_top_toast',
      category: MotionSampleCategory.sheetsDialogsDisclosures,
      titleVi: 'Top Toast Dynamic-Island & chống lặp 1200ms',
      uxPurposeVi:
          'Thông báo nổi chuẩn đĩa kính 3D ở đỉnh màn hình, tự gộp các sự kiện trùng lặp trong cửa sổ 1200ms.',
      tokenSummary:
          'LifeOsTopToast.show · standard 220ms · toastDedupeWindow 1200ms',
      upstreamRef: 'Apple Dynamic Island Platter + LifeOS Dedupe Guard',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample48DynamicTopToast(
            key: ValueKey<String>('s48_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 49,
      id: 'sheet_fade_scale_dialog',
      category: MotionSampleCategory.sheetsDialogsDisclosures,
      titleVi: 'Hộp thoại Kính xuất hiện bằng FadeScaleTransition',
      uxPurposeVi:
          'Mở hộp thoại xác nhận quan trọng với độ phóng tinh tế (0.80 -> 1.0) và tự chuyển về mờ phẳng khi Giảm chuyển động.',
      tokenSummary: 'FadeScaleTransition · standard 220ms / exitFast 140ms',
      upstreamRef: 'Material Motion FadeScaleTransition (animations ^2.2.0)',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample49FadeScaleDialog(
            key: ValueKey<String>('s49_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),

    // ══════════════════════════════════════════════════════════════════════════
    // NHÓM 7 — chartsCountersTruth (#50–#57, 8 mẫu)
    // ══════════════════════════════════════════════════════════════════════════
    MotionSampleSpec(
      number: 50,
      id: 'chart_morph_donut',
      category: MotionSampleCategory.chartsCountersTruth,
      titleVi: 'Biểu đồ Donut đa phân khúc biến hình 0% vọt lố',
      uxPurposeVi:
          'Nội suy góc cung từng nhóm chi tiêu bằng lò xo tới hạn (ζ=1.001) để tổng tỷ lệ không bao giờ vượt 100%.',
      tokenSummary:
          'chartMorphSpring (m:1, k:240, c:31, ζ=1.001, 0% overshoot)',
      upstreamRef: 'UI/UX Pro Max Native CustomPainter Donut',
      previewBuilder: (context, speedFactor, replaySeed) => _Sample50MorphDonut(
        key: ValueKey<String>('s50_$replaySeed'),
        speedFactor: speedFactor,
      ),
    ),
    MotionSampleSpec(
      number: 51,
      id: 'chart_cashflow_scrub',
      category: MotionSampleCategory.chartsCountersTruth,
      titleVi: 'Biểu đồ dòng tiền 7 ngày & đường ngắm chạm trượt',
      uxPurposeVi:
          'Chạm kéo ngang qua các cột ngày để đọc ngay số tiền thu/chi từng ngày với chữ số thẳng cột tuyệt đối.',
      tokenSummary: 'chartMorphSpring + Scrub Crosshair · tabularFigures',
      upstreamRef: 'Revolut / Apple Stocks Interactive Scrubbing',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample51CashflowScrub(
            key: ValueKey<String>('s51_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 52,
      id: 'chart_path_sparkline',
      category: MotionSampleCategory.chartsCountersTruth,
      titleVi: 'Đường Sparkline tài sản ròng & kiểm chứng biến động 0',
      uxPurposeVi:
          'Vẽ mượt quỹ đạo tài sản bằng PathMetric.extractPath và giữ đường phẳng chính xác khi dữ liệu không đổi.',
      tokenSummary:
          'PathMetric.extractPath · expressive 420ms · flat-line safe',
      upstreamRef: 'Skia/Impeller PathMetric Progressive Stroke',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample52PathSparkline(
            key: ValueKey<String>('s52_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 53,
      id: 'chart_truthful_balance',
      category: MotionSampleCategory.chartsCountersTruth,
      titleVi: 'Số dư trung thực Crossfade 160ms & che bảo mật',
      uxPurposeVi:
          'Chuyển trực tiếp giữa hai số dư xác thực trong 160ms, tuyệt đối không đếm giả từ 0 gây hiểu lầm tài chính.',
      tokenSummary: 'LifeOsTruthfulNumericText · micro 160ms · tabularFigures',
      upstreamRef: 'LifeOS TX-04 Truthful Financial Readout',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample53TruthfulBalance(
            key: ValueKey<String>('s53_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 54,
      id: 'chart_simulator_scrub',
      category: MotionSampleCategory.chartsCountersTruth,
      titleVi: 'Thanh trượt mô phỏng tự do tài chính FIRE thời gian thực',
      uxPurposeVi:
          'Cập nhật tức thì đường cong tích lũy và số năm đạt mục tiêu theo tỷ lệ tiết kiệm với chữ số cố định độ rộng.',
      tokenSummary: 'Synchronous Slider Scrub · CustomPainter · tabularFigures',
      upstreamRef: 'LifeOS Wealth & FIRE Interactive Simulator',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample54SimulatorScrub(
            key: ValueKey<String>('s54_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 55,
      id: 'chart_six_jars_rings',
      category: MotionSampleCategory.chartsCountersTruth,
      titleVi: 'Vòng đồng tâm 6 Hũ tài chính 0% vọt lố',
      uxPurposeVi:
          'Ba vòng tiến độ đồng tâm co giãn mượt bằng lò xo tới hạn để không bao giờ báo hoàn thành giả quá ngưỡng.',
      tokenSummary:
          'chartMorphSpring (ζ=1.001, 0% overshoot) · 3 concentric arcs',
      upstreamRef: 'Apple Activity Rings / LifeOS 6-Jars Gauge',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample55SixJarsRings(
            key: ValueKey<String>('s55_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 56,
      id: 'chart_pomodoro_ring',
      category: MotionSampleCategory.chartsCountersTruth,
      titleVi: 'Vòng đếm ngược Tập trung Pomodoro hữu hạn',
      uxPurposeVi:
          'Vẽ cung thời gian tập trung rõ ràng theo chu kỳ hữu hạn, dừng sạch khi hoàn tất hoặc khi tắt chuyển động.',
      tokenSummary: 'Finite AnimationController · CustomPainter radial arc',
      upstreamRef: 'LifeOS Habits & Focus Countdown Ring',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample56PomodoroRing(
            key: ValueKey<String>('s56_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 57,
      id: 'chart_honest_budget_bar',
      category: MotionSampleCategory.chartsCountersTruth,
      titleVi: 'Thanh ngân sách trung thực: 68% an toàn vs 118% vượt mức',
      uxPurposeVi:
          'Chỉ giới hạn phần vẽ thanh ở 100% chiều rộng khung nhưng giữ nguyên con số 118% và cảnh báo vượt ngân sách.',
      tokenSummary:
          'LifeOsAnimatedProgressBar · medium 300ms · honest 118% label',
      upstreamRef: 'LifeOS Section 6.1 #5 Honest Budget Bar',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample57HonestBudgetBar(
            key: ValueKey<String>('s57_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),

    // ══════════════════════════════════════════════════════════════════════════
    // NHÓM 8 — shadersLottieSpritesMascot (#58–#66, 9 mẫu)
    // ══════════════════════════════════════════════════════════════════════════
    MotionSampleSpec(
      number: 58,
      id: 'creative_shader_caustics',
      category: MotionSampleCategory.shadersLottieSpritesMascot,
      titleVi: 'GLSL Fragment Shader — Khúc xạ Ngọc lục bảo lỏng',
      uxPurposeVi:
          'Chạy chương trình mảnh GLSL thực trên GPU cho mặt thẻ Hero với xung thời gian hữu hạn và fallback an toàn.',
      tokenSummary:
          'LifeOsShaderSurface(liquidCaustics) · shaders/liquid_caustics.frag',
      upstreamRef: 'Impeller / Skia RuntimeEffect FragmentProgram',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample58ShaderCaustics(
            key: ValueKey<String>('s58_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 59,
      id: 'creative_shader_foil',
      category: MotionSampleCategory.shadersLottieSpritesMascot,
      titleVi: 'GLSL Fragment Shader — Ánh kim Hologram theo ngón tay',
      uxPurposeVi:
          'Ánh xạ tọa độ kéo ngón tay thành vệt phản quang kim loại trên thẻ thành viên cao cấp.',
      tokenSummary:
          'LifeOsShaderSurface(holographicFoil) · shaders/holographic_foil.frag',
      upstreamRef: 'Apple Wallet Cash / Revolut Metal Foil Shader',
      previewBuilder: (context, speedFactor, replaySeed) => _Sample59ShaderFoil(
        key: ValueKey<String>('s59_$replaySeed'),
        speedFactor: speedFactor,
      ),
    ),
    MotionSampleSpec(
      number: 60,
      id: 'creative_voice_rms_aura',
      category: MotionSampleCategory.shadersLottieSpritesMascot,
      titleVi: 'Vầng sóng âm AI Voice RMS (0 setState/khung hình)',
      uxPurposeVi:
          'Nối trực tiếp ValueNotifier biên độ âm thanh vào CustomPainter(repaint:) để vẽ 60/120 FPS không rebuild widget.',
      tokenSummary:
          'ValueNotifier<double> + CustomPainter(repaint:) · 0 setState',
      upstreamRef: 'LifeOS On-Device Voice Capture Aura',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample60VoiceRmsAura(
            key: ValueKey<String>('s60_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 61,
      id: 'creative_lottie_check',
      category: MotionSampleCategory.shadersLottieSpritesMascot,
      titleVi: 'Hoạt ảnh Vector Lottie dấu tích xác thực (1 chu kỳ)',
      uxPurposeVi:
          'Phát đúng 1 lần dấu xác nhận hoàn tất cột mốc rồi dừng hẳn, bảo đảm kiểm thử tự động luôn hội tụ.',
      tokenSummary:
          'LifeOsLottieAnimation(lottieCheckCelebration, maxCycles: 1)',
      upstreamRef: 'xvrh/lottie-flutter ^3.8.2 Pure Dart Vector Player',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample61LottieCheck(
            key: ValueKey<String>('s61_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 62,
      id: 'creative_lottie_theme_radar',
      category: MotionSampleCategory.shadersLottieSpritesMascot,
      titleVi: 'Lottie Radar đồng bộ tự đổi màu theo Sáng / Tối',
      uxPurposeVi:
          'Ghi đè màu lớp vector Lottie động theo bảng màu ngữ nghĩa Light/Dark mà không cần nhân đôi file tài nguyên.',
      tokenSummary:
          'LifeOsLottieAnimation + LottieDelegates ValueDelegate.color',
      upstreamRef: 'lottie-flutter Dynamic Property ValueDelegate',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample62LottieThemeRadar(
            key: ValueKey<String>('s62_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 63,
      id: 'creative_sprite_vs_static',
      category: MotionSampleCategory.shadersLottieSpritesMascot,
      titleVi: 'Đối chiếu: Ảnh 3D tĩnh vs Sprite Sheet 8-frame chạy thật',
      uxPurposeVi:
          'Phân biệt minh bạch giữa minh họa 3D tĩnh Nano Banana và dải ảnh RGBA 8 khung cắt vẽ tuần tự bằng drawImageRect.',
      tokenSummary:
          'LifeOsSpriteSheetPlayer(8 frames, 12fps) vs Image.asset 3D tĩnh',
      upstreamRef: 'Canvas.drawImageRect Sprite Strip vs Static 3D Render',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample63SpriteVsStatic(
            key: ValueKey<String>('s63_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 64,
      id: 'creative_particle_burst',
      category: MotionSampleCategory.shadersLottieSpritesMascot,
      titleVi: 'Pháo hạt vật lý chúc mừng cột mốc (Zero-Allocation)',
      uxPurposeVi:
          'Bắn chùm hạt có trọng lực tại đúng tọa độ chạm bằng cấu trúc mảng tiền cấp phát không gây rác bộ nhớ.',
      tokenSummary: 'LifeOsParticleBurst · Struct-of-Arrays · 900ms finite',
      upstreamRef: 'gskinner/flutter-wonderous Particle Field Port',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample64ParticleBurst(
            key: ValueKey<String>('s64_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 65,
      id: 'creative_interactive_mascot',
      category: MotionSampleCategory.shadersLottieSpritesMascot,
      titleVi: 'Linh vật tương tác 5 trạng thái "Mầm Ngọc"',
      uxPurposeVi:
          'Máy trạng thái nhân vật thuần Dart với đôi mắt nhìn theo ngón tay và hai chiếc lá nảy lò xo biểu cảm.',
      tokenSummary:
          'LifeOsInteractiveMascotRig · 5 states · bouncySpring (ζ=0.616)',
      upstreamRef: 'Deterministic Pure-Dart Character State Machine',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample65InteractiveMascot(
            key: ValueKey<String>('s65_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
    MotionSampleSpec(
      number: 66,
      id: 'creative_marching_hydration',
      category: MotionSampleCategory.shadersLottieSpritesMascot,
      titleVi: 'Dòng chảy nét đứt Marching Ants & Sóng nước Lottie',
      uxPurposeVi:
          'Kết hợp đường dẫn nét đứt dịch pha hữu hạn với sóng nước vector khi người dùng ghi nhận thêm lượng nước uống.',
      tokenSummary:
          'AppAssets.lottieHydrationWave + CustomPainter dashed phase',
      upstreamRef: 'Marching Ants Conduit + Lottie Hydration Wave',
      previewBuilder: (context, speedFactor, replaySeed) =>
          _Sample66MarchingHydration(
            key: ValueKey<String>('s66_$replaySeed'),
            speedFactor: speedFactor,
          ),
    ),
  ];
}

// ════════════════════════════════════════════════════════════════════════════
// IMPLEMENTATIONS: GROUP 5 (#34–#41)
// ════════════════════════════════════════════════════════════════════════════

class _Sample34GuardedStagger extends StatefulWidget {
  final double speedFactor;
  const _Sample34GuardedStagger({super.key, required this.speedFactor});

  @override
  State<_Sample34GuardedStagger> createState() =>
      _Sample34GuardedStaggerState();
}

class _Sample34GuardedStaggerState extends State<_Sample34GuardedStagger> {
  final LifeOsStableListRegistry _registry = LifeOsStableListRegistry(
    animateInitialItems: true,
  );
  late List<(String id, String title, String amount)> _rows;
  int _counter = 3;
  String _statusNote = 'Khởi tạo 3 mục đầu (stagger 30ms)';

  @override
  void initState() {
    super.initState();
    _rows = <(String, String, String)>[
      ('tx_1', 'Cà phê sáng Highlands', '-55.000 ₫'),
      ('tx_2', 'Siêu thị WinMart+', '-245.000 ₫'),
      ('tx_3', 'Hoàn tiền thẻ tín dụng', '+120.000 ₫'),
    ];
  }

  void _addSingle() {
    setState(() {
      _counter++;
      _rows.insert(0, ('tx_$_counter', 'Giao dịch lẻ #$_counter', '-85.000 ₫'));
      _statusNote = 'Thêm +1 dòng: chạy entrance mượt';
    });
  }

  void _addBulkEight() {
    setState(() {
      for (var i = 0; i < 8; i++) {
        _counter++;
        _rows.insert(0, (
          'tx_$_counter',
          'Đồng bộ ngân hàng #$_counter',
          '-150.000 ₫',
        ));
      }
      _statusNote = 'Đồng bộ +8 dòng: tự bỏ qua stagger (TX-05)';
    });
  }

  void _reset() {
    setState(() {
      _registry.reset();
      _counter = 3;
      _rows = <(String, String, String)>[
        ('tx_1', 'Cà phê sáng Highlands', '-55.000 ₫'),
        ('tx_2', 'Siêu thị WinMart+', '-245.000 ₫'),
        ('tx_3', 'Hoàn tiền thẻ tín dụng', '+120.000 ₫'),
      ];
      _statusNote = 'Đã đặt lại danh sách mẫu';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final animateSet = _registry.registerSnapshot(_rows.map((e) => e.$1));
    final visibleRows = _rows.take(4).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _sampleChipButton(
              context: context,
              label: '+1 dòng',
              icon: Icons.add_rounded,
              primary: true,
              onTap: _addSingle,
            ),
            _sampleChipButton(
              context: context,
              label: '+8 đồng loạt',
              icon: Icons.sync_rounded,
              onTap: _addBulkEight,
            ),
            _sampleChipButton(
              context: context,
              label: 'Đặt lại',
              icon: Icons.refresh_rounded,
              onTap: _reset,
            ),
          ],
        ),
        const SizedBox(height: 8),
        LifeOsStatusPill(
          label: '$_statusNote · Tổng ${_rows.length} dòng',
          icon: Icons.bolt_rounded,
          tone: _statusNote.contains('TX-05')
              ? LifeOsAccentTone.amber
              : LifeOsAccentTone.emerald,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < visibleRows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: LifeOsAnimatedItemEntrance(
              key: ValueKey<String>(visibleRows[i].$1),
              itemId: visibleRows[i].$1,
              animateOnMount: animateSet.contains(visibleRows[i].$1),
              staggerIndex: i,
              duration: _scaledDuration(
                context,
                LifeOsMotionTokens.standard,
                widget.speedFactor,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border, width: 0.8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        visibleRows[i].$2,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.4,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      visibleRows[i].$3,
                      style: TextStyle(
                        fontSize: 12.4,
                        fontWeight: FontWeight.w800,
                        color: visibleRows[i].$3.startsWith('+')
                            ? c.success
                            : c.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Sample35CollapsingHeader extends StatefulWidget {
  final double speedFactor;
  const _Sample35CollapsingHeader({super.key, required this.speedFactor});

  @override
  State<_Sample35CollapsingHeader> createState() =>
      _Sample35CollapsingHeaderState();
}

class _Sample35CollapsingHeaderState extends State<_Sample35CollapsingHeader> {
  final ScrollController _scrollCtrl = ScrollController();
  double _collapseT = 0.0;

  static const _items = <(String, String)>[
    ('Lương tháng 11', '+28.500.000 ₫'),
    ('Tiền thuê căn hộ', '-8.500.000 ₫'),
    ('Điện lực EVN bậc thang', '-740.000 ₫'),
    ('Đi chợ rau củ hữu cơ', '-420.000 ₫'),
    ('Quỹ dự phòng gia đình', '-3.000.000 ₫'),
    ('Bảo dưỡng xe tay ga', '-380.000 ₫'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final next = (_scrollCtrl.offset / 76.0).clamp(0.0, 1.0);
    if ((next - _collapseT).abs() > 0.01 && mounted) {
      setState(() => _collapseT = next);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _toggleAutoScroll() {
    if (!_scrollCtrl.hasClients) return;
    final target = _collapseT > 0.5 ? 0.0 : 96.0;
    final dur = _scaledDuration(
      context,
      LifeOsMotionTokens.medium,
      widget.speedFactor,
    );
    if (dur == Duration.zero) {
      _scrollCtrl.jumpTo(target);
    } else {
      _scrollCtrl.animateTo(
        target,
        duration: dur,
        curve: LifeOsMotionTokens.emphasizedCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final headerPadV = ui.lerpDouble(12, 6, _collapseT)!;
    final titleSize = ui.lerpDouble(16.5, 13.0, _collapseT)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: headerPadV),
          decoration: BoxDecoration(
            color: c.primarySubtle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border.all(color: c.border, width: 0.8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Số dư Ví Gia đình',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 11.2,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                    Text(
                      '15.460.000 ₫',
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        color: c.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              _sampleChipButton(
                context: context,
                label: _collapseT > 0.5 ? 'Về đầu' : 'Cuộn thử',
                icon: Icons.swap_vert_rounded,
                onTap: _toggleAutoScroll,
              ),
            ],
          ),
        ),
        Container(
          height: 122,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(14),
            ),
            border: Border.all(color: c.border, width: 0.8),
          ),
          child: ListView.separated(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(8),
            itemCount: _items.length,
            separatorBuilder: (_, _) => Divider(height: 8, color: c.separator),
            itemBuilder: (ctx, index) => Row(
              children: [
                Expanded(
                  child: Text(
                    _items[index].$1,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                Text(
                  _items[index].$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _items[index].$2.startsWith('+')
                        ? c.success
                        : c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Sample36SwipeStatementRow extends StatefulWidget {
  final double speedFactor;
  const _Sample36SwipeStatementRow({super.key, required this.speedFactor});

  @override
  State<_Sample36SwipeStatementRow> createState() =>
      _Sample36SwipeStatementRowState();
}

class _Sample36SwipeStatementRowState extends State<_Sample36SwipeStatementRow>
    with SingleTickerProviderStateMixin {
  late final LifeOsSpringController _dragX;
  bool _passedThreshold = false;
  String _stateLabel = 'Chờ duyệt sao kê';
  LifeOsAccentTone _tone = LifeOsAccentTone.amber;

  @override
  void initState() {
    super.initState();
    _dragX = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: LifeOsMotionTokens.gestureThrowSpring,
      tolerance: LifeOsMotionTokens.pixelSpringTolerance,
    );
  }

  @override
  void dispose() {
    _dragX.dispose();
    super.dispose();
  }

  void _commitAction(bool approved) {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    setState(() {
      _stateLabel = approved ? 'Đã duyệt khớp sổ' : 'Đã hoàn tác chờ xem';
      _tone = approved ? LifeOsAccentTone.emerald : LifeOsAccentTone.purple;
    });
    if (!motion.isReducedMotion && TickerMode.valuesOf(context).enabled) {
      _dragX.jumpTo(approved ? 54.0 : -54.0);
      _dragX.animateTo(
        0.0,
        motion: motion,
        timeDilationFactor: widget.speedFactor,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        c.successSubtle,
                        c.surfaceRaised,
                        c.warningSubtle,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(Icons.check_circle_rounded, color: c.success),
                      Icon(Icons.undo_rounded, color: c.warning),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onHorizontalDragUpdate: (d) {
                  final next = LifeOsMotionTokens.rubberBandClamp(
                    _dragX.value + d.delta.dx,
                    min: -90,
                    max: 90,
                    viewportExtent: 140,
                  );
                  final crossed = next.abs() >= 56.0;
                  if (crossed && !_passedThreshold) {
                    _passedThreshold = true;
                    motion.selectionHaptic();
                  } else if (!crossed && _passedThreshold) {
                    _passedThreshold = false;
                  }
                  _dragX.jumpTo(next);
                },
                onHorizontalDragEnd: (d) {
                  final x = _dragX.value;
                  _passedThreshold = false;
                  if (x >= 56.0) {
                    setState(() {
                      _stateLabel = 'Đã duyệt khớp sổ';
                      _tone = LifeOsAccentTone.emerald;
                    });
                  } else if (x <= -56.0) {
                    setState(() {
                      _stateLabel = 'Đã hoàn tác chờ xem';
                      _tone = LifeOsAccentTone.purple;
                    });
                  }
                  _dragX.animateTo(
                    0.0,
                    velocity: d.velocity.pixelsPerSecond.dx,
                    motion: motion,
                    tickersEnabled: TickerMode.valuesOf(context).enabled,
                    timeDilationFactor: widget.speedFactor,
                  );
                },
                child: AnimatedBuilder(
                  animation: _dragX,
                  builder: (context, child) {
                    final dx = motion.isReducedMotion ? 0.0 : _dragX.value;
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        const LifeOsIconSquircle(
                          icon: Icons.bolt_rounded,
                          tone: LifeOsAccentTone.amber,
                          size: 36,
                          iconSize: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Điện lực EVN miền Nam',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                'Kéo phải duyệt · Kéo trái hoàn tác',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 11.4,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '-685.000 ₫',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            LifeOsAnimatedStatusBadge(
              statusKey: _stateLabel,
              label: _stateLabel,
              icon: _tone == LifeOsAccentTone.emerald
                  ? Icons.verified_rounded
                  : Icons.schedule_rounded,
              tone: _tone,
            ),
            _sampleChipButton(
              context: context,
              label: 'Duyệt nhanh',
              icon: Icons.check_rounded,
              onTap: () => _commitAction(true),
            ),
            _sampleChipButton(
              context: context,
              label: 'Hoàn tác',
              icon: Icons.undo_rounded,
              onTap: () => _commitAction(false),
            ),
          ],
        ),
      ],
    );
  }
}

class _Sample37PriorityLiftCard extends StatefulWidget {
  final double speedFactor;
  const _Sample37PriorityLiftCard({super.key, required this.speedFactor});

  @override
  State<_Sample37PriorityLiftCard> createState() =>
      _Sample37PriorityLiftCardState();
}

class _Sample37PriorityLiftCardState extends State<_Sample37PriorityLiftCard> {
  int _selectedIdx = 0;

  static const _tasks = <(String, String, LifeOsAccentTone)>[
    (
      'Thanh toán thẻ tín dụng trước 17:00',
      'Ưu tiên cao',
      LifeOsAccentTone.coral,
    ),
    ('Gửi báo cáo ngân sách gia đình', 'Hôm nay', LifeOsAccentTone.emerald),
    ('Đặt lịch bảo dưỡng xe định kỳ', 'Tuần này', LifeOsAccentTone.blue),
  ];

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final dur = _scaledDuration(
      context,
      LifeOsMotionTokens.standard,
      widget.speedFactor,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _tasks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: LifeOsPressable(
              onPressed: () => setState(() => _selectedIdx = i),
              child: AnimatedScale(
                duration: dur,
                curve: LifeOsMotionTokens.standardCurve,
                scale: (_selectedIdx == i && !motion.isReducedMotion)
                    ? 1.014
                    : 1.0,
                child: AnimatedContainer(
                  duration: dur,
                  curve: LifeOsMotionTokens.standardCurve,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _selectedIdx == i ? c.primarySubtle : c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _selectedIdx == i ? c.primary : c.border,
                      width: _selectedIdx == i ? 1.3 : 0.8,
                    ),
                    boxShadow: _selectedIdx == i
                        ? [
                            BoxShadow(
                              color: c.primary.withValues(alpha: 0.16),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedIdx == i
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 18,
                        color: _selectedIdx == i ? c.primary : c.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _tasks[i].$1,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: _selectedIdx == i
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      LifeOsStatusPill(label: _tasks[i].$2, tone: _tasks[i].$3),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Sample38BentoGridMorph extends StatefulWidget {
  final double speedFactor;
  const _Sample38BentoGridMorph({super.key, required this.speedFactor});

  @override
  State<_Sample38BentoGridMorph> createState() =>
      _Sample38BentoGridMorphState();
}

class _Sample38BentoGridMorphState extends State<_Sample38BentoGridMorph> {
  bool _isBento = true;

  static const _cells = <(String, String, IconData, LifeOsAccentTone)>[
    ('Ăn uống', '4,2 tr ₫', Icons.restaurant_rounded, LifeOsAccentTone.amber),
    ('Nhà cửa', '8,5 tr ₫', Icons.home_work_rounded, LifeOsAccentTone.purple),
    ('Di chuyển', '1,1 tr ₫', Icons.two_wheeler_rounded, LifeOsAccentTone.blue),
    ('Tiết kiệm', '6,0 tr ₫', Icons.savings_rounded, LifeOsAccentTone.emerald),
  ];

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final dur = _scaledDuration(
      context,
      LifeOsMotionTokens.medium,
      widget.speedFactor,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _sampleChipButton(
              context: context,
              label: 'Lưới Bento 2 cột',
              icon: Icons.grid_view_rounded,
              primary: _isBento,
              onTap: () => setState(() => _isBento = true),
            ),
            _sampleChipButton(
              context: context,
              label: 'Danh sách 1 cột',
              icon: Icons.view_agenda_outlined,
              primary: !_isBento,
              onTap: () => setState(() => _isBento = false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: dur,
          curve: LifeOsMotionTokens.emphasizedCurve,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: dur,
            child: _isBento
                ? Column(
                    key: const ValueKey<String>('bento_2col'),
                    children: [
                      for (var row = 0; row < 2; row++)
                        Padding(
                          padding: EdgeInsets.only(bottom: row == 0 ? 6 : 0),
                          child: Row(
                            children: [
                              for (var col = 0; col < 2; col++) ...[
                                if (col == 1) const SizedBox(width: 6),
                                Expanded(
                                  child: _buildBentoCell(
                                    c,
                                    _cells[row * 2 + col],
                                    compactRow: false,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  )
                : Column(
                    key: const ValueKey<String>('list_1col'),
                    children: [
                      for (final cell in _cells)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: _buildBentoCell(c, cell, compactRow: true),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildBentoCell(
    TammySemanticColors c,
    (String, String, IconData, LifeOsAccentTone) item, {
    required bool compactRow,
  }) {
    final (bg, fg) = item.$4.resolve(context);
    if (compactRow) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: c.border, width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.$3, size: 15, color: fg),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.$1,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
            ),
            Text(
              item.$2,
              style: TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w800,
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(item.$3, size: 16, color: fg),
          ),
          const SizedBox(height: 6),
          Text(
            item.$2,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            item.$1,
            softWrap: true,
            style: TextStyle(fontSize: 11.5, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Sample39ScrollProgressAdapter extends StatefulWidget {
  final double speedFactor;
  const _Sample39ScrollProgressAdapter({super.key, required this.speedFactor});

  @override
  State<_Sample39ScrollProgressAdapter> createState() =>
      _Sample39ScrollProgressAdapterState();
}

class _Sample39ScrollProgressAdapterState
    extends State<_Sample39ScrollProgressAdapter> {
  final ScrollController _ctrl = ScrollController();
  double _ratio = 0.0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_syncProgress);
  }

  void _syncProgress() {
    if (!_ctrl.hasClients) return;
    final max = _ctrl.position.maxScrollExtent;
    final next = max <= 0 ? 1.0 : (_ctrl.offset / max).clamp(0.0, 1.0);
    if ((next - _ratio).abs() > 0.01 && mounted) {
      setState(() => _ratio = next);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_syncProgress);
    _ctrl.dispose();
    super.dispose();
  }

  void _scrollToEnd(bool toEnd) {
    if (!_ctrl.hasClients) return;
    final target = toEnd ? _ctrl.position.maxScrollExtent : 0.0;
    final dur = _scaledDuration(
      context,
      LifeOsMotionTokens.medium,
      widget.speedFactor,
    );
    if (dur == Duration.zero) {
      _ctrl.jumpTo(target);
    } else {
      _ctrl.animateTo(
        target,
        duration: dur,
        curve: LifeOsMotionTokens.standardCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final pct = (_ratio * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tiến độ rà soát sổ tháng: $pct%',
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _sampleChipButton(
              context: context,
              label: pct >= 80 ? 'Đầu sổ' : 'Cuộn 100%',
              icon: Icons.south_rounded,
              onTap: () => _scrollToEnd(pct < 80),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: _ratio,
            minHeight: 6,
            backgroundColor: c.separator,
            valueColor: AlwaysStoppedAnimation<Color>(c.primary),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 108,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border, width: 0.8),
          ),
          child: ListView.builder(
            controller: _ctrl,
            padding: const EdgeInsets.all(8),
            itemCount: 8,
            itemBuilder: (_, idx) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Mục kiểm toán #0${idx + 1} · Đã đối chiếu chứng từ',
                softWrap: true,
                style: TextStyle(
                  fontSize: 12,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Sample40StaleWhileRevalidate extends StatefulWidget {
  final double speedFactor;
  const _Sample40StaleWhileRevalidate({super.key, required this.speedFactor});

  @override
  State<_Sample40StaleWhileRevalidate> createState() =>
      _Sample40StaleWhileRevalidateState();
}

class _Sample40StaleWhileRevalidateState
    extends State<_Sample40StaleWhileRevalidate> {
  bool _hasData = true;
  bool _isLoading = false;
  int _revision = 1;
  Timer? _resolveTimer;

  @override
  void dispose() {
    _resolveTimer?.cancel();
    super.dispose();
  }

  void _triggerSwrRefresh() {
    _resolveTimer?.cancel();
    setState(() {
      _hasData = true;
      _isLoading = true;
    });
    _resolveTimer = Timer(
      _scaledDuration(
        context,
        const Duration(milliseconds: 520),
        widget.speedFactor,
      ),
      () {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _revision++;
          });
        }
      },
    );
  }

  void _triggerColdSkeleton() {
    _resolveTimer?.cancel();
    setState(() {
      _hasData = false;
      _isLoading = true;
    });
    _resolveTimer = Timer(
      _scaledDuration(
        context,
        const Duration(milliseconds: 560),
        widget.speedFactor,
      ),
      () {
        if (mounted) {
          setState(() {
            _hasData = true;
            _isLoading = false;
            _revision++;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _sampleChipButton(
              context: context,
              label: 'Đồng bộ ngầm (SWR)',
              icon: Icons.cloud_sync_outlined,
              primary: true,
              onTap: _triggerSwrRefresh,
            ),
            _sampleChipButton(
              context: context,
              label: 'Tải lạnh (Skeleton)',
              icon: Icons.hourglass_top_rounded,
              onTap: _triggerColdSkeleton,
            ),
          ],
        ),
        const SizedBox(height: 8),
        LifeOsStaleWhileRevalidate(
          isLoading: _isLoading,
          hasData: _hasData,
          skeleton: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border, width: 0.8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LifeOsSkeletonBox(width: 140, height: 14),
                SizedBox(height: 8),
                LifeOsSkeletonBox(height: 22),
              ],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border, width: 0.8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ví Vietcombank · Bản ghi #$_revision',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      LifeOsTruthfulNumericText(
                        formattedValue:
                            '${(18450000 + _revision * 50000).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} ₫',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                LifeOsStatusPill(
                  label: _isLoading ? 'Đang làm mới...' : 'Đã lưu đệm',
                  icon: _isLoading
                      ? Icons.sync_rounded
                      : Icons.check_circle_outline_rounded,
                  tone: _isLoading
                      ? LifeOsAccentTone.blue
                      : LifeOsAccentTone.emerald,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Sample41AnimatedDiffLedger extends StatefulWidget {
  final double speedFactor;
  const _Sample41AnimatedDiffLedger({super.key, required this.speedFactor});

  @override
  State<_Sample41AnimatedDiffLedger> createState() =>
      _Sample41AnimatedDiffLedgerState();
}

class _Sample41AnimatedDiffLedgerState
    extends State<_Sample41AnimatedDiffLedger> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<(int id, String label, String amount)> _entries = [
    (1, 'Ăn trưa cơm tấm', '-55.000 ₫'),
    (2, 'Gửi xe trung tâm', '-10.000 ₫'),
  ];
  int _seq = 2;

  void _insertEntry() {
    if (_entries.length >= 5) return;
    _seq++;
    final item = (_seq, 'Giao dịch mới #$_seq', '-95.000 ₫');
    _entries.insert(0, item);
    _listKey.currentState?.insertItem(
      0,
      duration: _scaledDuration(
        context,
        LifeOsMotionTokens.standard,
        widget.speedFactor,
      ),
    );
    setState(() {});
  }

  void _removeTop() {
    if (_entries.isEmpty) return;
    final removed = _entries.removeAt(0);
    _listKey.currentState?.removeItem(
      0,
      (ctx, anim) => _buildAnimatedRow(ctx, removed, anim),
      duration: _scaledDuration(
        context,
        LifeOsMotionTokens.exitFast,
        widget.speedFactor,
      ),
    );
    setState(() {});
  }

  Widget _buildAnimatedRow(
    BuildContext context,
    (int, String, String) item,
    Animation<double> animation,
  ) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: c.border, width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.$2,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            Text(
              item.$3,
              style: TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );

    if (motion.isReducedMotion) {
      return FadeTransition(opacity: animation, child: row);
    }
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: LifeOsMotionTokens.standardCurve,
      ),
      child: FadeTransition(opacity: animation, child: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _sampleChipButton(
              context: context,
              label: '+ Chèn giao dịch',
              icon: Icons.add_rounded,
              primary: true,
              onTap: _insertEntry,
            ),
            _sampleChipButton(
              context: context,
              label: 'Xóa dòng đầu',
              icon: Icons.remove_circle_outline_rounded,
              onTap: _removeTop,
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedList(
          key: _listKey,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          initialItemCount: _entries.length,
          itemBuilder: (ctx, idx, anim) =>
              _buildAnimatedRow(ctx, _entries[idx], anim),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// IMPLEMENTATIONS: GROUP 6 (#42–#49)
// ════════════════════════════════════════════════════════════════════════════

class _Sample42MultiDetentSpring extends StatelessWidget {
  final double speedFactor;
  const _Sample42MultiDetentSpring({super.key, required this.speedFactor});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _sampleChipButton(
              context: context,
              label: 'Mở Sheet thật (42/72/92%)',
              icon: Icons.open_in_new_rounded,
              primary: true,
              onTap: () {
                showLifeOsSpringSheet<void>(
                  context: context,
                  detents: const <double>[0.42, 0.72, 0.92],
                  initialDetentIndex: 1,
                  header: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Text(
                      'LifeOsSpringBottomSheet (ζ = 1.003 · 0% vọt lố)',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  builder: (ctx, scrollCtrl) => ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: 8,
                    itemBuilder: (_, idx) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LifeOsSoftCard(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Hạng mục ngân sách #0${idx + 1} · Kéo thanh nắm để đổi nấc 42% / 72% / 92%',
                          softWrap: true,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 176,
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border, width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
          child: LifeOsSpringBottomSheet(
            detents: const <double>[0.42, 0.72, 0.92],
            initialDetentIndex: 1,
            dismissible: false,
            builder: (ctx, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                Text(
                  'Chạm nấc 42% / 72% / 92% hoặc kéo dọc trực tiếp tại sân khấu mini này.',
                  softWrap: true,
                  style: TextStyle(fontSize: 11.8, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Sample43NestedScrollHandoff extends StatefulWidget {
  final double speedFactor;
  const _Sample43NestedScrollHandoff({super.key, required this.speedFactor});

  @override
  State<_Sample43NestedScrollHandoff> createState() =>
      _Sample43NestedScrollHandoffState();
}

class _Sample43NestedScrollHandoffState
    extends State<_Sample43NestedScrollHandoff>
    with SingleTickerProviderStateMixin {
  late final LifeOsSpringController _sheetFrac;
  double _innerScrollPx = 0.0;

  @override
  void initState() {
    super.initState();
    _sheetFrac = LifeOsSpringController(
      vsync: this,
      initialValue: 0.82,
      spring: LifeOsMotionTokens.sheetSnapSpring,
    );
  }

  @override
  void dispose() {
    _sheetFrac.dispose();
    super.dispose();
  }

  void _handleVerticalDelta(double dy) {
    // Dragging up (dy < 0): expand sheet first up to 0.92, then scroll inner list
    if (dy < 0) {
      if (_sheetFrac.value < 0.92) {
        _sheetFrac.jumpTo((_sheetFrac.value - dy / 160.0).clamp(0.45, 0.92));
      } else {
        setState(() => _innerScrollPx = (_innerScrollPx - dy).clamp(0.0, 90.0));
      }
    } else {
      // Dragging down (dy > 0): consume inner scroll down to 0, then seamlessly handoff to sheet!
      if (_innerScrollPx > 0) {
        setState(() => _innerScrollPx = (_innerScrollPx - dy).clamp(0.0, 90.0));
      } else {
        _sheetFrac.jumpTo((_sheetFrac.value - dy / 160.0).clamp(0.45, 0.92));
      }
    }
  }

  void _settleSheet() {
    final motion = LifeOsMotionScope.read(context);
    final target = _sheetFrac.value >= 0.68 ? 0.86 : 0.52;
    _sheetFrac.animateTo(
      target,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onVerticalDragUpdate: (d) => _handleVerticalDelta(d.delta.dy),
          onVerticalDragEnd: (_) => _settleSheet(),
          child: Container(
            height: 142,
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border, width: 0.8),
            ),
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.antiAlias,
            child: AnimatedBuilder(
              animation: _sheetFrac,
              builder: (context, _) {
                final pct = (_sheetFrac.value * 100).round();
                return Container(
                  height: 142 * _sheetFrac.value,
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    border: Border(
                      top: BorderSide(color: c.primary, width: 1.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          LifeOsStatusPill(
                            label: 'Sheet: $pct%',
                            tone: LifeOsAccentTone.emerald,
                          ),
                          LifeOsStatusPill(
                            label: 'Cuộn trong: ${_innerScrollPx.round()} px',
                            tone: _innerScrollPx > 0
                                ? LifeOsAccentTone.blue
                                : LifeOsAccentTone.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          'Kéo dọc tại đây: cuộn danh sách về 0 px sẽ tự chuyển sang thu gọn Sheet không khựng.',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 11.6,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Sample44IosScaleBack extends StatefulWidget {
  final double speedFactor;
  const _Sample44IosScaleBack({super.key, required this.speedFactor});

  @override
  State<_Sample44IosScaleBack> createState() => _Sample44IosScaleBackState();
}

class _Sample44IosScaleBackState extends State<_Sample44IosScaleBack>
    with SingleTickerProviderStateMixin {
  late final LifeOsSpringController _openCtrl;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _openCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: LifeOsMotionTokens.sheetSnapSpring,
    );
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    final next = !_isOpen;
    setState(() => _isOpen = next);
    final motion = LifeOsMotionScope.read(context);
    _openCtrl.animateTo(
      next ? 1.0 : 0.0,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sampleChipButton(
          context: context,
          label: _isOpen ? 'Đóng tấm con (1.00)' : 'Mở tấm con (Nền 0.94)',
          icon: Icons.layers_outlined,
          primary: !_isOpen,
          onTap: _toggle,
        ),
        const SizedBox(height: 8),
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedBuilder(
            animation: _openCtrl,
            builder: (context, _) {
              final t = _openCtrl.value.clamp(0.0, 1.0);
              final bgScale = motion.isReducedMotion
                  ? 1.0
                  : ui.lerpDouble(1.0, 0.94, t)!;
              final sheetDy = motion.isReducedMotion
                  ? 0.0
                  : ui.lerpDouble(110.0, 0.0, t)!;

              return Stack(
                children: [
                  Positioned.fill(
                    child: Transform.scale(
                      scale: bgScale,
                      child: Opacity(
                        opacity: ui.lerpDouble(1.0, 0.76, t)!,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Text(
                            'Trang gốc: Tổng tài sản · Scale ${bgScale.toStringAsFixed(2)}',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 12.2,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (t > 0.01)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Transform.translate(
                        offset: Offset(0, sheetDy),
                        child: Opacity(
                          opacity: t,
                          child: Container(
                            height: 86,
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: c.primarySubtle,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              border: Border(
                                top: BorderSide(color: c.primary, width: 1.2),
                              ),
                            ),
                            child: Text(
                              'Tấm con nổi lên mượt · Chạm nút trên để thu hồi về 1.00',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12.2,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Sample45PagedSharedAxis extends StatefulWidget {
  final double speedFactor;
  const _Sample45PagedSharedAxis({super.key, required this.speedFactor});

  @override
  State<_Sample45PagedSharedAxis> createState() =>
      _Sample45PagedSharedAxisState();
}

class _Sample45PagedSharedAxisState extends State<_Sample45PagedSharedAxis> {
  int _step = 0;
  bool _reverse = false;

  static const _steps = <(String, String)>[
    ('Bước 1/3 · Nhập hóa đơn', 'Tổng bữa tối gia đình: 1.200.000 ₫'),
    ('Bước 2/3 · Chia thành viên', '4 thành viên · Mỗi người 300.000 ₫'),
    ('Bước 3/3 · Hoàn tất mã QR', 'Sẵn sàng gửi thông báo nhắc thanh toán'),
  ];

  void _goTo(int next) {
    if (next == _step || next < 0 || next >= _steps.length) return;
    setState(() {
      _reverse = next < _step;
      _step = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LifeOsMaterialContentSwitcher(
          reverse: _reverse,
          sharedAxis: LifeOsSharedAxis.horizontal,
          duration: _scaledDuration(
            context,
            LifeOsMotionTokens.medium,
            widget.speedFactor,
          ),
          child: Container(
            key: ValueKey<int>(_step),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LifeOsStatusPill(
                  label: _steps[_step].$1,
                  icon: Icons.swap_horiz_rounded,
                  tone: LifeOsAccentTone.emerald,
                ),
                const SizedBox(height: 6),
                Text(
                  _steps[_step].$2,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (_step > 0)
              _sampleChipButton(
                context: context,
                label: 'Quay lại',
                icon: Icons.arrow_back_rounded,
                onTap: () => _goTo(_step - 1),
              ),
            _sampleChipButton(
              context: context,
              label: _step < 2 ? 'Tiếp theo' : 'Làm lại từ Bước 1',
              icon: Icons.arrow_forward_rounded,
              primary: true,
              onTap: () => _goTo((_step + 1) % 3),
            ),
          ],
        ),
      ],
    );
  }
}

class _Sample46GooeyBezierEdge extends StatefulWidget {
  final double speedFactor;
  const _Sample46GooeyBezierEdge({super.key, required this.speedFactor});

  @override
  State<_Sample46GooeyBezierEdge> createState() =>
      _Sample46GooeyBezierEdgeState();
}

class _Sample46GooeyBezierEdgeState extends State<_Sample46GooeyBezierEdge>
    with SingleTickerProviderStateMixin {
  late final LifeOsSpringController _bendCtrl;
  double _anchorX = 0.5;

  @override
  void initState() {
    super.initState();
    _bendCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: LifeOsMotionTokens.bouncySpring,
      tolerance: LifeOsMotionTokens.pixelSpringTolerance,
    );
  }

  @override
  void dispose() {
    _bendCtrl.dispose();
    super.dispose();
  }

  void _pluckWave() {
    final motion = LifeOsMotionScope.read(context);
    motion.lightHaptic();
    if (motion.isReducedMotion || !TickerMode.valuesOf(context).enabled) return;
    _bendCtrl.jumpTo(46.0);
    _bendCtrl.animateTo(
      0.0,
      velocity: -220.0,
      motion: motion,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onPanUpdate: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize) {
              _anchorX = (d.localPosition.dx / box.size.width).clamp(
                0.15,
                0.85,
              );
            }
            _bendCtrl.jumpTo((_bendCtrl.value + d.delta.dy).clamp(-56.0, 56.0));
          },
          onPanEnd: (d) {
            _bendCtrl.animateTo(
              0.0,
              velocity: d.velocity.pixelsPerSecond.dy * 0.35,
              motion: motion,
              tickersEnabled: TickerMode.valuesOf(context).enabled,
              timeDilationFactor: widget.speedFactor,
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 118,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _bendCtrl,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _GooeyWavePainter(
                      bendPx: motion.isReducedMotion ? 0.0 : _bendCtrl.value,
                      anchorFractionX: _anchorX,
                      fillColor: c.primary,
                      bgColor: c.primarySubtle,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          'Kéo dọc màng sóng Bezier rồi thả tay',
                          textAlign: TextAlign.center,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12.2,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: _sampleChipButton(
            context: context,
            label: 'Búng sóng đàn hồi',
            icon: Icons.waves_rounded,
            onTap: _pluckWave,
          ),
        ),
      ],
    );
  }
}

class _GooeyWavePainter extends CustomPainter {
  final double bendPx;
  final double anchorFractionX;
  final Color fillColor;
  final Color bgColor;

  const _GooeyWavePainter({
    required this.bendPx,
    required this.anchorFractionX,
    required this.fillColor,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);
    final midY = size.height * 0.56;
    final peakX = size.width * anchorFractionX;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, midY)
      ..quadraticBezierTo(peakX, midY + bendPx * 1.45, size.width, midY)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fillColor.withValues(alpha: 0.28));
  }

  @override
  bool shouldRepaint(covariant _GooeyWavePainter oldDelegate) =>
      oldDelegate.bendPx != bendPx ||
      oldDelegate.anchorFractionX != anchorFractionX;
}

class _Sample47ProgressiveDisclosure extends StatelessWidget {
  final double speedFactor;
  const _Sample47ProgressiveDisclosure({super.key, required this.speedFactor});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Chuyển khoản Quỹ Học tập',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Text(
                '-1.250.000 ₫',
                style: TextStyle(
                  fontSize: 13.2,
                  fontWeight: FontWeight.w800,
                  color: c.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LifeOsDetailsDiscloseSection(
            label: 'Chi tiết',
            expandedLabel: 'Thu gọn',
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Mã tham chiếu: FT26328****91 · Phí chuyển: 0 ₫ · Kênh: VietQR Napas 247',
                softWrap: true,
                style: TextStyle(
                  fontSize: 11.8,
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sample48DynamicTopToast extends StatefulWidget {
  final double speedFactor;
  const _Sample48DynamicTopToast({super.key, required this.speedFactor});

  @override
  State<_Sample48DynamicTopToast> createState() =>
      _Sample48DynamicTopToastState();
}

class _Sample48DynamicTopToastState extends State<_Sample48DynamicTopToast> {
  int _tapCount = 0;
  int _uniqueShown = 0;
  DateTime? _lastBurstAt;

  void _fireToast({required bool burst}) {
    final now = DateTime.now();
    final hits = burst ? 3 : 1;
    for (var i = 0; i < hits; i++) {
      LifeOsTopToast.show(
        context,
        '✓ Đã lưu giao dịch khớp ngân sách gia đình',
      );
    }
    final withinDedupe =
        _lastBurstAt != null &&
        now.difference(_lastBurstAt!) <= LifeOsMotionTokens.toastDedupeWindow;
    setState(() {
      _tapCount += hits;
      if (!withinDedupe) {
        _uniqueShown++;
      }
      _lastBurstAt = now;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _sampleChipButton(
              context: context,
              label: 'Hiện Top Toast',
              icon: Icons.notifications_active_outlined,
              primary: true,
              onTap: () => _fireToast(burst: false),
            ),
            _sampleChipButton(
              context: context,
              label: 'Bắn x3 (Chống lặp 1200ms)',
              icon: Icons.filter_3_rounded,
              onTap: () => _fireToast(burst: true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LifeOsStatusPill(
          label:
              'Lệnh gửi: $_tapCount · Hiển thị thực: $_uniqueShown (gộp trùng 1200ms)',
          icon: Icons.shield_outlined,
          tone: LifeOsAccentTone.emerald,
        ),
      ],
    );
  }
}

class _Sample49FadeScaleDialog extends StatelessWidget {
  final double speedFactor;
  const _Sample49FadeScaleDialog({super.key, required this.speedFactor});

  Future<void> _openGlassDialog(BuildContext context) async {
    final c = TammySemanticColors.of(context);
    final dur = _scaledDuration(
      context,
      LifeOsMotionTokens.standard,
      speedFactor,
    );
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Đóng hộp thoại',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: dur,
      pageBuilder: (dialogCtx, _, _) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: LifeOsSoftCard(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xác nhận khóa sổ tháng',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hộp thoại xuất hiện bằng Material FadeScaleTransition mượt mà, không gây chói hoặc giật khung.',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.6,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _sampleChipButton(
                          context: dialogCtx,
                          label: 'Đã hiểu',
                          primary: true,
                          onTap: () => Navigator.of(dialogCtx).pop(),
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
      transitionBuilder: (ctx, anim, _, child) {
        final motion = LifeOsMotionScope.of(ctx);
        if (motion.isReducedMotion) {
          return FadeTransition(opacity: anim, child: child);
        }
        return FadeScaleTransition(animation: anim, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: _sampleChipButton(
        context: context,
        label: 'Mở hộp thoại FadeScale Kính',
        icon: Icons.open_in_browser_rounded,
        primary: true,
        onTap: () => _openGlassDialog(context),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// IMPLEMENTATIONS: GROUP 7 (#50–#57)
// ════════════════════════════════════════════════════════════════════════════

class _Sample50MorphDonut extends StatefulWidget {
  final double speedFactor;
  const _Sample50MorphDonut({super.key, required this.speedFactor});

  @override
  State<_Sample50MorphDonut> createState() => _Sample50MorphDonutState();
}

class _Sample50MorphDonutState extends State<_Sample50MorphDonut>
    with SingleTickerProviderStateMixin {
  static const _presets = <List<double>>[
    [0.42, 0.26, 0.18, 0.14],
    [0.25, 0.20, 0.20, 0.35],
    [0.50, 0.18, 0.17, 0.15],
  ];
  static const _labels = <String>['Ăn uống', 'Nhà cửa', 'Đi lại', 'Tiết kiệm'];
  static const _colors = <Color>[
    Color(0xFF0D8A3E),
    Color(0xFF2563EB),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
  ];

  int _presetIdx = 0;
  int _activeSlice = 0;
  List<double> _from = _presets[0];
  List<double> _to = _presets[0];
  late final LifeOsSpringController _morphCtrl;

  @override
  void initState() {
    super.initState();
    _morphCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: 1.0,
      spring: LifeOsMotionTokens.chartMorphSpring,
    );
  }

  @override
  void dispose() {
    _morphCtrl.dispose();
    super.dispose();
  }

  List<double> _currentWeights() {
    final t = _morphCtrl.value.clamp(0.0, 1.0);
    return List<double>.generate(4, (i) => ui.lerpDouble(_from[i], _to[i], t)!);
  }

  void _cyclePreset() {
    final motion = LifeOsMotionScope.read(context);
    setState(() {
      _from = _currentWeights();
      _presetIdx = (_presetIdx + 1) % _presets.length;
      _to = _presets[_presetIdx];
    });
    _morphCtrl.jumpTo(0.0);
    _morphCtrl.animateTo(
      1.0,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () =>
                  setState(() => _activeSlice = (_activeSlice + 1) % 4),
              child: SizedBox(
                width: 96,
                height: 96,
                child: AnimatedBuilder(
                  animation: _morphCtrl,
                  builder: (context, _) {
                    final weights = _currentWeights();
                    final pct = (weights[_activeSlice] * 100).round();
                    return CustomPaint(
                      painter: _DonutPainter(
                        weights: weights,
                        colors: _colors,
                        activeIndex: _activeSlice,
                      ),
                      child: Center(
                        child: Text(
                          '$pct%',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đang chọn: ${_labels[_activeSlice]} (ζ = 1.001)',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _sampleChipButton(
                        context: context,
                        label: 'Đổi phân bổ',
                        icon: Icons.pie_chart_outline_rounded,
                        primary: true,
                        onTap: _cyclePreset,
                      ),
                      _sampleChipButton(
                        context: context,
                        label: 'Đổi lát',
                        onTap: () => setState(
                          () => _activeSlice = (_activeSlice + 1) % 4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> weights;
  final List<Color> colors;
  final int activeIndex;

  const _DonutPainter({
    required this.weights,
    required this.colors,
    required this.activeIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.39;
    var startAngle = -math.pi / 2;

    for (var i = 0; i < weights.length; i++) {
      final sweep = weights[i] * math.pi * 2;
      final isSel = i == activeIndex;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 14.0 : 10.5
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + 0.03,
        math.max(0.02, sweep - 0.06),
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.activeIndex != activeIndex || oldDelegate.weights != weights;
}

class _Sample51CashflowScrub extends StatefulWidget {
  final double speedFactor;
  const _Sample51CashflowScrub({super.key, required this.speedFactor});

  @override
  State<_Sample51CashflowScrub> createState() => _Sample51CashflowScrubState();
}

class _Sample51CashflowScrubState extends State<_Sample51CashflowScrub>
    with SingleTickerProviderStateMixin {
  static const _days = <String>['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  static const _weekA = <int>[320, 580, 240, 790, 460, 910, 640];
  static const _weekB = <int>[610, 340, 820, 410, 730, 520, 880];

  bool _useWeekB = false;
  int _scrubIndex = 3;
  late final LifeOsSpringController _morphCtrl;

  @override
  void initState() {
    super.initState();
    _morphCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: LifeOsMotionTokens.chartMorphSpring,
    );
  }

  @override
  void dispose() {
    _morphCtrl.dispose();
    super.dispose();
  }

  void _toggleWeek() {
    final next = !_useWeekB;
    setState(() => _useWeekB = next);
    final motion = LifeOsMotionScope.read(context);
    _morphCtrl.animateTo(
      next ? 1.0 : 0.0,
      motion: motion,
      tickersEnabled: TickerMode.valuesOf(context).enabled,
      timeDilationFactor: widget.speedFactor,
    );
  }

  void _scrubAt(double localDx, double width) {
    if (width <= 0) return;
    final idx = ((localDx / width) * 7).floor().clamp(0, 6);
    if (idx != _scrubIndex) {
      LifeOsMotionScope.read(context).selectionHaptic();
      setState(() => _scrubIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final activeValues = _useWeekB ? _weekB : _weekA;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            LifeOsStatusPill(
              label:
                  '${_days[_scrubIndex]}: ${activeValues[_scrubIndex]}.000 ₫',
              icon: Icons.bar_chart_rounded,
              tone: LifeOsAccentTone.emerald,
            ),
            _sampleChipButton(
              context: context,
              label: _useWeekB ? 'Xem Tuần 1' : 'Xem Tuần 2',
              icon: Icons.swap_horiz_rounded,
              onTap: _toggleWeek,
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, constraints) {
            return GestureDetector(
              onTapDown: (d) =>
                  _scrubAt(d.localPosition.dx, constraints.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _scrubAt(d.localPosition.dx, constraints.maxWidth),
              child: SizedBox(
                height: 98,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: _morphCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _CashflowBarPainter(
                        t: _morphCtrl.value.clamp(0.0, 1.0),
                        weekA: _weekA,
                        weekB: _weekB,
                        selectedIdx: _scrubIndex,
                        activeColor: c.primary,
                        mutedColor: c.primary.withValues(alpha: 0.25),
                        lineColor: c.secondary,
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CashflowBarPainter extends CustomPainter {
  final double t;
  final List<int> weekA;
  final List<int> weekB;
  final int selectedIdx;
  final Color activeColor;
  final Color mutedColor;
  final Color lineColor;

  const _CashflowBarPainter({
    required this.t,
    required this.weekA,
    required this.weekB,
    required this.selectedIdx,
    required this.activeColor,
    required this.mutedColor,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slotW = size.width / 7;
    for (var i = 0; i < 7; i++) {
      final v = ui.lerpDouble(weekA[i].toDouble(), weekB[i].toDouble(), t)!;
      final normH = (v / 1000.0).clamp(0.12, 1.0) * (size.height - 14);
      final cx = slotW * i + slotW / 2;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 10, size.height - normH, 20, normH),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = i == selectedIdx ? activeColor : mutedColor,
      );
      if (i == selectedIdx) {
        canvas.drawLine(
          Offset(cx, 0),
          Offset(cx, size.height),
          Paint()
            ..color = lineColor.withValues(alpha: 0.55)
            ..strokeWidth = 1.3,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CashflowBarPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.selectedIdx != selectedIdx;
}

class _Sample52PathSparkline extends StatefulWidget {
  final double speedFactor;
  const _Sample52PathSparkline({super.key, required this.speedFactor});

  @override
  State<_Sample52PathSparkline> createState() => _Sample52PathSparklineState();
}

class _Sample52PathSparklineState extends State<_Sample52PathSparkline>
    with SingleTickerProviderStateMixin {
  static const _growthSeries = <double>[12, 15, 14, 19, 22, 21, 27];
  static const _flatSeries = <double>[20, 20, 20, 20, 20, 20, 20];

  bool _flatMode = false;
  late final AnimationController _drawCtrl;

  @override
  void initState() {
    super.initState();
    _drawCtrl = AnimationController(
      vsync: this,
      duration: LifeOsMotionTokens.expressive,
      value: 1.0,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _replayStroke());
  }

  void _replayStroke() {
    if (!mounted) return;
    final dur = _scaledDuration(
      context,
      LifeOsMotionTokens.expressive,
      widget.speedFactor,
    );
    if (dur == Duration.zero || !TickerMode.valuesOf(context).enabled) {
      _drawCtrl.value = 1.0;
      return;
    }
    _drawCtrl.duration = dur;
    _drawCtrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    _drawCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final points = _flatMode ? _flatSeries : _growthSeries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _sampleChipButton(
              context: context,
              label: 'Tăng trưởng (+14,2%)',
              primary: !_flatMode,
              onTap: () {
                setState(() => _flatMode = false);
                _replayStroke();
              },
            ),
            _sampleChipButton(
              context: context,
              label: 'Delta = 0 (Đường phẳng)',
              primary: _flatMode,
              onTap: () {
                setState(() => _flatMode = true);
                _replayStroke();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 86,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border, width: 0.8),
          ),
          child: AnimatedBuilder(
            animation: _drawCtrl,
            builder: (context, _) {
              return CustomPaint(
                painter: _SparklinePainter(
                  values: points,
                  progress: _drawCtrl.value,
                  strokeColor: c.primary,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final double progress;
  final Color strokeColor;

  const _SparklinePainter({
    required this.values,
    required this.progress,
    required this.strokeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = maxV - minV;

    final fullPath = Path();
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      // Guard delta == 0: render exact centered horizontal line without division by zero!
      final normY = span.abs() < 1e-6 ? 0.5 : (values[i] - minV) / span;
      final y = size.height - (normY * (size.height - 16) + 8);
      if (i == 0) {
        fullPath.moveTo(x, y);
      } else {
        fullPath.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final metric in fullPath.computeMetrics()) {
      final extracted = metric.extractPath(
        0.0,
        metric.length * progress.clamp(0.0, 1.0),
      );
      canvas.drawPath(extracted, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.values != values;
}

class _Sample53TruthfulBalance extends StatefulWidget {
  final double speedFactor;
  const _Sample53TruthfulBalance({super.key, required this.speedFactor});

  @override
  State<_Sample53TruthfulBalance> createState() =>
      _Sample53TruthfulBalanceState();
}

class _Sample53TruthfulBalanceState extends State<_Sample53TruthfulBalance> {
  static const _balances = <String>[
    '24.850.000 ₫',
    '25.120.000 ₫',
    '19.640.000 ₫',
  ];
  int _idx = 0;
  bool _obscured = false;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final shownText = _obscured ? '•••••••• ₫' : _balances[_idx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.primarySubtle,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Số dư thực tế (Crossfade 160ms · Không đếm giả từ 0)',
                softWrap: true,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              LifeOsTruthfulNumericText(
                formattedValue: shownText,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: c.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _sampleChipButton(
              context: context,
              label: 'Cập nhật số dư mới',
              icon: Icons.sync_alt_rounded,
              primary: true,
              onTap: () => setState(() => _idx = (_idx + 1) % _balances.length),
            ),
            _sampleChipButton(
              context: context,
              label: _obscured ? 'Hiện số dư' : 'Ẩn số dư',
              icon: _obscured
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              onTap: () => setState(() => _obscured = !_obscured),
            ),
          ],
        ),
      ],
    );
  }
}

class _Sample54SimulatorScrub extends StatefulWidget {
  final double speedFactor;
  const _Sample54SimulatorScrub({super.key, required this.speedFactor});

  @override
  State<_Sample54SimulatorScrub> createState() =>
      _Sample54SimulatorScrubState();
}

class _Sample54SimulatorScrubState extends State<_Sample54SimulatorScrub> {
  double _saveRate = 0.30;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final pct = (_saveRate * 100).round();
    final yearsToFire = math.max(6, (38 - _saveRate * 42).round());
    final projectedBn = (1.8 + _saveRate * 8.5).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            LifeOsStatusPill(
              label: 'Tiết kiệm: $pct%/tháng',
              tone: LifeOsAccentTone.emerald,
            ),
            LifeOsStatusPill(
              label: 'Đạt FIRE sau ~$yearsToFire năm ($projectedBn tỷ ₫)',
              tone: LifeOsAccentTone.blue,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border, width: 0.8),
          ),
          child: CustomPaint(
            painter: _FireCurvePainter(
              saveRate: _saveRate,
              strokeColor: c.primary,
            ),
          ),
        ),
        Slider(
          value: _saveRate,
          min: 0.10,
          max: 0.65,
          onChanged: (v) => setState(() => _saveRate = v),
        ),
      ],
    );
  }
}

class _FireCurvePainter extends CustomPainter {
  final double saveRate;
  final Color strokeColor;

  const _FireCurvePainter({required this.saveRate, required this.strokeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    const steps = 16;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      final compound = math.pow(t, 1.85 - saveRate * 0.9).toDouble();
      final y = size.height - (compound * (size.height - 8) + 4);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FireCurvePainter oldDelegate) =>
      oldDelegate.saveRate != saveRate ||
      oldDelegate.strokeColor != strokeColor;
}

class _Sample55SixJarsRings extends StatefulWidget {
  final double speedFactor;
  const _Sample55SixJarsRings({super.key, required this.speedFactor});

  @override
  State<_Sample55SixJarsRings> createState() => _Sample55SixJarsRingsState();
}

class _Sample55SixJarsRingsState extends State<_Sample55SixJarsRings>
    with TickerProviderStateMixin {
  late final LifeOsSpringController _r1;
  late final LifeOsSpringController _r2;
  late final LifeOsSpringController _r3;
  bool _alt = false;

  @override
  void initState() {
    super.initState();
    _r1 = LifeOsSpringController(
      vsync: this,
      initialValue: 0.78,
      spring: LifeOsMotionTokens.chartMorphSpring,
    );
    _r2 = LifeOsSpringController(
      vsync: this,
      initialValue: 0.62,
      spring: LifeOsMotionTokens.chartMorphSpring,
    );
    _r3 = LifeOsSpringController(
      vsync: this,
      initialValue: 0.90,
      spring: LifeOsMotionTokens.chartMorphSpring,
    );
  }

  @override
  void dispose() {
    _r1.dispose();
    _r2.dispose();
    _r3.dispose();
    super.dispose();
  }

  void _toggleTargets() {
    final next = !_alt;
    setState(() => _alt = next);
    final motion = LifeOsMotionScope.read(context);
    final tickers = TickerMode.valuesOf(context).enabled;
    _r1.animateTo(
      next ? 0.95 : 0.78,
      motion: motion,
      tickersEnabled: tickers,
      timeDilationFactor: widget.speedFactor,
    );
    _r2.animateTo(
      next ? 0.84 : 0.62,
      motion: motion,
      tickersEnabled: tickers,
      timeDilationFactor: widget.speedFactor,
    );
    _r3.animateTo(
      next ? 0.52 : 0.90,
      motion: motion,
      tickersEnabled: tickers,
      timeDilationFactor: widget.speedFactor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      children: [
        SizedBox(
          width: 92,
          height: 92,
          child: AnimatedBuilder(
            animation: Listenable.merge([_r1, _r2, _r3]),
            builder: (context, _) {
              return CustomPaint(
                painter: _ConcentricRingsPainter(
                  ratios: [_r1.value, _r2.value, _r3.value],
                  colors: [c.primary, c.secondary, c.warning],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thiết yếu · Tự do TC · Dự phòng (0% vọt lố)',
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.4,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _sampleChipButton(
                context: context,
                label: 'Đổi mục tiêu 6 Hũ',
                icon: Icons.track_changes_rounded,
                primary: true,
                onTap: _toggleTargets,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConcentricRingsPainter extends CustomPainter {
  final List<double> ratios;
  final List<Color> colors;

  const _ConcentricRingsPainter({required this.ratios, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < ratios.length; i++) {
      final radius = (size.width * 0.42) - i * 11.0;
      final trackPaint = Paint()
        ..color = colors[i].withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.5;
      final arcPaint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.5
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(center, radius, trackPaint);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        ratios[i].clamp(0.0, 1.0) * math.pi * 2,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConcentricRingsPainter oldDelegate) => true;
}

class _Sample56PomodoroRing extends StatefulWidget {
  final double speedFactor;
  const _Sample56PomodoroRing({super.key, required this.speedFactor});

  @override
  State<_Sample56PomodoroRing> createState() => _Sample56PomodoroRingState();
}

class _Sample56PomodoroRingState extends State<_Sample56PomodoroRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sprintCtrl;

  @override
  void initState() {
    super.initState();
    _sprintCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
      value: 0.75,
    );
  }

  @override
  void dispose() {
    _sprintCtrl.dispose();
    super.dispose();
  }

  void _runPreviewSprint() {
    final dur = _scaledDuration(
      context,
      const Duration(milliseconds: 1600),
      widget.speedFactor,
    );
    if (dur == Duration.zero || !TickerMode.valuesOf(context).enabled) {
      setState(() => _sprintCtrl.value = 1.0);
      return;
    }
    _sprintCtrl.duration = dur;
    _sprintCtrl.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      children: [
        SizedBox(
          width: 84,
          height: 84,
          child: AnimatedBuilder(
            animation: _sprintCtrl,
            builder: (context, _) {
              final remainSec = ((1.0 - _sprintCtrl.value) * 25 * 60).round();
              final mm = (remainSec ~/ 60).toString().padLeft(2, '0');
              final ss = (remainSec % 60).toString().padLeft(2, '0');
              return CustomPaint(
                painter: _ConcentricRingsPainter(
                  ratios: [1.0 - _sprintCtrl.value * 0.99],
                  colors: [c.primary],
                ),
                child: Center(
                  child: Text(
                    '$mm:$ss',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _sampleChipButton(
            context: context,
            label: 'Chạy thử chu kỳ hữu hạn',
            icon: Icons.timer_outlined,
            primary: true,
            onTap: _runPreviewSprint,
          ),
        ),
      ],
    );
  }
}

class _Sample57HonestBudgetBar extends StatefulWidget {
  final double speedFactor;
  const _Sample57HonestBudgetBar({super.key, required this.speedFactor});

  @override
  State<_Sample57HonestBudgetBar> createState() =>
      _Sample57HonestBudgetBarState();
}

class _Sample57HonestBudgetBarState extends State<_Sample57HonestBudgetBar> {
  bool _swapped = false;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final safeRatio = _swapped ? 0.54 : 0.68;
    final overRatio = _swapped ? 1.32 : 1.18;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRow(
          context,
          title: 'Ăn uống gia đình (An toàn)',
          ratio: safeRatio,
          color: c.success,
        ),
        const SizedBox(height: 10),
        _buildRow(
          context,
          title: 'Mua sắm cuối năm (Vượt hạn mức)',
          ratio: overRatio,
          color: c.error,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: _sampleChipButton(
            context: context,
            label: 'Đổi kịch bản tỷ lệ',
            icon: Icons.compare_arrows_rounded,
            onTap: () => setState(() => _swapped = !_swapped),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required String title,
    required double ratio,
    required Color color,
  }) {
    final c = TammySemanticColors.of(context);
    final pct = (ratio * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LifeOsAnimatedProgressBar(
          progressRatio: ratio,
          color: color,
          height: 9,
          semanticsLabel: title,
          semanticsValue: '$pct%',
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// IMPLEMENTATIONS: GROUP 8 (#58–#66)
// ════════════════════════════════════════════════════════════════════════════

class _Sample58ShaderCaustics extends StatelessWidget {
  final double speedFactor;
  const _Sample58ShaderCaustics({super.key, required this.speedFactor});

  @override
  Widget build(BuildContext context) {
    return const LifeOsShaderSurface(
      preset: LifeOsShaderPreset.liquidCaustics,
      height: 148,
      borderRadius: 16,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            'GLSL liquid_caustics.frag · Chạm hoặc kéo ngón tay để kích hoạt sóng ngọc lục bảo',
            softWrap: true,
            style: TextStyle(
              fontSize: 12.2,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _Sample59ShaderFoil extends StatelessWidget {
  final double speedFactor;
  const _Sample59ShaderFoil({super.key, required this.speedFactor});

  @override
  Widget build(BuildContext context) {
    return const LifeOsShaderSurface(
      preset: LifeOsShaderPreset.holographicFoil,
      height: 152,
      borderRadius: 16,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LIFEOS METAL FOIL PASS',
              softWrap: true,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: Color(0xFFA7F3D0),
              ),
            ),
            Flexible(
              child: Text(
                'Kéo ngón tay ngang thẻ để xoay dải phản quang Hologram GPU',
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sample60VoiceRmsAura extends StatefulWidget {
  final double speedFactor;
  const _Sample60VoiceRmsAura({super.key, required this.speedFactor});

  @override
  State<_Sample60VoiceRmsAura> createState() => _Sample60VoiceRmsAuraState();
}

class _Sample60VoiceRmsAuraState extends State<_Sample60VoiceRmsAura>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _rmsNotifier = ValueNotifier<double>(0.42);
  late final AnimationController _voicePulseCtrl;

  @override
  void initState() {
    super.initState();
    _voicePulseCtrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1100),
        )..addListener(() {
          final t = _voicePulseCtrl.value;
          _rmsNotifier.value =
              (0.25 + 0.65 * math.sin(t * math.pi * 3).abs()) * (1.0 - t * 0.4);
        });
  }

  @override
  void dispose() {
    _voicePulseCtrl.dispose();
    _rmsNotifier.dispose();
    super.dispose();
  }

  void _simulateUtterance() {
    final motion = LifeOsMotionScope.read(context);
    if (motion.isReducedMotion || !TickerMode.valuesOf(context).enabled) {
      _rmsNotifier.value = 0.55;
      return;
    }
    _voicePulseCtrl.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: CustomPaint(
                painter: _VoiceRmsAuraPainter(
                  rmsListenable: _rmsNotifier,
                  color: c.primary,
                ),
                child: const Center(
                  child: Icon(Icons.mic_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _rmsNotifier,
                    builder: (_, rms, _) => Text(
                      'Biên độ RMS: ${(rms * 100).round()}% (0 setState)',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _rmsNotifier,
                    builder: (_, rms, _) => Slider(
                      value: rms.clamp(0.0, 1.0),
                      onChanged: (v) => _rmsNotifier.value = v,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _sampleChipButton(
            context: context,
            label: 'Thử giọng nói AI (1.1s)',
            icon: Icons.graphic_eq_rounded,
            onTap: _simulateUtterance,
          ),
        ),
      ],
    );
  }
}

class _VoiceRmsAuraPainter extends CustomPainter {
  final ValueNotifier<double> rmsListenable;
  final Color color;

  _VoiceRmsAuraPainter({required this.rmsListenable, required this.color})
    : super(repaint: rmsListenable);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rms = rmsListenable.value.clamp(0.0, 1.0);
    for (var ring = 2; ring >= 0; ring--) {
      final radius = 19.0 + ring * 8.0 + rms * (ring + 1) * 6.5;
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: 0.22 - ring * 0.05),
      );
    }
    canvas.drawCircle(center, 20.0, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _VoiceRmsAuraPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.rmsListenable != rmsListenable;
}

class _Sample61LottieCheck extends StatefulWidget {
  final double speedFactor;
  const _Sample61LottieCheck({super.key, required this.speedFactor});

  @override
  State<_Sample61LottieCheck> createState() => _Sample61LottieCheckState();
}

class _Sample61LottieCheckState extends State<_Sample61LottieCheck> {
  int _runId = 0;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      children: [
        LifeOsLottieAnimation(
          key: ValueKey<int>(_runId),
          assetPath: AppAssets.lottieCheckCelebration,
          size: 80,
          maxCycles: 1,
          playbackSpeed: widget.speedFactor,
          primaryColorOverride: c.primary,
          semanticsLabel: 'Dấu tích xác nhận hoàn tất',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chạy đúng 1 chu kỳ (maxCycles: 1) rồi dừng sạch.',
                softWrap: true,
                style: TextStyle(fontSize: 12.2, color: c.textSecondary),
              ),
              const SizedBox(height: 8),
              _sampleChipButton(
                context: context,
                label: 'Phát lại dấu tích',
                icon: Icons.replay_rounded,
                primary: true,
                onTap: () => setState(() => _runId++),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Sample62LottieThemeRadar extends StatefulWidget {
  final double speedFactor;
  const _Sample62LottieThemeRadar({super.key, required this.speedFactor});

  @override
  State<_Sample62LottieThemeRadar> createState() =>
      _Sample62LottieThemeRadarState();
}

class _Sample62LottieThemeRadarState extends State<_Sample62LottieThemeRadar> {
  bool _usePulseMascot = false;
  int _seed = 0;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = _usePulseMascot
        ? AppAssets.lottiePulseMascot
        : AppAssets.lottieWalletSyncRadar;

    return Row(
      children: [
        LifeOsLottieAnimation(
          key: ValueKey<String>('${asset}_${isDark}_$_seed'),
          assetPath: asset,
          size: 82,
          maxCycles: 2,
          playbackSpeed: widget.speedFactor,
          primaryColorOverride: c.primary,
          accentColorOverride: c.secondary,
          semanticsLabel: 'Hoạt ảnh Lottie thích ứng giao diện',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              LifeOsStatusPill(
                label: isDark ? 'Màu Dark tự động' : 'Màu Light tự động',
                tone: LifeOsAccentTone.emerald,
              ),
              _sampleChipButton(
                context: context,
                label: _usePulseMascot ? 'Xem Radar Ví' : 'Xem Xung Mascot',
                icon: Icons.radar_rounded,
                onTap: () => setState(() {
                  _usePulseMascot = !_usePulseMascot;
                  _seed++;
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Sample63SpriteVsStatic extends StatefulWidget {
  final double speedFactor;
  const _Sample63SpriteVsStatic({super.key, required this.speedFactor});

  @override
  State<_Sample63SpriteVsStatic> createState() =>
      _Sample63SpriteVsStaticState();
}

class _Sample63SpriteVsStaticState extends State<_Sample63SpriteVsStatic> {
  double? _manualProgress;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final fps = (12 * widget.speedFactor).round().clamp(3, 24);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border, width: 0.8),
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 74,
                        height: 74,
                        child: Image.asset(
                          AppAssets.mascotLeafyGuardian3d,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: c.primarySubtle,
                            child: Icon(
                              Icons.image_outlined,
                              color: c.primary,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ảnh 3D tĩnh (Nano Banana)',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 11.8,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '1 khung tĩnh minh họa',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(fontSize: 10.8, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.primarySubtle,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.primary, width: 1.0),
                ),
                child: Column(
                  children: [
                    LifeOsSpriteSheetPlayer(
                      assetPath: AppAssets.spriteCoinSpinSheet,
                      frameCount: 8,
                      displaySize: 74,
                      fps: fps,
                      maxCycles: 3,
                      manualProgress: _manualProgress,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sprite 8-frame chạy thật',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 11.8,
                        fontWeight: FontWeight.w800,
                        color: c.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chạm xu để quay 8 khung',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(fontSize: 10.8, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Tua khung:',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: c.textSecondary,
              ),
            ),
            Expanded(
              child: Slider(
                value: _manualProgress ?? 0.0,
                onChanged: (v) => setState(() => _manualProgress = v),
              ),
            ),
            if (_manualProgress != null)
              _sampleChipButton(
                context: context,
                label: 'Tự chạy',
                onTap: () => setState(() => _manualProgress = null),
              ),
          ],
        ),
      ],
    );
  }
}

class _Sample64ParticleBurst extends StatelessWidget {
  final double speedFactor;
  const _Sample64ParticleBurst({super.key, required this.speedFactor});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.primarySubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border, width: 0.8),
      ),
      child: LifeOsParticleBurst(
        particleCount: 28,
        height: 122,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.celebration_rounded, color: c.primary, size: 26),
                const SizedBox(height: 4),
                Text(
                  'Chạm điểm bất kỳ để bắn hạt vật lý chúc mừng cột mốc',
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
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

class _Sample65InteractiveMascot extends StatefulWidget {
  final double speedFactor;
  const _Sample65InteractiveMascot({super.key, required this.speedFactor});

  @override
  State<_Sample65InteractiveMascot> createState() =>
      _Sample65InteractiveMascotState();
}

class _Sample65InteractiveMascotState
    extends State<_Sample65InteractiveMascot> {
  LifeOsMascotState _mascotState = LifeOsMascotState.idle;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            LifeOsInteractiveMascotRig(
              state: _mascotState,
              size: 108,
              onStateTapped: (next) => setState(() => _mascotState = next),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mầm Ngọc · ${_mascotState.labelVi}',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kéo ngón tay để mắt nhìn theo · Chạm để nhảy lò xo đổi 5 trạng thái.',
                    softWrap: true,
                    style: TextStyle(fontSize: 11.6, color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in LifeOsMascotState.values)
              _sampleChipButton(
                context: context,
                label: s.labelVi,
                primary: _mascotState == s,
                onTap: () => setState(() => _mascotState = s),
              ),
          ],
        ),
      ],
    );
  }
}

class _Sample66MarchingHydration extends StatefulWidget {
  final double speedFactor;
  const _Sample66MarchingHydration({super.key, required this.speedFactor});

  @override
  State<_Sample66MarchingHydration> createState() =>
      _Sample66MarchingHydrationState();
}

class _Sample66MarchingHydrationState extends State<_Sample66MarchingHydration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dashCtrl;
  int _ml = 1500;
  int _waveRun = 0;

  @override
  void initState() {
    super.initState();
    _dashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _runFlow());
  }

  void _runFlow() {
    if (!mounted) return;
    final motion = LifeOsMotionScope.read(context);
    if (motion.isReducedMotion || !TickerMode.valuesOf(context).enabled) return;
    _dashCtrl.duration = _scaledDuration(
      context,
      const Duration(milliseconds: 1400),
      widget.speedFactor,
    );
    _dashCtrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    _dashCtrl.dispose();
    super.dispose();
  }

  void _addWater() {
    setState(() {
      _ml = _ml >= 2250 ? 1250 : _ml + 250;
      _waveRun++;
    });
    _runFlow();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            LifeOsLottieAnimation(
              key: ValueKey<int>(_waveRun),
              assetPath: AppAssets.lottieHydrationWave,
              size: 68,
              maxCycles: 2,
              playbackSpeed: widget.speedFactor,
              primaryColorOverride: LifeOSBrandColors.primary,
              semanticsLabel: 'Sóng nước Hydration',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đã uống: $_ml / 2.000 ml',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 18,
                    width: double.infinity,
                    child: AnimatedBuilder(
                      animation: _dashCtrl,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _MarchingAntsFlowPainter(
                            phase: _dashCtrl.value,
                            color: c.secondary,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: _sampleChipButton(
            context: context,
            label: '+250 ml nước',
            icon: Icons.water_drop_outlined,
            primary: true,
            onTap: _addWater,
          ),
        ),
      ],
    );
  }
}

class _MarchingAntsFlowPainter extends CustomPainter {
  final double phase;
  final Color color;

  const _MarchingAntsFlowPainter({required this.phase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const dashW = 8.0;
    const gapW = 5.0;
    const step = dashW + gapW;
    final y = size.height / 2;
    final shift = (phase * step * 3) % step;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    for (var x = -step + shift; x < size.width; x += step) {
      final x1 = math.max(0.0, x);
      final x2 = math.min(size.width, x + dashW);
      if (x2 > x1) {
        canvas.drawLine(Offset(x1, y), Offset(x2, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarchingAntsFlowPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
