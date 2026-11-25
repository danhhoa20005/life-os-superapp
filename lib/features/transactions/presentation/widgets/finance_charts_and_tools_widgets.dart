import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';

class DailySpendingChartCard extends StatefulWidget {
  final List<int> buckets;
  final int totalSpentMinor;
  final bool obscureBalances;
  final VoidCallback onOpenReport;

  const DailySpendingChartCard({
    super.key,
    required this.buckets,
    required this.totalSpentMinor,
    this.obscureBalances = false,
    required this.onOpenReport,
  });

  @override
  State<DailySpendingChartCard> createState() => _DailySpendingChartCardState();
}

class _DailySpendingChartCardState extends State<DailySpendingChartCard> {
  static const List<String> _shortAxisLabels = [
    '01',
    '06',
    '11',
    '16',
    '21',
    '26',
    '29+',
  ];
  static const List<String> _rangeTitles = [
    'Ngày 01–05',
    'Ngày 06–10',
    'Ngày 11–15',
    'Ngày 16–20',
    'Ngày 21–25',
    'Ngày 26–28',
    'Cuối tháng (29+)',
  ];

  int? _selectedIdx;

  void _selectFromDx(double dx, double width, {required bool toggle}) {
    if (width <= 0) return;
    final idx = ((dx / width) * 7).floor().clamp(0, 6);
    if (toggle && _selectedIdx == idx) {
      HapticFeedback.selectionClick();
      setState(() => _selectedIdx = null);
      return;
    }
    if (_selectedIdx != idx) {
      HapticFeedback.selectionClick();
      setState(() => _selectedIdx = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final maxBucket = widget.buckets.fold<int>(0, (a, b) => a > b ? a : b);
    final sel = _selectedIdx;
    final selVal = (sel != null && sel < widget.buckets.length)
        ? widget.buckets[sel]
        : 0;
    final selPct = (widget.totalSpentMinor > 0 && selVal > 0)
        ? ((selVal * 100) / widget.totalSpentMinor).clamp(1, 100).round()
        : 0;

    return LifeOsSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onOpenReport,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_rounded, size: 19, color: c.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Chi tiêu theo ngày',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: c.textSecondary,
                    ),
                  ],
                ),
              ),
              LifeOsStatusPill(
                label: widget.obscureBalances
                    ? 'Tổng chi: •••••• ₫'
                    : 'Tổng chi: ${VndAmount.format(widget.totalSpentMinor)}',
                tone: LifeOsAccentTone.emerald,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (sel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selectedIdx = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_rangeTitles[sel]}: ${widget.obscureBalances ? '•••••• ₫' : VndAmount.format(selVal)}'
                    '${selPct > 0 ? ' ($selPct%)' : ''}',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: c.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(
            height: 114,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 44,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.obscureBalances
                                ? '••••'
                                : (maxBucket > 0
                                      ? VndAmount.formatCompact(maxBucket)
                                      : '0 ₫'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: c.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (maxBucket > 0)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.obscureBalances
                                  ? '••••'
                                  : VndAmount.formatCompact(maxBucket ~/ 2),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: c.textSecondary.withValues(alpha: 0.78),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        Text(
                          widget.obscureBalances ? '••••' : '0 ₫',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              key: const Key('daily_spending_chart_canvas'),
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (d) => _selectFromDx(
                                d.localPosition.dx,
                                constraints.maxWidth,
                                toggle: true,
                              ),
                              onHorizontalDragUpdate: (d) => _selectFromDx(
                                d.localPosition.dx,
                                constraints.maxWidth,
                                toggle: false,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox.expand(
                                    child: CustomPaint(
                                      painter: _DailySpendingChartPainter(
                                        buckets: widget.buckets,
                                        selectedIdx: _selectedIdx,
                                        barColor: c.primary,
                                        highlightBg: c.primary.withValues(
                                          alpha: 0.08,
                                        ),
                                        gridColor: c.separator.withValues(
                                          alpha: 0.65,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (widget.totalSpentMinor == 0)
                                    IgnorePointer(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.surface.withValues(
                                            alpha: 0.90,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: c.separator,
                                          ),
                                        ),
                                        child: Text(
                                          'Chưa có chi tiêu trong kỳ',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: List.generate(7, (i) {
                          final isSelected = _selectedIdx == i;
                          final isPeak =
                              maxBucket > 0 && widget.buckets[i] == maxBucket;
                          return Expanded(
                            child: InkWell(
                              key: Key('daily_spending_bucket_$i'),
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _selectedIdx = isSelected ? null : i;
                                });
                              },
                              child: Text(
                                _shortAxisLabels[i],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: (isSelected || isPeak)
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? c.primary
                                      : c.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
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

class _DailySpendingChartPainter extends CustomPainter {
  final List<int> buckets;
  final int? selectedIdx;
  final Color barColor;
  final Color highlightBg;
  final Color gridColor;

  const _DailySpendingChartPainter({
    required this.buckets,
    required this.selectedIdx,
    required this.barColor,
    required this.highlightBg,
    required this.gridColor,
  });

  void _drawDashedLine(Canvas canvas, double y, double width, Paint paint) {
    const dashW = 4.0;
    const gapW = 4.0;
    var x = 0.0;
    while (x < width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(width, x + dashW), y),
        paint,
      );
      x += dashW + gapW;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.85;

    _drawDashedLine(canvas, 3.0, size.width, gridPaint);
    _drawDashedLine(canvas, size.height * 0.5, size.width, gridPaint);
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      gridPaint,
    );

    final maxBucket = buckets.fold<int>(0, (a, b) => a > b ? a : b);
    final count = math.min(7, buckets.length);
    if (count == 0) return;

    final slotW = size.width / count;
    final barW = math.min(22.0, math.max(10.0, slotW * 0.54));
    final usableH = math.max(12.0, size.height - 8.0);

    if (selectedIdx != null && selectedIdx! >= 0 && selectedIdx! < count) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            slotW * selectedIdx! + 2,
            0,
            math.max(6.0, slotW - 4),
            size.height,
          ),
          const Radius.circular(8),
        ),
        Paint()..color = highlightBg,
      );
    }

    final barTopPoints = <Offset>[];

    for (var i = 0; i < count; i++) {
      final val = buckets[i];
      final cx = slotW * i + slotW / 2;
      final isPeak = maxBucket > 0 && val == maxBucket;
      final isSelected = selectedIdx == i;
      final dimmed = selectedIdx != null && !isSelected;

      final barH = (maxBucket <= 0 || val <= 0)
          ? 2.0
          : math.max(6.0, (val / maxBucket) * usableH);
      final topY = size.height - 1 - barH;
      barTopPoints.add(Offset(cx, topY));

      final rect = Rect.fromLTWH(cx - barW / 2, topY, barW, barH);
      final paint = Paint();
      if (val > 0 && maxBucket > 0) {
        final baseAlpha = dimmed ? 0.32 : (isSelected || isPeak ? 1.0 : 0.68);
        paint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            barColor.withValues(alpha: baseAlpha),
            barColor.withValues(alpha: baseAlpha * 0.58),
          ],
        ).createShader(rect);
      } else {
        paint.color = gridColor;
      }

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        paint,
      );
    }

    if (maxBucket > 0 && barTopPoints.length >= 2) {
      final spline = Path()
        ..moveTo(barTopPoints.first.dx, barTopPoints.first.dy);
      for (var i = 0; i < barTopPoints.length - 1; i++) {
        final p0 = barTopPoints[i];
        final p1 = barTopPoints[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        spline.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
      }
      canvas.drawPath(
        spline,
        Paint()
          ..color = barColor.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );

      for (var i = 0; i < count; i++) {
        if (buckets[i] <= 0) continue;
        final isFocus =
            selectedIdx == i ||
            (selectedIdx == null && buckets[i] == maxBucket);
        if (isFocus) {
          canvas.drawCircle(
            barTopPoints[i],
            3.6,
            Paint()..color = Colors.white,
          );
          canvas.drawCircle(barTopPoints[i], 2.6, Paint()..color = barColor);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DailySpendingChartPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.selectedIdx != selectedIdx ||
        oldDelegate.barColor != barColor;
  }
}

class MiniCategorySpendingCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String amount;
  final String pct;
  final double shareRatio;
  final bool highlighted;

  const MiniCategorySpendingCard({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.amount,
    required this.pct,
    this.shareRatio = 0.0,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted ? c.primarySubtle : c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? c.primary.withValues(alpha: 0.35) : c.separator,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16.5, color: accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 12.4,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        amount,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    pct,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: highlighted ? c.primary : c.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 4.5,
                  value: shareRatio.clamp(0.0, 1.0),
                  backgroundColor: c.surfaceRaised,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FinanceToolsHubTabView extends StatelessWidget {
  const FinanceToolsHubTabView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('finance_tools_hub_list_view'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.dockClearance,
          ),
          children: [
            const LifeOsSectionHeader(
              title: 'Kết nối Ngân hàng & Báo cáo',
              subtitle: 'Đồng bộ biến động tự động, mã QR thu tiền và sao kê',
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_bank_qr_tile'),
                      icon: Icons.qr_code_2_rounded,
                      tone: LifeOsAccentTone.emerald,
                      title: 'Ngân hàng & QR',
                      subtitle: 'Biến động tự động',
                      onTap: () => context.push('/notifications-privacy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_report_tile'),
                      icon: Icons.bar_chart_rounded,
                      tone: LifeOsAccentTone.blue,
                      title: 'Báo cáo thu chi',
                      subtitle: 'Thống kê & phân tích',
                      onTap: () => context.push('/finance-report'),
                    ),
                  ),
                ],
              ),
            ),
            const LifeOsSectionHeader(
              title: 'Thu nhập, Lãi vay & Tự động hóa',
              subtitle:
                  'Tính lương Gross–Net, trả góp, hóa đơn & quy tắc thông minh',
              tone: LifeOsAccentTone.purple,
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_salary_tax_tile'),
                      icon: Icons.request_quote_outlined,
                      tone: LifeOsAccentTone.purple,
                      title: 'Lương & Thuế',
                      subtitle: 'Gross–Net 2026',
                      onTap: () => context.push('/smart-notes-hub'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_wealth_tools_tile'),
                      icon: Icons.calculate_outlined,
                      tone: LifeOsAccentTone.blue,
                      title: 'Lãi vay & Bill',
                      subtitle: 'Tách món & tích lũy',
                      onTap: () => context.push('/wealth-tools'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_subs_tile'),
                      icon: Icons.radar_rounded,
                      tone: LifeOsAccentTone.amber,
                      title: 'Gói thuê bao',
                      subtitle: 'Gia hạn & bảo hành',
                      onTap: () => context.push('/subscriptions-warranty'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_auto_tx_tile'),
                      icon: Icons.bolt_rounded,
                      tone: LifeOsAccentTone.emerald,
                      title: 'Duyệt GD tự động',
                      subtitle: 'Đối soát biến động',
                      onTap: () => context.push('/auto-tx-review'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LifeOsFeatureBentoTile(
              tileKey: const Key('finance_hub_automation_studio_tile'),
              icon: Icons.auto_awesome_rounded,
              tone: LifeOsAccentTone.emerald,
              title: 'Tự động hóa Thông minh',
              subtitle:
                  'Quy tắc gợi ý phân bổ lương, xăng xe, hóa đơn & hoàn tác',
              onTap: () => context.push('/automation-studio'),
            ),
          ],
        ),
      ),
    );
  }
}
