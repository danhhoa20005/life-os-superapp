import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/pro_utilities_entities.dart';
import '../bloc/pro_utilities_bloc.dart';

/// Unified Habit Streaks, Hydration & Deep Focus Studio.
class HabitsFocusPage extends StatefulWidget {
  const HabitsFocusPage({super.key});

  @override
  State<HabitsFocusPage> createState() => _HabitsFocusPageState();
}

class _HabitsFocusPageState extends State<HabitsFocusPage>
    with WidgetsBindingObserver {
  int _selectedPresetMinutes = 25;
  int _remainingSeconds = 25 * 60;
  DateTime? _focusEndAt;
  bool _isRunning = false;
  String _habitCategoryFilter = 'all';
  Timer? _timer;
  String? _activeUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning) {
      _syncClock();
    }
  }

  void _selectPreset(int mins) {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _focusEndAt = null;
      _selectedPresetMinutes = mins;
      _remainingSeconds = mins * 60;
    });
  }

  void _syncClock() {
    final endAt = _focusEndAt;
    if (!_isRunning || endAt == null) return;
    final left = endAt.difference(DateTime.now()).inSeconds;
    if (left <= 0) {
      _completeFocusSession();
    } else if (left != _remainingSeconds && mounted) {
      setState(() => _remainingSeconds = left);
    }
  }

  void _completeFocusSession() {
    _timer?.cancel();
    final uid = _activeUserId;
    final mins = _selectedPresetMinutes;
    setState(() {
      _isRunning = false;
      _focusEndAt = null;
      _remainingSeconds = mins * 60;
    });
    if (uid != null && mounted) {
      context.read<ProUtilitiesBloc>().add(
        WellnessMetricsIncremented(
          userId: uid,
          addFocusMinutes: mins,
          addPomodoros: 1,
        ),
      );
      LifeOsTopToast.show(
        context,
        'Hoàn thành phiên tập trung $mins phút! Đã lưu vào nhật ký.',
        kind: LifeOsToastKind.success,
      );
    }
  }

  void _toggleTimer(String userId) {
    _activeUserId = userId;
    if (_isRunning) {
      _timer?.cancel();
      final endAt = _focusEndAt;
      final remaining = endAt == null
          ? _remainingSeconds
          : math.max(1, endAt.difference(DateTime.now()).inSeconds);
      setState(() {
        _isRunning = false;
        _focusEndAt = null;
        _remainingSeconds = remaining;
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _focusEndAt = DateTime.now().add(Duration(seconds: _remainingSeconds));
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _syncClock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _activeUserId = user.id;
    final c = TammySemanticColors.of(context);
    final now = DateTime.now();

    final mm = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_remainingSeconds % 60).toString().padLeft(2, '0');
    final totalSecs = _selectedPresetMinutes * 60;
    final hasStartedSession = _isRunning || _remainingSeconds < totalSecs;
    final progress = totalSecs > 0
        ? 1.0 - (_remainingSeconds / totalSecs)
        : 0.0;

    return BlocListener<ProUtilitiesBloc, ProUtilitiesState>(
      listenWhen: (p, n) =>
          (n.failure != null && p.failure != n.failure) ||
          (n.message != null && p.message != n.message),
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
                  title: 'Thói quen & Tập trung',
                  showBackButton: true,
                  trailingAction: IconButton.filledTonal(
                    tooltip: 'Thêm thói quen mới',
                    onPressed: () => _showSaveHabitDialog(context, user.id),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
                Expanded(
                  child: BlocBuilder<ProUtilitiesBloc, ProUtilitiesState>(
                    builder: (context, state) {
                      final w = state.todayWellness;
                      final visibleHabits = _habitCategoryFilter == 'all'
                          ? state.habits
                          : state.habits
                                .where(
                                  (h) => h.categoryTag == _habitCategoryFilter,
                                )
                                .toList();
                      return Center(
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
                              // 1. Deep Focus Pomodoro Studio Card
                              LifeOsMintHeroCard(
                                child: Column(
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const BananaGlassIcon(
                                              assetPath: AppAssets.icLifeHabits,
                                              fallbackIcon:
                                                  Icons.timer_outlined,
                                              size: 32,
                                              borderRadius: 10,
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Đồng hồ Tập trung Sâu (Pomodoro)',
                                                softWrap: true,
                                                style: TextStyle(
                                                  fontSize: 15.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: c.textPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        LifeOsStatusPill(
                                          label:
                                              '${w.completedPomodoros} phiên · ${w.focusMinutes} phút',
                                          tone: LifeOsAccentTone.emerald,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    LifeOsSegmentedPills<int>(
                                      selected: _selectedPresetMinutes,
                                      options: const [
                                        (15, '15 phút', null),
                                        (25, '25 phút', null),
                                        (45, '45 phút', null),
                                      ],
                                      onChanged: _selectPreset,
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: 132,
                                      height: 132,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox(
                                            width: 132,
                                            height: 132,
                                            child: CircularProgressIndicator(
                                              value: hasStartedSession
                                                  ? progress
                                                  : 1.0,
                                              strokeWidth: 9,
                                              backgroundColor: c.surface,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    c.primary,
                                                  ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(18),
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                '$mm:$ss',
                                                style: TextStyle(
                                                  fontSize: 30,
                                                  fontWeight: FontWeight.w800,
                                                  color: c.textPrimary,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 10,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: () =>
                                              _toggleTimer(user.id),
                                          icon: Icon(
                                            _isRunning
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                          ),
                                          label: Text(
                                            _isRunning
                                                ? 'Tạm dừng'
                                                : (_remainingSeconds < totalSecs
                                                      ? 'Tiếp tục'
                                                      : 'Bắt đầu tập trung'),
                                          ),
                                        ),
                                        OutlinedButton(
                                          onPressed: () => _selectPreset(
                                            _selectedPresetMinutes,
                                          ),
                                          child: const Text('Đặt lại'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 2. Hydration 1-Tap Tracker Card
                              LifeOsSoftCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const BananaGlassIcon(
                                              assetPath: AppAssets.ic3dHydration,
                                              fallbackIcon:
                                                  Icons.water_drop_outlined,
                                              size: 40,
                                            ),
                                            const SizedBox(width: 12),
                                            Flexible(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Nước uống hôm nay',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 15,
                                                      color: c.textPrimary,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${w.waterMl} ml / ${w.targetWaterMl} ml (${w.waterProgressPct}%)',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: c.textSecondary,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        FilledButton.tonalIcon(
                                          key: const Key('add_water_250_button'),
                                          onPressed: () => context
                                              .read<ProUtilitiesBloc>()
                                              .add(
                                                WellnessMetricsIncremented(
                                                  userId: user.id,
                                                  addWaterMl: 250,
                                                ),
                                              ),
                                          icon: const Icon(
                                            Icons.add_rounded,
                                            size: 17,
                                          ),
                                          label: const Text('+250ml'),
                                        ),
                                        OutlinedButton.icon(
                                          key: const Key(
                                            'open_water_reminder_settings_btn',
                                          ),
                                          onPressed: () => context.push(
                                            '/health-hub?tab=water',
                                          ),
                                          icon: const Icon(
                                            Icons.alarm_rounded,
                                            size: 16,
                                          ),
                                          label: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text('Hẹn nhắc'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        minHeight: 8,
                                        value: w.waterMl <= 0
                                            ? 0.0
                                            : (w.waterProgressPct / 100).clamp(
                                                0.03,
                                                1.0,
                                              ),
                                        backgroundColor: c.surfaceRaised,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                              Color(0xFF2563EB),
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              // 3. Daily Habit Streaks
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'Chuỗi Thói quen Tích cực (${state.habits.length})',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        _showSaveHabitDialog(context, user.id),
                                    child: const Text('+ Thói quen mới'),
                                  ),
                                ],
                              ),
                              if (state.habits.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      ChoiceChip(
                                        key: const Key('habits_filter_all'),
                                        label: Text(
                                          'Tất cả (${state.habits.length})',
                                        ),
                                        selected:
                                            _habitCategoryFilter == 'all',
                                        onSelected: (_) => setState(
                                          () => _habitCategoryFilter = 'all',
                                        ),
                                      ),
                                      for (final cat in const [
                                        'Tài chính',
                                        'Sức khỏe',
                                        'Học tập',
                                      ])
                                        ChoiceChip(
                                          label: Text(cat),
                                          selected:
                                              _habitCategoryFilter == cat,
                                          onSelected: (sel) => setState(
                                            () => _habitCategoryFilter = sel
                                                ? cat
                                                : 'all',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              if (state.habits.isEmpty)
                                LifeOsSoftCard(
                                  child: Column(
                                    children: [
                                      const BananaGlassIcon(
                                        assetPath: AppAssets.icLifeHabits,
                                        fallbackIcon:
                                            Icons.local_fire_department_rounded,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Chưa có thói quen nào',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Thêm thói quen kỷ luật hằng ngày như không mua trà sữa hoặc đọc sách 20 phút.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12.8,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (visibleHabits.isEmpty)
                                LifeOsSoftCard(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Chưa có thói quen thuộc nhóm "$_habitCategoryFilter"',
                                        softWrap: true,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      FilledButton.tonalIcon(
                                        key: const Key('habits_reset_filter_btn'),
                                        onPressed: () => setState(
                                          () => _habitCategoryFilter = 'all',
                                        ),
                                        icon: const Icon(
                                          Icons.filter_alt_off_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('Xem tất cả'),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...visibleHabits.map((h) {
                                  final doneToday = h.isCompletedOn(now);
                                  final streak = h.currentStreakAt(now);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LifeOsSoftCard(
                                      onTap: () =>
                                          context.read<ProUtilitiesBloc>().add(
                                            HabitToggledToday(
                                              userId: user.id,
                                              habit: h,
                                            ),
                                          ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: doneToday
                                                      ? c.primary
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: c.primary,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: doneToday
                                                    ? const Icon(
                                                        Icons.check_rounded,
                                                        size: 18,
                                                        color: Colors.white,
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 12),
                                              const BananaGlassIcon(
                                                assetPath:
                                                    AppAssets.icLifeHabits,
                                                fallbackIcon: Icons
                                                    .local_fire_department_rounded,
                                                size: 36,
                                                borderRadius: 10,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      h.title,
                                                      softWrap: true,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 14.8,
                                                        color: c.textPrimary,
                                                      ),
                                                    ),
                                                    Text(
                                                      h.categoryTag,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: c.textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                key: Key('habit_menu_${h.id}'),
                                                tooltip: 'Tùy chọn thói quen',
                                                onSelected: (action) async {
                                                  if (action == 'edit') {
                                                    await _showSaveHabitDialog(
                                                      context,
                                                      user.id,
                                                      existing: h,
                                                    );
                                                  } else if (action ==
                                                      'delete') {
                                                    final confirmed =
                                                        await showDestructiveConfirmDialog(
                                                          context: context,
                                                          title:
                                                              'Xóa thói quen "${h.title}"?',
                                                          message:
                                                              'Chuỗi ngày đã tích lũy của thói quen này sẽ bị xóa vĩnh viễn.',
                                                          confirmLabel: 'Xóa',
                                                        );
                                                    if (confirmed &&
                                                        context.mounted) {
                                                      context
                                                          .read<
                                                            ProUtilitiesBloc
                                                          >()
                                                          .add(
                                                            HabitDeleted(
                                                              userId: user.id,
                                                              habitId: h.id,
                                                            ),
                                                          );
                                                    }
                                                  }
                                                },
                                                itemBuilder: (_) => [
                                                  const PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text(
                                                      'Sửa tên & nhóm',
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text(
                                                      'Xóa thói quen',
                                                      style: TextStyle(
                                                        color: c.error,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              LifeOsStatusPill(
                                                icon: Icons
                                                    .local_fire_department_rounded,
                                                label: '$streak ngày',
                                                tone: streak > 0
                                                    ? LifeOsAccentTone.amber
                                                    : LifeOsAccentTone.neutral,
                                              ),
                                              LifeOsStatusPill(
                                                icon: doneToday
                                                    ? Icons.check_circle_rounded
                                                    : Icons.radio_button_unchecked,
                                                label: doneToday
                                                    ? 'Đã xong hôm nay'
                                                    : 'Chạm thẻ để hoàn thành',
                                                tone: doneToday
                                                    ? LifeOsAccentTone.emerald
                                                    : LifeOsAccentTone.neutral,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSaveHabitDialog(
    BuildContext context,
    String userId, {
    LifeHabitEntity? existing,
  }) async {
    final bloc = context.read<ProUtilitiesBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => _SaveHabitDialog(
        bloc: bloc,
        userId: userId,
        existing: existing,
      ),
    );
  }
}

class _SaveHabitDialog extends StatefulWidget {
  const _SaveHabitDialog({
    required this.bloc,
    required this.userId,
    this.existing,
  });

  final ProUtilitiesBloc bloc;
  final String userId;
  final LifeHabitEntity? existing;

  @override
  State<_SaveHabitDialog> createState() => _SaveHabitDialogState();
}

class _SaveHabitDialogState extends State<_SaveHabitDialog> {
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late String _category = widget.existing?.categoryTag ?? 'Tài chính';

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(
        existing != null ? 'Sửa Thói quen Kỷ luật' : 'Thêm Thói quen Kỷ luật',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('habit_title_input'),
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên thói quen hằng ngày',
                hintText: 'VD: Không mua trà sữa / Ngủ trước 23h',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Nhóm mục tiêu'),
              items: const [
                DropdownMenuItem(
                  value: 'Tài chính',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('Tài chính thông minh'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Sức khỏe',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('Sức khỏe & Năng lượng'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Học tập',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('Học tập & Sự nghiệp'),
                  ),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
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
        FilledButton(
          key: const Key('submit_habit_button'),
          onPressed: () {
            final cleanTitle = _titleCtrl.text.trim();
            if (cleanTitle.isEmpty) {
              LifeOsTopToast.show(
                context,
                'Vui lòng nhập tên thói quen hằng ngày.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            if (existing != null) {
              widget.bloc.add(
                HabitUpdated(
                  userId: widget.userId,
                  habitId: existing.id,
                  title: cleanTitle,
                  categoryTag: _category,
                ),
              );
            } else {
              widget.bloc.add(
                HabitAdded(
                  userId: widget.userId,
                  title: cleanTitle,
                  categoryTag: _category,
                ),
              );
            }
            Navigator.of(context).pop();
          },
          child: Text(existing != null ? 'Lưu thay đổi' : 'Tạo thói quen'),
        ),
      ],
    );
  }
}
