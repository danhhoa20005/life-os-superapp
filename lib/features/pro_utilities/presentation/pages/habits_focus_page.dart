import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../bloc/pro_utilities_bloc.dart';

/// Replaces Habitify Pro, Forest Pomodoro & Waterllama in one Unified LifeOS Studio.
class HabitsFocusPage extends StatefulWidget {
  const HabitsFocusPage({super.key});

  @override
  State<HabitsFocusPage> createState() => _HabitsFocusPageState();
}

class _HabitsFocusPageState extends State<HabitsFocusPage> {
  int _selectedPresetMinutes = 25;
  int _remainingSeconds = 25 * 60;
  bool _isRunning = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _selectPreset(int mins) {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _selectedPresetMinutes = mins;
      _remainingSeconds = mins * 60;
    });
  }

  void _toggleTimer(String userId) {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
      return;
    }
    setState(() => _isRunning = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remainingSeconds <= 1) {
        t.cancel();
        setState(() {
          _isRunning = false;
          _remainingSeconds = _selectedPresetMinutes * 60;
        });
        context.read<ProUtilitiesBloc>().add(
          WellnessMetricsIncremented(
            userId: userId,
            addFocusMinutes: _selectedPresetMinutes,
            addPomodoros: 1,
          ),
        );
        LifeOsTopToast.fromSnackBar(
          context,
          SnackBar(
            content: Text(
              '🎉 Hoàn thành phiên tập trung $_selectedPresetMinutes phút! Đã lưu vào nhật ký.',
            ),
          ),
        );
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final now = DateTime.now();

    final mm = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_remainingSeconds % 60).toString().padLeft(2, '0');
    final totalSecs = _selectedPresetMinutes * 60;
    final progress = totalSecs > 0
        ? 1.0 - (_remainingSeconds / totalSecs)
        : 0.0;

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              LifeOsTopBrandHeader(
                title: 'Thói quen & Tập trung',
                showBackButton: true,
                trailingAction: IconButton.filledTonal(
                  tooltip: 'Thêm thói quen mới',
                  onPressed: () => _showAddHabitDialog(context, user.id),
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
              Expanded(
                child: BlocBuilder<ProUtilitiesBloc, ProUtilitiesState>(
                  builder: (context, state) {
                    final w = state.todayWellness;
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
                            // 1. Deep Focus Pomodoro Studio Card (Replaces Forest Pro)
                            LifeOsMintHeroCard(
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.timer_outlined,
                                        size: 20,
                                        color: c.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Đồng hồ Tập trung Sâu (Pomodoro)',
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
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
                                            value: _isRunning ? progress : 1.0,
                                            strokeWidth: 9,
                                            backgroundColor: c.surface,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  c.primary,
                                                ),
                                          ),
                                        ),
                                        Text(
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
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () => _toggleTimer(user.id),
                                        icon: Icon(
                                          _isRunning
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                        ),
                                        label: Text(
                                          _isRunning
                                              ? 'Tạm dừng'
                                              : 'Bắt đầu tập trung',
                                        ),
                                      ),
                                      const SizedBox(width: 10),
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

                            // 2. Hydration 1-Tap Tracker Card (Replaces Waterllama)
                            LifeOsSoftCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.water_drop_outlined,
                                        tone: LifeOsAccentTone.blue,
                                        size: 40,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Nước uống hôm nay',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              '${w.waterMl} ml / ${w.targetWaterMl} ml (${w.waterProgressPct}%)',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
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
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      minHeight: 8,
                                      value: (w.waterProgressPct / 100).clamp(
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

                            // 3. Daily Habit Streaks & No-Spend Challenge (Replaces Habitify Pro)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Chuỗi Thói quen Tích cực (${state.habits.length})',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _showAddHabitDialog(context, user.id),
                                  child: const Text('+ Thói quen mới'),
                                ),
                              ],
                            ),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children:
                                    const [
                                          (
                                            'Ngày không chi tiêu thừa',
                                            'Tài chính',
                                          ),
                                          ('Đọc sách 20 phút', 'Học tập'),
                                          (
                                            'Vận động / Đi bộ 30 phút',
                                            'Sức khỏe',
                                          ),
                                        ]
                                        .map(
                                          (preset) => Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                              bottom: 8,
                                            ),
                                            child: ActionChip(
                                              label: Text('+ ${preset.$1}'),
                                              onPressed: () => context
                                                  .read<ProUtilitiesBloc>()
                                                  .add(
                                                    HabitAdded(
                                                      userId: user.id,
                                                      title: preset.$1,
                                                      categoryTag: preset.$2,
                                                    ),
                                                  ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ),

                            if (state.habits.isEmpty)
                              LifeOsSoftCard(
                                child: Text(
                                  'Chạm một gợi ý phía trên (như "Ngày không chi tiêu thừa") để bắt đầu xây dựng chuỗi kỷ luật mỗi ngày.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.textSecondary,
                                  ),
                                ),
                              )
                            else
                              ...state.habits.map((h) {
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
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            color: doneToday
                                                ? c.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: c.primary,
                                              width: 2,
                                            ),
                                          ),
                                          child: doneToday
                                              ? const Icon(
                                                  Icons.check_rounded,
                                                  size: 17,
                                                  color: Colors.white,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                h.title,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14.5,
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
                                        LifeOsStatusPill(
                                          icon: Icons
                                              .local_fire_department_rounded,
                                          label: '$streak ngày',
                                          tone: streak > 0
                                              ? LifeOsAccentTone.amber
                                              : LifeOsAccentTone.neutral,
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
    );
  }

  Future<void> _showAddHabitDialog(BuildContext context, String userId) async {
    final titleCtrl = TextEditingController();
    var category = 'Tài chính';
    final bloc = context.read<ProUtilitiesBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Thêm Thói quen Kỷ luật'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên thói quen hằng ngày',
                  hintText: 'VD: Không mua trà sữa / Ngủ trước 23h',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Nhóm mục tiêu'),
                items: const [
                  DropdownMenuItem(
                    value: 'Tài chính',
                    child: Text('Tài chính thông minh'),
                  ),
                  DropdownMenuItem(
                    value: 'Sức khỏe',
                    child: Text('Sức khỏe & Năng lượng'),
                  ),
                  DropdownMenuItem(
                    value: 'Học tập',
                    child: Text('Học tập & Sự nghiệp'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => category = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                bloc.add(
                  HabitAdded(
                    userId: userId,
                    title: titleCtrl.text,
                    categoryTag: category,
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Tạo thói quen'),
            ),
          ],
        ),
      ),
    );
  }
}
