import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../domain/entities/calendar_entities.dart';
import '../bloc/calendar_bloc.dart';

/// Screen 03: "Chi tiết sự kiện" following Unified LifeOS Design System (`03_Chi_tiet_su_kien.png`).
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

    final calEvents =
        maybeCalBloc?.state.events ?? const <CalendarEventEntity>[];
    final family = maybeFamilyBloc?.state.activeFamily;

    final event =
        widget.initialEvent ?? (calEvents.isNotEmpty ? calEvents.first : null);
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
                                'Hãy đồng bộ Lịch của bạn và chọn một sự kiện thật từ tab Lịch trình để xem chi tiết hoặc đặt báo thức.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.38,
                                  color: c.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              LifeOsPrimaryCtaButton(
                                icon: Icons.calendar_month_rounded,
                                label: 'Mở Lịch trình & Đồng bộ',
                                onPressed: () => context.go('/planning'),
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
    ];

    final memberNames =
        (event.visibility == CalendarEventVisibility.sharedEvent &&
            family != null &&
            family.members.isNotEmpty)
        ? family.members.map((m) => m.fullName).take(4).toList()
        : const <String>[];

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              LifeOsTopBrandHeader(
                title: 'Chi tiết sự kiện',
                showBackButton: true,
                trailingAction: TextButton.icon(
                  onPressed: () => context.push('/event-alarm', extra: event),
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

                        // 2. Event Metadata Card (Ngày | Thời gian | Địa điểm | Ghi chú)
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

                        // 3. Invited Family Members Card (Only shown for real Shared Family Events)
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

                        // 4. Reminder Selector Card ("Nhắc nhở")
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
                                      'Nhắc nhở',
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
                                'Chọn thời điểm nhắc nhở cho sự kiện này.',
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
                                  'Báo thức toàn màn hình khi đến giờ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Phát chuông nhắc & hiển thị màn hình báo thức',
                                ),
                                value: _enableFullScreenAlarm,
                                onChanged: (v) =>
                                    setState(() => _enableFullScreenAlarm = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 5. Real OS Alarm Scheduler CTA ("Lưu nhắc nhở" + Cancel + Optional Preview)
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
                                    'Đã hẹn báo thức lúc ${DateFormat('HH:mm dd/MM').format(_scheduledAlarm!.triggerAt)}',
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
                                    LifeOsTopToast.fromSnackBar(
                                      context,
                                      const SnackBar(
                                        content: Text(
                                          'Đã hủy lịch báo thức trên hệ thống.',
                                        ),
                                      ),
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
                              ? 'Lưu nhắc nhở hệ thống'
                              : 'Cập nhật giờ báo thức',
                          onPressed: () async {
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
                            LifeOsTopToast.fromSnackBar(
                              context,
                              SnackBar(
                                content: Text(
                                  '✓ Đã đặt báo thức hệ thống lúc $triggerFmt cho "${event.title}".',
                                ),
                                action: !info.exactScheduled
                                    ? SnackBarAction(
                                        label: 'Cấp quyền đúng giây',
                                        onPressed: () =>
                                            NativeAlarmSchedulerBridge.instance
                                                .openExactAlarmSettings(),
                                      )
                                    : null,
                              ),
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
                            label: const Text('Xem thử màn hình báo thức'),
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
                maxLines: multiLine ? 4 : 2,
                overflow: TextOverflow.ellipsis,
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

/// Screen 10 of Auth/Setup Sheet: Full-Screen Emerald "Báo thức sự kiện" (`07:30`).
class EventAlarmPage extends StatefulWidget {
  final CalendarEventEntity? event;

  const EventAlarmPage({super.key, this.event});

  @override
  State<EventAlarmPage> createState() => _EventAlarmPageState();
}

class _EventAlarmPageState extends State<EventAlarmPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    CalendarEventEntity? ev = widget.event;
    if (ev == null) {
      try {
        final upcoming =
            context
                .watch<CalendarBloc>()
                .state
                .events
                .where((e) => e.endsAt.isAfter(DateTime.now()))
                .toList()
              ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        if (upcoming.isNotEmpty) {
          ev = upcoming.first;
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final alarmTime = ev != null
        ? DateFormat('HH:mm').format(
            ev.startsAt.subtract(Duration(minutes: ev.reminderMinutesBefore)),
          )
        : DateFormat('HH:mm').format(now);
    final eventTitle = ev?.title ?? 'Chưa có sự kiện đặt báo thức';
    final eventTimeLine = ev != null
        ? '${DateFormat('dd/MM/yyyy').format(ev.startsAt)} • ${DateFormat('HH:mm').format(ev.startsAt)}'
        : 'Đồng bộ Lịch trình để hẹn chuông nhắc tự động';
    final eventLocation = (ev != null && (ev.location ?? '').trim().isNotEmpty)
        ? ev.location!
        : (ev != null ? 'Lịch trình đã đồng bộ' : 'Chưa chọn sự kiện');

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0C7430), Color(0xFF0A6128), Color(0xFF074E20)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                child: Column(
                  children: [
                    Text(
                      'LifeOS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Báo thức sự kiện',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const Spacer(),

                    // Animated Concentric Radar Rings + Glowing Bell
                    SizedBox(
                      width: 210,
                      height: 210,
                      child: AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => CustomPaint(
                          painter: _AlarmRadarRingsPainter(
                            progress: _pulseCtrl.value,
                          ),
                          child: Center(
                            child: Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1CC856),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF22C55E,
                                    ).withValues(alpha: 0.48),
                                    blurRadius: 28,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.notifications_active_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Giant Tabular Clock ("07:30")
                    Text(
                      alarmTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 58,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Event Preview White Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAFBF0),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.calendar_today_rounded,
                              color: Color(0xFF12B847),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  eventTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF101828),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  eventTimeLine,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF475467),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  eventLocation,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Snooze 5m Button ("Hoãn 5 phút")
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF101828),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        onPressed: () async {
                          final activeEv = ev;
                          if (activeEv != null) {
                            final snoozeAt = DateTime.now().add(
                              const Duration(minutes: 5),
                            );
                            await NativeAlarmSchedulerBridge.instance
                                .scheduleEventAlarm(
                                  eventId: activeEv.id,
                                  title: activeEv.title,
                                  subtitle:
                                      activeEv.location ??
                                      'Nhắc lại sau 5 phút',
                                  eventStartsAt: snoozeAt,
                                  minutesBefore: 0,
                                  fullScreen: true,
                                );
                          }
                          if (!context.mounted) return;
                          LifeOsTopToast.fromSnackBar(
                            context,
                            const SnackBar(
                              content: Text('⏰ Đã hoãn báo thức thêm 5 phút.'),
                            ),
                          );
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/planning');
                          }
                        },
                        child: const Text(
                          'Hoãn 5 phút',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Dismiss Alarm Button ("Tắt báo thức")
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF1F2),
                          foregroundColor: const Color(0xFFDC2626),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/planning');
                          }
                        },
                        child: const Text(
                          'Tắt báo thức',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlarmRadarRingsPainter extends CustomPainter {
  final double progress;

  const _AlarmRadarRingsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    for (var i = 1; i <= 3; i++) {
      final baseR = maxR * (0.48 + i * 0.16);
      final ringPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.22 - i * 0.04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..isAntiAlias = true;

      if (i == 2) {
        // Dashed middle radar ring matching Image 3 Screen 10
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
      oldDelegate.progress != progress;
}
