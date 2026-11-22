import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../tasks/domain/repositories/task_repository.dart';
import '../../../tasks/presentation/bloc/task_bloc.dart';
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
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('⚠ ${state.failure!.message}')));
            } else if (state.message != null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('✓ ${state.message!}')));
            }
          },
        ),
        BlocListener<TaskBloc, TaskState>(
          listenWhen: (p, c) => p.failure != c.failure || p.message != c.message,
          listener: (context, state) {
            if (state.failure != null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('⚠ ${state.failure!.message}')));
            } else if (state.message != null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('✓ ${state.message!}')));
            }
          },
        ),
      ],
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: LiquidGlassBar(
            title: const Text('Lịch trình & Giao việc'),
            actions: [
              IconButton(
                tooltip: 'Thêm sự kiện lịch',
                onPressed: () => _showCreateEventDialog(
                  context,
                  userId: user.id,
                  userName: user.fullName,
                  familyId: activeFamily?.id,
                  availabilityOptIn: user.availabilityOptIn,
                ),
                icon: const Icon(Icons.calendar_month_outlined),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: FilledButton.icon(
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
            ],
          ),
          body: Column(
            children: [
              const ProPillTabContainer(
                tabBar: TabBar(
                  tabs: [
                    Tab(text: 'Công việc & Nhiệm vụ'),
                    Tab(text: 'Lịch Riêng / Lịch Chung'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _TasksListView(userId: user.id),
                    _CalendarListView(userId: user.id, familyId: activeFamily?.id),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateEventDialog(
    BuildContext context, {
    required String userId,
    required String userName,
    String? familyId,
    required bool availabilityOptIn,
  }) async {
    final titleCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    var visibility = CalendarEventVisibility.privateEvent;
    final calBloc = context.read<CalendarBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Thêm Sự kiện Lịch'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tiêu đề sự kiện'),
              const SizedBox(height: 6),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(hintText: 'VD: Khám sức khỏe / Họp gia đình'),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Quyền hiển thị (Privacy Policy)'),
              const SizedBox(height: 6),
              DropdownButtonFormField<CalendarEventVisibility>(
                isExpanded: true,
                initialValue: visibility,
                items: [
                  const DropdownMenuItem(
                    value: CalendarEventVisibility.privateEvent,
                    child: Text('PRIVATE — Chỉ mình tôi xem được'),
                  ),
                  if (familyId != null)
                    const DropdownMenuItem(
                      value: CalendarEventVisibility.sharedEvent,
                      child: Text('SHARED — Chia sẻ với gia đình'),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => visibility = v);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Địa điểm (tùy chọn)'),
              const SizedBox(height: 6),
              TextField(controller: locCtrl),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                final start = DateTime.now().add(const Duration(hours: 2));
                final end = start.add(const Duration(hours: 1));
                calBloc.add(
                  CalendarEventCreated(
                    CreateCalendarEventParams(
                      userId: userId,
                      userName: userName,
                      familyId: familyId,
                      visibility: visibility,
                      title: titleCtrl.text,
                      location: locCtrl.text,
                      startsAt: start,
                      endsAt: end,
                      publishBusySlot: availabilityOptIn,
                    ),
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Lưu sự kiện'),
            ),
          ],
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
          title: const Text('Tạo / Giao việc (Đồng thuận)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nội dung công việc'),
              const SizedBox(height: 6),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(hintText: 'VD: Đón bé lúc 16:30 / Mua nước uống'),
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text('Giao cho thành viên'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: assigneeId,
                  items: members
                      .map((m) => DropdownMenuItem<String>(
                            value: m.userId as String,
                            child: Text(m.fullName as String),
                          ))
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
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                taskBloc.add(
                  TaskCreateSubmitted(
                    CreateTaskParams(
                      createdBy: userId,
                      creatorName: userName,
                      familyId: assigneeId == userId ? familyId : familyId,
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
  }
}

class _TasksListView extends StatelessWidget {
  final String userId;
  const _TasksListView({required this.userId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TaskBloc, TaskState>(
      builder: (context, state) {
        if (state.tasks.isEmpty) {
          return const EmptyStateView(
            icon: Icons.checklist_rounded,
            imageAsset: AppAssets.planningAssetsIllustration,
            title: 'Chưa có công việc nào',
            subtitle:
                'Giao việc cho thành viên gia đình mà không cần xem hay can thiệp vào lịch riêng tư của họ.',
          );
        }

        final completedByMember = <String, int>{};
        final totalByMember = <String, int>{};
        for (final task in state.tasks) {
          totalByMember[task.assigneeName] = (totalByMember[task.assigneeName] ?? 0) + 1;
          if (task.status == TaskWorkflowStatus.done) {
            completedByMember[task.assigneeName] =
                (completedByMember[task.assigneeName] ?? 0) + 1;
          }
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (totalByMember.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bảng Cân bằng Việc nhà & Nhiệm vụ Thành viên',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          ...totalByMember.entries.map((e) {
                            final done = completedByMember[e.key] ?? 0;
                            final total = e.value;
                            final ratio = total > 0 ? done / total : 0.0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        e.key,
                                        style: Theme.of(context).textTheme.labelLarge,
                                      ),
                                      Text(
                                        '$done/$total hoàn thành',
                                        style: Theme.of(context).textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                ...List.generate(state.tasks.length, (index) {
                  final t = state.tasks[index];
                  final isAssignee = t.assigneeId == userId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(t.title, style: Theme.of(context).textTheme.titleMedium),
                            ),
                            SemanticStatusBadge(
                              kind: switch (t.status) {
                                TaskWorkflowStatus.done => SemanticStatusKind.success,
                                TaskWorkflowStatus.proposed => SemanticStatusKind.provisional,
                                TaskWorkflowStatus.declined => SemanticStatusKind.error,
                                _ => SemanticStatusKind.info,
                              },
                              label: t.status.name.toUpperCase(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Người giao: ${t.creatorName} → Người nhận: ${t.assigneeName}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        if (t.status == TaskWorkflowStatus.proposed && isAssignee)
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => context.read<TaskBloc>().add(
                                      TaskResponseSubmitted(
                                        RespondToTaskParams(
                                          actorUserId: userId,
                                          task: t,
                                          accept: false,
                                        ),
                                      ),
                                    ),
                                child: const Text('Từ chối'),
                              ),
                              FilledButton(
                                onPressed: () => context.read<TaskBloc>().add(
                                      TaskResponseSubmitted(
                                        RespondToTaskParams(
                                          actorUserId: userId,
                                          task: t,
                                          accept: true,
                                        ),
                                      ),
                                    ),
                                child: const Text('Chấp nhận việc'),
                              ),
                            ],
                          )
                        else if (t.status == TaskWorkflowStatus.accepted ||
                            t.status == TaskWorkflowStatus.inProgress)
                          FilledButton.tonalIcon(
                            onPressed: () => context.read<TaskBloc>().add(
                                  TaskStatusChanged(
                                    actorUserId: userId,
                                    task: t,
                                    nextStatus: TaskWorkflowStatus.done,
                                  ),
                                ),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Đánh dấu Hoàn thành'),
                          ),
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

class _CalendarListView extends StatelessWidget {
  final String userId;
  final String? familyId;

  const _CalendarListView({required this.userId, this.familyId});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return BlocBuilder<CalendarBloc, CalendarState>(
      builder: (context, state) {
        if (state.events.isEmpty) {
          return const EmptyStateView(
            icon: Icons.event_note_outlined,
            imageAsset: AppAssets.planningAssetsIllustration,
            title: 'Lịch trình đang trống',
            subtitle:
                'Sự kiện PRIVATE lưu riêng trong không gian cá nhân; sự kiện SHARED chỉ hiển thị cho nhóm gia đình bạn chọn.',
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: state.events.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                final ev = state.events[index];
                final isPrivate = ev.visibility == CalendarEventVisibility.privateEvent;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      isPrivate ? Icons.lock_outline_rounded : Icons.groups_outlined,
                    ),
                    title: Text(ev.title),
                    subtitle: Text('${fmt.format(ev.startsAt)} · ${ev.location ?? ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SemanticStatusBadge(
                          kind: isPrivate ? SemanticStatusKind.info : SemanticStatusKind.success,
                          label: isPrivate ? 'Riêng tư' : 'Gia đình',
                        ),
                        if (ev.ownerId == userId)
                          IconButton(
                            tooltip: 'Xóa sự kiện',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => context.read<CalendarBloc>().add(
                                  CalendarEventDeleted(
                                    userId: userId,
                                    familyId: familyId,
                                    visibility: ev.visibility,
                                    eventId: ev.id,
                                  ),
                                ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
