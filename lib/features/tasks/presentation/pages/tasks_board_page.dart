import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../domain/entities/task_entities.dart';
import '../../domain/repositories/task_repository.dart';
import '../bloc/task_bloc.dart';

/// Screen 07: "Công việc / Phân công công việc" (`07_Phan_cong_cong_viec.png`).
class TasksBoardPage extends StatelessWidget {
  final DateTime? referenceDate;

  const TasksBoardPage({super.key, this.referenceDate});

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BlocListener<TaskBloc, TaskState>(
      listenWhen: (p, c) => p.failure != c.failure || p.message != c.message,
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.show(
            context,
            state.failure!.message,
            kind: LifeOsToastKind.error,
          );
        } else if (state.message != null) {
          LifeOsTopToast.show(
            context,
            state.message!,
            kind: LifeOsToastKind.success,
          );
        }
      },
      child: Scaffold(
        body: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Column(
              children: [
                LifeOsTopBrandHeader(
                  title: 'Công việc',
                  showBackButton: true,
                  trailingAction: FilledButton.icon(
                    key: const Key('tasks_page_add_button'),
                    onPressed: () {
                      final family = context
                          .read<FamilyBloc>()
                          .state
                          .activeFamily;
                      showUnifiedCreateTaskDialog(
                        context,
                        userId: user.id,
                        userName: user.fullName,
                        familyId: family?.id,
                        members: family?.members ?? const [],
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Thêm việc'),
                  ),
                ),
                Expanded(
                  child: UnifiedTasksBoardView(
                    userId: user.id,
                    referenceDate: referenceDate,
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

/// Reusable unified tasks body shared by `/tasks-board` and `PlanningPage`'s Work tab.
class UnifiedTasksBoardView extends StatefulWidget {
  final String userId;
  final DateTime? referenceDate;

  const UnifiedTasksBoardView({
    super.key,
    required this.userId,
    this.referenceDate,
  });

  @override
  State<UnifiedTasksBoardView> createState() => _UnifiedTasksBoardViewState();
}

class _UnifiedTasksBoardViewState extends State<UnifiedTasksBoardView> {
  bool _isBoardMode = false;
  String _statusFilter = 'all'; // 'all' | 'open' | 'today' | 'overdue' | 'done'
  String _selectedAssigneeFilter = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  final LifeOsStableListRegistry _taskEntranceRegistry =
      LifeOsStableListRegistry(animateInitialItems: false);
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _statusFilter != 'all' ||
      _selectedAssigneeFilter != 'all' ||
      _searchQuery.trim().isNotEmpty;

  void _resetAllFilters() {
    setState(() {
      _statusFilter = 'all';
      _selectedAssigneeFilter = 'all';
      _searchQuery = '';
      _searchCtrl.clear();
    });
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _statusSortRank(TaskWorkflowStatus status) => switch (status) {
    TaskWorkflowStatus.proposed => 0,
    TaskWorkflowStatus.inProgress => 1,
    TaskWorkflowStatus.accepted => 2,
    TaskWorkflowStatus.done => 3,
    TaskWorkflowStatus.declined => 4,
  };

  static int _prioritySortRank(TaskPriorityLevel p) => switch (p) {
    TaskPriorityLevel.high => 0,
    TaskPriorityLevel.medium => 1,
    TaskPriorityLevel.low => 2,
  };

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.select((AuthBloc b) => b.state.user);
    final members = context.select(
      (FamilyBloc b) => b.state.activeFamily?.members ?? const [],
    );
    final now = widget.referenceDate ?? DateTime.now();

    return BlocBuilder<TaskBloc, TaskState>(
      buildWhen: (p, n) => p.tasks != n.tasks,
      builder: (context, state) {
        final allTasks = state.tasks;
        final openCount = allTasks
            .where(
              (t) =>
                  t.status == TaskWorkflowStatus.proposed ||
                  t.status == TaskWorkflowStatus.accepted ||
                  t.status == TaskWorkflowStatus.inProgress,
            )
            .length;
        final todayCount = allTasks
            .where(
              (t) =>
                  t.status != TaskWorkflowStatus.done &&
                  t.status != TaskWorkflowStatus.declined &&
                  t.dueAt != null &&
                  _isSameDay(t.dueAt!, now),
            )
            .length;
        final overdueCount = allTasks
            .where(
              (t) =>
                  t.status != TaskWorkflowStatus.done &&
                  t.status != TaskWorkflowStatus.declined &&
                  t.dueAt != null &&
                  t.dueAt!.isBefore(now),
            )
            .length;
        final doneCount = allTasks
            .where((t) => t.status == TaskWorkflowStatus.done)
            .length;

        final q = _searchQuery.trim();
        final filtered =
            allTasks.where((t) {
              if (_selectedAssigneeFilter != 'all' &&
                  t.assigneeId != _selectedAssigneeFilter) {
                return false;
              }
              if (q.isNotEmpty) {
                final matches = VietnameseSearchMatcher.matchesAny(q, [
                  t.title,
                  t.description,
                  t.assigneeName,
                  t.creatorName,
                ]);
                if (!matches) return false;
              }
              return switch (_statusFilter) {
                'open' =>
                  t.status == TaskWorkflowStatus.proposed ||
                      t.status == TaskWorkflowStatus.accepted ||
                      t.status == TaskWorkflowStatus.inProgress,
                'today' =>
                  t.status != TaskWorkflowStatus.done &&
                      t.status != TaskWorkflowStatus.declined &&
                      t.dueAt != null &&
                      _isSameDay(t.dueAt!, now),
                'overdue' =>
                  t.status != TaskWorkflowStatus.done &&
                      t.status != TaskWorkflowStatus.declined &&
                      t.dueAt != null &&
                      t.dueAt!.isBefore(now),
                'done' => t.status == TaskWorkflowStatus.done,
                _ => true,
              };
            }).toList()..sort((a, b) {
              final sr = _statusSortRank(
                a.status,
              ).compareTo(_statusSortRank(b.status));
              if (sr != 0) return sr;
              final pr = _prioritySortRank(
                a.priority,
              ).compareTo(_prioritySortRank(b.priority));
              if (pr != 0) return pr;
              final aDue = a.dueAt ?? DateTime(2099);
              final bDue = b.dueAt ?? DateTime(2099);
              return aDue.compareTo(bDue);
            });

        final filterOptions = <(String key, String label, int? badge)>[
          ('all', 'Tất cả', null),
          ('open', 'Cần làm', openCount > 0 ? openCount : null),
          ('today', 'Hôm nay', todayCount > 0 ? todayCount : null),
          if (overdueCount > 0 || _statusFilter == 'overdue')
            ('overdue', 'Quá hạn', overdueCount),
          ('done', 'Đã xong', doneCount > 0 ? doneCount : null),
        ];

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.maxContentWidth,
            ),
            child: ListView(
              key: const Key('tasks_board_list_view'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                6,
                AppSpacing.md,
                AppSpacing.dockClearance,
              ),
              children: [
                // 1. Interactive 4-Column Summary Strip (Tap any metric to filter immediately!)
                LifeOsMintHeroCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        _TaskStatColumn(
                          icon: Icons.list_alt_rounded,
                          count: '${allTasks.length}',
                          label: 'Tổng việc',
                          selected: !_hasActiveFilters,
                          onTap: _resetAllFilters,
                        ),
                        VerticalDivider(width: 8, color: c.separator),
                        _TaskStatColumn(
                          icon: Icons.pending_actions_rounded,
                          count: '$openCount',
                          label: 'Cần làm',
                          selected: _statusFilter == 'open',
                          onTap: () => setState(() => _statusFilter = 'open'),
                        ),
                        VerticalDivider(width: 8, color: c.separator),
                        _TaskStatColumn(
                          icon: Icons.today_rounded,
                          count: '$todayCount',
                          label: 'Hôm nay',
                          selected: _statusFilter == 'today',
                          onTap: () => setState(() => _statusFilter = 'today'),
                        ),
                        VerticalDivider(width: 8, color: c.separator),
                        _TaskStatColumn(
                          icon: Icons.check_circle_outline_rounded,
                          count: '$doneCount',
                          label: 'Đã xong',
                          selected: _statusFilter == 'done',
                          onTap: () => setState(() => _statusFilter = 'done'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 1b. Fast Vietnamese Accent-Insensitive Task Search Bar
                TextField(
                  key: const Key('tasks_search_field'),
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Tìm việc cần làm',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('tasks_search_clear_btn'),
                            tooltip: 'Xóa từ khóa',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _searchQuery = '';
                            }),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                  ),
                ),
                const SizedBox(height: 10),

                // 2. Single Clean Row: Quick Filter Pills + List/Board Toggle
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: filterOptions.map((opt) {
                            final isSelected = opt.$1 == 'all'
                                ? !_hasActiveFilters
                                : _statusFilter == opt.$1;
                            final isOverdueChip = opt.$1 == 'overdue';
                            final activeColor = isOverdueChip
                                ? c.error
                                : c.primary;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                key: Key('task_filter_${opt.$1}'),
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  if (opt.$1 == 'all') {
                                    _resetAllFilters();
                                  } else {
                                    setState(() {
                                      _statusFilter = _statusFilter == opt.$1
                                          ? 'all'
                                          : opt.$1;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected ? activeColor : c.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? activeColor
                                          : c.separator,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        opt.$2,
                                        style: TextStyle(
                                          fontSize: 12.2,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? Colors.white
                                              : (isOverdueChip
                                                    ? c.error
                                                    : c.textPrimary),
                                        ),
                                      ),
                                      if (opt.$3 != null) ...[
                                        const SizedBox(width: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? Colors.white.withValues(
                                                    alpha: 0.24,
                                                  )
                                                : activeColor.withValues(
                                                    alpha: 0.12,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            '${opt.$3}',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: isSelected
                                                  ? Colors.white
                                                  : activeColor,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: _isBoardMode
                          ? 'Chuyển sang Danh sách'
                          : 'Chuyển sang Bảng nhóm',
                      child: InkWell(
                        key: const Key('task_view_mode_toggle'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () =>
                            setState(() => _isBoardMode = !_isBoardMode),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _isBoardMode ? c.primarySubtle : c.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _isBoardMode
                                  ? c.primary.withValues(alpha: 0.4)
                                  : c.separator,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isBoardMode
                                    ? Icons.view_agenda_outlined
                                    : Icons.view_kanban_outlined,
                                size: 17,
                                color: c.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isBoardMode ? 'Danh sách' : 'Nhóm',
                                style: TextStyle(
                                  fontSize: 11.8,
                                  fontWeight: FontWeight.w700,
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

                // 3. Family Member Filter Strip (ONLY shown when family has >= 2 members!)
                if (members.length > 1) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: const Text('Mọi thành viên'),
                            selected: _selectedAssigneeFilter == 'all',
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) =>
                                setState(() => _selectedAssigneeFilter = 'all'),
                          ),
                        ),
                        if (user != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: const Text('Việc của tôi'),
                              selected: _selectedAssigneeFilter == user.id,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => setState(
                                () => _selectedAssigneeFilter = user.id,
                              ),
                            ),
                          ),
                        ...members
                            .where((m) => m.userId != user?.id)
                            .map(
                              (m) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(m.fullName),
                                  selected: _selectedAssigneeFilter == m.userId,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) => setState(
                                    () => _selectedAssigneeFilter = m.userId,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // 4. Task List or Grouped Board View
                if (filtered.isEmpty)
                  LifeOsSoftCard(
                    child: Column(
                      children: [
                        const LifeOsIconSquircle(
                          icon: Icons.task_alt_rounded,
                          tone: LifeOsAccentTone.emerald,
                          size: 48,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          allTasks.isEmpty
                              ? 'Chưa có công việc nào'
                              : 'Không có công việc khớp bộ lọc',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          allTasks.isEmpty
                              ? 'Tạo việc cần làm kèm giờ hẹn và mức độ ưu tiên để theo dõi gọn gàng mỗi ngày.'
                              : 'Bấm "Xóa bộ lọc" để hiển thị lại toàn bộ công việc hoặc thêm việc mới.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (allTasks.isNotEmpty && _hasActiveFilters) ...[
                          FilledButton.tonalIcon(
                            key: const Key('tasks_reset_filters_btn'),
                            onPressed: _resetAllFilters,
                            icon: const Icon(
                              Icons.filter_alt_off_rounded,
                              size: 17,
                            ),
                            label: const Text('Xóa bộ lọc'),
                          ),
                          const SizedBox(height: 8),
                        ],
                        LifeOsPrimaryCtaButton(
                          icon: Icons.add_rounded,
                          label: 'Thêm việc mới',
                          onPressed: user == null
                              ? null
                              : () {
                                  final familyId = context
                                      .read<FamilyBloc>()
                                      .state
                                      .activeFamily
                                      ?.id;
                                  showUnifiedCreateTaskDialog(
                                    context,
                                    userId: user.id,
                                    userName: user.fullName,
                                    familyId: familyId,
                                    members: members,
                                  );
                                },
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (_isBoardMode)
                    _KanbanColumnsView(
                      tasks: filtered,
                      currentUserId: widget.userId,
                      referenceNow: now,
                      showAssignee: members.length > 1,
                    )
                  else ...[
                    Builder(
                      builder: (_) {
                        final newTaskIds = _taskEntranceRegistry
                            .registerSnapshot(filtered.map((t) => t.id));
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: filtered
                              .map(
                                (task) => Padding(
                                  key: ValueKey('task_pad_${task.id}'),
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: LifeOsAnimatedItemEntrance(
                                    key: ValueKey('task_entrance_${task.id}'),
                                    itemId: task.id,
                                    animateOnMount: newTaskIds.contains(
                                      task.id,
                                    ),
                                    child: _UnifiedTaskRowCard(
                                      task: task,
                                      currentUserId: widget.userId,
                                      referenceNow: now,
                                      showAssignee: members.length > 1,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  LifeOsPrimaryCtaButton(
                    icon: Icons.add_rounded,
                    label: 'Thêm việc mới',
                    onPressed: user == null
                        ? null
                        : () {
                            final familyId = context
                                .read<FamilyBloc>()
                                .state
                                .activeFamily
                                ?.id;
                            showUnifiedCreateTaskDialog(
                              context,
                              userId: user.id,
                              userName: user.fullName,
                              familyId: familyId,
                              members: members,
                            );
                          },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TaskStatColumn extends StatelessWidget {
  final IconData icon;
  final String count;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TaskStatColumn({
    required this.icon,
    required this.count,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? c.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? c.primary : c.textSecondary,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  count,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: c.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? c.primary : c.textSecondary,
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

class _UnifiedTaskRowCard extends StatelessWidget {
  final TaskEntity task;
  final String currentUserId;
  final DateTime referenceNow;
  final bool showAssignee;

  const _UnifiedTaskRowCard({
    required this.task,
    required this.currentUserId,
    required this.referenceNow,
    this.showAssignee = false,
  });

  static final DateFormat _hmFmt = DateFormat('HH:mm');
  static final DateFormat _dmHmFmt = DateFormat('dd/MM, HH:mm');

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDeadlineLabel(DateTime? due) {
    if (due == null) return 'Trong ngày (linh hoạt)';
    final hm = _hmFmt.format(due);
    if (_sameDay(due, referenceNow)) return 'Hôm nay, $hm';
    final tomorrow = referenceNow.add(const Duration(days: 1));
    if (_sameDay(due, tomorrow)) return 'Ngày mai, $hm';
    return _dmHmFmt.format(due);
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDone = task.status == TaskWorkflowStatus.done;
    final isDeclined = task.status == TaskWorkflowStatus.declined;
    final isPending = task.status == TaskWorkflowStatus.proposed;
    final isOverdue =
        !isDone &&
        !isDeclined &&
        task.dueAt != null &&
        task.dueAt!.isBefore(referenceNow);

    final (barColor, pillTone, pillLabel) = switch (task.status) {
      TaskWorkflowStatus.done => (
        c.primary,
        LifeOsAccentTone.emerald,
        'Đã xong',
      ),
      TaskWorkflowStatus.proposed => (
        const Color(0xFFF59E0B),
        LifeOsAccentTone.amber,
        'Chờ nhận',
      ),
      TaskWorkflowStatus.declined => (
        c.error,
        LifeOsAccentTone.coral,
        'Từ chối',
      ),
      TaskWorkflowStatus.accepted || TaskWorkflowStatus.inProgress => (
        isOverdue ? c.error : const Color(0xFF2563EB),
        isOverdue ? LifeOsAccentTone.coral : LifeOsAccentTone.blue,
        isOverdue ? 'Quá hạn' : 'Đang làm',
      ),
    };

    final recurrenceLabel = switch (task.recurrence) {
      TaskRecurrence.daily => 'Hằng ngày',
      TaskRecurrence.weekly => 'Hằng tuần',
      TaskRecurrence.monthly => 'Hằng tháng',
      TaskRecurrence.none => null,
    };

    return LifeOsSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  key: Key('task_checkbox_${task.id}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    if (isDone) {
                      context.read<TaskBloc>().add(
                        TaskStatusChanged(
                          actorUserId: currentUserId,
                          task: task,
                          nextStatus: TaskWorkflowStatus.accepted,
                        ),
                      );
                    } else if (isPending) {
                      if (task.assigneeId == currentUserId || task.isPersonal) {
                        context.read<TaskBloc>().add(
                          TaskResponseSubmitted(
                            RespondToTaskParams(
                              actorUserId: currentUserId,
                              task: task,
                              accept: true,
                            ),
                          ),
                        );
                      } else {
                        context.read<TaskBloc>().add(
                          TaskStatusChanged(
                            actorUserId: currentUserId,
                            task: task,
                            nextStatus: TaskWorkflowStatus.done,
                          ),
                        );
                      }
                    } else {
                      context.read<TaskBloc>().add(
                        TaskStatusChanged(
                          actorUserId: currentUserId,
                          task: task,
                          nextStatus: TaskWorkflowStatus.done,
                        ),
                      );
                    }
                  },
                  child: Semantics(
                    button: true,
                    checked: isDone,
                    label: 'Đánh dấu hoàn thành ${task.title}',
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AnimatedContainer(
                        duration: LifeOsMotionScope.of(
                          context,
                        ).resolveDuration(LifeOsMotionTokens.micro),
                        curve: LifeOsMotionTokens.standardCurve,
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isDone ? c.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: isDone
                                ? c.primary
                                : (isOverdue ? c.error : c.primary),
                            width: 2,
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: LifeOsMotionScope.of(
                            context,
                          ).resolveDuration(LifeOsMotionTokens.micro),
                          child: isDone
                              ? const Icon(
                                  Icons.check_rounded,
                                  key: ValueKey('checked'),
                                  size: 16,
                                  color: Colors.white,
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('unchecked'),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        task.title,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 14.8,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: isDone ? c.textSecondary : c.textPrimary,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (task.description != null &&
                          task.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          task.description!.trim(),
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12.2,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          LifeOsStatusPill(label: pillLabel, tone: pillTone),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isOverdue
                                    ? Icons.error_outline_rounded
                                    : Icons.schedule_rounded,
                                size: 13,
                                color: isOverdue ? c.error : c.textSecondary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  _formatDeadlineLabel(task.dueAt),
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 11.8,
                                    fontWeight: isOverdue
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isOverdue
                                        ? c.error
                                        : c.textSecondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (task.priority == TaskPriorityLevel.high &&
                              !isDone)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: c.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Quan trọng',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.error,
                                ),
                              ),
                            ),
                          if (recurrenceLabel != null)
                            Text(
                              '🔁 $recurrenceLabel',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: c.primary,
                              ),
                            ),
                          if (showAssignee || task.assigneeId != currentUserId)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 8.5,
                                  backgroundColor: c.primarySubtle,
                                  child: Text(
                                    task.assigneeName.trim().isEmpty
                                        ? 'U'
                                        : task.assigneeName
                                              .trim()
                                              .characters
                                              .first
                                              .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: c.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    task.assigneeName,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: Key('task_menu_${task.id}'),
                  tooltip: 'Tùy chọn công việc',
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 19,
                    color: c.textSecondary,
                  ),
                  onSelected: (action) async {
                    if (action == 'edit') {
                      final user = context.read<AuthBloc>().state.user;
                      final family = context
                          .read<FamilyBloc>()
                          .state
                          .activeFamily;
                      if (user == null) return;
                      await showUnifiedCreateTaskDialog(
                        context,
                        userId: user.id,
                        userName: user.fullName,
                        familyId: family?.id,
                        members: family?.members ?? const [],
                        existingTask: task,
                      );
                      return;
                    }
                    if (action == 'delete') {
                      final ok = await showDestructiveConfirmDialog(
                        context: context,
                        title: 'Xóa công việc này?',
                        message:
                            'Công việc "${task.title}" sẽ bị xóa khỏi danh sách của bạn.',
                        confirmLabel: 'Xóa việc',
                      );
                      if (ok && context.mounted) {
                        context.read<TaskBloc>().add(
                          TaskDeleted(actorUserId: currentUserId, task: task),
                        );
                      }
                      return;
                    }
                    final next = switch (action) {
                      'inProgress' => TaskWorkflowStatus.inProgress,
                      'done' => TaskWorkflowStatus.done,
                      'reopen' => TaskWorkflowStatus.accepted,
                      _ => TaskWorkflowStatus.declined,
                    };
                    if (task.status == TaskWorkflowStatus.proposed &&
                        (next == TaskWorkflowStatus.accepted ||
                            next == TaskWorkflowStatus.declined) &&
                        (task.assigneeId == currentUserId || task.isPersonal)) {
                      context.read<TaskBloc>().add(
                        TaskResponseSubmitted(
                          RespondToTaskParams(
                            actorUserId: currentUserId,
                            task: task,
                            accept: next == TaskWorkflowStatus.accepted,
                          ),
                        ),
                      );
                    } else {
                      context.read<TaskBloc>().add(
                        TaskStatusChanged(
                          actorUserId: currentUserId,
                          task: task,
                          nextStatus: next,
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Sửa công việc'),
                    ),
                    if (!isDone)
                      const PopupMenuItem(
                        value: 'inProgress',
                        child: Text('Chuyển sang Đang làm'),
                      ),
                    if (!isDone)
                      const PopupMenuItem(
                        value: 'done',
                        child: Text('Đánh dấu Đã xong'),
                      ),
                    if (isDone)
                      const PopupMenuItem(
                        value: 'reopen',
                        child: Text('Mở lại công việc'),
                      ),
                    if (!isDone)
                      const PopupMenuItem(
                        value: 'decline',
                        child: Text('Từ chối việc này'),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Xóa công việc',
                        style: TextStyle(
                          color: c.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isPending) ...[
            const Divider(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Được giao bởi ${task.creatorName}',
                  style: TextStyle(
                    fontSize: 11.8,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: c.error,
                      ),
                      onPressed: () => context.read<TaskBloc>().add(
                        TaskResponseSubmitted(
                          RespondToTaskParams(
                            actorUserId: currentUserId,
                            task: task,
                            accept: false,
                          ),
                        ),
                      ),
                      child: const Text('Từ chối'),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => context.read<TaskBloc>().add(
                        TaskResponseSubmitted(
                          RespondToTaskParams(
                            actorUserId: currentUserId,
                            task: task,
                            accept: true,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Nhận việc'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _KanbanColumnsView extends StatelessWidget {
  final List<TaskEntity> tasks;
  final String currentUserId;
  final DateTime referenceNow;
  final bool showAssignee;

  const _KanbanColumnsView({
    required this.tasks,
    required this.currentUserId,
    required this.referenceNow,
    required this.showAssignee,
  });

  @override
  Widget build(BuildContext context) {
    final groups =
        <(String title, LifeOsAccentTone tone, List<TaskEntity> items)>[
          (
            'Chờ nhận việc',
            LifeOsAccentTone.amber,
            tasks
                .where((t) => t.status == TaskWorkflowStatus.proposed)
                .toList(),
          ),
          (
            'Đang thực hiện',
            LifeOsAccentTone.blue,
            tasks
                .where(
                  (t) =>
                      t.status == TaskWorkflowStatus.accepted ||
                      t.status == TaskWorkflowStatus.inProgress,
                )
                .toList(),
          ),
          (
            'Đã hoàn thành',
            LifeOsAccentTone.emerald,
            tasks.where((t) => t.status == TaskWorkflowStatus.done).toList(),
          ),
        ];

    return Column(
      children: groups.map((g) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: LifeOsSoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LifeOsStatusPill(label: g.$1, tone: g.$2),
                    Text(
                      '${g.$3.length} việc',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (g.$3.isEmpty)
                  Text(
                    'Chưa có việc nào trong nhóm này',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  ...g.$3.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _UnifiedTaskRowCard(
                        task: t,
                        currentUserId: currentUserId,
                        referenceNow: referenceNow,
                        showAssignee: showAssignee,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Unified, human-friendly Task Creation Dialog supporting quick deadlines, custom Date/Time picker,
/// priority levels, optional notes, recurrence, and family assignment.
Future<void> showUnifiedCreateTaskDialog(
  BuildContext context, {
  required String userId,
  required String userName,
  String? familyId,
  required List<dynamic> members,
  DateTime? initialDueDate,
  TaskEntity? existingTask,
}) async {
  final taskBloc = context.read<TaskBloc>();
  await showDialog<void>(
    context: context,
    builder: (_) => _UnifiedCreateTaskDialog(
      taskBloc: taskBloc,
      userId: userId,
      userName: userName,
      familyId: familyId,
      members: members,
      initialDueDate: initialDueDate,
      existingTask: existingTask,
    ),
  );
}

class _UnifiedCreateTaskDialog extends StatefulWidget {
  final TaskBloc taskBloc;
  final String userId;
  final String userName;
  final String? familyId;
  final List<dynamic> members;
  final DateTime? initialDueDate;
  final TaskEntity? existingTask;

  const _UnifiedCreateTaskDialog({
    required this.taskBloc,
    required this.userId,
    required this.userName,
    required this.familyId,
    required this.members,
    required this.initialDueDate,
    this.existingTask,
  });

  @override
  State<_UnifiedCreateTaskDialog> createState() =>
      _UnifiedCreateTaskDialogState();
}

class _UnifiedCreateTaskDialogState extends State<_UnifiedCreateTaskDialog> {
  static final DateFormat _dtFmt = DateFormat('dd/MM/yyyy HH:mm');

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  late String _assigneeId;
  late String _assigneeName;
  TaskPriorityLevel _priority = TaskPriorityLevel.medium;
  TaskRecurrence _recurrence = TaskRecurrence.none;
  late DateTime _defaultToday;
  late DateTime _tomorrowMorning;
  late String _duePreset;
  DateTime? _selectedDueAt;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTask;
    _assigneeId = existing != null && existing.assigneeId.isNotEmpty
        ? existing.assigneeId
        : widget.userId;
    _assigneeName = existing != null && existing.assigneeName.isNotEmpty
        ? existing.assigneeName
        : widget.userName;
    final now = DateTime.now();
    final todayEvening = DateTime(now.year, now.month, now.day, 18, 0);
    _defaultToday = todayEvening.isAfter(now)
        ? todayEvening
        : DateTime(now.year, now.month, now.day, 23, 50);
    _tomorrowMorning = DateTime(now.year, now.month, now.day + 1, 9, 0);

    if (existing != null) {
      _titleCtrl.text = existing.title;
      _descCtrl.text = existing.description ?? '';
      _priority = existing.priority;
      _recurrence = existing.recurrence;
      _duePreset = existing.dueAt != null ? 'custom' : 'none';
      _selectedDueAt = existing.dueAt;
    } else {
      _duePreset = widget.initialDueDate != null ? 'custom' : 'today';
      _selectedDueAt = widget.initialDueDate != null
          ? DateTime(
              widget.initialDueDate!.year,
              widget.initialDueDate!.month,
              widget.initialDueDate!.day,
              17,
              0,
            )
          : _defaultToday;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCustomDateTime() async {
    final base = _selectedDueAt ?? _defaultToday;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (pickedTime == null || !mounted) return;
    setState(() {
      _duePreset = 'custom';
      _selectedDueAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm công việc mới'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('create_task_title_field'),
              controller: _titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tên công việc *',
                hintText: 'VD: Gửi báo cáo tuần / Đón con 17:00',
                prefixIcon: Icon(Icons.task_alt_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('create_task_desc_field'),
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Ghi chú ngắn (tùy chọn)',
                hintText: 'Chi tiết cần lưu ý...',
                prefixIcon: Icon(Icons.notes_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Thời hạn hoàn thành',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Hôm nay'),
                  selected: _duePreset == 'today',
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() {
                    _duePreset = 'today';
                    _selectedDueAt = _defaultToday;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Ngày mai 09:00'),
                  selected: _duePreset == 'tomorrow',
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() {
                    _duePreset = 'tomorrow';
                    _selectedDueAt = _tomorrowMorning;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Không đặt giờ'),
                  selected: _duePreset == 'none',
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() {
                    _duePreset = 'none';
                    _selectedDueAt = null;
                  }),
                ),
                ActionChip(
                  avatar: const Icon(Icons.schedule_rounded, size: 16),
                  label: Text(
                    _duePreset == 'custom' && _selectedDueAt != null
                        ? _dtFmt.format(_selectedDueAt!)
                        : 'Chọn ngày giờ...',
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: _pickCustomDateTime,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Mức độ ưu tiên',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  key: const Key('task_priority_medium'),
                  label: const Text('Bình thường'),
                  selected: _priority == TaskPriorityLevel.medium,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) =>
                      setState(() => _priority = TaskPriorityLevel.medium),
                ),
                ChoiceChip(
                  key: const Key('task_priority_high'),
                  label: const Text('Quan trọng'),
                  selected: _priority == TaskPriorityLevel.high,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) =>
                      setState(() => _priority = TaskPriorityLevel.high),
                ),
                ChoiceChip(
                  key: const Key('task_priority_low'),
                  label: const Text('Ưu tiên thấp'),
                  selected: _priority == TaskPriorityLevel.low,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) =>
                      setState(() => _priority = TaskPriorityLevel.low),
                ),
              ],
            ),
            if (widget.members.length > 1) ...[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _assigneeId,
                decoration: const InputDecoration(
                  labelText: 'Người thực hiện',
                  isDense: true,
                ),
                items: widget.members
                    .map<DropdownMenuItem<String>>(
                      (m) => DropdownMenuItem(
                        value: m.userId as String,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${m.fullName} (${m.userId == widget.userId ? "Tôi thực hiện" : "Giao việc"})',
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    final found = widget.members
                        .where((m) => m.userId == val)
                        .first;
                    setState(() {
                      _assigneeId = val;
                      _assigneeName = found.fullName as String;
                    });
                  }
                },
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<TaskRecurrence>(
              isExpanded: true,
              initialValue: _recurrence,
              decoration: const InputDecoration(
                labelText: 'Lặp lại định kỳ',
                prefixIcon: Icon(Icons.repeat_rounded),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: TaskRecurrence.none,
                  child: Text('Không lặp'),
                ),
                DropdownMenuItem(
                  value: TaskRecurrence.daily,
                  child: Text('Hằng ngày'),
                ),
                DropdownMenuItem(
                  value: TaskRecurrence.weekly,
                  child: Text('Hằng tuần'),
                ),
                DropdownMenuItem(
                  value: TaskRecurrence.monthly,
                  child: Text('Hằng tháng'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _recurrence = v);
              },
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
          key: const Key('submit_create_task_button'),
          onPressed: () {
            if (_titleCtrl.text.trim().length < 2) {
              LifeOsTopToast.show(
                context,
                'Hãy nhập tên công việc (ít nhất 2 ký tự).',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            if (widget.existingTask != null) {
              widget.taskBloc.add(
                TaskUpdated(
                  actorUserId: widget.userId,
                  task: widget.existingTask!,
                  title: _titleCtrl.text,
                  description: _descCtrl.text,
                  dueAt: _selectedDueAt,
                  clearDueAt: _selectedDueAt == null,
                  priority: _priority,
                  recurrence: _recurrence,
                ),
              );
            } else {
              widget.taskBloc.add(
                TaskCreateSubmitted(
                  CreateTaskParams(
                    createdBy: widget.userId,
                    creatorName: widget.userName,
                    familyId: widget.familyId,
                    assigneeId: _assigneeId,
                    assigneeName: _assigneeName,
                    title: _titleCtrl.text,
                    description: _descCtrl.text,
                    dueAt: _selectedDueAt,
                    priority: _priority,
                    recurrence: _recurrence,
                  ),
                ),
              );
            }
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(
            widget.existingTask != null ? 'Cập nhật việc' : 'Lưu công việc',
          ),
        ),
      ],
    );
  }
}
