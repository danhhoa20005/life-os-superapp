import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../domain/entities/calendar_entities.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../../domain/services/daily_planner_timeblock_engine.dart';
import '../bloc/calendar_bloc.dart';

/// Hourly Time-Blocking, Schedule Conflict Detector & `Task -> Event` Slot Allocator (Section 26).
class DailyTimeblockPlannerCard extends StatelessWidget {
  final DateTime selectedDate;
  final String userId;
  final String userName;
  final String? familyId;
  final List<CalendarEventEntity> dayEvents;
  final List<TaskEntity> openTasks;

  const DailyTimeblockPlannerCard({
    super.key,
    required this.selectedDate,
    required this.userId,
    required this.userName,
    this.familyId,
    required this.dayEvents,
    required this.openTasks,
  });

  static final DateFormat _timeFmt = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    final slots = dayEvents.map((e) {
      final isShared = e.visibility != CalendarEventVisibility.privateEvent;
      return TimeBlockSlot(
        id: e.id,
        title: e.title,
        description: e.description,
        startsAt: e.startsAt,
        endsAt: e.endsAt,
        isAllDay: e.isAllDay,
        space: isShared
            ? PlannerCalendarSpace.familySpace
            : PlannerCalendarSpace.privateSpace,
        ownerUserId: e.ownerId.isEmpty ? userId : e.ownerId,
        sharedWithFamily: isShared,
      );
    }).toList();

    final vm = DailyPlannerTimeblockEngine.buildDayPlan(
      targetDay: selectedDate,
      viewerUserId: userId,
      rawBlocks: slots,
    );

    final candidateTask = openTasks
        .where(
          (t) =>
              t.status != TaskWorkflowStatus.done &&
              t.status != TaskWorkflowStatus.declined,
        )
        .firstOrNull;

    return LifeOsSoftCard(
      key: const Key('daily_timeblock_planner_card'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LifeOsIconSquircle(
                    icon: Icons.view_timeline_outlined,
                    tone: LifeOsAccentTone.blue,
                    size: 30,
                    iconSize: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Khung giờ tập trung (Time-Blocking)',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 13.6,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              LifeOsStatusPill(
                icon: vm.conflicts.isNotEmpty
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
                label: vm.conflicts.isNotEmpty
                    ? '${vm.conflicts.length} trùng giờ'
                    : '${vm.freeFocusWindows.length} khoảng trống',
                tone: vm.conflicts.isNotEmpty
                    ? LifeOsAccentTone.coral
                    : LifeOsAccentTone.emerald,
              ),
            ],
          ),
          if (vm.conflicts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Phát hiện ${vm.conflicts.length} cặp sự kiện trùng khung giờ (${vm.conflicts.first.overlapMinutes} phút) — hãy điều chỉnh để tránh trễ hẹn.',
              softWrap: true,
              style: TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                color: c.error,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (vm.freeFocusWindows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: vm.freeFocusWindows.take(3).map((w) {
                final label =
                    'Trống ${_timeFmt.format(w.startsAt)}–${_timeFmt.format(w.endsAt)}';
                return ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.bolt_rounded, size: 15, color: c.primary),
                  label: Text(
                    candidateTask != null ? '$label · Xếp việc' : label,
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  onPressed: candidateTask == null
                      ? null
                      : () {
                          final endSlot =
                              w.startsAt
                                  .add(const Duration(minutes: 45))
                                  .isBefore(w.endsAt)
                              ? w.startsAt.add(const Duration(minutes: 45))
                              : w.endsAt;
                          context.read<CalendarBloc>().add(
                            CalendarEventCreated(
                              CreateCalendarEventParams(
                                userId: userId,
                                userName: userName,
                                familyId: familyId,
                                visibility:
                                    CalendarEventVisibility.privateEvent,
                                title: 'Làm việc: ${candidateTask.title}',
                                description:
                                    'Liên kết nhiệm vụ #${candidateTask.id}',
                                startsAt: w.startsAt,
                                endsAt: endSlot,
                              ),
                            ),
                          );
                          LifeOsTopToast.show(
                            context,
                            'Đã xếp việc "${candidateTask.title}" vào khung ${_timeFmt.format(w.startsAt)}–${_timeFmt.format(endSlot)}.',
                            kind: LifeOsToastKind.success,
                          );
                        },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
