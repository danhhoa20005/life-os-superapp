import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../../../core/services/personal_alarm_service.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../domain/entities/calendar_entities.dart';
import '../bloc/calendar_bloc.dart';
import 'planning_page.dart';

/// Screen 03: "Chi tiết sự kiện" with real OS Alarm scheduling & past-event guard.
class EventDetailPage extends StatefulWidget {
  final CalendarEventEntity? initialEvent;

  const EventDetailPage({super.key, this.initialEvent});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  int _selectedReminderMinutes = 15;
  bool _enableFullScreenAlarm = true;
  ScheduledEventAlarmInfo? _scheduledAlarm;
  String? _loadedEventId;

  Future<void> _loadExistingAlarm(String eventId) async {
    if (_loadedEventId == eventId) return;
    _loadedEventId = eventId;
    final info = await NativeAlarmSchedulerBridge.instance.getScheduledAlarm(
      eventId,
    );
    if (!mounted) return;
    if (info != null) {
      setState(() {
        _scheduledAlarm = info;
        _selectedReminderMinutes = info.minutesBefore;
        _enableFullScreenAlarm = info.fullScreen;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    CalendarBloc? maybeCalBloc;
    try {
      maybeCalBloc = context.watch<CalendarBloc>();
    } catch (_) {
      maybeCalBloc = null;
    }
    FamilyBloc? maybeFamilyBloc;
    try {
      maybeFamilyBloc = context.watch<FamilyBloc>();
    } catch (_) {
      maybeFamilyBloc = null;
    }

    AuthBloc? maybeAuthBloc;
    try {
      maybeAuthBloc = context.watch<AuthBloc>();
    } catch (_) {
      maybeAuthBloc = null;
    }

    final calEvents =
        maybeCalBloc?.state.events ?? const <CalendarEventEntity>[];
    final family = maybeFamilyBloc?.state.activeFamily;
    final authUser = maybeAuthBloc?.state.user;

    CalendarEventEntity? latestFromState;
    if (widget.initialEvent != null) {
      for (final item in calEvents) {
        if (item.id == widget.initialEvent!.id) {
          if (item.isRecurring &&
              widget.initialEvent!.startsAt != item.startsAt) {
            final dur = item.endsAt.isAfter(item.startsAt)
                ? item.endsAt.difference(item.startsAt)
                : widget.initialEvent!.endsAt.difference(
                    widget.initialEvent!.startsAt,
                  );
            final occStart = DateTime(
              widget.initialEvent!.startsAt.year,
              widget.initialEvent!.startsAt.month,
              widget.initialEvent!.startsAt.day,
              item.startsAt.hour,
              item.startsAt.minute,
            );
            latestFromState = item.copyWith(
              startsAt: occStart,
              endsAt: occStart.add(dur),
            );
          } else {
            latestFromState = item;
          }
          break;
        }
      }
    }
    final event =
        latestFromState ??
        widget.initialEvent ??
        (calEvents.isNotEmpty ? calEvents.first : null);
    if (event == null) {
      return Scaffold(
        body: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Column(
              children: [
                const LifeOsTopBrandHeader(
                  title: 'Chi tiết sự kiện',
                  showBackButton: true,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: LifeOsSoftCard(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const LifeOsIconSquircle(
                                icon: Icons.event_busy_rounded,
                                tone: LifeOsAccentTone.emerald,
                                size: 54,
                                iconSize: 26,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Chưa có sự kiện được chọn',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Hãy chọn một sự kiện từ tab Lịch trình hoặc mở Quản lý Báo thức để đặt chuông hẹn giờ.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.38,
                                  color: c.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              LifeOsPrimaryCtaButton(
                                icon: Icons.alarm_rounded,
                                label: 'Mở Quản lý Báo thức',
                                onPressed: () => context.push('/event-alarm'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final weekdayNames = const <int, String>{
      DateTime.monday: 'Thứ Hai',
      DateTime.tuesday: 'Thứ Ba',
      DateTime.wednesday: 'Thứ Tư',
      DateTime.thursday: 'Thứ Năm',
      DateTime.friday: 'Thứ Sáu',
      DateTime.saturday: 'Thứ Bảy',
      DateTime.sunday: 'Chủ Nhật',
    };
    _loadExistingAlarm(event.id);
    final dateLabel =
        '${weekdayNames[event.startsAt.weekday]}, ${DateFormat('dd \'tháng\' MM, yyyy').format(event.startsAt)}';
    final timeLabel = event.isAllDay
        ? 'Cả ngày'
        : '${DateFormat('HH:mm').format(event.startsAt)} – ${DateFormat('HH:mm').format(event.endsAt)}';

    String reminderClock(int minsBefore) {
      final t = event.startsAt.subtract(Duration(minutes: minsBefore));
      return DateFormat('HH:mm').format(t);
    }

    final reminderOptions = <(int mins, String title, String subtitle)>[
      (0, 'Đúng giờ bắt đầu', 'Nhắc vào lúc ${reminderClock(0)}'),
      (5, 'Trước 5 phút', 'Nhắc vào lúc ${reminderClock(5)}'),
      (15, 'Trước 15 phút', 'Nhắc vào lúc ${reminderClock(15)}'),
      (30, 'Trước 30 phút', 'Nhắc vào lúc ${reminderClock(30)}'),
      (60, 'Trước 1 giờ', 'Nhắc vào lúc ${reminderClock(60)}'),
    ];

    final memberNames =
        (event.visibility == CalendarEventVisibility.sharedEvent &&
            family != null &&
            family.members.isNotEmpty)
        ? family.members.map((m) => m.fullName).take(4).toList()
        : const <String>[];

    final isPastEvent = event.startsAt.isBefore(DateTime.now());

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              LifeOsTopBrandHeader(
                title: 'Chi tiết sự kiện',
                showBackButton: true,
                extraBrandActions: [
                  if (maybeCalBloc != null && authUser != null) ...[
                    LifeOsHeaderCircleButton(
                      buttonKey: const Key('event_detail_edit_button'),
                      icon: Icons.edit_outlined,
                      tooltip: 'Chỉnh sửa lịch hẹn',
                      onTap: () => showUpsertCalendarEventDialog(
                        context,
                        userId: authUser.id,
                        userName: authUser.fullName,
                        familyId: family?.id,
                        availabilityOptIn: authUser.availabilityOptIn,
                        existingEvent: event,
                      ),
                    ),
                    LifeOsHeaderCircleButton(
                      buttonKey: const Key('event_detail_delete_button'),
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Xóa lịch hẹn',
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('Xóa sự kiện này?'),
                            content: Text(
                              'Sự kiện "${event.title}" sẽ được xóa khỏi lịch của bạn.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dCtx).pop(false),
                                child: const Text('Hủy'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: c.error,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.of(dCtx).pop(true),
                                child: const Text('Xóa sự kiện'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          maybeCalBloc!.add(
                            CalendarEventDeleted(
                              userId: authUser.id,
                              familyId: family?.id,
                              visibility: event.visibility,
                              eventId: event.id,
                              googleCalendarId: event.googleCalendarId,
                              googleEventId: event.googleEventId,
                            ),
                          );
                          LifeOsTopToast.show(
                            context,
                            'Đã xóa sự kiện "${event.title}".',
                          );
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/planning');
                          }
                        }
                      },
                    ),
                  ],
                ],
                trailingAction: TextButton.icon(
                  onPressed: () => context.push('/event-alarm'),
                  icon: const Icon(Icons.alarm_rounded, size: 18),
                  label: const Text('Báo thức'),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        4,
                        AppSpacing.md,
                        AppSpacing.xxl,
                      ),
                      children: [
                        // 1. Pastel Mint Event Title Card
                        LifeOsMintHeroCard(
                          child: Row(
                            children: [
                              const LifeOsIconSquircle(
                                icon: Icons.calendar_today_rounded,
                                tone: LifeOsAccentTone.emerald,
                                size: 52,
                                iconSize: 26,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.title,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    LifeOsStatusPill(
                                      icon:
                                          event.visibility ==
                                              CalendarEventVisibility
                                                  .privateEvent
                                          ? Icons.person_outline_rounded
                                          : Icons.groups_outlined,
                                      label:
                                          event.visibility ==
                                              CalendarEventVisibility
                                                  .privateEvent
                                          ? 'Sự kiện cá nhân'
                                          : 'Sự kiện gia đình',
                                      tone: LifeOsAccentTone.emerald,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 2. Event Metadata Card
                        LifeOsSoftCard(
                          child: Column(
                            children: [
                              _EventInfoRow(
                                icon: Icons.event_outlined,
                                label: 'Ngày',
                                value: dateLabel,
                              ),
                              const Divider(height: 22),
                              _EventInfoRow(
                                icon: Icons.access_time_rounded,
                                label: 'Thời gian',
                                value: timeLabel,
                              ),
                              const Divider(height: 22),
                              _EventInfoRow(
                                icon: Icons.location_on_outlined,
                                label: 'Địa điểm',
                                value: (event.location ?? '').trim().isEmpty
                                    ? 'Chưa thêm địa điểm'
                                    : event.location!,
                              ),
                              const Divider(height: 22),
                              _EventInfoRow(
                                icon: Icons.notes_rounded,
                                label: 'Ghi chú',
                                value: (event.description ?? '').trim().isEmpty
                                    ? 'Chưa có ghi chú'
                                    : event.description!,
                                multiLine: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 3. Invited Family Members Card
                        if (memberNames.isNotEmpty) ...[
                          LifeOsSoftCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.groups_outlined,
                                      size: 20,
                                      color: c.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Thành viên gia đình',
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${memberNames.length} thành viên',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 10,
                                  children: memberNames.map((name) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: c.primarySubtle,
                                          child: Text(
                                            name.trim().isEmpty
                                                ? 'U'
                                                : name
                                                      .trim()
                                                      .characters
                                                      .first
                                                      .toUpperCase(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: c.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // 4. Reminder Selector Card
                        LifeOsSoftCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.notifications_active_outlined,
                                    size: 20,
                                    color: c.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Báo thức sự kiện',
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Chọn thời điểm đổ chuông báo thức trên thiết bị.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...reminderOptions.map((opt) {
                                final isSelected =
                                    _selectedReminderMinutes == opt.$1;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => setState(
                                      () => _selectedReminderMinutes = opt.$1,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? c.primarySubtle
                                            : c.surface,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isSelected
                                              ? c.primary.withValues(
                                                  alpha: 0.45,
                                                )
                                              : c.separator,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isSelected
                                                ? Icons
                                                      .radio_button_checked_rounded
                                                : Icons
                                                      .radio_button_off_rounded,
                                            color: isSelected
                                                ? c.primary
                                                : c.border,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  opt.$2,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  opt.$3,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Đổ chuông toàn màn hình khi đến giờ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Đánh thức màn hình khóa, phát nhạc chuông & rung',
                                ),
                                value: _enableFullScreenAlarm,
                                onChanged: (v) =>
                                    setState(() => _enableFullScreenAlarm = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 5. Real OS Alarm Scheduler CTA
                        if (_scheduledAlarm != null) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: c.primarySubtle,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: c.primary.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.alarm_on_rounded,
                                  color: c.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Đã hẹn chuông lúc ${DateFormat('HH:mm dd/MM').format(_scheduledAlarm!.triggerAt)}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  key: const Key('cancel_event_alarm_button'),
                                  onPressed: () async {
                                    await NativeAlarmSchedulerBridge.instance
                                        .cancelEventAlarm(event.id);
                                    if (!context.mounted) return;
                                    setState(() => _scheduledAlarm = null);
                                    LifeOsTopToast.show(
                                      context,
                                      'Đã hủy chuông báo thức của sự kiện.',
                                      kind: LifeOsToastKind.info,
                                    );
                                  },
                                  child: Text(
                                    'Hủy',
                                    style: TextStyle(color: c.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        LifeOsPrimaryCtaButton(
                          icon: Icons.alarm_add_rounded,
                          label: _scheduledAlarm == null
                              ? 'Đặt báo thức cho sự kiện này'
                              : 'Cập nhật giờ báo thức',
                          onPressed: () async {
                            if (isPastEvent) {
                              LifeOsTopToast.show(
                                context,
                                'Sự kiện này đã qua giờ bắt đầu — không thể hẹn báo thức quá khứ.',
                                kind: LifeOsToastKind.warning,
                              );
                              return;
                            }
                            final info = await NativeAlarmSchedulerBridge
                                .instance
                                .scheduleEventAlarm(
                                  eventId: event.id,
                                  title: event.title,
                                  subtitle:
                                      '$timeLabel · ${event.location ?? "Lịch trình LifeOS"}',
                                  eventStartsAt: event.startsAt,
                                  minutesBefore: _selectedReminderMinutes,
                                  fullScreen: _enableFullScreenAlarm,
                                );
                            if (!context.mounted) return;
                            setState(() => _scheduledAlarm = info);
                            final triggerFmt = DateFormat(
                              'HH:mm dd/MM',
                            ).format(info.triggerAt);
                            LifeOsTopToast.show(
                              context,
                              '✓ Đã đặt báo thức lúc $triggerFmt cho "${event.title}".',
                              actionLabel: !info.exactScheduled
                                  ? 'Cấp quyền đúng giây'
                                  : null,
                              onAction: !info.exactScheduled
                                  ? () => NativeAlarmSchedulerBridge.instance
                                        .openExactAlarmSettings()
                                  : null,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            key: const Key('preview_alarm_screen_button'),
                            onPressed: () =>
                                context.push('/event-alarm', extra: event),
                            icon: const Icon(
                              Icons.volume_up_outlined,
                              size: 17,
                            ),
                            label: const Text('Xem thử màn hình đổ chuông'),
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
      ),
    );
  }
}

class _EventInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool multiLine;

  const _EventInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.multiLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      crossAxisAlignment: multiLine
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        LifeOsIconSquircle(
          icon: icon,
          tone: LifeOsAccentTone.emerald,
          size: 38,
          iconSize: 19,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                softWrap: true,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: multiLine ? FontWeight.w600 : FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dual-Mode Alarm Screen (`/event-alarm`):
/// - When [event] is provided (OS alarm ringing or preview): renders the Full-Screen 3D Ringing UI
///   with real audio/vibration stop, `+5m` Snooze, and Dismiss.
/// - When [event] is null (opened from Alarm tile / header): renders the Apple Clock–style
///   Alarm Hub to create, toggle, edit, and delete personal & event alarms.
class EventAlarmPage extends StatelessWidget {
  final CalendarEventEntity? event;

  const EventAlarmPage({super.key, this.event});

  @override
  Widget build(BuildContext context) {
    if (event != null) {
      return _AlarmRingingFullScreenView(event: event!);
    }
    return const _AlarmClockStudioHubView();
  }
}

class _AlarmClockStudioHubView extends StatefulWidget {
  const _AlarmClockStudioHubView();

  @override
  State<_AlarmClockStudioHubView> createState() =>
      _AlarmClockStudioHubViewState();
}

class _AlarmClockStudioHubViewState extends State<_AlarmClockStudioHubView> {
  List<PersonalAlarmItem> _personalAlarms = const <PersonalAlarmItem>[];
  Map<String, ScheduledEventAlarmInfo> _osAlarmsById =
      const <String, ScheduledEventAlarmInfo>{};
  bool _canExactAlarm = true;
  bool _loading = true;
  Timer? _minuteRefreshTimer;

  @override
  void initState() {
    super.initState();
    _reloadAll();
    _minuteRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minuteRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _reloadAll() async {
    final personal = await PersonalAlarmStore.instance.loadAlarms();
    final osList = await NativeAlarmSchedulerBridge.instance
        .listScheduledAlarms();
    final exact = await NativeAlarmSchedulerBridge.instance
        .canScheduleExactAlarms();
    if (!mounted) return;
    setState(() {
      _personalAlarms = personal;
      _osAlarmsById = <String, ScheduledEventAlarmInfo>{
        for (final item in osList) item.eventId: item,
      };
      _canExactAlarm = exact;
      _loading = false;
    });
  }

  ({DateTime triggerAt, String title})? _computeNearestActiveAlarm(
    DateTime now,
  ) {
    DateTime? bestAt;
    String? bestTitle;

    for (final a in _personalAlarms) {
      if (!a.enabled) continue;
      final nextAt = a.computeNextTriggerAt(now);
      if (bestAt == null || nextAt.isBefore(bestAt)) {
        bestAt = nextAt;
        bestTitle = a.label;
      }
    }
    for (final osAlarm in _osAlarmsById.values) {
      if (osAlarm.eventId.startsWith('palarm_')) continue;
      if (osAlarm.triggerAt.isAfter(now) &&
          (bestAt == null || osAlarm.triggerAt.isBefore(bestAt))) {
        bestAt = osAlarm.triggerAt;
        bestTitle = osAlarm.title;
      }
    }
    if (bestAt == null || bestTitle == null) return null;
    return (triggerAt: bestAt, title: bestTitle);
  }

  Future<void> _showUpsertAlarmSheet({PersonalAlarmItem? existing}) async {
    final saved = await showModalBottomSheet<PersonalAlarmItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UpsertPersonalAlarmBottomSheet(existing: existing),
    );
    if (saved == null || !mounted) return;
    await _reloadAll();
    if (!mounted) return;
    final nextAt = saved.computeNextTriggerAt(DateTime.now());
    final countdown = PersonalAlarmStore.formatCountdownVi(
      nextAt,
      DateTime.now(),
    );
    LifeOsTopToast.show(
      context,
      'Đã đặt báo thức ${saved.formattedTime} (${saved.label}) · $countdown.',
    );
  }

  void _openTestRingingPreview() {
    final now = DateTime.now();
    final activeFirst = _personalAlarms.where((a) => a.enabled).firstOrNull;
    final previewTime = activeFirst != null
        ? DateTime(
            now.year,
            now.month,
            now.day,
            activeFirst.hour,
            activeFirst.minute,
          )
        : now;
    final syntheticEvent = CalendarEventEntity(
      id: activeFirst?.id ?? 'alarm_preview_test',
      ownerId: 'self',
      ownerName: 'LifeOS',
      visibility: CalendarEventVisibility.privateEvent,
      title: activeFirst?.label ?? 'Báo thức buổi sáng',
      location: activeFirst?.repeatSummaryVi ?? 'Chuông thử nghiệm',
      startsAt: previewTime,
      endsAt: previewTime.add(const Duration(minutes: 30)),
      reminderMinutesBefore: 0,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AlarmRingingFullScreenView(
          event: syntheticEvent,
          playPreviewTone: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();

    List<CalendarEventEntity> upcomingEvents = const <CalendarEventEntity>[];
    try {
      upcomingEvents =
          context
              .watch<CalendarBloc>()
              .state
              .events
              .where((e) => !e.isAllDay && e.startsAt.isAfter(now))
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    } catch (_) {}

    final nearest = _computeNearestActiveAlarm(now);
    final hmFmt = DateFormat('HH:mm');
    final dmFmt = DateFormat('HH:mm · dd/MM');

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              LifeOsTopBrandHeader(
                title: 'Báo thức & Chuông hẹn',
                showBackButton: true,
                trailingAction: FilledButton.icon(
                  key: const Key('add_personal_alarm_btn'),
                  onPressed: () => _showUpsertAlarmSheet(),
                  icon: const Icon(Icons.add_alarm_rounded, size: 18),
                  label: const Text('Đặt giờ'),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppSpacing.maxContentWidth,
                          ),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              4,
                              AppSpacing.md,
                              AppSpacing.xxl,
                            ),
                            children: [
                              // 1. Next Alarm Bright Executive Summary Card
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? [c.surfaceRaised, c.surface]
                                        : const [
                                            Color(0xFFF6FCF8),
                                            Color(0xFFFFFFFF),
                                          ],
                                  ),
                                  border: Border.all(
                                    color: c.border,
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? 0.22
                                            : 0.045,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        LifeOsStatusPill(
                                          icon: Icons.alarm_on_rounded,
                                          label: _canExactAlarm
                                              ? 'Chuông đúng giờ'
                                              : 'Cần cấp quyền chuông',
                                          tone: _canExactAlarm
                                              ? LifeOsAccentTone.emerald
                                              : LifeOsAccentTone.amber,
                                        ),
                                        Material(
                                          color: c.surfaceRaised,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            side: BorderSide(
                                              color: c.border,
                                              width: 1.0,
                                            ),
                                          ),
                                          child: InkWell(
                                            key: const Key(
                                              'test_ring_screen_btn',
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            onTap: _openTestRingingPreview,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5.5,
                                                  ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.volume_up_rounded,
                                                    size: 15,
                                                    color: c.primary,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Thử chuông',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: c.primary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (nearest != null) ...[
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Text(
                                            hmFmt.format(nearest.triggerAt),
                                            style: TextStyle(
                                              fontSize: 36,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -1.0,
                                              color: c.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              nearest.title,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        PersonalAlarmStore.formatCountdownVi(
                                          nearest.triggerAt,
                                          now,
                                        ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: c.primary,
                                        ),
                                      ),
                                    ] else ...[
                                      Text(
                                        'Chưa có báo thức nào đang bật',
                                        style: TextStyle(
                                          fontSize: 17.5,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Bấm "+ Đặt giờ" hoặc chọn nhanh khung giờ mẫu bên dưới để máy tự đổ chuông đúng giờ.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.38,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                    if (!_canExactAlarm) ...[
                                      const SizedBox(height: 10),
                                      FilledButton.tonalIcon(
                                        onPressed: () =>
                                            NativeAlarmSchedulerBridge.instance
                                                .openExactAlarmSettings(),
                                        icon: const Icon(
                                          Icons.verified_user_outlined,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'Cấp quyền báo thức chính xác từng giây',
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              // 2. Quick 1-Tap Preset Strip
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final preset
                                        in const <
                                          (
                                            int h,
                                            int m,
                                            String label,
                                            List<int> days,
                                          )
                                        >[
                                          (
                                            6,
                                            0,
                                            'Dậy sớm tập thể dục',
                                            [1, 2, 3, 4, 5, 6, 7],
                                          ),
                                          (
                                            6,
                                            30,
                                            'Thức dậy đi làm',
                                            [1, 2, 3, 4, 5],
                                          ),
                                          (
                                            13,
                                            30,
                                            'Dậy sau nghỉ trưa',
                                            [1, 2, 3, 4, 5],
                                          ),
                                          (
                                            22,
                                            30,
                                            'Chuẩn bị đi ngủ',
                                            [1, 2, 3, 4, 5, 6, 7],
                                          ),
                                        ])
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ActionChip(
                                          key: Key(
                                            'quick_preset_${preset.$1}_${preset.$2}',
                                          ),
                                          avatar: Icon(
                                            Icons.alarm_add_rounded,
                                            size: 16,
                                            color: c.primary,
                                          ),
                                          label: Text(
                                            '${preset.$1.toString().padLeft(2, '0')}:${preset.$2.toString().padLeft(2, '0')} · ${preset.$3}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          onPressed: () async {
                                            final saved =
                                                await PersonalAlarmStore
                                                    .instance
                                                    .upsertAlarm(
                                                      hour: preset.$1,
                                                      minute: preset.$2,
                                                      label: preset.$3,
                                                      repeatWeekdays: preset.$4,
                                                    );
                                            await _reloadAll();
                                            if (!context.mounted) return;
                                            LifeOsTopToast.show(
                                              context,
                                              'Đã thêm báo thức ${saved.formattedTime} (${saved.label}).',
                                            );
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              // 3. Personal Alarms List (Apple Clock Style)
                              const LifeOsSectionHeader(
                                title: 'Báo thức hằng ngày',
                                subtitle:
                                    'Chạm vào thẻ để đổi giờ, ngày lặp lại hoặc nhãn ghi chú',
                                tone: LifeOsAccentTone.emerald,
                              ),
                              if (_personalAlarms.isEmpty)
                                LifeOsSoftCard(
                                  child: Column(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.access_alarm_rounded,
                                        tone: LifeOsAccentTone.emerald,
                                        size: 48,
                                        iconSize: 24,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Chưa có giờ báo thức cá nhân',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Đặt báo thức thức dậy, nghỉ trưa hoặc giờ cố định với chuông hệ thống chuẩn xác.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      FilledButton.tonalIcon(
                                        key: const Key(
                                          'empty_create_alarm_btn',
                                        ),
                                        onPressed: () =>
                                            _showUpsertAlarmSheet(),
                                        icon: const Icon(
                                          Icons.add_alarm_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Tạo báo thức đầu tiên',
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ..._personalAlarms.map((alarm) {
                                  final activeOpacity = alarm.enabled
                                      ? 1.0
                                      : 0.52;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LifeOsSoftCard(
                                      borderRadius: 16,
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        10,
                                        12,
                                      ),
                                      onTap: () => _showUpsertAlarmSheet(
                                        existing: alarm,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Opacity(
                                              opacity: activeOpacity,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    alarm.formattedTime,
                                                    style: TextStyle(
                                                      fontSize: 30,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: -0.9,
                                                      height: 1.08,
                                                      color: c.textPrimary,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${alarm.label} · ${alarm.repeatSummaryVi}',
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontSize: 12.8,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isDark
                                                          ? c.textSecondary
                                                          : const Color(
                                                              0xFF475467,
                                                            ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'personal_alarm_delete_${alarm.id}',
                                            ),
                                            tooltip: 'Xóa báo thức',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                              color: c.textSecondary,
                                            ),
                                            onPressed: () async {
                                              await PersonalAlarmStore.instance
                                                  .deleteAlarm(alarm.id);
                                              await _reloadAll();
                                              if (!context.mounted) return;
                                              LifeOsTopToast.show(
                                                context,
                                                'Đã xóa báo thức ${alarm.formattedTime}.',
                                                kind: LifeOsToastKind.info,
                                              );
                                            },
                                          ),
                                          Switch.adaptive(
                                            key: Key(
                                              'personal_alarm_switch_${alarm.id}',
                                            ),
                                            value: alarm.enabled,
                                            onChanged: (val) async {
                                              HapticFeedback.selectionClick();
                                              await PersonalAlarmStore.instance
                                                  .toggleAlarm(alarm.id, val);
                                              await _reloadAll();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),

                              // 4. Upcoming Calendar Event Alarms Section
                              if (upcomingEvents.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const LifeOsSectionHeader(
                                  title: 'Chuông nhắc Lịch hẹn sắp tới',
                                  subtitle:
                                      'Bật chuông báo thức toàn màn hình cho các cuộc hẹn quan trọng',
                                  tone: LifeOsAccentTone.blue,
                                ),
                                ...upcomingEvents.take(8).map((ev) {
                                  final scheduled = _osAlarmsById[ev.id];
                                  final isArmed =
                                      scheduled != null && scheduled.fullScreen;
                                  final leadMins = ev.reminderMinutesBefore > 0
                                      ? ev.reminderMinutesBefore
                                      : 15;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: LifeOsSoftCard(
                                      borderRadius: 16,
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        10,
                                        10,
                                        10,
                                      ),
                                      onTap: () => context.push(
                                        '/event-detail',
                                        extra: ev,
                                      ),
                                      child: Row(
                                        children: [
                                          LifeOsIconSquircle(
                                            icon: isArmed
                                                ? Icons.alarm_on_rounded
                                                : Icons.event_outlined,
                                            tone: isArmed
                                                ? LifeOsAccentTone.emerald
                                                : LifeOsAccentTone.blue,
                                            size: 38,
                                            iconSize: 19,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  ev.title,
                                                  softWrap: true,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  isArmed
                                                      ? 'Chuông lúc ${dmFmt.format(scheduled.triggerAt)}'
                                                      : 'Bắt đầu ${dmFmt.format(ev.startsAt)} · Nhắc trước ${leadMins}p',
                                                  softWrap: true,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: isArmed
                                                        ? c.primary
                                                        : c.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Switch.adaptive(
                                            key: Key(
                                              'upcoming_event_alarm_switch_${ev.id}',
                                            ),
                                            value: isArmed,
                                            onChanged: (val) async {
                                              HapticFeedback.selectionClick();
                                              if (val) {
                                                await NativeAlarmSchedulerBridge
                                                    .instance
                                                    .scheduleEventAlarm(
                                                      eventId: ev.id,
                                                      title: ev.title,
                                                      subtitle:
                                                          ev.location ??
                                                          'Lịch hẹn sắp diễn ra',
                                                      eventStartsAt:
                                                          ev.startsAt,
                                                      minutesBefore: leadMins,
                                                      fullScreen: true,
                                                    );
                                              } else {
                                                await NativeAlarmSchedulerBridge
                                                    .instance
                                                    .cancelEventAlarm(ev.id);
                                              }
                                              await _reloadAll();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpsertPersonalAlarmBottomSheet extends StatefulWidget {
  final PersonalAlarmItem? existing;

  const _UpsertPersonalAlarmBottomSheet({this.existing});

  @override
  State<_UpsertPersonalAlarmBottomSheet> createState() =>
      _UpsertPersonalAlarmBottomSheetState();
}

class _UpsertPersonalAlarmBottomSheetState
    extends State<_UpsertPersonalAlarmBottomSheet> {
  late int _hour;
  late int _minute;
  late int _snoozeMinutes;
  late final Set<int> _selectedDays;
  late final TextEditingController _labelCtrl;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _hour = ex?.hour ?? 6;
    _minute = ex?.minute ?? 30;
    _snoozeMinutes = ex?.snoozeMinutes ?? 5;
    _selectedDays = <int>{...(ex?.repeatWeekdays ?? const <int>[])};
    _labelCtrl = TextEditingController(text: ex?.label ?? 'Thức dậy buổi sáng');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  void _stepHour(int delta) {
    setState(() => _hour = (_hour + delta + 24) % 24);
  }

  void _stepMinute(int delta) {
    setState(() => _minute = (_minute + delta + 60) % 60);
  }

  Future<void> _openSystemTimePicker() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked != null && mounted) {
      setState(() {
        _hour = picked.hour;
        _minute = picked.minute;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final timeStr =
        '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: c.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.separator,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.existing == null
                      ? 'Đặt báo thức mới'
                      : 'Chỉnh sửa báo thức',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),

                // Interactive Tactile 3D Time Dial + Tap-to-Pick
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          IconButton(
                            key: const Key('alarm_hour_up_btn'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _stepHour(1),
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                          IconButton(
                            key: const Key('alarm_hour_down_btn'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _stepHour(-1),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: InkWell(
                            key: const Key('alarm_pick_time_btn'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: _openSystemTimePicker,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.2,
                                  color: c.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Column(
                        children: [
                          IconButton(
                            key: const Key('alarm_minute_up_btn'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _stepMinute(5),
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                          IconButton(
                            key: const Key('alarm_minute_down_btn'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _stepMinute(-5),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  key: const Key('alarm_label_field'),
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nhãn báo thức',
                    hintText: 'VD: Thức dậy đi làm / Đón con / Uống nước',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  'Lặp lại theo thứ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        key: Key('alarm_day_chip_$d'),
                        visualDensity: VisualDensity.compact,
                        label: Text(PersonalAlarmItem.shortWeekdayVi(d)),
                        selected: _selectedDays.contains(d),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _selectedDays.add(d);
                            } else {
                              _selectedDays.remove(d);
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                Text(
                  'Thời gian hoãn lặp (Snooze)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mins in const [5, 10, 15])
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('$mins phút'),
                        selected: _snoozeMinutes == mins,
                        onSelected: (_) =>
                            setState(() => _snoozeMinutes = mins),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('save_personal_alarm_submit_btn'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () async {
                          final saved = await PersonalAlarmStore.instance
                              .upsertAlarm(
                                existingId: widget.existing?.id,
                                hour: _hour,
                                minute: _minute,
                                label: _labelCtrl.text,
                                repeatWeekdays: _selectedDays.toList(),
                                snoozeMinutes: _snoozeMinutes,
                                enabled: true,
                              );
                          if (context.mounted) {
                            Navigator.of(context).pop(saved);
                          }
                        },
                        icon: const Icon(Icons.check_rounded, size: 19),
                        label: const Text(
                          'Lưu báo thức',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-Screen 3D Bright Apple AlarmKit Ringing Screen (`Báo thức sự kiện`).
class _AlarmRingingFullScreenView extends StatefulWidget {
  final CalendarEventEntity event;
  final bool playPreviewTone;

  const _AlarmRingingFullScreenView({
    required this.event,
    this.playPreviewTone = false,
  });

  @override
  State<_AlarmRingingFullScreenView> createState() =>
      _AlarmRingingFullScreenViewState();
}

class _AlarmRingingFullScreenViewState
    extends State<_AlarmRingingFullScreenView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.playPreviewTone) {
      NativeAlarmSchedulerBridge.instance.startTestRinging();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldPulse =
        TickerMode.valuesOf(context).enabled &&
        !LifeOsMotionScope.of(context).isReducedMotion;
    if (shouldPulse && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat();
    } else if (!shouldPulse && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0.25;
    }
  }

  @override
  void dispose() {
    if (widget.playPreviewTone) {
      NativeAlarmSchedulerBridge.instance.stopRingingAlarm(
        eventId: widget.event.id,
      );
    }
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _snoozeAlarm(int minutes) async {
    final ev = widget.event;
    await NativeAlarmSchedulerBridge.instance.stopRingingAlarm(eventId: ev.id);
    final snoozeAt = DateTime.now().add(Duration(minutes: minutes));
    await NativeAlarmSchedulerBridge.instance.scheduleEventAlarm(
      eventId: ev.id,
      title: ev.title,
      subtitle: ev.location ?? 'Nhắc lại sau $minutes phút',
      eventStartsAt: snoozeAt,
      minutesBefore: 0,
      fullScreen: true,
    );
    if (!mounted) return;
    LifeOsTopToast.show(
      context,
      'Đã hoãn báo thức thêm $minutes phút.',
      kind: LifeOsToastKind.info,
    );
    _closeScreen();
  }

  Future<void> _dismissAlarm() async {
    final ev = widget.event;
    await NativeAlarmSchedulerBridge.instance.stopRingingAlarm(eventId: ev.id);
    await PersonalAlarmStore.instance.handleAlarmDismissed(ev.id);
    if (!mounted) return;
    _closeScreen();
  }

  void _closeScreen() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/planning');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ev = widget.event;
    final alarmTime = DateFormat(
      'HH:mm',
    ).format(ev.startsAt.subtract(Duration(minutes: ev.reminderMinutesBefore)));
    final eventTitle = ev.title;
    final eventTimeLine =
        '${DateFormat('dd/MM/yyyy').format(ev.startsAt)} • ${DateFormat('HH:mm').format(ev.startsAt)}';
    final eventLocation = (ev.location ?? '').trim().isNotEmpty
        ? ev.location!
        : 'Báo thức hệ thống LifeOS';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [
                    Color(0xFF1A232D),
                    Color(0xFF161B22),
                    Color(0xFF12171D),
                  ]
                : const [
                    Color(0xFFF3FAF5),
                    Color(0xFFF8FAFC),
                    Color(0xFFFFFFFF),
                  ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Top Bar
                            Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const SizedBox(width: 36),
                                    Text(
                                      'LifeOS',
                                      style: TextStyle(
                                        color: c.textSecondary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Đóng màn hình chuông',
                                      onPressed: _dismissAlarm,
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Báo thức sự kiện',
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 22.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Center Daylight Bell Cushion + Giant Tabular Clock + Executive Event Card
                            Column(
                              children: [
                                SizedBox(
                                  width: 184,
                                  height: 184,
                                  child: AnimatedBuilder(
                                    animation: _pulseCtrl,
                                    builder: (_, __) => CustomPaint(
                                      painter: _AlarmRadarRingsPainter(
                                        progress: _pulseCtrl.value,
                                        ringColor: c.primary,
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 78,
                                          height: 78,
                                          decoration: ShapeDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                const Color(0xFF17B252),
                                                c.primary,
                                              ],
                                            ),
                                            shape: ContinuousRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(36),
                                              side: BorderSide(
                                                color: Colors.white.withValues(
                                                  alpha: 0.72,
                                                ),
                                                width: 1.2,
                                              ),
                                            ),
                                            shadows: [
                                              BoxShadow(
                                                color: c.primary.withValues(
                                                  alpha: isDark ? 0.36 : 0.24,
                                                ),
                                                blurRadius: 24,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.notifications_active_rounded,
                                            color: Colors.white,
                                            size: 36,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  alarmTime,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.6,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    color: c.surface,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: c.border,
                                      width: 1.0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.24 : 0.055,
                                        ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: c.primarySubtle,
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.alarm_rounded,
                                          color: c.primary,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              eventTitle,
                                              softWrap: true,
                                              style: TextStyle(
                                                color: c.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              eventTimeLine,
                                              softWrap: true,
                                              style: TextStyle(
                                                color: c.textSecondary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              eventLocation,
                                              softWrap: true,
                                              style: TextStyle(
                                                color: c.textSecondary,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Bottom Clean Executive Snooze & Dismiss Buttons
                            Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: FilledButton(
                                    key: const Key('ringing_snooze_button'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: c.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () => _snoozeAlarm(5),
                                    child: const Text(
                                      'Hoãn 5 phút',
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: FilledButton(
                                    key: const Key('ringing_dismiss_button'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: isDark
                                          ? const Color(0xFF3A1D22)
                                          : const Color(0xFFFFF1F2),
                                      foregroundColor: c.error,
                                      side: BorderSide(
                                        color: c.error.withValues(alpha: 0.25),
                                        width: 1.0,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: _dismissAlarm,
                                    child: Text(
                                      'Tắt báo thức',
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                        color: c.error,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
      ),
    );
  }
}

class _AlarmRadarRingsPainter extends CustomPainter {
  final double progress;
  final Color ringColor;

  const _AlarmRadarRingsPainter({
    required this.progress,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    for (var i = 1; i <= 3; i++) {
      final baseR = maxR * (0.48 + i * 0.16);
      final ringPaint = Paint()
        ..color = ringColor.withValues(alpha: 0.22 - i * 0.045)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..isAntiAlias = true;

      if (i == 2) {
        const segments = 12;
        const sweep = (2 * math.pi / segments) * 0.62;
        for (var s = 0; s < segments; s++) {
          final startAngle =
              (2 * math.pi / segments) * s + (progress * 2 * math.pi * 0.25);
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: baseR),
            startAngle,
            sweep,
            false,
            ringPaint,
          );
        }
      } else {
        canvas.drawCircle(center, baseR, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AlarmRadarRingsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.ringColor != ringColor;
}
