import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../lifeos_motion_scope.dart';
import '../lifeos_motion_tokens.dart';
import '../physics/lifeos_spring_controllers.dart';

/// Multi-detent physics-driven bottom sheet (`fujidaiti/smooth_sheets` architectural port)
/// featuring:
/// - `sheetSnapSpring` (`zeta = 1.003`, 0% overshoot)
/// - Velocity lookahead detent projection (`y + v * 0.18s`)
/// - Hyperbolic rubber-band resistance above max detent
/// - Seamless handoff with inner `ScrollController`
/// - Full OS Reduce Motion support
class LifeOsSpringBottomSheet extends StatefulWidget {
  final List<double> detents;
  final int initialDetentIndex;
  final bool dismissible;
  final VoidCallback? onDismissed;
  final Widget Function(BuildContext context, ScrollController scrollController)
  builder;
  final Widget? header;

  const LifeOsSpringBottomSheet({
    super.key,
    this.detents = const <double>[0.42, 0.72, 0.92],
    this.initialDetentIndex = 1,
    this.dismissible = true,
    this.onDismissed,
    this.header,
    required this.builder,
  });

  @override
  State<LifeOsSpringBottomSheet> createState() =>
      _LifeOsSpringBottomSheetState();
}

class _LifeOsSpringBottomSheetState extends State<LifeOsSpringBottomSheet>
    with SingleTickerProviderStateMixin {
  late final LifeOsSpringController _fractionCtrl;
  final ScrollController _scrollController = ScrollController();
  late List<double> _sortedDetents;

  @override
  void initState() {
    super.initState();
    _sortedDetents = List<double>.from(widget.detents)..sort();
    if (_sortedDetents.isEmpty) {
      _sortedDetents = <double>[0.6];
    }
    final safeIdx = widget.initialDetentIndex.clamp(
      0,
      _sortedDetents.length - 1,
    );
    _fractionCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: _sortedDetents[safeIdx],
      spring: LifeOsMotionTokens.sheetSnapSpring,
      tolerance: LifeOsMotionTokens.springTolerance,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fractionCtrl.dispose();
    super.dispose();
  }

  void _snapToDetent(double targetFraction, {double velocityUnitsPerSec = 0}) {
    final motion = LifeOsMotionScope.read(context);
    final tickers = TickerMode.valuesOf(context).enabled;
    _fractionCtrl.animateTo(
      targetFraction,
      velocity: velocityUnitsPerSec,
      motion: motion,
      tickersEnabled: tickers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = math.max(240.0, constraints.maxHeight);
        final minFrac = _sortedDetents.first;
        final maxFrac = _sortedDetents.last;

        return AnimatedBuilder(
          animation: _fractionCtrl,
          builder: (context, _) {
            final rawFrac = _fractionCtrl.value;
            final clampedFrac = motion.isReducedMotion
                ? rawFrac.clamp(0.15, maxFrac)
                : LifeOsMotionTokens.rubberBandClamp(
                    rawFrac,
                    min: widget.dismissible ? 0.08 : minFrac,
                    max: maxFrac,
                    viewportExtent: 1.0,
                    resistance: 0.18,
                  );
            final sheetHeight = (maxH * clampedFrac).clamp(120.0, maxH);

            return Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  final deltaFrac = -details.delta.dy / maxH;
                  _fractionCtrl.jumpTo(_fractionCtrl.value + deltaFrac);
                },
                onVerticalDragEnd: (details) {
                  final vyFrac = LifeOsMotionTokens.normalizeVelocity(
                    velocityPxPerSec: -details.velocity.pixelsPerSecond.dy,
                    extentPx: maxH,
                  );
                  if (widget.dismissible &&
                      (_fractionCtrl.value < minFrac * 0.62 || vyFrac < -3.2)) {
                    widget.onDismissed?.call();
                    return;
                  }
                  final target = LifeOsMotionTokens.projectNearestDetent(
                    current: _fractionCtrl.value,
                    velocityPerSec: vyFrac,
                    detents: _sortedDetents,
                  );
                  motion.selectionHaptic();
                  _snapToDetent(target, velocityUnitsPerSec: vyFrac);
                },
                child: Container(
                  height: sheetHeight,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                    border: Border(
                      top: BorderSide(color: c.border, width: 0.9),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 4.5,
                              decoration: BoxDecoration(
                                color: c.border,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            if (_sortedDetents.length > 1) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final d in _sortedDetents)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(99),
                                      onTap: () {
                                        motion.selectionHaptic();
                                        _snapToDetent(d);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              (d - _fractionCtrl.value).abs() <
                                                  0.06
                                              ? c.primarySubtle
                                              : c.surfaceRaised,
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                        child: Text(
                                          '${(d * 100).round()}%',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color:
                                                (d - _fractionCtrl.value)
                                                        .abs() <
                                                    0.06
                                                ? c.primary
                                                : c.textSecondary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.header != null) widget.header!,
                      Expanded(
                        child: widget.builder(context, _scrollController),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Future<T?> showLifeOsSpringSheet<T>({
  required BuildContext context,
  List<double> detents = const <double>[0.45, 0.75, 0.92],
  int initialDetentIndex = 1,
  Widget? header,
  required Widget Function(BuildContext context, ScrollController scrollCtrl)
  builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => LifeOsSpringBottomSheet(
      detents: detents,
      initialDetentIndex: initialDetentIndex,
      header: header,
      onDismissed: () => Navigator.of(sheetCtx).maybePop(),
      builder: builder,
    ),
  );
}
