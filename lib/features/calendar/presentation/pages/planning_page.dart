import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/pages/auth_pages.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../tasks/presentation/pages/tasks_board_page.dart';
import '../../domain/entities/calendar_entities.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../bloc/calendar_bloc.dart';

class PlanningPage extends StatefulWidget {
  final String? initialViewMode;
  final int initialTabIndex;

  const PlanningPage({
    super.key,
    this.initialViewMode,
    this.initialTabIndex = 0,
  });

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    )..addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PlanningPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      final nextIdx = widget.initialTabIndex.clamp(0, 2);
      if (_tabController.index != nextIdx) {
        _tabController.animateTo(nextIdx);
      }
    } else if (widget.initialViewMode != null &&
        widget.initialViewMode != oldWidget.initialViewMode &&
        _tabController.index != 0) {
      _tabController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final activeFamily = context.watch<FamilyBloc>().state.activeFamily;
    final isSyncingCal = context.select<CalendarBloc, bool>(
      (b) => b.state.isSyncingGoogle,
    );
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isCalendarTab = _tabController.index == 0;

    return MultiBlocListener(
      listeners: [
        BlocListener<CalendarBloc, CalendarState>(
          listenWhen: (p, c) =>
              (c.failure != null && p.failure != c.failure) ||
              (c.message != null && p.message != c.message),
          listener: (context, state) {
            if (state.failure != null) {
              LifeOsTopToast.fromSnackBar(
                context,
                SnackBar(content: Text('⚠ ${state.failure!.message}')),
              );
            } else if (state.message != null) {
              LifeOsTopToast.fromSnackBar(
                context,
                SnackBar(content: Text('✓ ${state.message!}')),
              );
            }
          },
        ),
        BlocListener<TaskBloc, TaskState>(
          listenWhen: (p, c) =>
              (c.failure != null && p.failure != c.failure) ||
              (c.message != null && p.message != c.message),
          listener: (context, state) {
            if (state.failure != null) {
              LifeOsTopToast.fromSnackBar(
                context,
                SnackBar(content: Text('⚠ ${state.failure!.message}')),
              );
            } else if (state.message != null) {
              LifeOsTopToast.fromSnackBar(
                context,
                SnackBar(content: Text('✓ ${state.message!}')),
              );
            }
          },
        ),
      ],
      child: Scaffold(
        body: LifeOsMintWaveCanvas(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                LifeOsTopBrandHeader(
                  title: 'Lịch & Việc',
                  extraBrandActions: [
                    if (isCalendarTab)
                      LifeOsHeaderCircleButton(
                        buttonKey: const Key('header_sync_calendar_button'),
                        icon: isSyncingCal
                            ? Icons.autorenew_rounded
                            : Icons.sync_rounded,
                        tooltip: 'Đồng bộ Lịch Google & điện thoại',
                        onTap: isSyncingCal
                            ? () {}
                            : () => context.read<CalendarBloc>().add(
                                GoogleCalendarSyncRequested(
                                  userId: user.id,
                                  userName: user.fullName,
                                ),
                              ),
                      )
                    else
                      LifeOsHeaderCircleButton(
                        buttonKey: const Key('open_create_event_button'),
                        icon: Icons.edit_calendar_rounded,
                        tooltip: 'Thêm lịch hẹn mới',
                        onTap: () => showUpsertCalendarEventDialog(
                          context,
                          userId: user.id,
                          userName: user.fullName,
                          familyId: activeFamily?.id,
                          availabilityOptIn: user.availabilityOptIn,
                        ),
                      ),
                  ],
                  trailingAction: isCalendarTab
                      ? FilledButton.icon(
                          key: const Key('open_create_event_button'),
                          onPressed: () => showUpsertCalendarEventDialog(
                            context,
                            userId: user.id,
                            userName: user.fullName,
                            familyId: activeFamily?.id,
                            availabilityOptIn: user.availabilityOptIn,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Thêm lịch'),
                        )
                      : FilledButton.icon(
                          key: const Key('open_create_task_header_button'),
                          onPressed: () => showUnifiedCreateTaskDialog(
                            context,
                            userId: user.id,
                            userName: user.fullName,
                            familyId: activeFamily?.id,
                            members: activeFamily?.members ?? const [],
                          ),
                          icon: const Icon(Icons.add_task_rounded, size: 18),
                          label: const Text('Thêm việc'),
                        ),
                ),
                ProPillTabContainer(
                  tabBar: TabBar(
                    controller: _tabController,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    tabs: const [
                      Tab(
                        key: Key('planning_calendar_tab'),
                        text: 'Lịch trình',
                      ),
                      Tab(key: Key('planning_tasks_tab'), text: 'Công việc'),
                      Tab(key: Key('planning_tools_tab'), text: 'Tiện ích'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _UnifiedWorkScheduleTab(
                        userId: user.id,
                        userName: user.fullName,
                        familyId: activeFamily?.id,
                        familyMembers: activeFamily?.members ?? const [],
                        availabilityOptIn: user.availabilityOptIn,
                        initialViewMode: widget.initialViewMode,
                      ),
                      UnifiedTasksBoardView(userId: user.id),
                      _PlanningHabitsAndNotesTabView(userId: user.id),
                    ],
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

Future<void> showCreateManagedCalendarDialog(
  BuildContext context, {
  required String userId,
}) async {
  final calBloc = context.read<CalendarBloc>();
  await showDialog<void>(
    context: context,
    builder: (_) =>
        _CreateManagedCalendarDialog(calBloc: calBloc, userId: userId),
  );
}

class _CreateManagedCalendarDialog extends StatefulWidget {
  final CalendarBloc calBloc;
  final String userId;

  const _CreateManagedCalendarDialog({
    required this.calBloc,
    required this.userId,
  });

  @override
  State<_CreateManagedCalendarDialog> createState() =>
      _CreateManagedCalendarDialogState();
}

class _CreateManagedCalendarDialogState
    extends State<_CreateManagedCalendarDialog> {
  static const List<String> _palette = <String>[
    '#0B7A2A',
    '#1971C2',
    '#6741D9',
    '#D9480F',
    '#C92A2A',
    '#087F5B',
  ];

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  String _selectedColor = '#0B7A2A';
  bool _createOnGoogle = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  static Color _parseHex(String hex) {
    final clean = hex.replaceFirst('#', '');
    final v = int.tryParse('FF$clean', radix: 16);
    return v != null ? Color(v) : Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tạo bộ lịch mới'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('new_calendar_name_field'),
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên bộ lịch',
                hintText: 'VD: Lịch Làm việc / Tập luyện / Học tập',
                prefixIcon: Icon(Icons.calendar_today_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Mô tả ngắn (tùy chọn)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Màu nhận diện',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: _palette.map((hex) {
                final color = _parseHex(hex);
                final isPicked = _selectedColor == hex;
                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _selectedColor = hex),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isPicked
                          ? Border.all(color: Colors.black87, width: 2.5)
                          : null,
                    ),
                    child: isPicked
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Đồng bộ lên Google Calendar'),
              value: _createOnGoogle,
              onChanged: (v) => setState(() => _createOnGoogle = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          key: const Key('submit_create_calendar_button'),
          onPressed: () {
            widget.calBloc.add(
              ManagedCalendarCreateSubmitted(
                CreateManagedCalendarParams(
                  userId: widget.userId,
                  summary: _nameCtrl.text,
                  description: _descCtrl.text,
                  colorHex: _selectedColor,
                  createOnGoogle: _createOnGoogle,
                ),
              ),
            );
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Tạo lịch'),
        ),
      ],
    );
  }
}

Future<void> showManageCalendarsSheet(
  BuildContext context, {
  required String userId,
}) async {
  final calBloc = context.read<CalendarBloc>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider<CalendarBloc>.value(
      value: calBloc,
      child: _ManageCalendarsBottomSheet(userId: userId),
    ),
  );
}

class _ManageCalendarsBottomSheet extends StatelessWidget {
  final String userId;

  const _ManageCalendarsBottomSheet({required this.userId});

  static Color _parseColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final clean = hex.replaceFirst('#', '');
    if (clean.length == 6) {
      final v = int.tryParse('FF$clean', radix: 16);
      if (v != null) return Color(v);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return BlocBuilder<CalendarBloc, CalendarState>(
      builder: (context, state) {
        final groups = state.deduplicatedCalendars;
        final userGroups = groups.where((g) => !g.isSystemFeed).toList();
        final systemGroups = groups.where((g) => g.isSystemFeed).toList();

        Widget buildGroupRow(DeduplicatedCalendarGroup group) {
          final dotColor = _parseColor(
            group.representative.colorHex,
            c.primary,
          );
          final isFilteredOnly =
              state.selectedCalendarId != null &&
              group.matchesCalendarId(state.selectedCalendarId);
          final mergedCount = group.members.length;

          return Padding(
            key: Key('calendar_group_tile_${group.canonicalId}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: isFilteredOnly
                  ? c.primary.withValues(alpha: 0.09)
                  : c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isFilteredOnly ? c.primary : c.separator,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  context.read<CalendarBloc>().add(
                    CalendarFilterSelected(
                      isFilteredOnly ? null : group.canonicalId,
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.displayTitle,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            if (mergedCount > 1)
                              Text(
                                'Đã gộp $mergedCount bộ lịch trùng tên',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: c.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (group.isDeletable)
                        IconButton(
                          key: Key(
                            'delete_calendar_group_${group.canonicalId}',
                          ),
                          tooltip: 'Xóa bộ lịch',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: c.error,
                          ),
                          onPressed: () => context.read<CalendarBloc>().add(
                            ManagedCalendarDeleteSubmitted(
                              userId: userId,
                              calendar: group.representative,
                            ),
                          ),
                        ),
                      if (!group.isPrimaryGroup)
                        Switch(
                          key: Key(
                            'toggle_calendar_group_${group.canonicalId}',
                          ),
                          value: group.isSelected,
                          onChanged: (val) => context.read<CalendarBloc>().add(
                            ManagedCalendarVisibilityToggled(
                              userId: userId,
                              calendar: group.representative,
                              isSelected: val,
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

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: Material(
            color: c.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Bộ lịch hiển thị',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('create_calendar_button'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            showCreateManagedCalendarDialog(
                              context,
                              userId: userId,
                            );
                          },
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text('Tạo bộ lịch'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (state.selectedCalendarId != null ||
                        userGroups.any((g) => !g.isSelected))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          key: const Key('sheet_show_all_calendars_btn'),
                          onPressed: () {
                            context.read<CalendarBloc>().add(
                              CalendarFiltersReset(
                                userId: userId,
                                enableHiddenUserCalendars: true,
                              ),
                            );
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.done_all_rounded, size: 17),
                          label: const Text('Hiển thị lại tất cả lịch'),
                        ),
                      ),
                    ...userGroups.map(buildGroupRow),
                    if (systemGroups.isNotEmpty)
                      Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: const Key('system_calendars_expansion_tile'),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          childrenPadding: EdgeInsets.zero,
                          title: Text(
                            'Lịch ngày lễ & hệ thống (${systemGroups.length})',
                            style: TextStyle(
                              fontSize: 13.2,
                              fontWeight: FontWeight.w700,
                              color: c.textSecondary,
                            ),
                          ),
                          children: systemGroups.map(buildGroupRow).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UnifiedWorkScheduleTab extends StatefulWidget {
  final String userId;
  final String userName;
  final String? familyId;
  final List<dynamic> familyMembers;
  final bool availabilityOptIn;
  final String? initialViewMode;

  const _UnifiedWorkScheduleTab({
    required this.userId,
    required this.userName,
    required this.familyId,
    required this.familyMembers,
    required this.availabilityOptIn,
    this.initialViewMode,
  });

  @override
  State<_UnifiedWorkScheduleTab> createState() =>
      _UnifiedWorkScheduleTabState();
}

class _UnifiedWorkScheduleTabState extends State<_UnifiedWorkScheduleTab>
    with WidgetsBindingObserver {
  static const Set<String> _validModes = {'day', 'week', 'month', 'year'};

  String _viewMode = 'day';
  late DateTime _focusedMonth;
  late DateTime _selectedDate;
  int _periodDirection = 1;
  bool _showSearchBar = false;
  bool _expandMonthInWeekMode = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
    final initQuery = context.read<CalendarBloc>().state.searchQuery;
    if (initQuery.isNotEmpty) {
      _searchCtrl.text = initQuery;
      _showSearchBar = true;
    }
    final initMode = widget.initialViewMode;
    if (initMode != null && _validModes.contains(initMode)) {
      _viewMode = initMode;
    }
  }

  @override
  void didUpdateWidget(covariant _UnifiedWorkScheduleTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextMode = widget.initialViewMode;
    if (nextMode != null &&
        nextMode != oldWidget.initialViewMode &&
        _validModes.contains(nextMode)) {
      _viewMode = nextMode;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<CalendarBloc>().add(
        GoogleCalendarSyncRequested(
          userId: widget.userId,
          userName: widget.userName,
          interactive: false,
        ),
      );
    }
  }

  static Color _parseHexColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final clean = hex.replaceFirst('#', '');
    if (clean.length == 6) {
      final v = int.tryParse('FF$clean', radix: 16);
      if (v != null) return Color(v);
    }
    return fallback;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Expands single, multi-day, and recurring events falling inside `[winStart, winEnd]`.
  static List<CalendarEventEntity> _eventsInWindow(
    List<CalendarEventEntity> source,
    DateTime winStart,
    DateTime winEnd,
  ) {
    final matches = <CalendarEventEntity>[];
    final maxOccs = winEnd.difference(winStart).inDays > 62 ? 400 : 40;
    for (final ev in source) {
      final duration = ev.endsAt.isAfter(ev.startsAt)
          ? ev.endsAt.difference(ev.startsAt)
          : const Duration(hours: 1);

      if (ev.isRecurring) {
        final occs = ev.recurrence.expandOccurrences(
          firstStart: ev.startsAt,
          windowStart: winStart.subtract(duration),
          windowEnd: winEnd,
          maxInstances: maxOccs,
        );
        for (final occStart in occs) {
          final occEnd = occStart.add(duration);
          if (!occStart.isAfter(winEnd) && !occEnd.isBefore(winStart)) {
            matches.add(ev.copyWith(startsAt: occStart, endsAt: occEnd));
          }
        }
      } else {
        if (!ev.startsAt.isAfter(winEnd) && !ev.endsAt.isBefore(winStart)) {
          matches.add(ev);
        }
      }
    }
    matches.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return matches;
  }

  void _stepPeriod(int delta) {
    setState(() {
      _periodDirection = delta >= 0 ? 1 : -1;
      if (_viewMode == 'week') {
        _selectedDate = _selectedDate.add(Duration(days: 7 * delta));
        _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      } else if (_viewMode == 'year') {
        final nextYear = _focusedMonth.year + delta;
        final maxDay = DateTime(nextYear, _selectedDate.month + 1, 0).day;
        final clampedDay = _selectedDate.day > maxDay
            ? maxDay
            : _selectedDate.day;
        _focusedMonth = DateTime(nextYear, _focusedMonth.month, 1);
        _selectedDate = DateTime(nextYear, _selectedDate.month, clampedDay);
      } else {
        final nextMonth = DateTime(
          _focusedMonth.year,
          _focusedMonth.month + delta,
          1,
        );
        final maxDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
        final clampedDay = _selectedDate.day > maxDay
            ? maxDay
            : _selectedDate.day;
        _focusedMonth = nextMonth;
        _selectedDate = DateTime(nextMonth.year, nextMonth.month, clampedDay);
      }
    });
  }

  void _jumpToToday() {
    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day);
    setState(() {
      _periodDirection = target.isBefore(_selectedDate) ? -1 : 1;
      _selectedDate = target;
      _focusedMonth = DateTime(now.year, now.month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final taskState = context.watch<TaskBloc>().state;
    final timeFmt = DateFormat('HH:mm');
    final shortDateFmt = DateFormat('dd/MM');
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    return BlocConsumer<CalendarBloc, CalendarState>(
      listenWhen: (p, c) => p.searchQuery != c.searchQuery,
      listener: (_, state) {
        if (state.searchQuery.isEmpty && _searchCtrl.text.isNotEmpty) {
          _searchCtrl.clear();
        }
      },
      builder: (context, state) {
        final dedupedGroups = state.deduplicatedCalendars;
        final groupByCalId = <String, DeduplicatedCalendarGroup>{
          for (final g in dedupedGroups)
            for (final memberId in g.memberIds) memberId: g,
        };
        final activeFilteredGroup =
            (state.selectedCalendarId != null &&
                state.selectedCalendarId != '__family__')
            ? dedupedGroups
                  .where(
                    (g) =>
                        g.canonicalId == state.selectedCalendarId ||
                        g.matchesCalendarId(state.selectedCalendarId),
                  )
                  .firstOrNull
            : null;
        final userCalendarCount = dedupedGroups
            .where((g) => !g.isSystemFeed)
            .length;
        final syncedCount = state.events
            .where((e) => e.syncStatus == CalendarSyncStatus.synced)
            .length;
        final events = state.filteredEvents;

        final isViewingToday =
            _sameDay(_selectedDate, todayDate) &&
            _focusedMonth.year == todayDate.year &&
            (_viewMode == 'year' || _focusedMonth.month == todayDate.month);

        const weekdaysVi = <int, String>{
          DateTime.monday: 'Thứ Hai',
          DateTime.tuesday: 'Thứ Ba',
          DateTime.wednesday: 'Thứ Tư',
          DateTime.thursday: 'Thứ Năm',
          DateTime.friday: 'Thứ Sáu',
          DateTime.saturday: 'Thứ Bảy',
          DateTime.sunday: 'Chủ Nhật',
        };

        final isSearching = state.searchQuery.trim().isNotEmpty;
        final (
          DateTime winStart,
          DateTime winEnd,
          String periodHeader,
        ) = isSearching
            ? (
                todayDate.subtract(const Duration(days: 365)),
                todayDate.add(const Duration(days: 365)),
                'Kết quả tìm kiếm "${state.searchQuery.trim()}"',
              )
            : switch (_viewMode) {
                'week' => () {
                  final monday = _selectedDate.subtract(
                    Duration(days: _selectedDate.weekday - 1),
                  );
                  final start = DateTime(monday.year, monday.month, monday.day);
                  final sunday = start.add(const Duration(days: 6));
                  final end = DateTime(
                    sunday.year,
                    sunday.month,
                    sunday.day,
                    23,
                    59,
                    59,
                    999,
                  );
                  return (
                    start,
                    end,
                    'Tuần ${shortDateFmt.format(start)} – ${shortDateFmt.format(sunday)}',
                  );
                }(),
                'month' => () {
                  final start = DateTime(
                    _focusedMonth.year,
                    _focusedMonth.month,
                    1,
                  );
                  final nextM = DateTime(
                    _focusedMonth.year,
                    _focusedMonth.month + 1,
                    1,
                  );
                  final end = nextM.subtract(const Duration(milliseconds: 1));
                  return (
                    start,
                    end,
                    'Lịch tháng ${_focusedMonth.month}/${_focusedMonth.year}',
                  );
                }(),
                'year' => () {
                  final start = DateTime(_focusedMonth.year, 1, 1);
                  final end = DateTime(
                    _focusedMonth.year,
                    12,
                    31,
                    23,
                    59,
                    59,
                    999,
                  );
                  return (start, end, 'Lịch cả năm ${_focusedMonth.year}');
                }(),
                _ => (
                  DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                  ),
                  DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    23,
                    59,
                    59,
                    999,
                  ),
                  _sameDay(_selectedDate, todayDate)
                      ? 'Hôm nay · ${_selectedDate.day}/${_selectedDate.month}'
                      : '${weekdaysVi[_selectedDate.weekday]}, ${_selectedDate.day}/${_selectedDate.month}',
                ),
              };

        final periodEvents = _eventsInWindow(events, winStart, winEnd);
        final searchTrimmed = state.searchQuery.trim();
        final dueTasks = taskState.tasks.where((t) {
          if (t.status == TaskWorkflowStatus.declined) return false;
          if (state.selectedCalendarId == '__family__' && t.isPersonal) {
            return false;
          }
          if (t.dueAt == null) return false;
          if (t.dueAt!.isBefore(winStart) || t.dueAt!.isAfter(winEnd)) {
            return false;
          }
          if (searchTrimmed.isNotEmpty &&
              !VietnameseSearchMatcher.matchesAny(searchTrimmed, [
                t.title,
                t.description,
                t.assigneeName,
              ])) {
            return false;
          }
          return true;
        }).toList()..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

        bool dateHasEvent(DateTime day) {
          final s = DateTime(day.year, day.month, day.day);
          final e = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
          return _eventsInWindow(events, s, e).isNotEmpty;
        }

        bool dateHasTask(DateTime day) {
          return taskState.tasks.any(
            (t) =>
                t.status != TaskWorkflowStatus.done &&
                t.status != TaskWorkflowStatus.declined &&
                t.dueAt != null &&
                _sameDay(t.dueAt!, day),
          );
        }

        final totalAgendaCount = periodEvents.length + dueTasks.length;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.maxContentWidth,
            ),
            child: ListView(
              key: const Key('calendar_events_list_view'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                6,
                AppSpacing.md,
                AppSpacing.dockClearance,
              ),
              children: [
                // 1. Clean View Horizon Switcher: Ngày · Tuần · Tháng · Năm
                LifeOsSegmentedPills<String>(
                  selected: _viewMode,
                  options: const [
                    ('day', 'Ngày', null),
                    ('week', 'Tuần', null),
                    ('month', 'Tháng', null),
                    ('year', 'Năm', null),
                  ],
                  onChanged: (v) => setState(() {
                    _viewMode = v;
                    if (v != 'week') _expandMonthInWeekMode = false;
                  }),
                ),
                const SizedBox(height: 8),

                // 2. Clean Filter & Search Strip (inline calendar list hidden into compact sheet!)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          key: const Key('toggle_calendar_search_chip'),
                          avatar: Icon(
                            Icons.search_rounded,
                            size: 16,
                            color:
                                (_showSearchBar || state.searchQuery.isNotEmpty)
                                ? c.primary
                                : c.textSecondary,
                          ),
                          label: Text(
                            state.searchQuery.isNotEmpty
                                ? 'Tìm: "${state.searchQuery}"'
                                : 'Tìm lịch',
                          ),
                          selected:
                              _showSearchBar || state.searchQuery.isNotEmpty,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            if (state.searchQuery.isNotEmpty) {
                              _searchCtrl.clear();
                              context.read<CalendarBloc>().add(
                                const CalendarSearchChanged(''),
                              );
                              setState(() => _showSearchBar = false);
                            } else {
                              setState(() => _showSearchBar = !_showSearchBar);
                            }
                          },
                        ),
                      ),
                      if (widget.familyId != null || state.hasActiveFilters)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            key: const Key('calendar_filter_all_chip'),
                            label: const Text('Tất cả'),
                            selected: !state.hasActiveFilters,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) {
                              _searchCtrl.clear();
                              context.read<CalendarBloc>().add(
                                CalendarFiltersReset(
                                  userId: widget.userId,
                                  enableHiddenUserCalendars: true,
                                ),
                              );
                            },
                          ),
                        ),
                      if (widget.familyId != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            avatar: Icon(
                              Icons.groups_rounded,
                              size: 15,
                              color: c.secondary,
                            ),
                            label: const Text('Gia đình'),
                            selected: state.selectedCalendarId == '__family__',
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => context.read<CalendarBloc>().add(
                              CalendarFilterSelected(
                                state.selectedCalendarId == '__family__'
                                    ? null
                                    : '__family__',
                              ),
                            ),
                          ),
                        ),
                      if (activeFilteredGroup != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            key: const Key('active_calendar_filter_chip'),
                            visualDensity: VisualDensity.compact,
                            avatar: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _parseHexColor(
                                  activeFilteredGroup.representative.colorHex,
                                  c.primary,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            label: Text(activeFilteredGroup.displayTitle),
                            selected: true,
                            onSelected: (_) => showManageCalendarsSheet(
                              context,
                              userId: widget.userId,
                            ),
                            onDeleted: () => context.read<CalendarBloc>().add(
                              const CalendarFilterSelected(null),
                            ),
                            deleteButtonTooltipMessage: 'Bỏ lọc bộ lịch',
                          ),
                        ),
                      ActionChip(
                        key: const Key('open_calendars_sheet_chip'),
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(
                          Icons.layers_outlined,
                          size: 16,
                          color: c.primary,
                        ),
                        label: Text(
                          userCalendarCount > 1
                              ? 'Bộ lịch ($userCalendarCount)'
                              : 'Bộ lịch',
                        ),
                        onPressed: () => showManageCalendarsSheet(
                          context,
                          userId: widget.userId,
                        ),
                      ),
                    ],
                  ),
                ),

                LifeOsAnimatedVisibility(
                  visible: _showSearchBar || state.searchQuery.isNotEmpty,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      key: const Key('calendar_search_field'),
                      controller: _searchCtrl,
                      onChanged: (q) => context.read<CalendarBloc>().add(
                        CalendarSearchChanged(q),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Tìm lịch hẹn, việc hoặc địa điểm',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        suffixIcon: state.searchQuery.isNotEmpty
                            ? IconButton(
                                tooltip: 'Xóa từ khóa',
                                onPressed: () {
                                  _searchCtrl.clear();
                                  context.read<CalendarBloc>().add(
                                    const CalendarSearchChanged(''),
                                  );
                                },
                                icon: const Icon(Icons.close_rounded, size: 18),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 3. Adaptive Calendar Card (Week Strip | Month Grid | 12-Month Year Grid)
                _buildAdaptiveCalendarCard(
                  context: context,
                  c: c,
                  todayDate: todayDate,
                  isViewingToday: isViewingToday,
                  allFilteredEvents: events,
                  dateHasEvent: dateHasEvent,
                  dateHasTask: dateHasTask,
                ),
                const SizedBox(height: 12),

                // 4. ONE Unified Chronological Work Schedule Card (Events + Task Deadlines!)
                LifeOsSoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                              Icon(
                                Icons.event_note_rounded,
                                size: 19,
                                color: c.primary,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  periodHeader,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LifeOsStatusPill(
                                label: totalAgendaCount == 0
                                    ? 'Trống lịch'
                                    : '$totalAgendaCount mục',
                                tone: totalAgendaCount == 0
                                    ? LifeOsAccentTone.blue
                                    : LifeOsAccentTone.emerald,
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                key: const Key('agenda_quick_add_event_btn'),
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => showUpsertCalendarEventDialog(
                                  context,
                                  userId: widget.userId,
                                  userName: widget.userName,
                                  familyId: widget.familyId,
                                  availabilityOptIn: widget.availabilityOptIn,
                                  initialDate: _selectedDate,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.primary.withValues(alpha: 0.11),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.add_rounded,
                                        size: 16,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Thêm',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: c.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (periodEvents.isEmpty && dueTasks.isEmpty)
                        _buildEmptyAgendaPrompt(
                          context: context,
                          c: c,
                          hasAnySyncedEvents: state.events.isNotEmpty,
                          isSyncing: state.isSyncingGoogle,
                          hasActiveFilters: state.hasActiveFilters,
                        )
                      else ...[
                        // 4a. Calendar Events in Period
                        ...periodEvents.take(30).map((ev) {
                          final isShared =
                              ev.visibility ==
                              CalendarEventVisibility.sharedEvent;
                          final calGroup = groupByCalId[ev.calendarId];
                          final barColor = _parseHexColor(
                            ev.colorHex ?? calGroup?.representative.colorHex,
                            isShared ? c.secondary : c.primary,
                          );
                          final datePrefix = _viewMode == 'day'
                              ? ''
                              : '${shortDateFmt.format(ev.startsAt)} · ';
                          final timeLabel = ev.isAllDay
                              ? '${datePrefix}Cả ngày'
                              : '$datePrefix${timeFmt.format(ev.startsAt)} – ${timeFmt.format(ev.endsAt)}';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _UnifiedAgendaEventTile(
                              event: ev,
                              barColor: barColor,
                              timeRangeLabel: timeLabel,
                              scopeLabel: isShared
                                  ? 'Gia đình'
                                  : (calGroup == null || calGroup.isPrimaryGroup
                                        ? 'Cá nhân'
                                        : calGroup.displayTitle),
                              tone: isShared
                                  ? LifeOsAccentTone.emerald
                                  : LifeOsAccentTone.blue,
                              onTap: () =>
                                  context.push('/event-detail', extra: ev),
                              onEdit: () => showUpsertCalendarEventDialog(
                                context,
                                userId: widget.userId,
                                userName: widget.userName,
                                familyId: widget.familyId,
                                availabilityOptIn: widget.availabilityOptIn,
                                existingEvent: ev,
                              ),
                              onSetAlarm: () =>
                                  context.push('/event-alarm', extra: ev),
                              onDelete: () => context.read<CalendarBloc>().add(
                                CalendarEventDeleted(
                                  userId: widget.userId,
                                  familyId: widget.familyId,
                                  visibility: ev.visibility,
                                  eventId: ev.id,
                                  googleCalendarId: ev.googleCalendarId,
                                  googleEventId: ev.googleEventId,
                                ),
                              ),
                            ),
                          );
                        }),

                        // 4b. Tasks with Deadlines in Period (Unified Work View!)
                        if (dueTasks.isNotEmpty) ...[
                          if (periodEvents.isNotEmpty)
                            const Divider(height: 18),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.task_alt_rounded,
                                  size: 16,
                                  color: c.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Công việc đến hạn (${dueTasks.length})',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...dueTasks.take(15).map((task) {
                            final isDone =
                                task.status == TaskWorkflowStatus.done;
                            final dueText = _viewMode == 'day'
                                ? timeFmt.format(task.dueAt!)
                                : '${shortDateFmt.format(task.dueAt!)} ${timeFmt.format(task.dueAt!)}';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: isDone
                                    ? null
                                    : () => context.read<TaskBloc>().add(
                                        TaskStatusChanged(
                                          actorUserId: widget.userId,
                                          task: task,
                                          nextStatus: TaskWorkflowStatus.done,
                                        ),
                                      ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: c.separator),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 21,
                                        height: 21,
                                        decoration: BoxDecoration(
                                          color: isDone
                                              ? c.primary
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: c.primary,
                                            width: 1.8,
                                          ),
                                        ),
                                        child: isDone
                                            ? const Icon(
                                                Icons.check_rounded,
                                                size: 14,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          task.title,
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 13.8,
                                            fontWeight: FontWeight.w700,
                                            color: isDone
                                                ? c.textSecondary
                                                : c.textPrimary,
                                            decoration: isDone
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        dueText,
                                        style: TextStyle(
                                          fontSize: 11.8,
                                          fontWeight: FontWeight.w700,
                                          color: c.textSecondary,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 5. Compact, Unobtrusive 2-Way Google & Device Sync Footer Bar
                LifeOsSoftCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: c.separator),
                            ),
                            child: const GoogleBrandMark(size: 18),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lịch thiết bị & Google Calendar',
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                                Text(
                                  state.lastSyncReport != null
                                      ? 'Đã đồng bộ lúc ${timeFmt.format(state.lastSyncReport!.syncedAt)}'
                                      : (syncedCount > 0
                                            ? '$syncedCount sự kiện đã kết nối'
                                            : 'Chưa đồng bộ sự kiện nào'),
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        key: const Key('sync_google_calendar_button'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: state.isSyncingGoogle
                            ? null
                            : () => context.read<CalendarBloc>().add(
                                GoogleCalendarSyncRequested(
                                  userId: widget.userId,
                                  userName: widget.userName,
                                ),
                              ),
                        icon: Icon(
                          state.isSyncingGoogle
                              ? Icons.hourglass_top_rounded
                              : Icons.sync_rounded,
                          size: 16,
                        ),
                        label: Text(
                          state.isSyncingGoogle ? 'Đang tải...' : 'Đồng bộ',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdaptiveCalendarCard({
    required BuildContext context,
    required TammySemanticColors c,
    required DateTime todayDate,
    required bool isViewingToday,
    required List<CalendarEventEntity> allFilteredEvents,
    required bool Function(DateTime) dateHasEvent,
    required bool Function(DateTime) dateHasTask,
  }) {
    final headerTitle = _viewMode == 'year'
        ? 'Năm ${_focusedMonth.year}'
        : 'Tháng ${_focusedMonth.month}, ${_focusedMonth.year}';

    return LifeOsSoftCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              LifeOsHeaderCircleButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Kỳ trước',
                onTap: () => _stepPeriod(-1),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      headerTitle,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (!isViewingToday)
                      InkWell(
                        key: const Key('calendar_jump_today_button'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: _jumpToToday,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: c.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Hôm nay',
                            style: TextStyle(
                              fontSize: 11.2,
                              fontWeight: FontWeight.w800,
                              color: c.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_viewMode == 'week') ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _expandMonthInWeekMode
                      ? 'Thu gọn về thanh tuần'
                      : 'Xem lưới cả tháng',
                  onPressed: () => setState(
                    () => _expandMonthInWeekMode = !_expandMonthInWeekMode,
                  ),
                  icon: Icon(
                    _expandMonthInWeekMode
                        ? Icons.unfold_less_rounded
                        : Icons.calendar_month_outlined,
                    size: 19,
                    color: c.textSecondary,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              LifeOsHeaderCircleButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Kỳ sau',
                onTap: () => _stepPeriod(1),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Builder(
            builder: (ctx) {
              final motion = LifeOsMotionScope.of(ctx);
              final periodKey = ValueKey<String>(
                'cal_grid_${_viewMode}_${_focusedMonth.year}_${_focusedMonth.month}_'
                '${_viewMode == 'week' ? '${_selectedDate.year}_${_selectedDate.month}_${_selectedDate.day ~/ 7}_$_expandMonthInWeekMode' : ''}',
              );
              final gridBody = KeyedSubtree(
                key: periodKey,
                child: _viewMode == 'year'
                    ? _buildYearMonthsOverview(
                        c: c,
                        todayDate: todayDate,
                        allFilteredEvents: allFilteredEvents,
                      )
                    : (_viewMode == 'week' && !_expandMonthInWeekMode)
                    ? _buildCompactWeekStrip(
                        c: c,
                        todayDate: todayDate,
                        dateHasEvent: dateHasEvent,
                        dateHasTask: dateHasTask,
                      )
                    : _buildMonthGrid(
                        c: c,
                        todayDate: todayDate,
                        dateHasEvent: dateHasEvent,
                        dateHasTask: dateHasTask,
                      ),
              );
              final dur = motion.resolveDuration(LifeOsMotionTokens.standard);
              if (dur == Duration.zero) return gridBody;
              return AnimatedSwitcher(
                duration: dur,
                switchInCurve: LifeOsMotionTokens.emphasizedCurve,
                switchOutCurve: LifeOsMotionTokens.exitCurve,
                transitionBuilder: (child, anim) {
                  if (motion.isReducedMotion || child.key != periodKey) {
                    return FadeTransition(opacity: anim, child: child);
                  }
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(_periodDirection * 0.032, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: gridBody,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWeekStrip({
    required TammySemanticColors c,
    required DateTime todayDate,
    required bool Function(DateTime) dateHasEvent,
    required bool Function(DateTime) dateHasTask,
  }) {
    final monday = _selectedDate.subtract(
      Duration(days: _selectedDate.weekday - 1),
    );
    const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final chipDur = LifeOsMotionScope.of(
      context,
    ).resolveDuration(LifeOsMotionTokens.micro);

    return Row(
      children: List.generate(7, (idx) {
        final cellDate = DateTime(monday.year, monday.month, monday.day + idx);
        final isSelected = _sameDay(cellDate, _selectedDate);
        final isToday = _sameDay(cellDate, todayDate);
        final hasEv = dateHasEvent(cellDate);
        final hasTk = dateHasTask(cellDate);

        return Expanded(
          child: Semantics(
            button: true,
            selected: isSelected,
            label:
                '${labels[idx]} ngày ${cellDate.day} tháng ${cellDate.month}',
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                LifeOsMotionScope.read(context).selectionHaptic();
                setState(() {
                  _periodDirection = cellDate.isBefore(_selectedDate) ? -1 : 1;
                  _selectedDate = cellDate;
                  _focusedMonth = DateTime(cellDate.year, cellDate.month, 1);
                });
              },
              child: AnimatedContainer(
                duration: chipDur,
                curve: LifeOsMotionTokens.standardCurve,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? c.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: (!isSelected && isToday)
                      ? Border.all(color: c.primary, width: 1.4)
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labels[idx],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.88)
                            : c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${cellDate.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : c.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (hasEv)
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : c.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (hasEv && hasTk) const SizedBox(width: 3),
                          if (hasTk)
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : const Color(0xFFF59E0B),
                                shape: BoxShape.circle,
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
        );
      }),
    );
  }

  Widget _buildYearMonthsOverview({
    required TammySemanticColors c,
    required DateTime todayDate,
    required List<CalendarEventEntity> allFilteredEvents,
  }) {
    final year = _focusedMonth.year;
    final monthCounts = List<int>.generate(12, (idx) {
      final m = idx + 1;
      final s = DateTime(year, m, 1);
      final e = DateTime(
        year,
        m + 1,
        1,
      ).subtract(const Duration(milliseconds: 1));
      return _eventsInWindow(allFilteredEvents, s, e).length;
    });

    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: List.generate(4, (col) {
                final mIdx = row * 4 + col;
                final monthNum = mIdx + 1;
                final count = monthCounts[mIdx];
                final isCurrentMonth =
                    todayDate.year == year && todayDate.month == monthNum;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      key: Key('year_month_cell_$monthNum'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        _focusedMonth = DateTime(year, monthNum, 1);
                        _selectedDate = DateTime(year, monthNum, 1);
                        _viewMode = 'month';
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 9,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: count > 0 ? c.primarySubtle : c.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrentMonth ? c.primary : c.separator,
                            width: isCurrentMonth ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Thg $monthNum',
                                style: TextStyle(
                                  fontSize: 12.2,
                                  fontWeight: FontWeight.w800,
                                  color: isCurrentMonth
                                      ? c.primary
                                      : c.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                count > 0 ? '$count lịch' : 'Trống',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: count > 0
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: count > 0
                                      ? c.primary
                                      : c.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildMonthGrid({
    required TammySemanticColors c,
    required DateTime todayDate,
    required bool Function(DateTime) dateHasEvent,
    required bool Function(DateTime) dateHasTask,
  }) {
    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startOffset = firstOfMonth.weekday - 1;
    final gridStart = firstOfMonth.subtract(Duration(days: startOffset));
    final sixthRowStart = gridStart.add(const Duration(days: 35));
    final weekRows = sixthRowStart.month == _focusedMonth.month ? 6 : 5;

    return Column(
      children: [
        Row(
          children: const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
              .map(
                (lbl) => Expanded(
                  child: Center(
                    child: Text(
                      lbl,
                      style: TextStyle(
                        fontSize: 11.8,
                        fontWeight: FontWeight.w700,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        for (var week = 0; week < weekRows; week++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              children: List.generate(7, (dow) {
                final cellDate = gridStart.add(Duration(days: week * 7 + dow));
                final inMonth = cellDate.month == _focusedMonth.month;
                final isSelected = _sameDay(cellDate, _selectedDate);
                final isToday = _sameDay(cellDate, todayDate);
                final hasEv = dateHasEvent(cellDate);
                final hasTk = dateHasTask(cellDate);

                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      _selectedDate = cellDate;
                      if (cellDate.month != _focusedMonth.month ||
                          cellDate.year != _focusedMonth.year) {
                        _focusedMonth = DateTime(
                          cellDate.year,
                          cellDate.month,
                          1,
                        );
                      }
                    }),
                    child: Container(
                      height: 39,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? c.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: (!isSelected && isToday)
                            ? Border.all(color: c.primary, width: 1.4)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${cellDate.day}',
                            style: TextStyle(
                              fontSize: 13.2,
                              fontWeight: (isSelected || isToday)
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : inMonth
                                  ? (isToday ? c.primary : c.textPrimary)
                                  : c.textSecondary.withValues(alpha: 0.42),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (hasEv || hasTk) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (hasEv)
                                  Container(
                                    width: 4.5,
                                    height: 4.5,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white
                                          : c.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                if (hasEv && hasTk) const SizedBox(width: 2.5),
                                if (hasTk)
                                  Container(
                                    width: 4.5,
                                    height: 4.5,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white.withValues(alpha: 0.85)
                                          : const Color(0xFFF59E0B),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyAgendaPrompt({
    required BuildContext context,
    required TammySemanticColors c,
    required bool hasAnySyncedEvents,
    required bool isSyncing,
    bool hasActiveFilters = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasActiveFilters
                ? 'Không có lịch hẹn khớp bộ lọc / tìm kiếm'
                : (hasAnySyncedEvents
                      ? 'Khoảng thời gian này đang trống lịch'
                      : 'Chưa có lịch hẹn hoặc công việc nào'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (hasActiveFilters)
                FilledButton.tonalIcon(
                  key: const Key('calendar_reset_all_filters_btn'),
                  onPressed: () {
                    _searchCtrl.clear();
                    context.read<CalendarBloc>().add(
                      CalendarFiltersReset(
                        userId: widget.userId,
                        enableHiddenUserCalendars: true,
                      ),
                    );
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                  label: const Text('Xóa bộ lọc & tìm kiếm'),
                ),
              if (!hasAnySyncedEvents && !hasActiveFilters)
                FilledButton.icon(
                  key: const Key('deck_sync_calendar_btn'),
                  onPressed: isSyncing
                      ? null
                      : () => context.read<CalendarBloc>().add(
                          GoogleCalendarSyncRequested(
                            userId: widget.userId,
                            userName: widget.userName,
                          ),
                        ),
                  icon: const Icon(Icons.sync_rounded, size: 17),
                  label: Text(
                    isSyncing ? 'Đang đồng bộ...' : 'Đồng bộ Lịch ngay',
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => showUpsertCalendarEventDialog(
                  context,
                  userId: widget.userId,
                  userName: widget.userName,
                  familyId: widget.familyId,
                  availabilityOptIn: widget.availabilityOptIn,
                  initialDate: _selectedDate,
                ),
                icon: const Icon(Icons.event_available_rounded, size: 17),
                label: const Text('Thêm lịch hẹn'),
              ),
              OutlinedButton.icon(
                onPressed: () => showUnifiedCreateTaskDialog(
                  context,
                  userId: widget.userId,
                  userName: widget.userName,
                  familyId: widget.familyId,
                  members: widget.familyMembers,
                  initialDueDate: _selectedDate,
                ),
                icon: const Icon(Icons.add_task_rounded, size: 17),
                label: const Text('Giao việc ngày này'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnifiedAgendaEventTile extends StatelessWidget {
  final CalendarEventEntity event;
  final Color barColor;
  final String timeRangeLabel;
  final String scopeLabel;
  final LifeOsAccentTone tone;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onSetAlarm;
  final VoidCallback onDelete;

  const _UnifiedAgendaEventTile({
    required this.event,
    required this.barColor,
    required this.timeRangeLabel,
    required this.scopeLabel,
    required this.tone,
    required this.onTap,
    required this.onEdit,
    required this.onSetAlarm,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.separator),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.22,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: c.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                timeRangeLabel,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: c.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (event.location != null &&
                            event.location!.trim().isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 13,
                                color: c.textSecondary,
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  event.location!.trim(),
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 11.8,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        LifeOsStatusPill(label: scopeLabel, tone: tone),
                        if (event.isRecurring)
                          Text(
                            '🔁 ${event.recurrence.humanReadableVi}',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 11.2,
                              fontWeight: FontWeight.w700,
                              color: c.primary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('event_menu_${event.id}'),
                tooltip: 'Tùy chọn lịch hẹn',
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 19,
                  color: c.textSecondary,
                ),
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      onEdit();
                    case 'alarm':
                      onSetAlarm();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Sửa lịch hẹn'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'alarm',
                    child: Row(
                      children: [
                        Icon(Icons.alarm_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Đặt chuông báo thức'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: c.error,
                        ),
                        const SizedBox(width: 8),
                        Text('Xóa sự kiện', style: TextStyle(color: c.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progressive-Disclosure Create & Update Event Dialog: fast 3-second basic entry
/// with expandable details (Location, Recurrence, Calendar & Google Sync).
Future<void> showUpsertCalendarEventDialog(
  BuildContext context, {
  required String userId,
  required String userName,
  String? familyId,
  required bool availabilityOptIn,
  CalendarEventEntity? existingEvent,
  DateTime? initialDate,
}) async {
  final calBloc = context.read<CalendarBloc>();
  final calendars = calBloc.state.calendars;
  await showDialog<void>(
    context: context,
    builder: (_) => _UpsertCalendarEventDialog(
      calBloc: calBloc,
      calendars: calendars,
      userId: userId,
      userName: userName,
      familyId: familyId,
      availabilityOptIn: availabilityOptIn,
      existingEvent: existingEvent,
      initialDate: initialDate,
    ),
  );
}

class _UpsertCalendarEventDialog extends StatefulWidget {
  final CalendarBloc calBloc;
  final List<ManagedCalendarEntity> calendars;
  final String userId;
  final String userName;
  final String? familyId;
  final bool availabilityOptIn;
  final CalendarEventEntity? existingEvent;
  final DateTime? initialDate;

  const _UpsertCalendarEventDialog({
    required this.calBloc,
    required this.calendars,
    required this.userId,
    required this.userName,
    required this.familyId,
    required this.availabilityOptIn,
    required this.existingEvent,
    required this.initialDate,
  });

  @override
  State<_UpsertCalendarEventDialog> createState() =>
      _UpsertCalendarEventDialogState();
}

class _UpsertCalendarEventDialogState
    extends State<_UpsertCalendarEventDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _locCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _intervalCtrl;
  late final TextEditingController _countCtrl;

  late CalendarEventVisibility _visibility;
  late String _selectedCalendarId;
  late bool _isAllDay;
  late DateTime _startsAt;
  late DateTime _endsAt;
  late int _reminderMinutes;
  late bool _syncToGoogle;
  late RecurrenceFrequency _frequency;
  late final Set<String> _selectedWeekDays;
  late bool _showAdvanced;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEvent;
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _locCtrl = TextEditingController(text: existing?.location ?? '');
    _descCtrl = TextEditingController(text: existing?.description ?? '');
    _intervalCtrl = TextEditingController(
      text: '${existing?.recurrence.interval ?? 1}',
    );
    _countCtrl = TextEditingController(
      text: existing?.recurrence.count?.toString() ?? '',
    );

    _visibility = existing?.visibility ?? CalendarEventVisibility.privateEvent;
    final writableGroups = CalendarListDeduplicator.group(
      widget.calendars,
    ).where((g) => !g.isReadOnly).toList();
    final matchedExistingGroup = existing?.calendarId != null
        ? writableGroups
              .where((g) => g.matchesCalendarId(existing!.calendarId))
              .firstOrNull
        : null;
    _selectedCalendarId =
        matchedExistingGroup?.canonicalId ??
        (writableGroups.isNotEmpty
            ? writableGroups.first.canonicalId
            : 'primary');

    final now = DateTime.now();
    final targetDay = widget.initialDate ?? now;
    final startHour = (now.hour + 1).clamp(8, 22);
    final baseStart = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      startHour,
      0,
    );
    final baseEnd = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      (startHour + 1).clamp(9, 23),
      30,
    );

    _isAllDay = existing?.isAllDay ?? false;
    _startsAt = existing?.startsAt ?? baseStart;
    _endsAt = existing?.endsAt ?? baseEnd;
    _reminderMinutes = existing?.reminderMinutesBefore ?? 30;
    _syncToGoogle = existing != null
        ? (existing.isLinkedWithGoogle ||
              existing.isLinkedWithDeviceCalendar ||
              existing.syncStatus == CalendarSyncStatus.pendingUpload)
        : true;

    _frequency = existing?.recurrence.frequency ?? RecurrenceFrequency.none;
    _selectedWeekDays = <String>{
      ...(existing?.recurrence.byWeekDays ?? const <String>[]),
    };

    _showAdvanced =
        existing != null &&
        ((existing.location ?? '').isNotEmpty ||
            (existing.description ?? '').isNotEmpty ||
            existing.isRecurring);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locCtrl.dispose();
    _descCtrl.dispose();
    _intervalCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _startsAt : _endsAt;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) return;

    if (_isAllDay) {
      setState(() {
        if (isStart) {
          _startsAt = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            0,
            0,
          );
          if (_endsAt.isBefore(_startsAt)) {
            _endsAt = DateTime(
              pickedDate.year,
              pickedDate.month,
              pickedDate.day,
              23,
              59,
            );
          }
        } else {
          _endsAt = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            23,
            59,
          );
        }
      });
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !mounted) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() {
      if (isStart) {
        _startsAt = combined;
        if (!_endsAt.isAfter(_startsAt)) {
          _endsAt = _startsAt.add(const Duration(hours: 1));
        }
      } else {
        _endsAt = combined;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingEvent != null;
    final dtLabelFmt = DateFormat('dd/MM HH:mm');
    final dLabelFmt = DateFormat('dd/MM/yyyy');

    const quickReminders = <(int mins, String label)>[
      (0, 'Không nhắc'),
      (15, '15 phút'),
      (30, '30 phút'),
      (60, '1 giờ'),
      (1440, '1 ngày'),
    ];

    return AlertDialog(
      title: Text(isEditing ? 'Sửa lịch hẹn' : 'Thêm lịch hẹn mới'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('event_title_field'),
              controller: _titleCtrl,
              autofocus: !isEditing,
              decoration: const InputDecoration(
                labelText: 'Tên sự kiện / Lịch làm việc *',
                hintText: 'VD: Họp nhóm 9h / Khám răng / Đóng tiền nhà',
                prefixIcon: Icon(Icons.event_rounded),
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Diễn ra cả ngày'),
              value: _isAllDay,
              onChanged: (v) => setState(() => _isAllDay = v),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDateTime(isStart: true),
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _isAllDay
                            ? dLabelFmt.format(_startsAt)
                            : dtLabelFmt.format(_startsAt),
                        style: const TextStyle(
                          fontSize: 12.2,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDateTime(isStart: false),
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _isAllDay
                            ? dLabelFmt.format(_endsAt)
                            : dtLabelFmt.format(_endsAt),
                        style: const TextStyle(
                          fontSize: 12.2,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nhắc trước giờ hẹn',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: quickReminders.map((r) {
                return ChoiceChip(
                  label: Text(r.$2),
                  selected: _reminderMinutes == r.$1,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _reminderMinutes = r.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),

            Builder(
              builder: (context) {
                final writableGroups = CalendarListDeduplicator.group(
                  widget.calendars,
                ).where((g) => !g.isReadOnly).toList();
                final hasMultipleWritable = writableGroups.length > 1;
                final safeSelectedId =
                    writableGroups.any(
                      (g) => g.canonicalId == _selectedCalendarId,
                    )
                    ? _selectedCalendarId
                    : (writableGroups.isNotEmpty
                          ? writableGroups.first.canonicalId
                          : 'primary');

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Progressive Disclosure Toggle for Advanced Options
                    InkWell(
                      key: const Key('toggle_event_advanced_options'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () =>
                          setState(() => _showAdvanced = !_showAdvanced),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              _showAdvanced
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _showAdvanced
                                    ? 'Ẩn tùy chọn chi tiết'
                                    : (hasMultipleWritable
                                          ? 'Thêm địa điểm, lặp lại & bộ lịch'
                                          : 'Thêm địa điểm & lặp lại'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showAdvanced) ...[
                      const SizedBox(height: 6),
                      TextField(
                        key: const Key('event_location_field'),
                        controller: _locCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Địa điểm / Link họp trực tuyến',
                          hintText: 'Phòng họp / Google Meet / Quận 1',
                          prefixIcon: Icon(Icons.place_outlined),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (!isEditing && widget.familyId != null) ...[
                        DropdownButtonFormField<CalendarEventVisibility>(
                          isExpanded: true,
                          initialValue: _visibility,
                          decoration: const InputDecoration(
                            labelText: 'Phạm vi hiển thị',
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: CalendarEventVisibility.privateEvent,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text('Lịch cá nhân của tôi'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: CalendarEventVisibility.sharedEvent,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text('Chia sẻ với Gia đình / Nhóm'),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _visibility = v);
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      if (_visibility == CalendarEventVisibility.privateEvent &&
                          hasMultipleWritable) ...[
                        DropdownButtonFormField<String>(
                          key: const Key('event_calendar_dropdown'),
                          isExpanded: true,
                          initialValue: safeSelectedId,
                          decoration: const InputDecoration(
                            labelText: 'Thuộc bộ lịch',
                            isDense: true,
                          ),
                          items: writableGroups
                              .map(
                                (g) => DropdownMenuItem(
                                  value: g.canonicalId,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(g.displayTitle),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _selectedCalendarId = v);
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ],
                );
              },
            ),
            if (_showAdvanced) ...[
              DropdownButtonFormField<RecurrenceFrequency>(
                key: const Key('event_recurrence_dropdown'),
                isExpanded: true,
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Lặp lại tự động',
                  prefixIcon: Icon(Icons.repeat_rounded),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: RecurrenceFrequency.none,
                    child: Text('Không lặp'),
                  ),
                  DropdownMenuItem(
                    value: RecurrenceFrequency.daily,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Hằng ngày'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: RecurrenceFrequency.weekly,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Hằng tuần theo thứ'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: RecurrenceFrequency.monthly,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Hằng tháng'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: RecurrenceFrequency.yearly,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Hằng năm (Sinh nhật / Kỷ niệm)'),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _frequency = v;
                      if (_frequency == RecurrenceFrequency.weekly &&
                          _selectedWeekDays.isEmpty) {
                        _selectedWeekDays.add(
                          CalendarRecurrenceRule.weekDayCodeForDate(_startsAt),
                        );
                      }
                    });
                  }
                },
              ),
              if (_frequency != RecurrenceFrequency.none) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _intervalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Mỗi (chu kỳ)',
                          hintText: '1',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _countCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Số lần (tùy chọn)',
                          hintText: 'Không giới hạn',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_frequency == RecurrenceFrequency.weekly) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: CalendarRecurrenceRule.allWeekDayCodes.map((
                      code,
                    ) {
                      final selected = _selectedWeekDays.contains(code);
                      return FilterChip(
                        label: Text(
                          CalendarRecurrenceRule.weekDayLabelVi(code),
                        ),
                        selected: selected,
                        visualDensity: VisualDensity.compact,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedWeekDays.add(code);
                            } else if (_selectedWeekDays.length > 1) {
                              _selectedWeekDays.remove(code);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('event_description_field'),
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú chi tiết',
                  isDense: true,
                ),
              ),
              if (_visibility == CalendarEventVisibility.privateEvent)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Đồng bộ Google & Lịch điện thoại'),
                  value: _syncToGoogle,
                  onChanged: (v) => setState(() => _syncToGoogle = v),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          key: const Key('submit_event_dialog_button'),
          onPressed: () {
            final parsedInterval = int.tryParse(_intervalCtrl.text.trim()) ?? 1;
            final parsedCount = int.tryParse(_countCtrl.text.trim());
            final rule = CalendarRecurrenceRule(
              frequency: _frequency,
              interval: parsedInterval < 1 ? 1 : parsedInterval,
              byWeekDays: _frequency == RecurrenceFrequency.weekly
                  ? _selectedWeekDays.toList()
                  : const <String>[],
              count: (parsedCount != null && parsedCount > 0)
                  ? parsedCount
                  : null,
            );

            if (isEditing) {
              widget.calBloc.add(
                CalendarEventUpdated(
                  UpdateCalendarEventParams(
                    userId: widget.userId,
                    userName: widget.userName,
                    existingEvent: widget.existingEvent!,
                    title: _titleCtrl.text,
                    description: _descCtrl.text,
                    location: _locCtrl.text,
                    startsAt: _startsAt,
                    endsAt: _endsAt,
                    isAllDay: _isAllDay,
                    calendarId: _selectedCalendarId,
                    reminderMinutesBefore: _reminderMinutes,
                    recurrence: rule,
                    publishBusySlot: widget.availabilityOptIn,
                    syncToGoogle: _syncToGoogle,
                  ),
                ),
              );
            } else {
              widget.calBloc.add(
                CalendarEventCreated(
                  CreateCalendarEventParams(
                    userId: widget.userId,
                    userName: widget.userName,
                    calendarId: _selectedCalendarId,
                    familyId: widget.familyId,
                    visibility: _visibility,
                    title: _titleCtrl.text,
                    description: _descCtrl.text,
                    location: _locCtrl.text,
                    startsAt: _startsAt,
                    endsAt: _endsAt,
                    isAllDay: _isAllDay,
                    reminderMinutesBefore: _reminderMinutes,
                    recurrence: rule,
                    publishBusySlot: widget.availabilityOptIn,
                    syncToGoogle: _syncToGoogle,
                  ),
                ),
              );
            }
            Navigator.of(context).pop();
          },
          icon: Icon(
            isEditing ? Icons.save_outlined : Icons.check_rounded,
            size: 18,
          ),
          label: Text(isEditing ? 'Lưu thay đổi' : 'Lưu lịch hẹn'),
        ),
      ],
    );
  }
}

class _PlanningHabitsAndNotesTabView extends StatelessWidget {
  final String userId;

  const _PlanningHabitsAndNotesTabView({required this.userId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('planning_tools_hub_list_view'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.dockClearance,
          ),
          children: [
            const LifeOsSectionHeader(
              title: 'Báo thức & Tập trung',
              tone: LifeOsAccentTone.amber,
              padding: EdgeInsets.only(top: 6, bottom: 8, left: 2, right: 2),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('planning_hub_alarm_tile'),
                      icon: Icons.alarm_on_rounded,
                      tone: LifeOsAccentTone.blue,
                      title: 'Báo thức lịch',
                      subtitle: 'Chuông nhắc đúng giờ',
                      onTap: () => context.push('/event-alarm'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('planning_hub_habits_tile'),
                      icon: Icons.local_fire_department_outlined,
                      tone: LifeOsAccentTone.amber,
                      title: 'Pomodoro & Nước',
                      subtitle: 'Đồng hồ tập trung',
                      onTap: () => context.push('/habits-focus'),
                    ),
                  ),
                ],
              ),
            ),
            const LifeOsSectionHeader(
              title: 'Ghi chú & Bộ lịch',
              tone: LifeOsAccentTone.purple,
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('planning_hub_notes_tile'),
                      icon: Icons.sticky_note_2_outlined,
                      tone: LifeOsAccentTone.purple,
                      title: 'Sổ tay & Ghi chú',
                      subtitle: 'Ghi chú & mã số ghim',
                      onTap: () => context.push('/smart-notes-hub'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('planning_hub_new_calendar_tile'),
                      icon: Icons.layers_outlined,
                      tone: LifeOsAccentTone.emerald,
                      title: 'Bộ lịch hiển thị',
                      subtitle: 'Ẩn/hiện & phân màu',
                      onTap: () =>
                          showManageCalendarsSheet(context, userId: userId),
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
