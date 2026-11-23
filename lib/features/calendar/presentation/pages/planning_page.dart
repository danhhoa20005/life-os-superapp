import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/pages/auth_pages.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/domain/repositories/task_repository.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
import '../../../tasks/presentation/pages/tasks_board_page.dart';
import '../../domain/entities/calendar_entities.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../bloc/calendar_bloc.dart';

class PlanningPage extends StatelessWidget {
  const PlanningPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final activeFamily = context.watch<FamilyBloc>().state.activeFamily;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<CalendarBloc, CalendarState>(
          listenWhen: (p, c) => p.failure != c.failure || p.message != c.message,
          listener: (context, state) {
            if (state.failure != null) {
              LifeOsTopToast.fromSnackBar(context, SnackBar(content: Text('⚠ ${state.failure!.message}')));
            } else if (state.message != null) {
              LifeOsTopToast.fromSnackBar(context, SnackBar(content: Text('✓ ${state.message!}')));
            }
          },
        ),
        BlocListener<TaskBloc, TaskState>(
          listenWhen: (p, c) => p.failure != c.failure || p.message != c.message,
          listener: (context, state) {
            if (state.failure != null) {
              LifeOsTopToast.fromSnackBar(context, SnackBar(content: Text('⚠ ${state.failure!.message}')));
            } else if (state.message != null) {
              LifeOsTopToast.fromSnackBar(context, SnackBar(content: Text('✓ ${state.message!}')));
            }
          },
        ),
      ],
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  LifeOsTopBrandHeader(
                    title: 'Lịch & Việc',
                    extraBrandActions: [
                      LifeOsHeaderCircleButton(
                        buttonKey: const Key('open_create_event_button'),
                        icon: Icons.edit_calendar_rounded,
                        tooltip: 'Thêm sự kiện lịch mới',
                        onTap: () => showUpsertCalendarEventDialog(
                          context,
                          userId: user.id,
                          userName: user.fullName,
                          familyId: activeFamily?.id,
                          availabilityOptIn: user.availabilityOptIn,
                        ),
                      ),
                    ],
                    trailingAction: FilledButton.icon(
                      onPressed: () => _showCreateTaskDialog(
                        context,
                        userId: user.id,
                        userName: user.fullName,
                        familyId: activeFamily?.id,
                        members: activeFamily?.members ?? const [],
                      ),
                      icon: const Icon(Icons.add_task_rounded, size: 18),
                      label: const Text('Giao việc'),
                    ),
                  ),
                  const ProPillTabContainer(
                    tabBar: TabBar(
                      labelPadding: EdgeInsets.symmetric(horizontal: 6),
                      tabs: [
                        Tab(
                          key: Key('planning_calendar_tab'),
                          text: 'Lịch trình',
                        ),
                        Tab(
                          key: Key('planning_tasks_tab'),
                          text: 'Việc làm',
                        ),
                        Tab(
                          key: Key('planning_tools_tab'),
                          text: 'Thói quen & Sổ',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _GoogleAndLifeOsCalendarTab(
                          userId: user.id,
                          userName: user.fullName,
                          familyId: activeFamily?.id,
                          availabilityOptIn: user.availabilityOptIn,
                        ),
                        UnifiedTasksBoardView(userId: user.id),
                        const _PlanningHabitsAndNotesTabView(),
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

  Future<void> _showCreateTaskDialog(
    BuildContext context, {
    required String userId,
    required String userName,
    String? familyId,
    required List<dynamic> members,
  }) async {
    final titleCtrl = TextEditingController();
    var assigneeId = userId;
    var assigneeName = userName;
    var recurrence = TaskRecurrence.none;
    final taskBloc = context.read<TaskBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Giao Nhiệm vụ (Cơ chế Đồng thuận)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Nội dung công việc'),
                const SizedBox(height: 6),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(hintText: 'VD: Đón bé lúc 17h / Đóng tiền điện'),
                ),
                if (members.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Giao cho thành viên'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: assigneeId,
                    items: members
                        .map<DropdownMenuItem<String>>(
                          (m) => DropdownMenuItem(
                            value: m.userId as String,
                            child: Text(
                              '${m.fullName} (${m.userId == userId ? "Bản thân" : "Cần đồng ý"})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final found = members.where((m) => m.userId == val).first;
                        setDialogState(() {
                          assigneeId = val;
                          assigneeName = found.fullName as String;
                        });
                      }
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                const Text('Chu kỳ lặp lại'),
                const SizedBox(height: 6),
                DropdownButtonFormField<TaskRecurrence>(
                  isExpanded: true,
                  initialValue: recurrence,
                  items: const [
                    DropdownMenuItem(value: TaskRecurrence.none, child: Text('Không lặp')),
                    DropdownMenuItem(value: TaskRecurrence.daily, child: Text('Hằng ngày')),
                    DropdownMenuItem(value: TaskRecurrence.weekly, child: Text('Hằng tuần')),
                    DropdownMenuItem(value: TaskRecurrence.monthly, child: Text('Hằng tháng')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => recurrence = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                taskBloc.add(
                  TaskCreateSubmitted(
                    CreateTaskParams(
                      createdBy: userId,
                      creatorName: userName,
                      familyId: familyId,
                      assigneeId: assigneeId,
                      assigneeName: assigneeName,
                      title: titleCtrl.text,
                      dueAt: DateTime.now().add(const Duration(days: 1)),
                      recurrence: recurrence,
                    ),
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Tạo nhiệm vụ'),
            ),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
  }
}

class _GoogleAndLifeOsCalendarTab extends StatefulWidget {
  final String userId;
  final String userName;
  final String? familyId;
  final bool availabilityOptIn;

  const _GoogleAndLifeOsCalendarTab({
    required this.userId,
    required this.userName,
    required this.familyId,
    required this.availabilityOptIn,
  });

  @override
  State<_GoogleAndLifeOsCalendarTab> createState() => _GoogleAndLifeOsCalendarTabState();
}

class _GoogleAndLifeOsCalendarTabState extends State<_GoogleAndLifeOsCalendarTab>
    with WidgetsBindingObserver {
  String get userId => widget.userId;
  String get userName => widget.userName;
  String? get familyId => widget.familyId;
  bool get availabilityOptIn => widget.availabilityOptIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<CalendarBloc>().add(
            GoogleCalendarSyncRequested(
              userId: userId,
              userName: userName,
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

  Future<void> _showCreateCalendarDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var selectedColor = '#0B7A2A';
    var createOnGoogle = false;
    final calBloc = context.read<CalendarBloc>();

    const palette = <String>[
      '#0B7A2A',
      '#1971C2',
      '#6741D9',
      '#D9480F',
      '#C92A2A',
      '#087F5B',
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Tạo Bộ Lịch Mới'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('new_calendar_name_field'),
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên bộ lịch',
                    hintText: 'VD: Lịch Dự án / Lịch Tập Gym / Học tập',
                    prefixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả (Tùy chọn)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Màu nhận diện lịch', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: palette.map((hex) {
                    final color = _parseHexColor(hex, Colors.green);
                    final isPicked = selectedColor == hex;
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setModalState(() => selectedColor = hex),
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
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đồng bộ lên Google Calendar'),
                  value: createOnGoogle,
                  onChanged: (v) => setModalState(() => createOnGoogle = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton.icon(
              key: const Key('submit_create_calendar_button'),
              onPressed: () {
                calBloc.add(
                  ManagedCalendarCreateSubmitted(
                    CreateManagedCalendarParams(
                      userId: userId,
                      summary: nameCtrl.text,
                      description: descCtrl.text,
                      colorHex: selectedColor,
                      createOnGoogle: createOnGoogle,
                    ),
                  ),
                );
                Navigator.of(ctx).pop();
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tạo lịch'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _showOAuthTokenSyncDialog(BuildContext context) async {
    final tokenCtrl = TextEditingController();
    final calBloc = context.read<CalendarBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kết nối thủ công (nâng cao)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ứng dụng tự kết nối qua tài khoản Google. Chỉ nhập mã bên dưới nếu cần kiểm thử thủ công:',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: tokenCtrl,
              decoration: const InputDecoration(
                labelText: 'Mã kết nối Google (tùy chọn)',
                hintText: 'ya29...',
                prefixIcon: Icon(Icons.key_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Đóng')),
          FilledButton.icon(
            onPressed: () {
              final manual = tokenCtrl.text.trim();
              Navigator.of(ctx).pop();
              calBloc.add(
                GoogleCalendarSyncRequested(
                  userId: userId,
                  userName: userName,
                  interactive: true,
                  manualAccessTokenOverride: manual.isEmpty ? null : manual,
                ),
              );
            },
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Đồng bộ ngay'),
          ),
        ],
      ),
    );
    tokenCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final dtFmt = DateFormat('dd/MM/yyyy HH:mm');
    final dayFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');

    return BlocBuilder<CalendarBloc, CalendarState>(
      builder: (context, state) {
        final calById = <String, ManagedCalendarEntity>{
          for (final cal in state.calendars) cal.id: cal,
        };
        final syncedCount =
            state.events.where((e) => e.syncStatus == CalendarSyncStatus.synced).length;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: ListView(
              key: const Key('calendar_events_list_view'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                // 0. Unified LifeOS Month Grid + Day/Week/Month Real Timeline (Zero Mock Data)
                _LifeOsInteractiveCalendarDeck(
                  events: state.filteredEvents,
                  isSyncing: state.isSyncingGoogle,
                  onSyncRequested: () => context.read<CalendarBloc>().add(
                        GoogleCalendarSyncRequested(
                          userId: userId,
                          userName: userName,
                        ),
                      ),
                  onAddEventForDate: (selectedDate) => showUpsertCalendarEventDialog(
                    context,
                    userId: userId,
                    userName: userName,
                    familyId: familyId,
                    availabilityOptIn: availabilityOptIn,
                    initialDate: selectedDate,
                  ),
                ),

                // Clearly Separated Section: Đồng bộ Google Calendar & Lịch máy
                const LifeOsSectionHeader(
                  title: 'Đồng bộ Lịch & Nguồn sự kiện',
                  tone: LifeOsAccentTone.blue,
                  padding: EdgeInsets.only(top: 12, bottom: 6, left: 2, right: 2),
                ),

                // 1. Device & Google Calendar 2-Way Sync Card
                LifeOsMintHeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: c.separator),
                            ),
                            child: const GoogleBrandMark(size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Đồng bộ Lịch thiết bị & Google Calendar',
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  state.lastSyncReport != null
                                      ? 'Cập nhật lúc ${timeFmt.format(state.lastSyncReport!.syncedAt)} · ${state.calendars.length} bộ lịch · ${state.events.length} sự kiện'
                                      : '${state.calendars.length} bộ lịch · $syncedCount sự kiện đã đồng bộ',
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Tùy chọn nâng cao',
                            onPressed: () => _showOAuthTokenSyncDialog(context),
                            icon: Icon(Icons.tune_rounded, color: c.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const Key('sync_google_calendar_button'),
                            onPressed: state.isSyncingGoogle
                                ? null
                                : () => context.read<CalendarBloc>().add(
                                      GoogleCalendarSyncRequested(
                                        userId: userId,
                                        userName: userName,
                                      ),
                                    ),
                            icon: state.isSyncingGoogle
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.sync_rounded, size: 18),
                            label: Text(
                              state.isSyncingGoogle
                                  ? 'Đang đồng bộ Lịch...'
                                  : 'Đồng bộ Lịch ngay',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _showCreateCalendarDialog(context),
                            icon: const Icon(Icons.create_new_folder_outlined, size: 17),
                            label: const Text('Tạo bộ lịch'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => showUpsertCalendarEventDialog(
                              context,
                              userId: userId,
                              userName: userName,
                              familyId: familyId,
                              availabilityOptIn: availabilityOptIn,
                            ),
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
                            label: const Text('Thêm sự kiện / Lịch lặp'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // 2. Multi-Calendar Selector & Management Strip
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Danh sách Bộ lịch (${state.calendars.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    TextButton.icon(
                      key: const Key('create_calendar_button'),
                      onPressed: () => _showCreateCalendarDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Thêm lịch'),
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('Tất cả lịch'),
                          selected: state.selectedCalendarId == null,
                          onSelected: (_) => context
                              .read<CalendarBloc>()
                              .add(const CalendarFilterSelected(null)),
                        ),
                      ),
                      if (familyId != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(Icons.groups_rounded, size: 16, color: c.secondary),
                            label: const Text('Lịch Chung Gia đình'),
                            selected: state.selectedCalendarId == '__family__',
                            onSelected: (_) => context
                                .read<CalendarBloc>()
                                .add(const CalendarFilterSelected('__family__')),
                          ),
                        ),
                      ...state.calendars.map((cal) {
                        final dotColor = _parseHexColor(cal.colorHex, c.primary);
                        final isFiltered = state.selectedCalendarId == cal.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InputChip(
                            avatar: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            label: Text(
                              cal.isGoogleSynced
                                  ? '${cal.summary} · GCal'
                                  : (cal.isDeviceSynced ? '${cal.summary} · Máy' : cal.summary),
                            ),
                            selected: isFiltered,
                            onSelected: (_) => context.read<CalendarBloc>().add(
                                  CalendarFilterSelected(isFiltered ? null : cal.id),
                                ),
                            onDeleted: cal.isPrimary
                                ? null
                                : () => context.read<CalendarBloc>().add(
                                      ManagedCalendarDeleteSubmitted(
                                        userId: userId,
                                        calendar: cal,
                                      ),
                                    ),
                            deleteButtonTooltipMessage: 'Xóa bộ lịch này',
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),

                // 3. Search Events Bar
                TextField(
                  key: const Key('calendar_search_field'),
                  onChanged: (q) =>
                      context.read<CalendarBloc>().add(CalendarSearchChanged(q)),
                  decoration: const InputDecoration(
                    labelText: 'Tìm sự kiện theo tiêu đề, địa điểm hoặc ghi chú',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // 4. Events & Recurring Series List
                if (state.filteredEvents.isEmpty)
                  EmptyStateView(
                    icon: Icons.sync_rounded,
                    imageAsset: AppAssets.planningAssetsIllustration,
                    title: 'Chưa có sự kiện nào trong danh sách',
                    subtitle:
                        'Nhấn "Đồng bộ Lịch ngay" để tải lịch trình thật từ điện thoại & Google Calendar, hoặc tạo sự kiện mới.',
                    actionLabel: 'Đồng bộ Lịch ngay',
                    onAction: () => context.read<CalendarBloc>().add(
                          GoogleCalendarSyncRequested(
                            userId: userId,
                            userName: userName,
                          ),
                        ),
                  )
                else
                  ...state.filteredEvents.map((ev) {
                    final isPrivate = ev.visibility == CalendarEventVisibility.privateEvent;
                    final calMeta = calById[ev.calendarId];
                    final accent = _parseHexColor(
                      ev.colorHex ?? calMeta?.colorHex,
                      isPrivate ? c.primary : c.secondary,
                    );
                    final timeText = ev.isAllDay
                        ? '${dayFmt.format(ev.startsAt)} · Cả ngày'
                        : '${dtFmt.format(ev.startsAt)} – ${timeFmt.format(ev.endsAt)}';

                    final upcomingInstances = ev.isRecurring
                        ? ev.recurrence.expandOccurrences(
                            firstStart: ev.startsAt,
                            windowStart: DateTime.now().subtract(const Duration(days: 1)),
                            windowEnd: DateTime.now().add(const Duration(days: 60)),
                            maxInstances: 3,
                          )
                        : const <DateTime>[];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ev.title,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          timeText,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    key: Key('edit_event_${ev.id}'),
                                    tooltip: 'Cập nhật sự kiện',
                                    onPressed: () => showUpsertCalendarEventDialog(
                                      context,
                                      userId: userId,
                                      userName: userName,
                                      familyId: familyId,
                                      availabilityOptIn: availabilityOptIn,
                                      existingEvent: ev,
                                    ),
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                  ),
                                  IconButton(
                                    key: Key('delete_event_${ev.id}'),
                                    tooltip: 'Xóa sự kiện',
                                    onPressed: () => context.read<CalendarBloc>().add(
                                          CalendarEventDeleted(
                                            userId: userId,
                                            familyId: familyId,
                                            visibility: ev.visibility,
                                            eventId: ev.id,
                                            googleCalendarId: ev.googleCalendarId,
                                            googleEventId: ev.googleEventId,
                                          ),
                                        ),
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 20,
                                      color: c.error,
                                    ),
                                  ),
                                ],
                              ),
                              if (ev.location != null && ev.location!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.place_outlined, size: 15, color: c.textSecondary),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        ev.location!,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (ev.description != null && ev.description!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  ev.description!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  SemanticStatusBadge(
                                    kind: isPrivate
                                        ? SemanticStatusKind.info
                                        : SemanticStatusKind.success,
                                    label: isPrivate
                                        ? (calMeta?.summary ?? 'Lịch Riêng')
                                        : 'Lịch Chung Gia đình',
                                  ),
                                  if (ev.isRecurring)
                                    SemanticStatusBadge(
                                      kind: SemanticStatusKind.warning,
                                      label: '🔁 ${ev.recurrence.humanReadableVi}',
                                    ),
                                  SemanticStatusBadge(
                                    kind: switch (ev.syncStatus) {
                                      CalendarSyncStatus.synced => SemanticStatusKind.success,
                                      CalendarSyncStatus.pendingUpload =>
                                        SemanticStatusKind.provisional,
                                      _ => SemanticStatusKind.info,
                                    },
                                    label: switch (ev.syncStatus) {
                                      CalendarSyncStatus.synced => '☁ Đã đồng bộ Lịch',
                                      CalendarSyncStatus.pendingUpload => '⏳ Chờ đồng bộ',
                                      _ => 'Lưu nội bộ',
                                    },
                                  ),
                                ],
                              ),
                              if (upcomingInstances.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Lần lặp kế tiếp: ${upcomingInstances.map((d) => dayFmt.format(d)).join(" · ")}',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: c.textSecondary,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Unified Create & Update Event Dialog supporting RFC 5545 RRULE recurring events & Google Sync.
Future<void> showUpsertCalendarEventDialog(
  BuildContext context, {
  required String userId,
  required String userName,
  String? familyId,
  required bool availabilityOptIn,
  CalendarEventEntity? existingEvent,
  DateTime? initialDate,
}) async {
  final isEditing = existingEvent != null;
  final calBloc = context.read<CalendarBloc>();
  final calendars = calBloc.state.calendars;

  final titleCtrl = TextEditingController(text: existingEvent?.title ?? '');
  final locCtrl = TextEditingController(text: existingEvent?.location ?? '');
  final descCtrl = TextEditingController(text: existingEvent?.description ?? '');
  final intervalCtrl = TextEditingController(
    text: '${existingEvent?.recurrence.interval ?? 1}',
  );
  final countCtrl = TextEditingController(
    text: existingEvent?.recurrence.count?.toString() ?? '',
  );

  var visibility = existingEvent?.visibility ?? CalendarEventVisibility.privateEvent;
  var selectedCalendarId = existingEvent?.calendarId ??
      (calendars.isNotEmpty ? calendars.first.id : 'primary');
  if (calendars.isNotEmpty && !calendars.any((c) => c.id == selectedCalendarId)) {
    selectedCalendarId = calendars.first.id;
  }

  final now = DateTime.now();
  final baseStart = initialDate != null
      ? DateTime(initialDate.year, initialDate.month, initialDate.day, now.hour + 1, 0)
      : now.add(const Duration(hours: 1));
  var isAllDay = existingEvent?.isAllDay ?? false;
  var startsAt = existingEvent?.startsAt ?? baseStart;
  var endsAt = existingEvent?.endsAt ?? startsAt.add(const Duration(hours: 1));
  var reminderMinutes = existingEvent?.reminderMinutesBefore ?? 30;
  var syncToGoogle = existingEvent != null
      ? (existingEvent.isLinkedWithGoogle ||
          existingEvent.isLinkedWithDeviceCalendar ||
          existingEvent.syncStatus == CalendarSyncStatus.pendingUpload)
      : true;

  var frequency = existingEvent?.recurrence.frequency ?? RecurrenceFrequency.none;
  final selectedWeekDays = <String>{
    ...(existingEvent?.recurrence.byWeekDays ?? const <String>[]),
  };

  final dtLabelFmt = DateFormat('dd/MM/yyyy HH:mm');
  final dLabelFmt = DateFormat('dd/MM/yyyy');

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> pickDateTime({required bool isStart}) async {
          final initial = isStart ? startsAt : endsAt;
          final pickedDate = await showDatePicker(
            context: ctx,
            initialDate: initial,
            firstDate: DateTime(2020),
            lastDate: DateTime(2035),
          );
          if (pickedDate == null || !ctx.mounted) return;

          if (isAllDay) {
            setDialogState(() {
              if (isStart) {
                startsAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 0, 0);
                if (endsAt.isBefore(startsAt)) {
                  endsAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 23, 59);
                }
              } else {
                endsAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 23, 59);
              }
            });
            return;
          }

          final pickedTime = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay.fromDateTime(initial),
          );
          if (pickedTime == null) return;

          final combined = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          setDialogState(() {
            if (isStart) {
              startsAt = combined;
              if (!endsAt.isAfter(startsAt)) {
                endsAt = startsAt.add(const Duration(hours: 1));
              }
            } else {
              endsAt = combined;
            }
          });
        }

        return AlertDialog(
          title: Text(isEditing ? 'Cập nhật Sự kiện Lịch' : 'Thêm Sự kiện & Lịch lặp'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('event_title_field'),
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu đề sự kiện *',
                    hintText: 'VD: Họp Sprint / Đóng tiền trọ / Tập Yoga',
                    prefixIcon: Icon(Icons.event_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (!isEditing) ...[
                  DropdownButtonFormField<CalendarEventVisibility>(
                    isExpanded: true,
                    initialValue: visibility,
                    decoration: const InputDecoration(
                      labelText: 'Không gian hiển thị',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: CalendarEventVisibility.privateEvent,
                        child: Text(
                          'PRIVATE — Chỉ mình tôi & Google Calendar',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (familyId != null)
                        const DropdownMenuItem(
                          value: CalendarEventVisibility.sharedEvent,
                          child: Text(
                            'SHARED — Chia sẻ với Gia đình / Hội nhóm',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => visibility = v);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (visibility == CalendarEventVisibility.privateEvent &&
                    calendars.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedCalendarId,
                    decoration: const InputDecoration(
                      labelText: 'Thuộc bộ lịch',
                      isDense: true,
                    ),
                    items: calendars
                        .map(
                          (cal) => DropdownMenuItem(
                            value: cal.id,
                            child: Text(cal.summary, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedCalendarId = v);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Sự kiện cả ngày (All-day)'),
                  value: isAllDay,
                  onChanged: (v) => setDialogState(() => isAllDay = v),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pickDateTime(isStart: true),
                        icon: const Icon(Icons.schedule_rounded, size: 16),
                        label: Text(
                          isAllDay ? dLabelFmt.format(startsAt) : dtLabelFmt.format(startsAt),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pickDateTime(isStart: false),
                        icon: const Icon(Icons.flag_outlined, size: 16),
                        label: Text(
                          isAllDay ? dLabelFmt.format(endsAt) : dtLabelFmt.format(endsAt),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<RecurrenceFrequency>(
                  key: const Key('event_recurrence_dropdown'),
                  isExpanded: true,
                  initialValue: frequency,
                  decoration: const InputDecoration(
                    labelText: 'Lịch lặp tự động (Chuẩn Google RRULE)',
                    prefixIcon: Icon(Icons.repeat_rounded),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: RecurrenceFrequency.none, child: Text('Không lặp')),
                    DropdownMenuItem(
                      value: RecurrenceFrequency.daily,
                      child: Text('Lặp hằng ngày (DAILY)'),
                    ),
                    DropdownMenuItem(
                      value: RecurrenceFrequency.weekly,
                      child: Text('Lặp hằng tuần theo thứ (WEEKLY)'),
                    ),
                    DropdownMenuItem(
                      value: RecurrenceFrequency.monthly,
                      child: Text('Lặp hằng tháng (MONTHLY)'),
                    ),
                    DropdownMenuItem(
                      value: RecurrenceFrequency.yearly,
                      child: Text('Lặp hằng năm / Giỗ Tết / Sinh nhật (YEARLY)'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() {
                        frequency = v;
                        if (frequency == RecurrenceFrequency.weekly &&
                            selectedWeekDays.isEmpty) {
                          selectedWeekDays.add(
                            CalendarRecurrenceRule.weekDayCodeForDate(startsAt),
                          );
                        }
                      });
                    }
                  },
                ),
                if (frequency != RecurrenceFrequency.none) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: intervalCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Khoảng cách (INTERVAL)',
                            hintText: '1',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: countCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Giới hạn số lần (Tùy chọn)',
                            hintText: 'Trống = Mãi mãi',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (frequency == RecurrenceFrequency.weekly) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: CalendarRecurrenceRule.allWeekDayCodes.map((code) {
                        final selected = selectedWeekDays.contains(code);
                        return FilterChip(
                          label: Text(CalendarRecurrenceRule.weekDayLabelVi(code)),
                          selected: selected,
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            setDialogState(() {
                              if (val) {
                                selectedWeekDays.add(code);
                              } else if (selectedWeekDays.length > 1) {
                                selectedWeekDays.remove(code);
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
                  key: const Key('event_location_field'),
                  controller: locCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Địa điểm / Link Google Meet',
                    hintText: 'Phòng họp / Quận 1',
                    prefixIcon: Icon(Icons.place_outlined),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('event_description_field'),
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú chi tiết',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: reminderMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Nhắc trước giờ diễn ra',
                    prefixIcon: Icon(Icons.notifications_active_outlined),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Không nhắc')),
                    DropdownMenuItem(value: 10, child: Text('Trước 10 phút')),
                    DropdownMenuItem(value: 30, child: Text('Trước 30 phút')),
                    DropdownMenuItem(value: 60, child: Text('Trước 1 giờ')),
                    DropdownMenuItem(value: 1440, child: Text('Trước 1 ngày')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => reminderMinutes = v);
                  },
                ),
                if (visibility == CalendarEventVisibility.privateEvent)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Đồng bộ vào Lịch thiết bị & Google Calendar'),
                    subtitle: const Text('Tự động tạo và cập nhật hai chiều trên ứng dụng Lịch'),
                    value: syncToGoogle,
                    onChanged: (v) => setDialogState(() => syncToGoogle = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton.icon(
              key: const Key('submit_event_dialog_button'),
              onPressed: () {
                final parsedInterval = int.tryParse(intervalCtrl.text.trim()) ?? 1;
                final parsedCount = int.tryParse(countCtrl.text.trim());
                final rule = CalendarRecurrenceRule(
                  frequency: frequency,
                  interval: parsedInterval < 1 ? 1 : parsedInterval,
                  byWeekDays: frequency == RecurrenceFrequency.weekly
                      ? selectedWeekDays.toList()
                      : const <String>[],
                  count: (parsedCount != null && parsedCount > 0) ? parsedCount : null,
                );

                if (isEditing) {
                  calBloc.add(
                    CalendarEventUpdated(
                      UpdateCalendarEventParams(
                        userId: userId,
                        userName: userName,
                        existingEvent: existingEvent,
                        title: titleCtrl.text,
                        description: descCtrl.text,
                        location: locCtrl.text,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        calendarId: selectedCalendarId,
                        reminderMinutesBefore: reminderMinutes,
                        recurrence: rule,
                        publishBusySlot: availabilityOptIn,
                        syncToGoogle: syncToGoogle,
                      ),
                    ),
                  );
                } else {
                  calBloc.add(
                    CalendarEventCreated(
                      CreateCalendarEventParams(
                        userId: userId,
                        userName: userName,
                        calendarId: selectedCalendarId,
                        familyId: familyId,
                        visibility: visibility,
                        title: titleCtrl.text,
                        description: descCtrl.text,
                        location: locCtrl.text,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        reminderMinutesBefore: reminderMinutes,
                        recurrence: rule,
                        publishBusySlot: availabilityOptIn,
                        syncToGoogle: syncToGoogle,
                      ),
                    ),
                  );
                }
                Navigator.of(ctx).pop();
              },
              icon: Icon(isEditing ? Icons.save_outlined : Icons.check_rounded, size: 18),
              label: Text(isEditing ? 'Lưu cập nhật' : 'Lưu sự kiện'),
            ),
          ],
        );
      },
    ),
  );

  titleCtrl.dispose();
  locCtrl.dispose();
  descCtrl.dispose();
  intervalCtrl.dispose();
  countCtrl.dispose();
}

/// Interactive Month Grid + Day/Week/Month Real Timeline (100% Real Synced Events — Zero Mock Data).
class _LifeOsInteractiveCalendarDeck extends StatefulWidget {
  final List<CalendarEventEntity> events;
  final bool isSyncing;
  final VoidCallback onSyncRequested;
  final ValueChanged<DateTime> onAddEventForDate;

  const _LifeOsInteractiveCalendarDeck({
    required this.events,
    required this.isSyncing,
    required this.onSyncRequested,
    required this.onAddEventForDate,
  });

  @override
  State<_LifeOsInteractiveCalendarDeck> createState() =>
      _LifeOsInteractiveCalendarDeckState();
}

class _LifeOsInteractiveCalendarDeckState
    extends State<_LifeOsInteractiveCalendarDeck> {
  String _viewMode = 'day';
  late DateTime _focusedMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Expands single, multi-day, and RRULE-recurring events that actually fall inside `[winStart, winEnd]`.
  List<CalendarEventEntity> _eventsInWindow(DateTime winStart, DateTime winEnd) {
    final matches = <CalendarEventEntity>[];
    for (final ev in widget.events) {
      final duration = ev.endsAt.isAfter(ev.startsAt)
          ? ev.endsAt.difference(ev.startsAt)
          : const Duration(hours: 1);

      if (ev.isRecurring) {
        final occs = ev.recurrence.expandOccurrences(
          firstStart: ev.startsAt,
          windowStart: winStart.subtract(duration),
          windowEnd: winEnd,
          maxInstances: 40,
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

  bool _dateHasRealEvent(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
    return _eventsInWindow(dayStart, dayEnd).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final timeFmt = DateFormat('HH:mm');
    final shortDateFmt = DateFormat('dd/MM');

    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startOffset = firstOfMonth.weekday - 1; // Monday = 0
    final gridStart = firstOfMonth.subtract(Duration(days: startOffset));

    const weekdaysVi = <int, String>{
      DateTime.monday: 'Thứ Hai',
      DateTime.tuesday: 'Thứ Ba',
      DateTime.wednesday: 'Thứ Tư',
      DateTime.thursday: 'Thứ Năm',
      DateTime.friday: 'Thứ Sáu',
      DateTime.saturday: 'Thứ Bảy',
      DateTime.sunday: 'Chủ Nhật',
    };

    final (DateTime winStart, DateTime winEnd, String periodHeader) = switch (_viewMode) {
      'week' => () {
          final monday = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
          final start = DateTime(monday.year, monday.month, monday.day);
          final sunday = start.add(const Duration(days: 6));
          final end = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59, 999);
          return (
            start,
            end,
            'Tuần ${shortDateFmt.format(start)} – ${shortDateFmt.format(sunday)}',
          );
        }(),
      'month' => () {
          final start = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
          final nextM = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
          final end = nextM.subtract(const Duration(milliseconds: 1));
          return (
            start,
            end,
            'Tháng ${_focusedMonth.month}, ${_focusedMonth.year}',
          );
        }(),
      _ => (
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59, 999),
          '${weekdaysVi[_selectedDate.weekday]}, ${_selectedDate.day} tháng ${_selectedDate.month}',
        ),
    };

    final periodEvents = _eventsInWindow(winStart, winEnd);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Segmented Bar: Ngày | Tuần | Tháng
        LifeOsSegmentedPills<String>(
          selected: _viewMode,
          options: const [
            ('day', 'Ngày', null),
            ('week', 'Tuần', null),
            ('month', 'Tháng', null),
          ],
          onChanged: (v) => setState(() => _viewMode = v),
        ),
        const SizedBox(height: 12),

        // 2. Interactive Month Calendar Card
        LifeOsSoftCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  LifeOsHeaderCircleButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Tháng trước',
                    onTap: () => setState(() {
                      _focusedMonth =
                          DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                    }),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Tháng ${_focusedMonth.month}, ${_focusedMonth.year}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  LifeOsHeaderCircleButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Tháng sau',
                    onTap: () => setState(() {
                      _focusedMonth =
                          DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
                    .map(
                      (lbl) => Expanded(
                        child: Center(
                          child: Text(
                            lbl,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF667085),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              for (var week = 0; week < 6; week++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: List.generate(7, (dow) {
                      final cellDate =
                          gridStart.add(Duration(days: week * 7 + dow));
                      final inMonth = cellDate.month == _focusedMonth.month;
                      final isSelected = _sameDay(cellDate, _selectedDate);
                      final hasEvent = _dateHasRealEvent(cellDate);

                      return Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            _selectedDate = cellDate;
                            if (cellDate.month != _focusedMonth.month ||
                                cellDate.year != _focusedMonth.year) {
                              _focusedMonth = DateTime(cellDate.year, cellDate.month, 1);
                            }
                          }),
                          child: Container(
                            height: 40,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? c.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${cellDate.day}',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : inMonth
                                            ? c.textPrimary
                                            : c.textSecondary
                                                .withValues(alpha: 0.45),
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                if (hasEvent) ...[
                                  const SizedBox(height: 2),
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.white : c.primary,
                                      shape: BoxShape.circle,
                                    ),
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
          ),
        ),
        const SizedBox(height: 12),

        // 3. Real Synced Events Card (Zero Mock Fallbacks)
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 19, color: c.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      periodHeader,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  LifeOsStatusPill(
                    label: '${periodEvents.length} sự kiện',
                    tone: LifeOsAccentTone.emerald,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.events.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.separator),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chưa đồng bộ sự kiện nào',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Đồng bộ trực tiếp với Lịch trên điện thoại & Google Calendar để hiển thị đúng lịch trình thật của bạn.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const Key('deck_sync_calendar_btn'),
                            onPressed: widget.isSyncing ? null : widget.onSyncRequested,
                            icon: const Icon(Icons.sync_rounded, size: 17),
                            label: Text(
                              widget.isSyncing ? 'Đang đồng bộ...' : 'Đồng bộ Lịch ngay',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => widget.onAddEventForDate(_selectedDate),
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('Thêm sự kiện'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else if (periodEvents.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        _viewMode == 'day'
                            ? 'Không có sự kiện nào trong ngày này.'
                            : 'Không có sự kiện nào trong khoảng thời gian này.',
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => widget.onAddEventForDate(_selectedDate),
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('Thêm sự kiện'),
                      ),
                    ],
                  ),
                )
              else
                ...periodEvents.take(25).toList().asMap().entries.map((entry) {
                  final idx = entry.key;
                  final ev = entry.value;
                  final isShared =
                      ev.visibility == CalendarEventVisibility.sharedEvent;
                  final datePrefix = _viewMode == 'day'
                      ? ''
                      : '${shortDateFmt.format(ev.startsAt)} · ';
                  final timeLabel = ev.isAllDay
                      ? '${datePrefix}Cả ngày'
                      : '$datePrefix${timeFmt.format(ev.startsAt)} – ${timeFmt.format(ev.endsAt)}';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DayTimelineRow(
                      barColor:
                          idx.isEven ? c.primary : const Color(0xFF2563EB),
                      icon: isShared
                          ? Icons.groups_outlined
                          : Icons.event_note_outlined,
                      tone: isShared
                          ? LifeOsAccentTone.emerald
                          : LifeOsAccentTone.blue,
                      title: ev.title,
                      timeRange: timeLabel,
                      tagLabel: isShared ? 'Gia đình' : 'Cá nhân',
                      onTap: () => context.push('/event-detail', extra: ev),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayTimelineRow extends StatelessWidget {
  final Color barColor;
  final IconData icon;
  final LifeOsAccentTone tone;
  final String title;
  final String timeRange;
  final String tagLabel;
  final VoidCallback onTap;

  const _DayTimelineRow({
    required this.barColor,
    required this.icon,
    required this.tone,
    required this.title,
    required this.timeRange,
    required this.tagLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
              LifeOsIconSquircle(icon: icon, tone: tone, size: 38, iconSize: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.22,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 13,
                          color: c.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              timeRange,
                              style: TextStyle(fontSize: 12, color: c.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              LifeOsStatusPill(label: tagLabel, tone: tone),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 19, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanningHabitsAndNotesTabView extends StatelessWidget {
  const _PlanningHabitsAndNotesTabView();

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
            AppSpacing.xxl,
          ),
          children: [
            const LifeOsSectionHeader(
              title: 'Báo thức & Tập trung mỗi ngày',
              subtitle: 'Chuông nhắc sự kiện, đồng hồ Pomodoro và uống nước',
              tone: LifeOsAccentTone.amber,
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
                      subtitle: 'Chuông nhắc hẹn',
                      onTap: () => context.push('/event-alarm'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('planning_hub_habits_tile'),
                      icon: Icons.local_fire_department_outlined,
                      tone: LifeOsAccentTone.amber,
                      title: 'Thói quen & Nước',
                      subtitle: 'Pomodoro tập trung',
                      onTap: () => context.push('/habits-focus'),
                    ),
                  ),
                ],
              ),
            ),
            const LifeOsSectionHeader(
              title: 'Sổ tay cá nhân & Nhiệm vụ',
              subtitle: 'Ghi chú ghim nhanh, nhật ký cảm xúc và bảng việc làm',
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
                      title: 'Sổ tay & Cảm xúc',
                      subtitle: 'Ghi chú & tâm trạng',
                      onTap: () => context.push('/smart-notes-hub'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('planning_hub_tasks_tile'),
                      icon: Icons.task_alt_rounded,
                      tone: LifeOsAccentTone.emerald,
                      title: 'Bảng việc làm',
                      subtitle: 'Việc cá nhân & nhóm',
                      onTap: () => context.push('/tasks-board'),
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
