import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../calendar/domain/entities/calendar_entities.dart';

enum UpcomingScheduleHorizon {
  week,
  month,
  year;

  String get badgeLabelVi => switch (this) {
    UpcomingScheduleHorizon.week => 'Tuần',
    UpcomingScheduleHorizon.month => 'Tháng',
    UpcomingScheduleHorizon.year => 'Năm',
  };

  IconData get icon => switch (this) {
    UpcomingScheduleHorizon.week => Icons.schedule_rounded,
    UpcomingScheduleHorizon.month => Icons.calendar_month_rounded,
    UpcomingScheduleHorizon.year => Icons.event_repeat_rounded,
  };

  LifeOsAccentTone get tone => switch (this) {
    UpcomingScheduleHorizon.week => LifeOsAccentTone.emerald,
    UpcomingScheduleHorizon.month => LifeOsAccentTone.blue,
    UpcomingScheduleHorizon.year => LifeOsAccentTone.purple,
  };

  UpcomingScheduleHorizon get next => switch (this) {
    UpcomingScheduleHorizon.week => UpcomingScheduleHorizon.month,
    UpcomingScheduleHorizon.month => UpcomingScheduleHorizon.year,
    UpcomingScheduleHorizon.year => UpcomingScheduleHorizon.week,
  };
}

/// Interactive & gently auto-rotating "Lịch sắp tới" Bento card cycling across
/// `Tuần` (7 days) -> `Tháng` (30 days) -> `Năm` (365 days), or switching immediately on tap.
class UpcomingScheduleCycleCard extends StatefulWidget {
  final Key? cardKey;
  final int weekCount;
  final int monthCount;
  final int yearCount;
  final Duration autoCycleInterval;
  final ValueChanged<UpcomingScheduleHorizon>? onLongPressOpenPlanning;

  const UpcomingScheduleCycleCard({
    super.key,
    this.cardKey,
    required this.weekCount,
    required this.monthCount,
    required this.yearCount,
    this.autoCycleInterval = const Duration(seconds: 6),
    this.onLongPressOpenPlanning,
  });

  static int countUpcomingInWindow(
    List<CalendarEventEntity> events,
    DateTime now,
    Duration window,
  ) {
    final winEnd = now.add(window);
    var total = 0;
    for (final ev in events) {
      final duration = ev.endsAt.isAfter(ev.startsAt)
          ? ev.endsAt.difference(ev.startsAt)
          : const Duration(hours: 1);
      if (ev.isRecurring) {
        final occs = ev.recurrence.expandOccurrences(
          firstStart: ev.startsAt,
          windowStart: now.subtract(duration),
          windowEnd: winEnd,
          maxInstances: 400,
        );
        for (final occStart in occs) {
          final occEnd = occStart.add(duration);
          if (!occEnd.isBefore(now) && !occStart.isAfter(winEnd)) {
            total++;
          }
        }
      } else {
        if (!ev.endsAt.isBefore(now) && !ev.startsAt.isAfter(winEnd)) {
          total++;
        }
      }
    }
    return total;
  }

  @override
  State<UpcomingScheduleCycleCard> createState() =>
      _UpcomingScheduleCycleCardState();
}

class _UpcomingScheduleCycleCardState extends State<UpcomingScheduleCycleCard> {
  UpcomingScheduleHorizon _horizon = UpcomingScheduleHorizon.week;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _restartAutoTimer();
  }

  @override
  void didUpdateWidget(covariant UpcomingScheduleCycleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoCycleInterval != widget.autoCycleInterval) {
      _restartAutoTimer();
    }
  }

  void _restartAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(widget.autoCycleInterval, (_) {
      if (!mounted) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      if (LifeOsMotionScope.read(context).isReducedMotion) return;
      setState(() {
        _horizon = _horizon.next;
      });
    });
  }

  void _handleManualTap() {
    LifeOsMotionScope.read(context).selectionHaptic();
    setState(() {
      _horizon = _horizon.next;
    });
    _restartAutoTimer();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  int _countFor(UpcomingScheduleHorizon h) => switch (h) {
    UpcomingScheduleHorizon.week => widget.weekCount,
    UpcomingScheduleHorizon.month => widget.monthCount,
    UpcomingScheduleHorizon.year => widget.yearCount,
  };

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final motion = LifeOsMotionScope.of(context);
    final switchDur = motion.resolveDuration(LifeOsMotionTokens.standard);
    final (bg, fg) = _horizon.tone.resolve(context);
    final count = _countFor(_horizon);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: widget.onLongPressOpenPlanning == null
          ? null
          : () => widget.onLongPressOpenPlanning!(_horizon),
      child: LifeOsSoftCard(
        key: widget.cardKey,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        borderRadius: 18,
        onTap: _handleManualTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                AnimatedSwitcher(
                  duration: switchDur,
                  switchInCurve: LifeOsMotionTokens.standardCurve,
                  switchOutCurve: LifeOsMotionTokens.exitCurve,
                  child: LifeOsIconSquircle(
                    key: ValueKey('upcoming_icon_${_horizon.name}'),
                    icon: _horizon.icon,
                    tone: _horizon.tone,
                    size: 28,
                    iconSize: 15,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: switchDur,
                  switchInCurve: LifeOsMotionTokens.standardCurve,
                  switchOutCurve: LifeOsMotionTokens.exitCurve,
                  transitionBuilder: (child, anim) {
                    if (motion.isReducedMotion) {
                      return FadeTransition(opacity: anim, child: child);
                    }
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.24),
                      end: Offset.zero,
                    ).animate(anim);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: FittedBox(
                    key: ValueKey('upcoming_cnt_${_horizon.name}_$count'),
                    fit: BoxFit.scaleDown,
                    child: Text(
                      count.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 18.5,
                        fontWeight: FontWeight.w800,
                        color: fg,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Lịch sắp tới',
                style: TextStyle(
                  fontSize: 12.2,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: switchDur,
                    curve: LifeOsMotionTokens.standardCurve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.5,
                      vertical: 1.8,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: AnimatedSwitcher(
                      duration: switchDur,
                      child: Text(
                        _horizon.badgeLabelVi,
                        key: ValueKey('upcoming_badge_${_horizon.name}'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (final h in UpcomingScheduleHorizon.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: AnimatedContainer(
                        duration: switchDur,
                        curve: LifeOsMotionTokens.standardCurve,
                        width: h == _horizon ? 10 : 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: h == _horizon
                              ? fg
                              : c.textSecondary.withValues(alpha: 0.26),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
