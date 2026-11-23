import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../domain/entities/task_entities.dart';
import '../../domain/repositories/task_repository.dart';
import '../bloc/task_bloc.dart';

/// Screen 07: "Việc làm / Phân công công việc" (`07_Phan_cong_cong_viec.png`).
class TasksBoardPage extends StatelessWidget {
  const TasksBoardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BlocListener<TaskBloc, TaskState>(
      listenWhen: (p, c) => p.failure != c.failure || p.message != c.message,
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(context, 
            SnackBar(content: Text('⚠ ${state.failure!.message}')),
          );
        } else if (state.message != null) {
          LifeOsTopToast.fromSnackBar(context, 
            SnackBar(content: Text('✓ ${state.message!}')),
          );
        }
      },
      child: Scaffold(
        body: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Column(
              children: [
                const LifeOsTopBrandHeader(
                  title: 'Việc làm',
                  showBackButton: true,
                ),
                Expanded(
                  child: UnifiedTasksBoardView(userId: user.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable unified tasks body shared by `/tasks-board` and `PlanningPage`'s Tasks tab.
class UnifiedTasksBoardView extends StatefulWidget {
  final String userId;

  const UnifiedTasksBoardView({super.key, required this.userId});

  @override
  State<UnifiedTasksBoardView> createState() => _UnifiedTasksBoardViewState();
}

class _UnifiedTasksBoardViewState extends State<UnifiedTasksBoardView> {
  bool _isBoardMode = false;
  String _selectedAssigneeFilter = 'all';
  String _selectedDateFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final family = context.watch<FamilyBloc>().state.activeFamily;
    final members = family?.members ?? const [];
    final timeFmt = DateFormat('dd/MM, HH:mm');

    return BlocBuilder<TaskBloc, TaskState>(
      builder: (context, state) {
        final allTasks = state.tasks;
        final activeCount = allTasks
            .where(
              (t) =>
                  t.status == TaskWorkflowStatus.accepted ||
                  t.status == TaskWorkflowStatus.inProgress,
            )
            .length;
        final pendingCount =
            allTasks.where((t) => t.status == TaskWorkflowStatus.proposed).length;
        final doneCount =
            allTasks.where((t) => t.status == TaskWorkflowStatus.done).length;

        final now = DateTime.now();
        final filtered = allTasks.where((t) {
          if (_selectedAssigneeFilter != 'all' && t.assigneeId != _selectedAssigneeFilter) {
            return false;
          }
          if (_selectedDateFilter == 'today' && t.dueAt != null) {
            final d = t.dueAt!;
            if (d.year != now.year || d.month != now.month || d.day != now.day) {
              return false;
            }
          }
          return true;
        }).toList();

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                4,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                // 1. 4-Column Pastel Mint Summary Card ("Tổng việc | Đang làm | Chờ | Hoàn thành")
                LifeOsMintHeroCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        _TaskStatColumn(
                          icon: Icons.check_box_outlined,
                          count: '${allTasks.length}',
                          label: 'Tổng việc',
                        ),
                        VerticalDivider(width: 12, color: c.separator),
                        _TaskStatColumn(
                          icon: Icons.autorenew_rounded,
                          count: '$activeCount',
                          label: 'Đang làm',
                        ),
                        VerticalDivider(width: 12, color: c.separator),
                        _TaskStatColumn(
                          icon: Icons.schedule_rounded,
                          count: '$pendingCount',
                          label: 'Chờ',
                        ),
                        VerticalDivider(width: 12, color: c.separator),
                        _TaskStatColumn(
                          icon: Icons.check_circle_outline_rounded,
                          count: '$doneCount',
                          label: 'Hoàn thành',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Segmented Toggle: "Danh sách | Bảng"
                LifeOsSegmentedPills<bool>(
                  selected: _isBoardMode,
                  options: const [
                    (false, 'Danh sách', Icons.format_list_bulleted_rounded),
                    (true, 'Bảng', Icons.dashboard_outlined),
                  ],
                  onChanged: (v) => setState(() => _isBoardMode = v),
                ),
                const SizedBox(height: 12),

                // 3. Filter Dropdown Pills ("Tất cả thành viên v" | "Hôm nay v")
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: c.separator),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedAssigneeFilter,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text(
                                  'Tất cả thành viên',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (user != null)
                                DropdownMenuItem(
                                  value: user.id,
                                  child: const Text(
                                    'Việc của tôi',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ...members
                                  .where((m) => m.userId != user?.id)
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m.userId,
                                      child: Text(
                                        m.fullName,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedAssigneeFilter = val);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: c.separator),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedDateFilter,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text(
                                  'Mọi thời điểm',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'today',
                                child: Text(
                                  'Hôm nay',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedDateFilter = val);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 4. Task List or Kanban Board View
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
                          'Chưa có công việc nào trong bộ lọc này',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Nhấn "+ Thêm việc mới" bên dưới để tạo việc cá nhân hoặc phân công việc nhà cho thành viên.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                        ),
                      ],
                    ),
                  )
                else if (_isBoardMode)
                  _KanbanColumnsView(
                    tasks: filtered,
                    currentUserId: widget.userId,
                    timeFmt: timeFmt,
                  )
                else
                  ...filtered.map(
                    (task) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _UnifiedTaskRowCard(
                        task: task,
                        currentUserId: widget.userId,
                        timeFmt: timeFmt,
                      ),
                    ),
                  ),

                const SizedBox(height: 14),

                // 5. Full-width Emerald "+ Thêm việc mới" Button
                LifeOsPrimaryCtaButton(
                  icon: Icons.add_rounded,
                  label: 'Thêm việc mới',
                  onPressed: user == null
                      ? null
                      : () => showUnifiedCreateTaskDialog(
                            context,
                            userId: user.id,
                            userName: user.fullName,
                            familyId: family?.id,
                            members: members,
                          ),
                ),
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

  const _TaskStatColumn({
    required this.icon,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: c.primary),
          const SizedBox(height: 6),
          Text(
            count,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedTaskRowCard extends StatelessWidget {
  final TaskEntity task;
  final String currentUserId;
  final DateFormat timeFmt;

  const _UnifiedTaskRowCard({
    required this.task,
    required this.currentUserId,
    required this.timeFmt,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDone = task.status == TaskWorkflowStatus.done;
    final isPending = task.status == TaskWorkflowStatus.proposed;

    final (barColor, pillTone, pillLabel, pillIcon) = switch (task.status) {
      TaskWorkflowStatus.done => (
          c.primary,
          LifeOsAccentTone.emerald,
          'Hoàn thành',
          Icons.check_circle_outline_rounded,
        ),
      TaskWorkflowStatus.proposed => (
          const Color(0xFFF59E0B),
          LifeOsAccentTone.amber,
          'Chờ',
          Icons.schedule_rounded,
        ),
      TaskWorkflowStatus.declined => (
          c.error,
          LifeOsAccentTone.coral,
          'Từ chối',
          Icons.cancel_outlined,
        ),
      TaskWorkflowStatus.accepted || TaskWorkflowStatus.inProgress => (
          const Color(0xFF2563EB),
          LifeOsAccentTone.blue,
          'Đang làm',
          Icons.autorenew_rounded,
        ),
    };

    return LifeOsSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: isDone
                  ? null
                  : () {
                      if (isPending) {
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
                    },
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isDone ? c.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: c.primary,
                    width: 2,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.22,
                      fontWeight: FontWeight.w800,
                      color: isDone ? c.textSecondary : c.textPrimary,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 12.5, color: c.textSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          task.dueAt != null
                              ? timeFmt.format(task.dueAt!)
                              : 'Linh hoạt trong ngày',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.2, color: c.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: c.primarySubtle,
                  child: Text(
                    task.assigneeName.trim().isEmpty
                        ? 'U'
                        : task.assigneeName.trim().characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 54),
                  child: Text(
                    task.assigneeName.split(' ').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            LifeOsStatusPill(
              icon: pillIcon,
              label: pillLabel,
              tone: pillTone,
            ),
            PopupMenuButton<TaskWorkflowStatus>(
              tooltip: 'Cập nhật trạng thái',
              icon: Icon(Icons.more_vert_rounded, size: 19, color: c.textSecondary),
              onSelected: (next) {
                if (task.status == TaskWorkflowStatus.proposed &&
                    (next == TaskWorkflowStatus.accepted ||
                        next == TaskWorkflowStatus.declined)) {
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
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: TaskWorkflowStatus.inProgress,
                  child: Text('Chuyển sang Đang làm'),
                ),
                PopupMenuItem(
                  value: TaskWorkflowStatus.done,
                  child: Text('Đánh dấu Hoàn thành'),
                ),
                PopupMenuItem(
                  value: TaskWorkflowStatus.declined,
                  child: Text('Từ chối nhận việc'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KanbanColumnsView extends StatelessWidget {
  final List<TaskEntity> tasks;
  final String currentUserId;
  final DateFormat timeFmt;

  const _KanbanColumnsView({
    required this.tasks,
    required this.currentUserId,
    required this.timeFmt,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <(String title, LifeOsAccentTone tone, List<TaskEntity> items)>[
      (
        'Chờ xác nhận',
        LifeOsAccentTone.amber,
        tasks.where((t) => t.status == TaskWorkflowStatus.proposed).toList(),
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
                Row(
                  children: [
                    LifeOsStatusPill(label: g.$1, tone: g.$2),
                    const Spacer(),
                    Text(
                      '${g.$3.length} việc',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (g.$3.isEmpty)
                  Text(
                    'Trống',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  ...g.$3.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _UnifiedTaskRowCard(
                        task: t,
                        currentUserId: currentUserId,
                        timeFmt: timeFmt,
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

Future<void> showUnifiedCreateTaskDialog(
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
        title: const Text('Giao Việc & Phân công Gia đình'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nội dung công việc',
                  hintText: 'VD: Đổ rác / Mua đồ siêu thị / Đón con 16:30',
                ),
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: assigneeId,
                  decoration: const InputDecoration(labelText: 'Giao cho thành viên'),
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
              DropdownButtonFormField<TaskRecurrence>(
                isExpanded: true,
                initialValue: recurrence,
                decoration: const InputDecoration(labelText: 'Chu kỳ lặp lại'),
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
                    dueAt: DateTime.now().add(const Duration(hours: 4)),
                    recurrence: recurrence,
                  ),
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Tạo việc'),
          ),
        ],
      ),
    ),
  );
  titleCtrl.dispose();
}
