import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/native_alarm_scheduler_bridge.dart';
import '../../../../core/utils/privacy_mask_formatter.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../bloc/daily_life_bloc.dart';

class HealthMedicalHubPage extends StatefulWidget {
  final String? initialTab;

  const HealthMedicalHubPage({super.key, this.initialTab});

  @override
  State<HealthMedicalHubPage> createState() => _HealthMedicalHubPageState();
}

class _HealthMedicalHubPageState extends State<HealthMedicalHubPage>
    with WidgetsBindingObserver {
  late String _tab;
  BackgroundReminderReadiness _bgReadiness =
      BackgroundReminderReadiness.allReady;

  // Interactive Asian BMI / TDEE / Blood Pressure & Body Hydration State
  double _weightKg = 63.0;
  double _heightCm = 168.0;
  final int _ageYears = 29;
  bool _isMale = true;
  int _systolic = 118;
  int _diastolic = 76;
  int _heartRate = 72;
  double _sleepHours = 7.5;
  bool _hydratedFromLogs = false;
  bool _userEditedBodyMetrics = false;
  String _selectedBeverage = 'Nước lọc';
  bool _revealMedicalIdentifiers = false;

  static const List<
    ({String name, String dosage, MedicationScheduleSlot slot, int pills})
  >
  _medPresets = [
    (
      name: 'Vitamin D3 + K2 MK7',
      dosage: '1 viên sau ăn sáng',
      slot: MedicationScheduleSlot.morning,
      pills: 60,
    ),
    (
      name: 'Omega-3 Dầu cá tinh khiết',
      dosage: '1 viên buổi trưa',
      slot: MedicationScheduleSlot.noon,
      pills: 90,
    ),
    (
      name: 'Hạ sốt giảm đau Paracetamol 500mg',
      dosage: '1 viên khi sốt >= 38.5°C',
      slot: MedicationScheduleSlot.asNeeded,
      pills: 20,
    ),
    (
      name: 'Oresol bù nước & điện giải',
      dosage: '1 gói pha đúng 200ml nước sôi để nguội',
      slot: MedicationScheduleSlot.asNeeded,
      pills: 15,
    ),
    (
      name: 'Men vi sinh tiêu hóa Probiotics',
      dosage: '1 ống buổi tối',
      slot: MedicationScheduleSlot.evening,
      pills: 30,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final t = widget.initialTab;
    _tab = (t == 'water' || t == 'vitals' || t == 'sos' || t == 'meds')
        ? t!
        : 'meds';
    _refreshBgReadiness();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBgReadiness();
    }
  }

  Future<void> _refreshBgReadiness() async {
    final r = await NativeAlarmSchedulerBridge.instance
        .getBackgroundReadiness();
    if (!mounted) return;
    setState(() => _bgReadiness = r);
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final userId = user?.id ?? '';

    return BlocConsumer<DailyLifeBloc, DailyLifeState>(
      listenWhen: (p, n) =>
          (n.failure != null && p.failure != n.failure) ||
          (n.successBanner != null && p.successBanner != n.successBanner),
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.show(
            context,
            state.failure!.message,
            kind: LifeOsToastKind.error,
          );
        } else if (state.successBanner != null) {
          LifeOsTopToast.show(context, state.successBanner!);
        }
      },
      builder: (context, state) {
        final snap = state.snapshot;
        final hyd = snap.hydration;
        if (!_hydratedFromLogs && snap.healthLogs.isNotEmpty) {
          final latest = snap.healthLogs.first;
          _systolic = latest.systolicMmHg;
          _diastolic = latest.diastolicMmHg;
          _heartRate = latest.heartRateBpm;
          _sleepHours = latest.sleepHours;
          _hydratedFromLogs = true;
        }
        if (!_userEditedBodyMetrics) {
          _weightKg = hyd.weightKg;
          _heightCm = hyd.heightCm;
        }

        final todayKey = DailyLifeBloc.todayDayKey();
        final scheduledMeds = snap.medications
            .where((m) => m.slot != MedicationScheduleSlot.asNeeded)
            .toList();
        final takenToday = snap.medicationsTakenCount(todayKey);
        final assessment = AsianHealthBmiTdeeEngine.evaluate(
          weightKg: _weightKg,
          heightCm: _heightCm,
          ageYears: _ageYears,
          isMale: _isMale,
          hydrationActivity: hyd.activityLevel,
          systolicMmHg: _systolic,
          diastolicMmHg: _diastolic,
        );

        return Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  const LifeOsTopBrandHeader(
                    title: 'Sức khỏe & Tủ thuốc',
                    showBackButton: true,
                    trailingAction: LifeOsStatusPill(
                      icon: Icons.emergency_rounded,
                      label: 'SOS 115',
                      tone: LifeOsAccentTone.coral,
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
                            // Hero Card
                            LifeOsMintHeroCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.favorite_rounded,
                                        tone: LifeOsAccentTone.coral,
                                        size: 42,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Hồ sơ Sức khỏe Gia đình',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'Nhóm máu ${snap.emergencyCard.bloodType.isEmpty ? "Chưa rõ" : snap.emergencyCard.bloodType} · ${assessment.bmiCategory}',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        _HeroKpiCol(
                                          value:
                                              '$takenToday/${scheduledMeds.isEmpty ? snap.medications.length : scheduledMeds.length}',
                                          label: 'Cữ thuốc hôm nay',
                                          color: c.primary,
                                        ),
                                        VerticalDivider(
                                          width: 14,
                                          color: c.separator,
                                        ),
                                        _HeroKpiCol(
                                          value: '${hyd.waterMl} ml',
                                          label: 'Nước (${hyd.progressPct}%)',
                                          color: const Color(0xFF0EA5E9),
                                        ),
                                        VerticalDivider(
                                          width: 14,
                                          color: c.separator,
                                        ),
                                        _HeroKpiCol(
                                          value: '${assessment.bmi}',
                                          label: 'BMI Châu Á',
                                          color: const Color(0xFF8B5CF6),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            LifeOsSegmentedPills<String>(
                              selected: _tab,
                              onChanged: (v) => setState(() => _tab = v),
                              options: const [
                                ('meds', 'Tủ thuốc', null),
                                ('water', 'Uống nước', null),
                                ('vitals', 'Chỉ số', null),
                                ('sos', 'Thẻ SOS', null),
                              ],
                            ),
                            const SizedBox(height: 14),

                            if (_tab == 'meds')
                              _buildMedicationsTab(
                                context,
                                c,
                                userId,
                                snap,
                                todayKey,
                              )
                            else if (_tab == 'water')
                              _buildWaterReminderTab(
                                context,
                                c,
                                userId,
                                hyd,
                                assessment,
                              )
                            else if (_tab == 'vitals')
                              _buildVitalsTab(
                                context,
                                c,
                                userId,
                                snap,
                                assessment,
                              )
                            else
                              _buildEmergencyCardTab(
                                context,
                                c,
                                userId,
                                snap.emergencyCard,
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
      },
    );
  }

  Widget _buildMedicationsTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    DailyLifeSnapshot snap,
    String todayKey,
  ) {
    final now = DateTime.now();
    final dateFmt = DateFormat('dd/MM/yyyy');
    final dueToday = snap.dueScheduledMedications(todayKey)
      ..sort(
        (a, b) => (a.effectiveReminderHour * 60 + a.effectiveReminderMinute)
            .compareTo(
              b.effectiveReminderHour * 60 + b.effectiveReminderMinute,
            ),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Next Dose Reminder Banner
        if (snap.medications.any((m) => m.slot.isScheduledDaily)) ...[
          LifeOsSoftCard(
            key: const Key('medication_schedule_banner'),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                LifeOsIconSquircle(
                  icon: dueToday.isEmpty
                      ? Icons.verified_rounded
                      : Icons.notifications_active_outlined,
                  tone: dueToday.isEmpty
                      ? LifeOsAccentTone.emerald
                      : LifeOsAccentTone.amber,
                  size: 40,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dueToday.isEmpty
                            ? 'Đã uống đủ tất cả cữ thuốc hôm nay!'
                            : 'Còn ${dueToday.length} cữ thuốc cần uống hôm nay',
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      if (dueToday.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Gần nhất: ${dueToday.first.name} · Hẹn lúc ${dueToday.first.formattedReminderTime}',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12.2,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Text(
          'Mẫu thuốc & vitamin phổ biến',
          softWrap: true,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _medPresets.map((p) {
            return ActionChip(
              avatar: Icon(
                Icons.add_circle_outline_rounded,
                size: 16,
                color: c.primary,
              ),
              label: Text(p.name, style: const TextStyle(fontSize: 12.2)),
              onPressed: userId.isEmpty
                  ? null
                  : () {
                      context.read<DailyLifeBloc>().add(
                        MedicationCabinetAdded(
                          userId: userId,
                          name: p.name,
                          dosage: p.dosage,
                          slot: p.slot,
                          remainingPills: p.pills,
                          expiryDate: now.add(const Duration(days: 270)),
                        ),
                      );
                    },
            );
          }).toList(),
        ),
        const SizedBox(height: 14),

        LifeOsPrimaryCtaButton(
          key: const Key('open_add_medication_btn'),
          label: '+ Thêm thuốc & Hẹn giờ nhắc',
          icon: Icons.medication_liquid_rounded,
          onPressed: userId.isEmpty
              ? null
              : () => _showAddMedSheet(context, userId),
        ),
        const SizedBox(height: 14),

        if (snap.medications.isEmpty)
          LifeOsSoftCard(
            child: Column(
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  size: 40,
                  color: c.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tủ thuốc gia đình đang trống',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          )
        else
          ...snap.medications.map((med) {
            final taken = med.isTakenOn(todayKey);
            final expiring = med.isExpiringSoon(now);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LifeOsSoftCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LifeOsIconSquircle(
                          icon: taken
                              ? Icons.check_circle_rounded
                              : Icons.medication_outlined,
                          tone: taken
                              ? LifeOsAccentTone.emerald
                              : (expiring
                                    ? LifeOsAccentTone.coral
                                    : LifeOsAccentTone.blue),
                          size: 42,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                med.name,
                                softWrap: true,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                '${med.dosage} · ${med.slot.label}',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 12.2,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Xóa thuốc',
                          onPressed: () => context.read<DailyLifeBloc>().add(
                            MedicationCabinetDeleted(
                              userId: userId,
                              medId: med.id,
                            ),
                          ),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (med.slot.isScheduledDaily)
                          InkWell(
                            key: Key('med_reminder_pill_${med.id}'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () =>
                                _showEditMedReminderSheet(context, userId, med),
                            child: LifeOsStatusPill(
                              icon: med.reminderEnabled
                                  ? Icons.alarm_on_rounded
                                  : Icons.alarm_off_rounded,
                              label: med.reminderEnabled
                                  ? 'Nhắc ${med.formattedReminderTime}'
                                  : 'Tắt nhắc',
                              tone: med.reminderEnabled
                                  ? LifeOsAccentTone.emerald
                                  : LifeOsAccentTone.neutral,
                            ),
                          ),
                        LifeOsStatusPill(
                          icon: Icons.inventory_2_outlined,
                          label: 'Còn ${med.remainingPills} viên',
                          tone: med.remainingPills <= 5
                              ? LifeOsAccentTone.amber
                              : LifeOsAccentTone.neutral,
                        ),
                        LifeOsStatusPill(
                          icon: Icons.event_busy_outlined,
                          label: 'HSD: ${dateFmt.format(med.expiryDate)}',
                          tone: expiring
                              ? LifeOsAccentTone.coral
                              : LifeOsAccentTone.emerald,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          key: Key('med_toggle_taken_${med.id}'),
                          onPressed: () => context.read<DailyLifeBloc>().add(
                            MedicationTakenToggled(userId: userId, item: med),
                          ),
                          icon: Icon(
                            taken
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 17,
                          ),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              taken ? 'Đã uống hôm nay' : 'Đánh dấu đã uống',
                            ),
                          ),
                        ),
                        if (!taken && med.slot.isScheduledDaily)
                          OutlinedButton.icon(
                            key: Key('med_snooze_15m_${med.id}'),
                            onPressed: () => context.read<DailyLifeBloc>().add(
                              MedicationSnoozed15Min(med),
                            ),
                            icon: const Icon(Icons.snooze_rounded, size: 17),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Nhắc sau 15p'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildWaterReminderTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    HydrationReminderStatusEntity hyd,
    AsianHealthAssessment assessment,
  ) {
    final now = DateTime.now();
    final timeFmt = DateFormat('HH:mm');
    final nextAt = hyd.nextReminderAt(now);
    final progressFrac = hyd.targetWaterMl > 0
        ? (hyd.waterMl / hyd.targetWaterMl).clamp(0.0, 1.0)
        : 0.0;
    final bodyRecommendedMl = assessment.recommendedWaterMl;
    final upcomingTodaySlots = hyd
        .upcomingScheduleAt(now, maxSlots: 16)
        .where(
          (dt) =>
              dt.year == now.year && dt.month == now.month && dt.day == now.day,
        )
        .toList();
    final paceMl = hyd.suggestedMlPerSlot(now);

    final goalPresets = <int>{
      1500,
      2000,
      bodyRecommendedMl,
      2500,
      3000,
    }.toList()..sort();

    void saveSettings({
      bool? enabled,
      int? intervalMins,
      int? startH,
      int? startM,
      int? endH,
      int? endM,
      int? targetMl,
      double? weightKg,
      double? heightCm,
      HydrationActivityLevel? activity,
      bool? autoSyncBody,
      int? cupMl,
      bool clearSnooze = false,
      String? toast,
    }) {
      if (userId.isEmpty) return;
      final nextWeight = double.parse(
        (weightKg ?? _weightKg).clamp(25.0, 250.0).toStringAsFixed(1),
      );
      final nextHeight = (heightCm ?? _heightCm)
          .clamp(100.0, 230.0)
          .roundToDouble();
      final nextAct = activity ?? hyd.activityLevel;
      final nextAuto = autoSyncBody ?? hyd.autoSyncTargetByBody;
      final autoComputedMl = AsianHealthBmiTdeeEngine.computeRecommendedWaterMl(
        weightKg: nextWeight,
        heightCm: nextHeight,
        activityLevel: nextAct,
      );
      final resolvedTarget =
          targetMl ?? (nextAuto ? autoComputedMl : hyd.targetWaterMl);

      context.read<DailyLifeBloc>().add(
        HydrationReminderSettingsSaved(
          userId: userId,
          reminderEnabled: enabled ?? hyd.reminderEnabled,
          intervalMinutes: intervalMins ?? hyd.intervalMinutes,
          startHour: startH ?? hyd.startHour,
          startMinute: startM ?? hyd.startMinute,
          endHour: endH ?? hyd.endHour,
          endMinute: endM ?? hyd.endMinute,
          targetWaterMl: resolvedTarget,
          weightKg: nextWeight,
          heightCm: nextHeight,
          activityLevel: nextAct,
          autoSyncTargetByBody: nextAuto,
          preferredCupMl: cupMl ?? hyd.preferredCupMl,
          clearSnooze: clearSnooze,
          customToastMessage: toast,
        ),
      );
    }

    void stepBodyMetric({double deltaWeight = 0, double deltaHeight = 0}) {
      final nextW = double.parse(
        (_weightKg + deltaWeight).clamp(35.0, 150.0).toStringAsFixed(1),
      );
      final nextH = (_heightCm + deltaHeight)
          .clamp(130.0, 210.0)
          .roundToDouble();
      setState(() {
        _userEditedBodyMetrics = true;
        _weightKg = nextW;
        _heightCm = nextH;
      });
      saveSettings(
        weightKg: nextW,
        heightCm: nextH,
        toast: hyd.autoSyncTargetByBody
            ? '✓ Đã cập nhật chỉ số (${nextW.toStringAsFixed(1)} kg · ${nextH.round()} cm) & mục tiêu nước.'
            : '✓ Đã lưu chỉ số cơ thể (${nextW.toStringAsFixed(1)} kg · ${nextH.round()} cm).',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Visual Hydration Wave Vessel + Beverage Selector + 1-Tap Cup Buttons
        LifeOsSoftCard(
          key: const Key('hydration_tracker_card'),
          child: Column(
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
                      const Icon(
                        Icons.water_drop_rounded,
                        color: Color(0xFF0284C7),
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Theo dõi Nước uống Hôm nay',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  LifeOsStatusPill(
                    label: hyd.isGoalReached
                        ? 'Đạt mục tiêu!'
                        : 'Còn ${hyd.remainingMl} ml',
                    tone: hyd.isGoalReached
                        ? LifeOsAccentTone.emerald
                        : LifeOsAccentTone.blue,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 156,
                height: 156,
                child: CustomPaint(
                  painter: _HydrationWaveRingPainter(
                    progress: progressFrac,
                    trackColor: c.surfaceRaised,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${hyd.waterMl} ml',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: c.textPrimary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '/ ${hyd.targetWaterMl} ml (${hyd.progressPct}%)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.textSecondary,
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
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final bev in const [
                    'Nước lọc',
                    'Nước ấm',
                    'Trà nhạt',
                    'Điện giải',
                  ])
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(bev, style: const TextStyle(fontSize: 11.8)),
                      selected: _selectedBeverage == bev,
                      onSelected: (_) =>
                          setState(() => _selectedBeverage = bev),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final cup in const [
                    (150, '+150ml'),
                    (250, '+250ml'),
                    (350, '+350ml'),
                    (500, '+500ml'),
                  ])
                    FilledButton.tonalIcon(
                      key: Key('water_quick_add_${cup.$1}'),
                      onPressed: userId.isEmpty
                          ? null
                          : () => context.read<DailyLifeBloc>().add(
                              WaterIntakeLogged(
                                userId: userId,
                                deltaMl: cup.$1,
                                targetWaterMl: hyd.targetWaterMl,
                                beverageLabel: _selectedBeverage,
                              ),
                            ),
                      icon: const Icon(Icons.local_drink_outlined, size: 16),
                      label: Text(
                        cup.$2,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    key: const Key('water_custom_amount_btn'),
                    onPressed: userId.isEmpty
                        ? null
                        : () => _showCustomWaterDialog(
                            context,
                            userId: userId,
                            targetWaterMl: hyd.targetWaterMl,
                            defaultMl: hyd.preferredCupMl,
                            beverageLabel: _selectedBeverage,
                          ),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Tùy chọn'),
                  ),
                  if (hyd.waterMl > 0)
                    OutlinedButton.icon(
                      key: const Key('water_undo_last_btn'),
                      onPressed: userId.isEmpty
                          ? null
                          : () => context.read<DailyLifeBloc>().add(
                              WaterIntakeLogged(
                                userId: userId,
                                deltaMl: -hyd.lastCupMl,
                                targetWaterMl: hyd.targetWaterMl,
                              ),
                            ),
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Hoàn tác'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Body Profile Hydration Calibration Card (Weight + Height + Activity)
        LifeOsSoftCard(
          key: const Key('hydration_body_calculator_card'),
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
                        Icons.accessibility_new_rounded,
                        size: 20,
                        color: c.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Chỉ số theo Cân nặng & Chiều cao',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  LifeOsStatusPill(
                    label: 'BMI ${assessment.bmi}',
                    tone: (assessment.bmi >= 18.5 && assessment.bmi < 23.0)
                        ? LifeOsAccentTone.emerald
                        : LifeOsAccentTone.amber,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Weight row with tactile +/- steppers, exact tap-input & smooth slider
              Material(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Cân nặng',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 34,
                                height: 34,
                                child: IconButton(
                                  key: const Key('water_weight_minus_btn'),
                                  padding: EdgeInsets.zero,
                                  tooltip: 'Giảm 0.5 kg',
                                  onPressed: () =>
                                      stepBodyMetric(deltaWeight: -0.5),
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                              InkWell(
                                key: const Key('water_weight_exact_tap'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _showExactBodyMetricDialog(
                                  context,
                                  title: 'Nhập cân nặng (kg)',
                                  initialValue: _weightKg.toStringAsFixed(1),
                                  unit: 'kg',
                                  min: 25,
                                  max: 250,
                                  onConfirmed: (val) {
                                    final rounded = double.parse(
                                      val.toStringAsFixed(1),
                                    );
                                    setState(() {
                                      _userEditedBodyMetrics = true;
                                      _weightKg = rounded;
                                    });
                                    saveSettings(weightKg: rounded);
                                  },
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    '${_weightKg.toStringAsFixed(1)} kg',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                      color: c.primary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 34,
                                height: 34,
                                child: IconButton(
                                  key: const Key('water_weight_plus_btn'),
                                  padding: EdgeInsets.zero,
                                  tooltip: 'Tăng 0.5 kg',
                                  onPressed: () =>
                                      stepBodyMetric(deltaWeight: 0.5),
                                  icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Slider(
                        key: const Key('water_weight_slider'),
                        value: _weightKg.clamp(35.0, 130.0),
                        min: 35.0,
                        max: 130.0,
                        divisions: 190,
                        onChanged: (v) => setState(() {
                          _userEditedBodyMetrics = true;
                          _weightKg = double.parse(v.toStringAsFixed(1));
                        }),
                        onChangeEnd: (v) => saveSettings(
                          weightKg: double.parse(v.toStringAsFixed(1)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Height row with tactile +/- steppers, exact tap-input & smooth slider
              Material(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Chiều cao',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 34,
                                height: 34,
                                child: IconButton(
                                  key: const Key('water_height_minus_btn'),
                                  padding: EdgeInsets.zero,
                                  tooltip: 'Giảm 1 cm',
                                  onPressed: () =>
                                      stepBodyMetric(deltaHeight: -1.0),
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                              InkWell(
                                key: const Key('water_height_exact_tap'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _showExactBodyMetricDialog(
                                  context,
                                  title: 'Nhập chiều cao (cm)',
                                  initialValue: '${_heightCm.round()}',
                                  unit: 'cm',
                                  min: 100,
                                  max: 230,
                                  onConfirmed: (val) {
                                    final rounded = val.roundToDouble();
                                    setState(() {
                                      _userEditedBodyMetrics = true;
                                      _heightCm = rounded;
                                    });
                                    saveSettings(heightCm: rounded);
                                  },
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    '${_heightCm.round()} cm',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                      color: c.primary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 34,
                                height: 34,
                                child: IconButton(
                                  key: const Key('water_height_plus_btn'),
                                  padding: EdgeInsets.zero,
                                  tooltip: 'Tăng 1 cm',
                                  onPressed: () =>
                                      stepBodyMetric(deltaHeight: 1.0),
                                  icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Slider(
                        key: const Key('water_height_slider'),
                        value: _heightCm.clamp(135.0, 205.0),
                        min: 135.0,
                        max: 205.0,
                        divisions: 70,
                        onChanged: (v) => setState(() {
                          _userEditedBodyMetrics = true;
                          _heightCm = v.roundToDouble();
                        }),
                        onChangeEnd: (v) =>
                            saveSettings(heightCm: v.roundToDouble()),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Text(
                'Mức độ vận động & Thời tiết',
                style: TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: HydrationActivityLevel.values.map((lvl) {
                  final bonusText = lvl.bonusWaterMl > 0
                      ? ' (+${lvl.bonusWaterMl}ml)'
                      : '';
                  return ChoiceChip(
                    key: Key('water_activity_chip_${lvl.name}'),
                    label: Text(
                      '${lvl.shortLabel}$bonusText',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: hyd.activityLevel == lvl,
                    onSelected: (_) => saveSettings(activity: lvl),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              Material(
                color: c.primarySubtle,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: c.primary.withValues(alpha: 0.25)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mức nước chuẩn theo cơ thể',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: c.textSecondary,
                                ),
                              ),
                              Text(
                                '$bodyRecommendedMl ml / ngày',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: c.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (hyd.targetWaterMl != bodyRecommendedMl ||
                              !hyd.autoSyncTargetByBody)
                            FilledButton.tonalIcon(
                              key: const Key('apply_body_water_target_btn'),
                              onPressed: () => saveSettings(
                                targetMl: bodyRecommendedMl,
                                autoSyncBody: true,
                                toast:
                                    '✓ Đã áp dụng mức chuẩn $bodyRecommendedMl ml/ngày theo cân nặng & chiều cao.',
                              ),
                              icon: const Icon(
                                Icons.auto_fix_high_rounded,
                                size: 16,
                              ),
                              label: const Text('Áp dụng chuẩn'),
                            )
                          else
                            const LifeOsStatusPill(
                              icon: Icons.check_circle_outline_rounded,
                              label: 'Tự động theo chỉ số',
                              tone: LifeOsAccentTone.emerald,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tự cập nhật mục tiêu khi đổi cân nặng / chiều cao',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 12.2,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch(
                            key: const Key('water_auto_sync_body_switch'),
                            value: hyd.autoSyncTargetByBody,
                            onChanged: (v) => saveSettings(
                              autoSyncBody: v,
                              targetMl: v
                                  ? bodyRecommendedMl
                                  : hyd.targetWaterMl,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              LifeOsDetailsDiscloseSection(
                toggleKey: const Key('water_body_metrics_details_toggle'),
                label: 'Chi tiết chỉ số',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        LifeOsStatusPill(
                          icon: Icons.person_pin_circle_outlined,
                          label: assessment.bmiCategory,
                          tone:
                              (assessment.bmi >= 18.5 && assessment.bmi < 23.0)
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.amber,
                        ),
                        LifeOsStatusPill(
                          icon: Icons.monitor_weight_outlined,
                          label:
                              'Lý tưởng: ${assessment.idealMinWeightKg}–${assessment.idealMaxWeightKg} kg',
                          tone: LifeOsAccentTone.emerald,
                        ),
                        LifeOsStatusPill(
                          icon: Icons.local_drink_outlined,
                          label:
                              '~${(hyd.targetWaterMl / hyd.preferredCupMl).ceil()} cốc/ngày',
                          tone: LifeOsAccentTone.blue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Định mức thủ công',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: goalPresets.map((ml) {
                        final isRecommended = ml == bodyRecommendedMl;
                        return ChoiceChip(
                          key: Key('water_goal_chip_$ml'),
                          label: Text(
                            isRecommended ? '$ml ml (Chuẩn)' : '$ml ml',
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: hyd.targetWaterMl == ml,
                          onSelected: (_) => saveSettings(
                            targetMl: ml,
                            autoSyncBody: isRecommended,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Smart Periodic Hydration Reminder Schedule Card
        LifeOsSoftCard(
          key: const Key('hydration_reminder_schedule_card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const Key('toggle_water_reminder_switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Bật chuông nhắc uống nước',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: c.textPrimary,
                  ),
                ),
                subtitle: Text(
                  hyd.reminderEnabled
                      ? (hyd.isGoalReached
                            ? 'Đã đủ nước hôm nay · Nhắc lại ${hyd.startHour.toString().padLeft(2, "0")}:${hyd.startMinute.toString().padLeft(2, "0")} mai'
                            : (nextAt != null
                                  ? 'Nhắc tiếp ${timeFmt.format(nextAt)} (~$paceMl ml)'
                                  : 'Đang bật chuông nhắc định kỳ'))
                      : 'Nhắc định kỳ trong khung giờ thức',
                ),
                value: hyd.reminderEnabled,
                onChanged: (val) {
                  if (val) {
                    NativeAlarmSchedulerBridge.instance
                        .requestNotificationPermission()
                        .then((_) => _refreshBgReadiness());
                  }
                  saveSettings(enabled: val, clearSnooze: true);
                },
              ),
              if (hyd.reminderEnabled && !hyd.isGoalReached) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('water_snooze_15m_btn'),
                      onPressed: userId.isEmpty
                          ? null
                          : () => context.read<DailyLifeBloc>().add(
                              WaterReminderSnoozed(userId: userId, minutes: 15),
                            ),
                      icon: const Icon(Icons.snooze_rounded, size: 16),
                      label: const Text('Hoãn nhắc 15 phút'),
                    ),
                  ],
                ),
              ],
              const Divider(height: 18),
              Text(
                'Chu kỳ nhắc lại',
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
                children: const [30, 45, 60, 90, 120, 180].map((mins) {
                  final label = mins < 60
                      ? 'Mỗi $mins phút'
                      : (mins == 60
                            ? 'Mỗi 1 giờ'
                            : (mins == 90
                                  ? 'Mỗi 90 phút'
                                  : 'Mỗi ${mins ~/ 60} giờ'));
                  return ChoiceChip(
                    key: Key('water_interval_chip_$mins'),
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: hyd.intervalMinutes == mins,
                    onSelected: (_) => saveSettings(intervalMins: mins),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text(
                'Cỡ cốc mỗi lần nhắc (${hyd.preferredCupMl} ml)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: const [150, 200, 250, 300, 350].map((cup) {
                  return ChoiceChip(
                    key: Key('water_cup_size_chip_$cup'),
                    label: Text(
                      '$cup ml',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: hyd.preferredCupMl == cup,
                    onSelected: (_) => saveSettings(cupMl: cup),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text(
                'Khung giờ hoạt động (${hyd.formattedActiveWindow})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    const [
                      (6, 20, '06:00 – 20:00'),
                      (7, 21, '07:00 – 21:00'),
                      (8, 22, '08:00 – 22:00'),
                    ].map((win) {
                      final selected =
                          hyd.startHour == win.$1 &&
                          hyd.startMinute == 0 &&
                          hyd.endHour == win.$2 &&
                          hyd.endMinute == 0;
                      return ChoiceChip(
                        label: Text(
                          win.$3,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: selected,
                        onSelected: (_) => saveSettings(
                          startH: win.$1,
                          startM: 0,
                          endH: win.$2,
                          endM: 0,
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('water_start_time_btn'),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: hyd.startHour,
                          minute: hyd.startMinute,
                        ),
                      );
                      if (picked != null) {
                        final safeStartH = picked.hour.clamp(4, 14);
                        final safeEndH = hyd.endHour <= safeStartH + 1
                            ? (safeStartH + 2).clamp(6, 23)
                            : hyd.endHour;
                        saveSettings(
                          startH: safeStartH,
                          startM: picked.minute,
                          endH: safeEndH,
                        );
                      }
                    },
                    icon: const Icon(Icons.wb_sunny_outlined, size: 16),
                    label: Text(
                      'Thức: ${hyd.startHour.toString().padLeft(2, "0")}:${hyd.startMinute.toString().padLeft(2, "0")}',
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('water_end_time_btn'),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: hyd.endHour,
                          minute: hyd.endMinute,
                        ),
                      );
                      if (picked != null) {
                        final minEnd = (hyd.startHour + 2).clamp(6, 23);
                        saveSettings(
                          endH: picked.hour.clamp(minEnd, 23),
                          endM: picked.minute,
                        );
                      }
                    },
                    icon: const Icon(Icons.bedtime_outlined, size: 16),
                    label: Text(
                      'Nghỉ: ${hyd.endHour.toString().padLeft(2, "0")}:${hyd.endMinute.toString().padLeft(2, "0")}',
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              if (hyd.reminderEnabled && upcomingTodaySlots.isNotEmpty) ...[
                const SizedBox(height: 10),
                LifeOsDetailsDiscloseSection(
                  toggleKey: const Key('water_upcoming_slots_details_toggle'),
                  label: 'Chi tiết mốc nhắc (${upcomingTodaySlots.length})',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: upcomingTodaySlots.take(10).map((slot) {
                      final isFirst = slot == upcomingTodaySlots.first;
                      return LifeOsStatusPill(
                        icon: isFirst
                            ? Icons.notifications_active_outlined
                            : Icons.schedule_rounded,
                        label: timeFmt.format(slot),
                        tone: isFirst
                            ? LifeOsAccentTone.blue
                            : LifeOsAccentTone.neutral,
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Material(
                key: const Key('background_notif_readiness_panel'),
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
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
                                Icons.phonelink_ring_rounded,
                                size: 18,
                                color: c.primary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Thông báo ngoài màn hình & Chạy ngầm',
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 13.2,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          LifeOsStatusPill(
                            icon: _bgReadiness.isFullyOptimized
                                ? Icons.verified_rounded
                                : Icons.info_outline_rounded,
                            label: _bgReadiness.isFullyOptimized
                                ? 'Sẵn sàng'
                                : 'Cần cấp quyền',
                            tone: _bgReadiness.isFullyOptimized
                                ? LifeOsAccentTone.emerald
                                : LifeOsAccentTone.amber,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          LifeOsStatusPill(
                            icon: _bgReadiness.notificationsGranted
                                ? Icons.check_circle_outline_rounded
                                : Icons.notifications_off_outlined,
                            label:
                                'Thông báo: ${_bgReadiness.notificationsGranted ? "Đã cấp" : "Chưa cấp"}',
                            tone: _bgReadiness.notificationsGranted
                                ? LifeOsAccentTone.emerald
                                : LifeOsAccentTone.amber,
                          ),
                          LifeOsStatusPill(
                            icon: _bgReadiness.exactAlarmGranted
                                ? Icons.schedule_rounded
                                : Icons.warning_amber_rounded,
                            label:
                                'Đúng giờ: ${_bgReadiness.exactAlarmGranted ? "Chuẩn" : "Cần bật"}',
                            tone: _bgReadiness.exactAlarmGranted
                                ? LifeOsAccentTone.emerald
                                : LifeOsAccentTone.amber,
                          ),
                          LifeOsStatusPill(
                            icon: _bgReadiness.batteryOptimizationIgnored
                                ? Icons.bolt_rounded
                                : Icons.battery_saver_rounded,
                            label:
                                'Chạy ngầm: ${_bgReadiness.batteryOptimizationIgnored ? "Tối ưu" : "Tiết kiệm pin"}',
                            tone: _bgReadiness.batteryOptimizationIgnored
                                ? LifeOsAccentTone.emerald
                                : LifeOsAccentTone.amber,
                          ),
                        ],
                      ),
                      if (!_bgReadiness.isFullyOptimized) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!_bgReadiness.notificationsGranted)
                              FilledButton.tonalIcon(
                                key: const Key('grant_notif_perm_btn'),
                                onPressed: () async {
                                  final ok = await NativeAlarmSchedulerBridge
                                      .instance
                                      .requestNotificationPermission();
                                  if (!ok) {
                                    await NativeAlarmSchedulerBridge.instance
                                        .openNotificationSettings();
                                  }
                                  await _refreshBgReadiness();
                                },
                                icon: const Icon(
                                  Icons.notifications_active_outlined,
                                  size: 16,
                                ),
                                label: const Text('Bật thông báo'),
                              ),
                            if (!_bgReadiness.exactAlarmGranted)
                              OutlinedButton.icon(
                                key: const Key('grant_exact_alarm_btn'),
                                onPressed: () async {
                                  await NativeAlarmSchedulerBridge.instance
                                      .openExactAlarmSettings();
                                  await _refreshBgReadiness();
                                },
                                icon: const Icon(
                                  Icons.alarm_on_rounded,
                                  size: 16,
                                ),
                                label: const Text('Bật báo đúng giờ'),
                              ),
                            if (!_bgReadiness.batteryOptimizationIgnored)
                              OutlinedButton.icon(
                                key: const Key('grant_unrestricted_bg_btn'),
                                onPressed: () async {
                                  await NativeAlarmSchedulerBridge.instance
                                      .requestIgnoreBatteryOptimizations();
                                  await _refreshBgReadiness();
                                },
                                icon: const Icon(
                                  Icons.battery_charging_full_rounded,
                                  size: 16,
                                ),
                                label: const Text('Bỏ chặn chạy ngầm'),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            key: const Key('test_instant_water_notif_btn'),
                            onPressed: () => context.read<DailyLifeBloc>().add(
                              const WaterTestNotificationRequested(
                                delaySeconds: 0,
                              ),
                            ),
                            icon: const Icon(
                              Icons.notifications_active_outlined,
                              size: 16,
                            ),
                            label: const Text('Gửi thử ngay'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('test_5s_bg_water_notif_btn'),
                            onPressed: () => context.read<DailyLifeBloc>().add(
                              const WaterTestNotificationRequested(
                                delaySeconds: 5,
                              ),
                            ),
                            icon: const Icon(
                              Icons.lock_clock_outlined,
                              size: 16,
                            ),
                            label: const Text('Hẹn 5 giây (Khóa máy)'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 4. Today's Logged Cups History Card
        if (hyd.todayEntries.isNotEmpty) ...[
          const SizedBox(height: 14),
          LifeOsSoftCard(
            key: const Key('hydration_today_log_card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nhật ký uống hôm nay (${hyd.todayEntries.length} lần)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ...hyd.todayEntries.take(12).map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const LifeOsIconSquircle(
                          icon: Icons.local_drink_rounded,
                          tone: LifeOsAccentTone.blue,
                          size: 32,
                          iconSize: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${entry.formattedTime} · ${entry.beverageLabel}',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          '+${entry.ml} ml',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0284C7),
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        IconButton(
                          key: Key('delete_water_entry_${entry.id}'),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Xóa lần ghi này',
                          onPressed: userId.isEmpty
                              ? null
                              : () => context.read<DailyLifeBloc>().add(
                                  WaterIntakeLogged(
                                    userId: userId,
                                    deltaMl: -entry.ml,
                                    targetWaterMl: hyd.targetWaterMl,
                                    deleteEntryId: entry.id,
                                  ),
                                ),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 17,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVitalsTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    DailyLifeSnapshot snap,
    AsianHealthAssessment assessment,
  ) {
    final dtFmt = DateFormat('dd/MM HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chỉ số Cơ thể & Sinh hiệu',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _isMale,
                    onChanged: (v) => setState(() => _isMale = v),
                  ),
                  Text(
                    _isMale ? 'Nam' : 'Nữ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                width: double.infinity,
                child: CustomPaint(
                  painter: _AsianBmiSpectrumPainter(bmi: assessment.bmi),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  LifeOsStatusPill(
                    icon: Icons.person_pin_circle_outlined,
                    label: 'BMI ${assessment.bmi} · ${assessment.bmiCategory}',
                    tone: (assessment.bmi >= 18.5 && assessment.bmi < 23.0)
                        ? LifeOsAccentTone.emerald
                        : LifeOsAccentTone.amber,
                  ),
                  LifeOsStatusPill(
                    icon: Icons.local_fire_department_outlined,
                    label: 'TDEE: ${assessment.tdeeKcal} kcal/ngày',
                    tone: LifeOsAccentTone.blue,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LifeOsDetailsDiscloseSection(
                toggleKey: const Key('vitals_metrics_details_toggle'),
                label: 'Chi tiết chỉ số',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        LifeOsStatusPill(
                          icon: Icons.bolt_rounded,
                          label: 'BMR: ${assessment.bmrKcal} kcal',
                          tone: LifeOsAccentTone.neutral,
                        ),
                        LifeOsStatusPill(
                          icon: Icons.water_drop_outlined,
                          label:
                              'Nước chuẩn: ${assessment.recommendedWaterMl} ml/ngày',
                          tone: LifeOsAccentTone.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cân nặng lý tưởng (${_heightCm.round()} cm): ${assessment.idealMinWeightKg}–${assessment.idealMaxWeightKg} kg · ${assessment.bloodPressureStatus}',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 22),

              _SliderMetricRow(
                label: 'Cân nặng',
                valueLabel: '${_weightKg.toStringAsFixed(1)} kg',
                value: _weightKg,
                min: 35,
                max: 130,
                onChanged: (v) => setState(() => _weightKg = v),
              ),
              _SliderMetricRow(
                label: 'Chiều cao',
                valueLabel: '${_heightCm.round()} cm',
                value: _heightCm,
                min: 135,
                max: 200,
                onChanged: (v) => setState(() => _heightCm = v),
              ),
              _SliderMetricRow(
                label: 'Huyết áp tâm thu',
                valueLabel: '$_systolic/$_diastolic mmHg',
                value: _systolic.toDouble(),
                min: 85,
                max: 180,
                onChanged: (v) => setState(() {
                  _systolic = v.round();
                  _diastolic = (_systolic * 0.65).round().clamp(55, 115);
                }),
              ),
              _SliderMetricRow(
                label: 'Giấc ngủ đêm qua',
                valueLabel:
                    '${_sleepHours.toStringAsFixed(1)} giờ · $_heartRate bpm',
                value: _sleepHours,
                min: 3.5,
                max: 11.0,
                onChanged: (v) => setState(() => _sleepHours = v),
              ),
              const SizedBox(height: 10),
              LifeOsPrimaryCtaButton(
                key: const Key('save_health_vital_btn'),
                label: 'Lưu Chỉ Số Vào Sổ Sức Khỏe',
                icon: Icons.favorite_border_rounded,
                onPressed: userId.isEmpty
                    ? null
                    : () {
                        context.read<DailyLifeBloc>().add(
                          HealthVitalLogAdded(
                            userId: userId,
                            weightKg: double.parse(
                              _weightKg.toStringAsFixed(1),
                            ),
                            heightCm: _heightCm.roundToDouble(),
                            systolicMmHg: _systolic,
                            diastolicMmHg: _diastolic,
                            heartRateBpm: _heartRate,
                            sleepHours: double.parse(
                              _sleepHours.toStringAsFixed(1),
                            ),
                            note: assessment.bmiCategory,
                          ),
                        );
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (snap.healthLogs.isNotEmpty) ...[
          Text(
            'Lịch sử đo gần đây (${snap.healthLogs.length})',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...snap.healthLogs
              .take(5)
              .map(
                (log) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LifeOsSoftCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        const LifeOsIconSquircle(
                          icon: Icons.monitor_weight_outlined,
                          tone: LifeOsAccentTone.emerald,
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${log.weightKg} kg · HA ${log.systolicMmHg}/${log.diastolicMmHg} mmHg · Ngủ ${log.sleepHours}h',
                                softWrap: true,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: c.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(
                                '${dtFmt.format(log.recordedAt)} · ${log.note}',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 11.8,
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
              ),
        ],
      ],
    );
  }

  Widget _buildEmergencyCardTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    EmergencyMedicalCardEntity card,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const LifeOsIconSquircle(
                    icon: Icons.medical_services_rounded,
                    tone: LifeOsAccentTone.coral,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'THẺ Y TẾ KHẨN CẤP (ICE) & BHYT',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  if (card.insuranceCode.trim().isNotEmpty ||
                      card.emergencyContactPhone.trim().isNotEmpty)
                    IconButton(
                      key: const Key('toggle_medical_sensitive_btn'),
                      tooltip: _revealMedicalIdentifiers
                          ? 'Ẩn mã BHYT & SĐT'
                          : 'Hiện mã BHYT & SĐT',
                      onPressed: () => setState(() {
                        _revealMedicalIdentifiers = !_revealMedicalIdentifiers;
                      }),
                      icon: Icon(
                        _revealMedicalIdentifiers
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: c.textSecondary,
                      ),
                    ),
                ],
              ),
              const Divider(height: 22),
              if (!card.isConfigured)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.warningSubtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: c.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Chưa điền thông tin y tế khẩn cấp.',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _MedicalFieldRow(
                label: 'Nhóm máu',
                value: card.bloodType.trim().isEmpty
                    ? 'Chưa cung cấp'
                    : card.bloodType,
              ),
              _MedicalFieldRow(
                label: 'Dị ứng thuốc / thức ăn',
                value: card.allergies.trim().isEmpty
                    ? 'Chưa cung cấp'
                    : card.allergies,
              ),
              _MedicalFieldRow(
                label: 'Tiền sử / Bệnh nền',
                value: card.chronicConditions.trim().isEmpty
                    ? 'Chưa cung cấp'
                    : card.chronicConditions,
              ),
              _MedicalFieldRow(
                label: 'Mã số BHYT',
                value: card.insuranceCode.trim().isEmpty
                    ? 'Chưa cung cấp'
                    : (_revealMedicalIdentifiers
                          ? card.insuranceCode
                          : PrivacyMaskFormatter.maskCode(card.insuranceCode)),
              ),
              _MedicalFieldRow(
                label: 'Nơi ĐK khám chữa bệnh',
                value: card.preferredHospital.trim().isEmpty
                    ? 'Chưa cung cấp'
                    : card.preferredHospital,
              ),
              _MedicalFieldRow(
                label: 'Liên hệ khẩn cấp',
                value:
                    card.emergencyContactName.trim().isEmpty &&
                        card.emergencyContactPhone.trim().isEmpty
                    ? 'Chưa cung cấp'
                    : card.emergencyContactPhone.trim().isEmpty
                    ? card.emergencyContactName
                    : '${card.emergencyContactName} (${_revealMedicalIdentifiers ? card.emergencyContactPhone : PrivacyMaskFormatter.maskPhone(card.emergencyContactPhone)})',
              ),
              const SizedBox(height: 12),
              LifeOsPrimaryCtaButton(
                label: 'Cập nhật Thẻ Y Tế & Mã BHYT',
                icon: Icons.edit_note_rounded,
                onPressed: userId.isEmpty
                    ? null
                    : () => _showEditEmergencyCardSheet(context, userId, card),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tổng đài Khẩn cấp Quốc gia Việt Nam (Miễn cước)',
                softWrap: true,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  LifeOsStatusPill(
                    icon: Icons.local_hospital_rounded,
                    label: '115 · Cấp cứu Y tế',
                    tone: LifeOsAccentTone.coral,
                  ),
                  LifeOsStatusPill(
                    icon: Icons.local_fire_department_rounded,
                    label: '114 · Cứu hỏa & Cứu nạn',
                    tone: LifeOsAccentTone.amber,
                  ),
                  LifeOsStatusPill(
                    icon: Icons.shield_outlined,
                    label: '113 · Cảnh sát Phản ứng nhanh',
                    tone: LifeOsAccentTone.blue,
                  ),
                  LifeOsStatusPill(
                    icon: Icons.child_care_rounded,
                    label: '111 · Bảo vệ Trẻ em',
                    tone: LifeOsAccentTone.emerald,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddMedSheet(BuildContext context, String userId) async {
    final bloc = context.read<DailyLifeBloc>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BlocProvider<DailyLifeBloc>.value(
        value: bloc,
        child: _AddMedicationSheet(userId: userId),
      ),
    );
  }

  Future<void> _showEditMedReminderSheet(
    BuildContext context,
    String userId,
    MedicationCabinetItemEntity med,
  ) async {
    final bloc = context.read<DailyLifeBloc>();
    var enabled = med.reminderEnabled;
    var selectedTime = TimeOfDay(
      hour: med.effectiveReminderHour,
      minute: med.effectiveReminderMinute,
    );

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final c = TammySemanticColors.of(ctx);
            final hh = selectedTime.hour.toString().padLeft(2, '0');
            final mm = selectedTime.minute.toString().padLeft(2, '0');

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hẹn giờ uống thuốc: ${med.name}',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bật chuông báo mỗi ngày'),
                    subtitle: Text('${med.dosage} · ${med.slot.label}'),
                    value: enabled,
                    onChanged: (v) => setModal(() => enabled = v),
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setModal(() => selectedTime = picked);
                        }
                      },
                      icon: const Icon(Icons.access_time_rounded, size: 18),
                      label: Text('Giờ nhắc: $hh:$mm'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  LifeOsPrimaryCtaButton(
                    icon: Icons.check_rounded,
                    label: 'Lưu lịch nhắc',
                    onPressed: () {
                      bloc.add(
                        MedicationReminderUpdated(
                          userId: userId,
                          item: med,
                          reminderEnabled: enabled,
                          reminderHour: selectedTime.hour,
                          reminderMinute: selectedTime.minute,
                        ),
                      );
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditEmergencyCardSheet(
    BuildContext context,
    String userId,
    EmergencyMedicalCardEntity current,
  ) async {
    final bloc = context.read<DailyLifeBloc>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BlocProvider<DailyLifeBloc>.value(
        value: bloc,
        child: _EditEmergencyCardSheet(userId: userId, current: current),
      ),
    );
  }

  Future<void> _showCustomWaterDialog(
    BuildContext context, {
    required String userId,
    required int targetWaterMl,
    required int defaultMl,
    required String beverageLabel,
  }) async {
    final bloc = context.read<DailyLifeBloc>();
    final ml = await showDialog<int>(
      context: context,
      builder: (_) => _CustomWaterDialog(
        initialMl: defaultMl,
        beverageLabel: beverageLabel,
      ),
    );
    if (ml != null && ml > 0) {
      bloc.add(
        WaterIntakeLogged(
          userId: userId,
          deltaMl: ml,
          targetWaterMl: targetWaterMl,
          beverageLabel: beverageLabel,
        ),
      );
    }
  }

  Future<void> _showExactBodyMetricDialog(
    BuildContext context, {
    required String title,
    required String initialValue,
    required String unit,
    required double min,
    required double max,
    required ValueChanged<double> onConfirmed,
  }) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _ExactBodyMetricDialog(
        title: title,
        initialValue: initialValue,
        unit: unit,
        min: min,
        max: max,
      ),
    );
    if (result != null) {
      onConfirmed(result);
    }
  }
}

class _CustomWaterDialog extends StatefulWidget {
  final int initialMl;
  final String beverageLabel;

  const _CustomWaterDialog({
    required this.initialMl,
    required this.beverageLabel,
  });

  @override
  State<_CustomWaterDialog> createState() => _CustomWaterDialogState();
}

class _CustomWaterDialogState extends State<_CustomWaterDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.initialMl}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ghi lượng ${widget.beverageLabel.toLowerCase()}'),
      content: TextField(
        key: const Key('custom_water_ml_input'),
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Dung tích (ml)',
          hintText: 'VD: 220',
          suffixText: 'ml',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('confirm_custom_water_btn'),
          onPressed: () {
            final parsed = int.tryParse(_ctrl.text.trim()) ?? 0;
            if (parsed < 20 || parsed > 3000) {
              LifeOsTopToast.show(
                context,
                'Vui lòng nhập lượng nước từ 20 ml đến 3000 ml.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            Navigator.of(context).pop(parsed);
          },
          child: const Text('Ghi nhận'),
        ),
      ],
    );
  }
}

class _ExactBodyMetricDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String unit;
  final double min;
  final double max;

  const _ExactBodyMetricDialog({
    required this.title,
    required this.initialValue,
    required this.unit,
    required this.min,
    required this.max,
  });

  @override
  State<_ExactBodyMetricDialog> createState() => _ExactBodyMetricDialogState();
}

class _ExactBodyMetricDialogState extends State<_ExactBodyMetricDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('exact_body_metric_input'),
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Giá trị (${widget.unit})',
          suffixText: widget.unit,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('confirm_exact_metric_btn'),
          onPressed: () {
            final normalized = _ctrl.text.trim().replaceAll(',', '.');
            final parsed = double.tryParse(normalized);
            if (parsed == null || parsed < widget.min || parsed > widget.max) {
              LifeOsTopToast.show(
                context,
                'Vui lòng nhập trong khoảng ${widget.min.round()} – ${widget.max.round()} ${widget.unit}.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            Navigator.of(context).pop(parsed);
          },
          child: const Text('Lưu chỉ số'),
        ),
      ],
    );
  }
}

class _AddMedicationSheet extends StatefulWidget {
  final String userId;
  const _AddMedicationSheet({required this.userId});

  @override
  State<_AddMedicationSheet> createState() => _AddMedicationSheetState();
}

class _AddMedicationSheetState extends State<_AddMedicationSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _doseCtrl = TextEditingController(
    text: '1 viên sau ăn',
  );
  final TextEditingController _pillsCtrl = TextEditingController(text: '30');
  MedicationScheduleSlot _selectedSlot = MedicationScheduleSlot.morning;
  bool _reminderEnabled = true;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 7, minute: 30);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _doseCtrl.dispose();
    _pillsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _reminderTime.hour.toString().padLeft(2, '0');
    final mm = _reminderTime.minute.toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Thêm Thuốc & Đặt Chuông Nhắc',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('add_med_name_input'),
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên thuốc',
                hintText: 'VD: Canxi, Vitamin C',
                hintMaxLines: 2,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _doseCtrl,
              decoration: const InputDecoration(
                labelText: 'Liều dùng',
                hintText: 'VD: 1 viên sau ăn',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<MedicationScheduleSlot>(
              isExpanded: true,
              initialValue: _selectedSlot,
              decoration: const InputDecoration(labelText: 'Cữ uống'),
              items: MedicationScheduleSlot.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(s.label),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedSlot = v;
                    _reminderEnabled = v.isScheduledDaily;
                    _reminderTime = TimeOfDay(
                      hour: v.defaultHour,
                      minute: v.defaultMinute,
                    );
                  });
                }
              },
            ),
            if (_selectedSlot.isScheduledDaily) ...[
              const SizedBox(height: 6),
              SwitchListTile(
                key: const Key('add_med_reminder_switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Bật chuông nhắc uống thuốc'),
                subtitle: Text('Giờ nhắc mặc định: $hh:$mm'),
                value: _reminderEnabled,
                onChanged: (v) => setState(() => _reminderEnabled = v),
              ),
              if (_reminderEnabled)
                OutlinedButton.icon(
                  key: const Key('add_med_time_picker_btn'),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _reminderTime,
                    );
                    if (picked != null && mounted) {
                      setState(() => _reminderTime = picked);
                    }
                  },
                  icon: const Icon(Icons.alarm_rounded, size: 18),
                  label: Text('Đổi giờ nhắc ($hh:$mm)'),
                ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _pillsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Số lượng tồn'),
            ),
            const SizedBox(height: 14),
            LifeOsPrimaryCtaButton(
              key: const Key('confirm_save_med_btn'),
              label: 'Lưu vào Tủ thuốc',
              icon: Icons.check_rounded,
              onPressed: () {
                final name = _nameCtrl.text.trim();
                if (name.isEmpty) return;
                context.read<DailyLifeBloc>().add(
                  MedicationCabinetAdded(
                    userId: widget.userId,
                    name: name,
                    dosage: _doseCtrl.text.trim(),
                    slot: _selectedSlot,
                    remainingPills: int.tryParse(_pillsCtrl.text.trim()) ?? 30,
                    expiryDate: DateTime.now().add(const Duration(days: 300)),
                    reminderEnabled:
                        _selectedSlot.isScheduledDaily && _reminderEnabled,
                    reminderHour: _reminderTime.hour,
                    reminderMinute: _reminderTime.minute,
                  ),
                );
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EditEmergencyCardSheet extends StatefulWidget {
  final String userId;
  final EmergencyMedicalCardEntity current;

  const _EditEmergencyCardSheet({required this.userId, required this.current});

  @override
  State<_EditEmergencyCardSheet> createState() =>
      _EditEmergencyCardSheetState();
}

class _EditEmergencyCardSheetState extends State<_EditEmergencyCardSheet> {
  static const _validBloodOptions = [
    '',
    'O+',
    'O-',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
  ];

  late String _blood;
  late final TextEditingController _allergyCtrl;
  late final TextEditingController _bhytCtrl;
  late final TextEditingController _contactNameCtrl;
  late final TextEditingController _contactPhoneCtrl;
  late final TextEditingController _hospitalCtrl;

  @override
  void initState() {
    super.initState();
    _blood = _validBloodOptions.contains(widget.current.bloodType)
        ? widget.current.bloodType
        : '';
    _allergyCtrl = TextEditingController(text: widget.current.allergies);
    _bhytCtrl = TextEditingController(text: widget.current.insuranceCode);
    _contactNameCtrl = TextEditingController(
      text: widget.current.emergencyContactName,
    );
    _contactPhoneCtrl = TextEditingController(
      text: widget.current.emergencyContactPhone,
    );
    _hospitalCtrl = TextEditingController(
      text: widget.current.preferredHospital,
    );
  }

  @override
  void dispose() {
    _allergyCtrl.dispose();
    _bhytCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _hospitalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cập nhật Thẻ Y Tế Khẩn Cấp & BHYT',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _blood,
              decoration: const InputDecoration(labelText: 'Nhóm máu'),
              items: _validBloodOptions
                  .map(
                    (b) => DropdownMenuItem(
                      value: b,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          b.isEmpty ? 'Chưa xét nghiệm' : 'Nhóm máu $b',
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _blood = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _allergyCtrl,
              decoration: const InputDecoration(labelText: 'Dị ứng'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bhytCtrl,
              decoration: const InputDecoration(
                labelText: 'Mã thẻ BHYT',
                hintText: 'VD: DN4797912345',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _hospitalCtrl,
              decoration: const InputDecoration(labelText: 'Bệnh viện KCB'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contactNameCtrl,
              decoration: const InputDecoration(labelText: 'Người liên hệ'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contactPhoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'SĐT khẩn cấp'),
            ),
            const SizedBox(height: 14),
            LifeOsPrimaryCtaButton(
              label: 'Lưu Thẻ Y Tế SOS',
              icon: Icons.save_outlined,
              onPressed: () {
                context.read<DailyLifeBloc>().add(
                  EmergencyMedicalCardSaved(
                    EmergencyMedicalCardEntity(
                      ownerId: widget.userId,
                      bloodType: _blood,
                      allergies: _allergyCtrl.text.trim(),
                      chronicConditions: widget.current.chronicConditions,
                      insuranceCode: _bhytCtrl.text.trim(),
                      emergencyContactName: _contactNameCtrl.text.trim(),
                      emergencyContactPhone: _contactPhoneCtrl.text.trim(),
                      preferredHospital: _hospitalCtrl.text.trim(),
                    ),
                  ),
                );
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroKpiCol extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _HeroKpiCol({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: TextStyle(fontSize: 11.8, color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderMetricRow extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _SliderMetricRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                softWrap: true,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _MedicalFieldRow extends StatelessWidget {
  final String label;
  final String value;

  const _MedicalFieldRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              softWrap: true,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HydrationWaveRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;

  const _HydrationWaveRingPainter({
    required this.progress,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 6;

    // 1. Soft inner wave fill clipped to circle
    final innerCircle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius - 7));
    canvas.save();
    canvas.clipPath(innerCircle);

    final waterHeight = (radius * 2) * progress.clamp(0.06, 1.0);
    final baseWaterY = (center.dy + radius) - waterHeight;
    final wavePath = Path()..moveTo(0, size.height);
    wavePath.lineTo(0, baseWaterY);

    for (var x = 0.0; x <= size.width; x += 4.0) {
      final dy = math.sin((x / size.width) * math.pi * 2) * 4.5;
      wavePath.lineTo(x, baseWaterY + dy);
    }
    wavePath
      ..lineTo(size.width, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: 0.28),
          const Color(0xFF0284C7).withValues(alpha: 0.42),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(wavePath, fillPaint);
    canvas.restore();

    // 2. Outer precision progress ring
    final strokeTrack = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.0;
    canvas.drawCircle(center, radius, strokeTrack);

    final sweep = 2 * math.pi * progress.clamp(0.02, 1.0);
    final strokeActive = Paint()
      ..shader = const SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [Color(0xFF38BDF8), Color(0xFF0284C7), Color(0xFF10B981)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9.0;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      strokeActive,
    );
  }

  @override
  bool shouldRepaint(covariant _HydrationWaveRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.trackColor != trackColor;
}

class _AsianBmiSpectrumPainter extends CustomPainter {
  final double bmi;
  const _AsianBmiSpectrumPainter({required this.bmi});

  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 10, size.width, 14),
      const Radius.circular(8),
    );
    canvas.save();
    canvas.clipRRect(trackRect);

    final segments = <(double frac, Color color)>[
      (0.22, const Color(0xFF38BDF8)),
      (0.32, const Color(0xFF12B847)),
      (0.18, const Color(0xFFF59E0B)),
      (0.28, const Color(0xFFEF4444)),
    ];
    var x = 0.0;
    for (final s in segments) {
      final w = size.width * s.$1;
      canvas.drawRect(Rect.fromLTWH(x, 10, w, 14), Paint()..color = s.$2);
      x += w;
    }
    canvas.restore();

    final normalized = ((bmi - 15.0) / (33.0 - 15.0)).clamp(0.03, 0.97);
    final markerX = size.width * normalized;
    canvas.drawCircle(Offset(markerX, 17), 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(markerX, 17),
      6.5,
      Paint()..color = const Color(0xFF101828),
    );
  }

  @override
  bool shouldRepaint(covariant _AsianBmiSpectrumPainter oldDelegate) =>
      oldDelegate.bmi != bmi;
}
