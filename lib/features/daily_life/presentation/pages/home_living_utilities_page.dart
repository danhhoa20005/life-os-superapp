import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/privacy_mask_formatter.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../../transactions/presentation/bloc/transaction_state.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../bloc/daily_life_bloc.dart';

class HomeLivingUtilitiesPage extends StatefulWidget {
  const HomeLivingUtilitiesPage({super.key});

  @override
  State<HomeLivingUtilitiesPage> createState() =>
      _HomeLivingUtilitiesPageState();
}

class _HomeLivingUtilitiesPageState extends State<HomeLivingUtilitiesPage> {
  String _tab = 'evn';

  // EVN & Roommate Utility Meter Calculator State (2892/QĐ-BCT 5-Tier Default)
  bool _useEvnTiered = true;
  EvnTariffPolicy _evnPolicy = EvnTariffPolicy.qd2892Nov2026;
  int _vatRatePercent = 8;
  int _prevKwh = 1240;
  int _currKwh = 1485; // 245 kWh
  int _prevWater = 82;
  int _currWater = 94; // 12 m3
  int _flatRoomElectricRate = 3800;
  int _waterRatePerM3 = 15000;
  int _fixedInternetTrashMinor = 220000;
  int _splitMembers = 1;

  bool _seededPrevFromReadings = false;
  bool _userEditedMeters = false;
  bool _revealWifiCredentials = false;
  String? _selectedWalletId;
  bool _isSubmittingUtilityPay = false;
  bool _isSubmittingRentPay = false;

  late final TextEditingController _prevKwhCtrl;
  late final TextEditingController _currKwhCtrl;
  late final TextEditingController _prevWaterCtrl;
  late final TextEditingController _currWaterCtrl;
  late final TextEditingController _flatElectricRateCtrl;
  late final TextEditingController _waterRateCtrl;

  @override
  void initState() {
    super.initState();
    _prevKwhCtrl = TextEditingController(text: '$_prevKwh');
    _currKwhCtrl = TextEditingController(text: '$_currKwh');
    _prevWaterCtrl = TextEditingController(text: '$_prevWater');
    _currWaterCtrl = TextEditingController(text: '$_currWater');
    _flatElectricRateCtrl = TextEditingController(
      text: '$_flatRoomElectricRate',
    );
    _waterRateCtrl = TextEditingController(text: '$_waterRatePerM3');
  }

  @override
  void dispose() {
    _prevKwhCtrl.dispose();
    _currKwhCtrl.dispose();
    _prevWaterCtrl.dispose();
    _currWaterCtrl.dispose();
    _flatElectricRateCtrl.dispose();
    _waterRateCtrl.dispose();
    super.dispose();
  }

