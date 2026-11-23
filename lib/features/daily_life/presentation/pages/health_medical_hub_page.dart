import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../bloc/daily_life_bloc.dart';

class HealthMedicalHubPage extends StatefulWidget {
  const HealthMedicalHubPage({super.key});

  @override
  State<HealthMedicalHubPage> createState() => _HealthMedicalHubPageState();
}

class _HealthMedicalHubPageState extends State<HealthMedicalHubPage> {
  String _tab = 'meds';

  // Interactive Asian BMI / TDEE / Blood Pressure Calculator State
  double _weightKg = 63.0;
  double _heightCm = 168.0;
  final int _ageYears = 29;
  bool _isMale = true;
  int _systolic = 118;
  int _diastolic = 76;
  int _heartRate = 72;
  double _sleepHours = 7.5;
  bool _hydratedFromLogs = false;

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
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final userId = user?.id ?? '';

    return BlocConsumer<DailyLifeBloc, DailyLifeState>(
      listenWhen: (p, n) =>
          p.successBanner != n.successBanner || p.failure != n.failure,
      listener: (context, state) {
        if (state.successBanner != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text(state.successBanner!)),
          );
        } else if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text(state.failure!.message)),
          );
        }
      },
      builder: (context, state) {
        final snap = state.snapshot;
        if (!_hydratedFromLogs && snap.healthLogs.isNotEmpty) {
          final latest = snap.healthLogs.first;
          _weightKg = latest.weightKg;
          _heightCm = latest.heightCm;
          _systolic = latest.systolicMmHg;
          _diastolic = latest.diastolicMmHg;
          _heartRate = latest.heartRateBpm;
          _sleepHours = latest.sleepHours;
          _hydratedFromLogs = true;
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
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'Nhóm máu ${snap.emergencyCard.bloodType} · ${assessment.bmiCategory}',
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
                                          width: 16,
                                          color: c.separator,
                                        ),
                                        _HeroKpiCol(
                                          value: '${assessment.bmi}',
                                          label: 'BMI Châu Á',
                                          color: const Color(0xFF0EA5E9),
                                        ),
                                        VerticalDivider(
                                          width: 16,
                                          color: c.separator,
                                        ),
                                        _HeroKpiCol(
                                          value: '$_systolic/$_diastolic',
                                          label: 'Huyết áp mmHg',
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
                                ('meds', 'Tủ thuốc', Icons.medication_outlined),
                                (
                                  'vitals',
                                  'BMI & Chỉ số',
                                  Icons.monitor_heart_outlined,
                                ),
                                (
                                  'sos',
                                  'Thẻ SOS',
                                  Icons.medical_information_outlined,
                                ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thêm nhanh thuốc & thực phẩm bổ sung phổ biến',
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
              label: Text(p.name, style: const TextStyle(fontSize: 12.5)),
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
          label: '+ Thêm thuốc / Vitamin vào Tủ thuốc',
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
                const SizedBox(height: 4),
                Text(
                  'Chọn nhanh các mẫu Vitamin, Hạ sốt, Oresol phía trên để nhắc uống đúng cữ và cảnh báo trước khi thuốc hết hạn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
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
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                '${med.dosage} · ${med.slot.label}',
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
                        LifeOsStatusPill(
                          icon: Icons.inventory_2_outlined,
                          label: 'Còn ${med.remainingPills} viên/gói',
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
                        FilledButton.tonalIcon(
                          onPressed: () => context.read<DailyLifeBloc>().add(
                            MedicationTakenToggled(userId: userId, item: med),
                          ),
                          icon: Icon(
                            taken
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 17,
                          ),
                          label: Text(
                            taken ? 'Đã uống hôm nay' : 'Đánh dấu đã uống',
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
                      'Thước đo BMI Chuẩn Châu Á & Năng lượng TDEE',
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
                'Cân nặng lý tưởng cho chiều cao ${_heightCm.round()} cm: ${assessment.idealMinWeightKg} kg – ${assessment.idealMaxWeightKg} kg · ${assessment.bloodPressureStatus}',
                style: TextStyle(fontSize: 12.2, color: c.textSecondary),
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
        // High-visibility Emergency Medical Card
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'THẺ Y TẾ KHẨN CẤP (ICE) & BHYT',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          'Xuất trình nhanh khi khám chữa bệnh hoặc cấp cứu',
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
                    : card.insuranceCode,
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
                    : '${card.emergencyContactName} (${card.emergencyContactPhone})',
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
    final nameCtrl = TextEditingController();
    final doseCtrl = TextEditingController(text: '1 viên sau ăn');
    final pillsCtrl = TextEditingController(text: '30');
    var selectedSlot = MedicationScheduleSlot.morning;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Thêm Thuốc / Thực phẩm chức năng',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên thuốc hoặc Vitamin',
                    hintText: 'VD: Canxi hữu cơ, Siro ho Thảo dược...',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: doseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Liều dùng & Ghi chú',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<MedicationScheduleSlot>(
                  isExpanded: true,
                  initialValue: selectedSlot,
                  decoration: const InputDecoration(
                    labelText: 'Khung giờ uống',
                  ),
                  items: MedicationScheduleSlot.values
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setModal(() => selectedSlot = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pillsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số lượng tồn (viên/gói)',
                  ),
                ),
                const SizedBox(height: 14),
                LifeOsPrimaryCtaButton(
                  label: 'Lưu vào Tủ thuốc',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    context.read<DailyLifeBloc>().add(
                      MedicationCabinetAdded(
                        userId: userId,
                        name: name,
                        dosage: doseCtrl.text.trim(),
                        slot: selectedSlot,
                        remainingPills:
                            int.tryParse(pillsCtrl.text.trim()) ?? 30,
                        expiryDate: DateTime.now().add(
                          const Duration(days: 300),
                        ),
                      ),
                    );
                    Navigator.of(sheetCtx).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditEmergencyCardSheet(
    BuildContext context,
    String userId,
    EmergencyMedicalCardEntity current,
  ) async {
    const validBloodOptions = [
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
    var blood = validBloodOptions.contains(current.bloodType)
        ? current.bloodType
        : '';
    final allergyCtrl = TextEditingController(text: current.allergies);
    final bhytCtrl = TextEditingController(text: current.insuranceCode);
    final contactNameCtrl = TextEditingController(
      text: current.emergencyContactName,
    );
    final contactPhoneCtrl = TextEditingController(
      text: current.emergencyContactPhone,
    );
    final hospitalCtrl = TextEditingController(text: current.preferredHospital);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
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
                    initialValue: blood,
                    decoration: const InputDecoration(
                      labelText: 'Nhóm máu (theo phiếu xét nghiệm)',
                    ),
                    items: validBloodOptions
                        .map(
                          (b) => DropdownMenuItem(
                            value: b,
                            child: Text(
                              b.isEmpty
                                  ? 'Chưa biết / Chưa xét nghiệm'
                                  : 'Nhóm máu $b',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setModal(() => blood = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: allergyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dị ứng thuốc / Thực phẩm',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bhytCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mã số Thẻ BHYT (10 chữ số BHXH)',
                      hintText: 'VD: DN4797912345678',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: hospitalCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bệnh viện đăng ký KCB ban đầu',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: contactNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Người liên hệ khẩn cấp',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: contactPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại khẩn cấp',
                    ),
                  ),
                  const SizedBox(height: 14),
                  LifeOsPrimaryCtaButton(
                    label: 'Lưu Thẻ Y Tế SOS',
                    icon: Icons.save_outlined,
                    onPressed: () {
                      context.read<DailyLifeBloc>().add(
                        EmergencyMedicalCardSaved(
                          EmergencyMedicalCardEntity(
                            ownerId: userId,
                            bloodType: blood,
                            allergies: allergyCtrl.text.trim(),
                            chronicConditions: current.chronicConditions,
                            insuranceCode: bhytCtrl.text.trim(),
                            emergencyContactName: contactNameCtrl.text.trim(),
                            emergencyContactPhone: contactPhoneCtrl.text.trim(),
                            preferredHospital: hospitalCtrl.text.trim(),
                          ),
                        ),
                      );
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.8, color: c.textSecondary),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
          SizedBox(
            width: 142,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
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
      (0.22, const Color(0xFF38BDF8)), // <18.5
      (0.32, const Color(0xFF12B847)), // 18.5 - 22.9 (Asian Ideal)
      (0.18, const Color(0xFFF59E0B)), // 23.0 - 24.9
      (0.28, const Color(0xFFEF4444)), // >=25.0
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