  void _applyLatestReadingSuggestion(UtilityMeterReadingEntity latest) {
    _prevKwh = latest.currElectricKwh;
    _currKwh =
        latest.currElectricKwh +
        (latest.kwhUsed > 0 ? latest.kwhUsed : 150);
    _prevWater = latest.currWaterM3;
    _currWater =
        latest.currWaterM3 +
        (latest.waterM3Used > 0 ? latest.waterM3Used : 10);
    _prevKwhCtrl.text = '$_prevKwh';
    _currKwhCtrl.text = '$_currKwh';
    _prevWaterCtrl.text = '$_prevWater';
    _currWaterCtrl.text = '$_currWater';
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final userId = user?.id ?? '';
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final String? resolvedWalletId = wallets.isEmpty
        ? null
        : (_selectedWalletId != null &&
                  wallets.any((w) => w.id == _selectedWalletId)
              ? _selectedWalletId!
              : UserBehaviorPrefs.resolvePreferredWalletId(
                  wallets.map((w) => w.id),
                ));
    final monthKey = DateFormat('yyyy-MM').format(DateTime.now());

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
        if (!_seededPrevFromReadings &&
            !_userEditedMeters &&
            snap.utilityReadings.isNotEmpty) {
          _seededPrevFromReadings = true;
          _applyLatestReadingSuggestion(snap.utilityReadings.first);
        }

        final calc = VietnamEvnUtilityEngine.calculate(
          prevElectricKwh: _prevKwh,
          currElectricKwh: _currKwh,
          prevWaterM3: _prevWater,
          currWaterM3: _currWater,
          useEvnTieredTariff: _useEvnTiered,
          policy: _evnPolicy,
          vatRatePercent: _vatRatePercent,
          customFlatElectricVndPerKwh: _flatRoomElectricRate,
          waterVndPerM3: _waterRatePerM3,
          internetAndManagementMinor: _fixedInternetTrashMinor,
          splitMemberCount: _splitMembers,
        );
        final contract = snap.homeContracts.isNotEmpty
            ? snap.homeContracts.first
            : null;

        return Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  const LifeOsTopBrandHeader(
                    title: 'Điện nước EVN & Nhà cửa',
                    showBackButton: true,
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
                            // Hero Bill Summary Card
                            LifeOsMintHeroCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.electric_bolt_rounded,
                                        bananaAsset: AppAssets.icCatUtilities,
                                        tone: LifeOsAccentTone.amber,
                                        size: 42,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Tổng Hóa Đơn Sinh Hoạt Kỳ $monthKey',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              _useEvnTiered
                                                  ? '${_evnPolicy.title} (+$_vatRatePercent% VAT)'
                                                  : 'Biểu giá Điện phòng trọ (${VndAmount.format(_flatRoomElectricRate)}/kWh)',
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
                                  const SizedBox(height: 12),
                                  Text(
                                    VndAmount.format(calc.grandTotalMinor),
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: c.primary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      LifeOsStatusPill(
                                        icon: Icons.electric_meter_outlined,
                                        label: '${calc.kwhConsumed} kWh điện',
                                        tone: LifeOsAccentTone.amber,
                                      ),
                                      LifeOsStatusPill(
                                        icon: Icons.water_drop_outlined,
                                        label:
                                            '${calc.waterM3Consumed} m³ nước',
                                        tone: LifeOsAccentTone.blue,
                                      ),
                                      if (_splitMembers > 1)
                                        LifeOsStatusPill(
                                          icon: Icons.groups_outlined,
                                          label:
                                              'Chia $_splitMembers người: ${VndAmount.format(calc.perPersonShareMinor)}/người',
                                          tone: LifeOsAccentTone.emerald,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            LifeOsSegmentedPills<String>(
                              selected: _tab,
                              onChanged: (v) => setState(() => _tab = v),
                              options: const [
                                (
                                  'evn',
                                  'Công tơ Điện · Nước',
                                  Icons.electric_bolt_rounded,
                                ),
                                (
                                  'lease',
                                  'Thuê nhà & Bảo trì',
                                  Icons.home_work_outlined,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            if (_tab == 'evn')
                              _buildEvnTab(
                                context,
                                c,
                                userId,
                                wallets,
                                resolvedWalletId,
                                monthKey,
                                calc,
                                snap.utilityReadings,
                              )
                            else
                              _buildHomeLeaseTab(
                                context,
                                c,
                                userId,
                                wallets,
                                resolvedWalletId,
                                contract,
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

  Future<void> _payUtilityToWallet({
    required String userId,
    required List<WalletEntity> wallets,
    required String? selectedWalletId,
    required String monthKey,
    required UtilityBillCalculation calc,
    required List<UtilityMeterReadingEntity> readings,
  }) async {
    if (wallets.isEmpty || selectedWalletId == null) {
      LifeOsTopToast.show(
        context,
        'Vui lòng tạo ít nhất 1 Ví trong tab Tài chính trước khi ghi hóa đơn.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    if (_isSubmittingUtilityPay) return;

    final txActionBloc = context.read<TransactionActionBloc>();
    final dailyBloc = context.read<DailyLifeBloc>();
    final amountToPay =
        _splitMembers > 1 ? calc.perPersonShareMinor : calc.grandTotalMinor;

    setState(() => _isSubmittingUtilityPay = true);
    late final TransactionActionState outcome;
    try {
      outcome = await txActionBloc.submitAndAwaitCreate(
        TransactionCreateSubmitted(
          operationId: 'evn_${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          walletId: selectedWalletId,
          categoryId: 'cat_bills',
          categoryName: 'Điện nước',
          kind: TransactionKind.expense,
          amountMinor: amountToPay,
          merchant: 'Điện nước & Internet kỳ $monthKey',
          note: '${calc.kwhConsumed} kWh điện · ${calc.waterM3Consumed} m³ nước',
          occurredAt: DateTime.now(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingUtilityPay = false);
      }
    }

    if (!mounted) return;
    final createdTx = outcome.lastCreatedTransaction;
    if (outcome.status != ActionStatus.success || createdTx == null) {
      LifeOsTopToast.show(
        context,
        outcome.failure?.message ??
            'Không thể ghi hóa đơn Điện Nước vào Ví — vui lòng thử lại.',
        kind: LifeOsToastKind.error,
      );
      return;
    }

    await UserBehaviorPrefs.rememberWallet(selectedWalletId);

    UtilityMeterReadingEntity? matchingUnpaid;
    for (final r in readings) {
      if (!r.isPaid &&
          r.monthKey == monthKey &&
          r.prevElectricKwh == _prevKwh &&
          r.currElectricKwh == _currKwh &&
          r.prevWaterM3 == _prevWater &&
          r.currWaterM3 == _currWater &&
          r.totalAmountMinor == calc.grandTotalMinor) {
        matchingUnpaid = r;
        break;
      }
    }

    if (matchingUnpaid != null) {
      dailyBloc.add(
        UtilityReadingMarkedPaid(
          userId: userId,
          readingId: matchingUnpaid.id,
        ),
      );
    } else {
      dailyBloc.add(
        UtilityReadingSaved(
          userId: userId,
          monthKey: monthKey,
          prevElectricKwh: _prevKwh,
          currElectricKwh: _currKwh,
          prevWaterM3: _prevWater,
          currWaterM3: _currWater,
          useEvnTieredTariff: _useEvnTiered,
          fixedServicesMinor: _fixedInternetTrashMinor,
          totalAmountMinor: calc.grandTotalMinor,
          isPaid: true,
          suppressSuccessBanner: true,
        ),
      );
    }

    if (!mounted) return;
    final confirmedTxId = createdTx.id;
    LifeOsTopToast.show(
      context,
      'Đã ghi hóa đơn Điện Nước (${VndAmount.format(amountToPay)}) vào Ví & đánh dấu đã thanh toán.',
      actionLabel: 'Hoàn tác',
      onAction: () {
        txActionBloc.add(
          TransactionReverseRequested(
            userId: userId,
            transactionId: confirmedTxId,
            reason: 'Hoàn tác hóa đơn Điện Nước',
          ),
        );
        if (mounted) {
          LifeOsTopToast.show(
            context,
            'Đã hoàn tác khoản chi Điện Nước.',
            kind: LifeOsToastKind.info,
          );
        }
      },
    );
  }

  Future<void> _payRentToWallet({
    required String userId,
    required List<WalletEntity> wallets,
    required String? selectedWalletId,
    required HomeContractMaintenanceEntity contract,
  }) async {
    if (wallets.isEmpty || selectedWalletId == null) {
      LifeOsTopToast.show(
        context,
        'Vui lòng tạo ít nhất 1 Ví trong tab Tài chính trước khi đóng tiền nhà.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    if (_isSubmittingRentPay) return;

    final txActionBloc = context.read<TransactionActionBloc>();
    setState(() => _isSubmittingRentPay = true);
    late final TransactionActionState outcome;
    try {
      outcome = await txActionBloc.submitAndAwaitCreate(
        TransactionCreateSubmitted(
          operationId: 'rent_${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          walletId: selectedWalletId,
          categoryId: 'cat_housing',
          categoryName: 'Nhà cửa',
          kind: TransactionKind.expense,
          amountMinor: contract.monthlyRentMinor,
          merchant: 'Tiền thuê ${contract.homeName}',
          note: 'Thanh toán tiền nhà định kỳ',
          occurredAt: DateTime.now(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRentPay = false);
      }
    }

    if (!mounted) return;
    final createdTx = outcome.lastCreatedTransaction;
    if (outcome.status != ActionStatus.success || createdTx == null) {
      LifeOsTopToast.show(
        context,
        outcome.failure?.message ??
            'Không thể ghi khoản Tiền nhà vào Ví — vui lòng thử lại.',
        kind: LifeOsToastKind.error,
      );
      return;
    }

    await UserBehaviorPrefs.rememberWallet(selectedWalletId);
    if (!mounted) return;
    final confirmedTxId = createdTx.id;
    LifeOsTopToast.show(
      context,
      'Đã ghi khoản Tiền nhà (${VndAmount.format(contract.monthlyRentMinor)}) vào Ví.',
      actionLabel: 'Hoàn tác',
      onAction: () {
        txActionBloc.add(
          TransactionReverseRequested(
            userId: userId,
            transactionId: confirmedTxId,
            reason: 'Hoàn tác tiền thuê nhà',
          ),
        );
        if (mounted) {
          LifeOsTopToast.show(
            context,
            'Đã hoàn tác khoản Tiền nhà.',
            kind: LifeOsToastKind.info,
          );
        }
      },
    );
  }

  Widget _buildEvnTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    List<WalletEntity> wallets,
    String? resolvedWalletId,
    String monthKey,
    UtilityBillCalculation calc,
    List<UtilityMeterReadingEntity> readings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Chế độ tính giá Điện',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: c.textPrimary,
                    ),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('EVN 5 bậc'),
                        ),
                      ),
                      ButtonSegment(
                        value: false,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Phòng trọ'),
                        ),
                      ),
                    ],
                    selected: {_useEvnTiered},
                    onSelectionChanged: (s) =>
                        setState(() => _useEvnTiered = s.first),
                  ),
                ],
              ),
              if (_useEvnTiered) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<EvnTariffPolicy>(
                  isExpanded: true,
                  initialValue: _evnPolicy,
                  decoration: const InputDecoration(
                    labelText: 'Biểu giá điện',
                    isDense: true,
                  ),
                  items: EvnTariffPolicy.values
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(p.title),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _evnPolicy = v);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Thuế suất GTGT (VAT) áp dụng theo kỳ',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('8%'),
                      selected: _vatRatePercent == 8,
                      onSelected: (_) => setState(() => _vatRatePercent = 8),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('10%'),
                      selected: _vatRatePercent == 10,
                      onSelected: (_) => setState(() => _vatRatePercent = 10),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 10),
                TextField(
                  key: const Key('flat_electric_rate_input'),
                  controller: _flatElectricRateCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  decoration: const InputDecoration(
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Đơn giá điện phòng trọ (₫/kWh)'),
                    ),
                    isDense: true,
                    suffixText: '₫/kWh',
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null) {
                      setState(() {
                        _flatRoomElectricRate = parsed.clamp(0, 50000);
                      });
                    }
                  },
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                key: const Key('water_rate_input'),
                controller: _waterRateCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('Đơn giá nước sạch (₫/m³)'),
                  ),
                  isDense: true,
                  suffixText: '₫/m³',
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v.trim());
                  if (parsed != null) {
                    setState(() {
                      _waterRatePerM3 = parsed.clamp(0, 200000);
                    });
                  }
                },
              ),
              if (readings.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    key: const Key('prefill_prev_meter_chip'),
                    avatar: const Icon(Icons.history_rounded, size: 16),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Điền kỳ trước từ ${readings.first.monthKey} (${readings.first.currElectricKwh} kWh · ${readings.first.currWaterM3} m³)',
                        style: const TextStyle(
                          fontSize: 11.8,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _userEditedMeters = true;
                        _applyLatestReadingSuggestion(readings.first);
                      });
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('prev_electric_kwh_input'),
                      controller: _prevKwhCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('Điện kỳ trước'),
                        ),
                        isDense: true,
                        suffixText: 'kWh',
                      ),
                      onChanged: (v) {
                        final parsed = int.tryParse(v.trim());
                        if (parsed != null) {
                          setState(() {
                            _userEditedMeters = true;
                            _prevKwh = parsed.clamp(0, 999999);
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const Key('curr_electric_kwh_input'),
                      controller: _currKwhCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('Điện kỳ này'),
                        ),
                        isDense: true,
                        suffixText: 'kWh',
                      ),
                      onChanged: (v) {
                        final parsed = int.tryParse(v.trim());
                        if (parsed != null) {
                          setState(() {
                            _userEditedMeters = true;
                            _currKwh = parsed.clamp(0, 999999);
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _MeterSliderControl(
                title: 'Sản lượng Điện tiêu thụ trong tháng',
                trailing: '$_prevKwh → $_currKwh (${calc.kwhConsumed} kWh)',
                value: calc.kwhConsumed.toDouble().clamp(0, 900),
                min: 0,
                max: 900,
                onChanged: (v) => setState(() {
                  _userEditedMeters = true;
                  _currKwh = _prevKwh + v.round();
                  _currKwhCtrl.text = '$_currKwh';
                }),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('prev_water_m3_input'),
                      controller: _prevWaterCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('Nước kỳ trước'),
                        ),
                        isDense: true,
                        suffixText: 'm³',
                      ),
                      onChanged: (v) {
                        final parsed = int.tryParse(v.trim());
                        if (parsed != null) {
                          setState(() {
                            _userEditedMeters = true;
                            _prevWater = parsed.clamp(0, 999999);
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const Key('curr_water_m3_input'),
                      controller: _currWaterCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('Nước kỳ này'),
                        ),
                        isDense: true,
                        suffixText: 'm³',
                      ),
                      onChanged: (v) {
                        final parsed = int.tryParse(v.trim());
                        if (parsed != null) {
                          setState(() {
                            _userEditedMeters = true;
                            _currWater = parsed.clamp(0, 999999);
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _MeterSliderControl(
                title: 'Khối lượng Nước sạch tiêu thụ',
                trailing:
                    '$_prevWater → $_currWater (${calc.waterM3Consumed} m³)',
                value: calc.waterM3Consumed.toDouble().clamp(0, 50),
                min: 0,
                max: 50,
                onChanged: (v) => setState(() {
                  _userEditedMeters = true;
                  _currWater = _prevWater + v.round();
                  _currWaterCtrl.text = '$_currWater';
                }),
              ),
              _MeterSliderControl(
                title: 'Internet cáp quang + Rác / Phí quản lý',
                trailing: VndAmount.format(_fixedInternetTrashMinor),
                value: (_fixedInternetTrashMinor / 10000).clamp(0, 150),
                min: 0,
                max: 150,
                onChanged: (v) => setState(
                  () => _fixedInternetTrashMinor = v.round() * 10000,
                ),
              ),
              _MeterSliderControl(
                title: 'Chia đều hóa đơn cho số thành viên',
                trailing: '$_splitMembers người',
                value: _splitMembers.toDouble(),
                min: 1,
                max: 8,
                onChanged: (v) => setState(() => _splitMembers = v.round()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Detailed Tier-by-Tier Breakdown Card
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bóc tách chi tiết từng bậc thang & phụ phí',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ...calc.evnTiers.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t.rangeLabel} · ${t.kwhUsed} kWh × ${VndAmount.format(t.unitPriceVnd)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        VndAmount.format(t.subtotalMinor),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.8,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_useEvnTiered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Thuế GTGT Điện (VAT $_vatRatePercent%)',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        VndAmount.format(calc.electricityVatMinor),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.8,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tiền Nước (${calc.waterM3Consumed} m³)',
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                  ),
                  Text(
                    VndAmount.format(calc.waterTotalMinor),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.8,
                      color: c.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Internet & Phí quản lý cố định',
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                  ),
                  Text(
                    VndAmount.format(calc.fixedServicesMinor),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.8,
                      color: c.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              if (wallets.length > 1) ...[
                DropdownButtonFormField<String>(
                  key: const Key('utility_wallet_selector'),
                  isExpanded: true,
                  initialValue: resolvedWalletId,
                  decoration: const InputDecoration(
                    labelText: 'Chọn Ví thanh toán hóa đơn',
                    isDense: true,
                  ),
                  items: wallets
                      .map(
                        (w) => DropdownMenuItem(
                          value: w.id,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${w.name} (${VndAmount.format(w.balanceMinor)})',
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedWalletId = v);
                  },
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('save_utility_reading_btn'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      onPressed: userId.isEmpty
                          ? null
                          : () {
                              context.read<DailyLifeBloc>().add(
                                UtilityReadingSaved(
                                  userId: userId,
                                  monthKey: monthKey,
                                  prevElectricKwh: _prevKwh,
                                  currElectricKwh: _currKwh,
                                  prevWaterM3: _prevWater,
                                  currWaterM3: _currWater,
                                  useEvnTieredTariff: _useEvnTiered,
                                  fixedServicesMinor: _fixedInternetTrashMinor,
                                  totalAmountMinor: calc.grandTotalMinor,
                                ),
                              );
                            },
                      icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Lưu chỉ số tháng'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('pay_utility_to_wallet_btn'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      onPressed: userId.isEmpty || _isSubmittingUtilityPay
                          ? null
                          : () => _payUtilityToWallet(
                              userId: userId,
                              wallets: wallets,
                              selectedWalletId: resolvedWalletId,
                              monthKey: monthKey,
                              calc: calc,
                              readings: readings,
                            ),
                      icon: const Icon(Icons.payments_outlined, size: 17),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Ghi vào Ví'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (readings.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Lịch sử chốt công tơ (${readings.length})',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...readings
              .take(4)
              .map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LifeOsSoftCard(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        LifeOsIconSquircle(
                          icon: r.isPaid
                              ? Icons.verified_rounded
                              : Icons.receipt_long_outlined,
                          tone: r.isPaid
                              ? LifeOsAccentTone.emerald
                              : LifeOsAccentTone.amber,
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kỳ ${r.monthKey} · ${VndAmount.format(r.totalAmountMinor)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.8,
                                  color: c.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(
                                'Điện: ${r.kwhUsed} kWh · Nước: ${r.waterM3Used} m³',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!r.isPaid)
                          TextButton(
                            onPressed: () => context.read<DailyLifeBloc>().add(
                              UtilityReadingMarkedPaid(
                                userId: userId,
                                readingId: r.id,
                              ),
                            ),
                            child: const Text('Đã đóng'),
                          )
                        else
                          const LifeOsStatusPill(
                            label: 'Đã thanh toán',
                            tone: LifeOsAccentTone.emerald,
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

  Widget _buildHomeLeaseTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    List<WalletEntity> wallets,
    String? resolvedWalletId,
    HomeContractMaintenanceEntity? contract,
  ) {
    if (contract == null) {
      return LifeOsSoftCard(
        key: const Key('empty_home_contract_card'),
        child: Column(
          children: [
            const LifeOsIconSquircle(
              icon: Icons.home_work_outlined,
              tone: LifeOsAccentTone.blue,
              size: 46,
            ),
            const SizedBox(height: 10),
            Text(
              'Chưa thiết lập Hợp đồng thuê nhà',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Lưu thông tin tiền thuê hằng tháng, tiền đặt cọc, ngày đóng tiền, hạn hợp đồng và mật khẩu Wi-Fi riêng tư tại đây.',
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
            const SizedBox(height: 14),
            LifeOsPrimaryCtaButton(
              key: const Key('setup_home_contract_btn'),
              label: 'Thiết lập Hợp đồng thuê nhà',
              icon: Icons.add_home_work_outlined,
              onPressed: userId.isEmpty
                  ? null
                  : () => _showEditContractSheet(context, userId, null),
            ),
          ],
        ),
      );
    }

    final dateFmt = DateFormat('dd/MM/yyyy');
    final hasWifi = contract.wifiCredentials.trim().isNotEmpty;
    final wifiLabel = !hasWifi
        ? 'Chưa lưu Wi-Fi khách'
        : (_revealWifiCredentials
              ? contract.wifiCredentials
              : PrivacyMaskFormatter.maskCode(contract.wifiCredentials));

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
                    icon: Icons.apartment_rounded,
                    tone: LifeOsAccentTone.blue,
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contract.homeName,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          'Đóng tiền ngày ${contract.paymentDayOfMonth} hằng tháng · Hết hạn HĐ: ${dateFmt.format(contract.leaseEndDate)}',
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
                ],
              ),
              const Divider(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tiền thuê / tháng',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            VndAmount.format(contract.monthlyRentMinor),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tiền đặt cọc đang giữ',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            VndAmount.format(contract.depositMinor),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: c.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Flexible(
                    child: LifeOsStatusPill(
                      icon: Icons.wifi_rounded,
                      label: wifiLabel,
                      tone: LifeOsAccentTone.purple,
                    ),
                  ),
                  if (hasWifi) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      key: const Key('toggle_home_wifi_reveal_btn'),
                      visualDensity: VisualDensity.compact,
                      tooltip: _revealWifiCredentials
                          ? 'Ẩn thông tin Wi-Fi'
                          : 'Hiện thông tin Wi-Fi',
                      onPressed: () => setState(
                        () => _revealWifiCredentials = !_revealWifiCredentials,
                      ),
                      icon: Icon(
                        _revealWifiCredentials
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 19,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
              if (contract.nextApplianceMaintenanceNote.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Bảo trì thiết bị nhà cửa: ${contract.nextApplianceMaintenanceNote}',
                  softWrap: true,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
              ],
              if (wallets.length > 1 && contract.monthlyRentMinor > 0) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('rent_wallet_selector'),
                  isExpanded: true,
                  initialValue: resolvedWalletId,
                  decoration: const InputDecoration(
                    labelText: 'Chọn Ví đóng tiền nhà',
                    isDense: true,
                  ),
                  items: wallets
                      .map(
                        (w) => DropdownMenuItem(
                          value: w.id,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${w.name} (${VndAmount.format(w.balanceMinor)})',
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedWalletId = v);
                  },
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('edit_home_contract_btn'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      onPressed: userId.isEmpty
                          ? null
                          : () => _showEditContractSheet(
                              context,
                              userId,
                              contract,
                            ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Cập nhật HĐ'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('pay_rent_to_wallet_btn'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      onPressed:
                          userId.isEmpty ||
                              contract.monthlyRentMinor <= 0 ||
                              _isSubmittingRentPay
                          ? null
                          : () => _payRentToWallet(
                              userId: userId,
                              wallets: wallets,
                              selectedWalletId: resolvedWalletId,
                              contract: contract,
                            ),
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                      ),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Đóng tiền nhà'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showEditContractSheet(
    BuildContext context,
    String userId,
    HomeContractMaintenanceEntity? current,
  ) async {
    final bloc = context.read<DailyLifeBloc>();
    final nameCtrl = TextEditingController(text: current?.homeName ?? '');
    final rentCtrl = TextEditingController(
      text: current != null && current.monthlyRentMinor > 0
          ? '${current.monthlyRentMinor}'
          : '',
    );
    final depCtrl = TextEditingController(
      text: current != null && current.depositMinor > 0
          ? '${current.depositMinor}'
          : '',
    );
    final wifiCtrl = TextEditingController(
      text: current?.wifiCredentials ?? '',
    );
    final maintCtrl = TextEditingController(
      text: current?.nextApplianceMaintenanceNote ?? '',
    );
    var paymentDay = (current?.paymentDayOfMonth ?? 5).clamp(1, 31);
    var leaseEndDate =
        current?.leaseEndDate ?? DateTime.now().add(const Duration(days: 365));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final leaseFmt = DateFormat('dd/MM/yyyy').format(leaseEndDate);
            return Padding(
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
                    Text(
                      current == null
                          ? 'Thiết lập Hợp đồng thuê nhà'
                          : 'Cập nhật Hợp đồng Nhà & Bảo trì',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('contract_home_name_input'),
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên căn hộ / Phòng trọ',
                        hintText: 'VD: Phòng 402 · Chung cư Sunrise',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('contract_rent_input'),
                            controller: rentCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Tiền thuê/tháng (₫)',
                              hintText: 'VD: 6500000',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: const Key('contract_deposit_input'),
                            controller: depCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Tiền đặt cọc (₫)',
                              hintText: 'VD: 13000000',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      key: const Key('contract_payment_day_dropdown'),
                      isExpanded: true,
                      initialValue: paymentDay,
                      decoration: const InputDecoration(
                        labelText: 'Ngày đóng tiền hằng tháng',
                      ),
                      items: List.generate(31, (i) => i + 1)
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(
                                'Ngày $d hằng tháng',
                                style: const TextStyle(
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModal(() => paymentDay = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('contract_lease_end_picker_btn'),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: leaseEndDate.isBefore(DateTime(2020))
                              ? now.add(const Duration(days: 365))
                              : leaseEndDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(now.year + 20),
                        );
                        if (picked != null && ctx.mounted) {
                          setModal(() => leaseEndDate = picked);
                        }
                      },
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text(
                        'Ngày hết hạn hợp đồng: $leaseFmt',
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('contract_wifi_input'),
                      controller: wifiCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên & Mật khẩu Wi-Fi / Mã thẻ cư dân',
                        hintText: 'VD: VNPT_5G / Mật khẩu...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('contract_maint_input'),
                      controller: maintCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú vệ sinh máy lạnh / lọc nước RO',
                        hintText: 'VD: Vệ sinh điều hòa & thay lõi lọc RO',
                      ),
                    ),
                    const SizedBox(height: 14),
                    LifeOsPrimaryCtaButton(
                      key: const Key('confirm_save_home_contract_btn'),
                      label: 'Lưu Hợp đồng & Lịch Bảo trì',
                      icon: Icons.check_rounded,
                      onPressed: () {
                        final homeName = nameCtrl.text.trim();
                        if (homeName.isEmpty) {
                          LifeOsTopToast.show(
                            ctx,
                            'Vui lòng nhập tên căn hộ hoặc phòng trọ.',
                            kind: LifeOsToastKind.warning,
                          );
                          return;
                        }
                        final rentMinor =
                            VndAmount.tryParseInput(rentCtrl.text) ??
                            int.tryParse(rentCtrl.text.trim()) ??
                            0;
                        final depMinor =
                            VndAmount.tryParseInput(depCtrl.text) ??
                            int.tryParse(depCtrl.text.trim()) ??
                            0;
                        bloc.add(
                          HomeContractSaved(
                            userId: userId,
                            homeName: homeName,
                            monthlyRentMinor: rentMinor.clamp(0, 1000000000),
                            depositMinor: depMinor.clamp(0, 5000000000),
                            paymentDayOfMonth: paymentDay,
                            leaseEndDate: leaseEndDate,
                            wifiCredentials: wifiCtrl.text.trim(),
                            nextApplianceMaintenanceNote: maintCtrl.text.trim(),
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
      },
    );
  }
}

class _MeterSliderControl extends StatelessWidget {
  final String title;
  final String trailing;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _MeterSliderControl({
    required this.title,
    required this.trailing,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              softWrap: true,
              style: TextStyle(fontSize: 12.8, color: c.textSecondary),
            ),
            Text(
              trailing,
              style: TextStyle(
                fontSize: 13,
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
