import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../domain/entities/daily_life_entities.dart';
import '../bloc/daily_life_bloc.dart';

class HomeLivingUtilitiesPage extends StatefulWidget {
  const HomeLivingUtilitiesPage({super.key});

  @override
  State<HomeLivingUtilitiesPage> createState() => _HomeLivingUtilitiesPageState();
}

class _HomeLivingUtilitiesPageState extends State<HomeLivingUtilitiesPage> {
  String _tab = 'evn';

  // EVN & Roommate Utility Meter Calculator State (2892/QĐ-BCT 5-Tier Default)
  bool _useEvnTiered = true;
  EvnTariffPolicy _evnPolicy = EvnTariffPolicy.qd2892Nov2026;
  int _vatRatePercent = 8;
  final int _prevKwh = 1240;
  int _currKwh = 1485; // 245 kWh
  final int _prevWater = 82;
  int _currWater = 94; // 12 m3
  final int _flatRoomElectricRate = 3800;
  final int _waterRatePerM3 = 15000;
  int _fixedInternetTrashMinor = 220000;
  int _splitMembers = 1;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final userId = user?.id ?? '';
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final primaryWalletId = wallets.isNotEmpty ? wallets.first.id : 'wallet_bank_default';
    final monthKey = DateFormat('yyyy-MM').format(DateTime.now());

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

    return BlocConsumer<DailyLifeBloc, DailyLifeState>(
      listenWhen: (p, n) =>
          p.successBanner != n.successBanner || p.failure != n.failure,
      listener: (context, state) {
        if (state.successBanner != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.successBanner!)),
          );
        } else if (state.failure != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.failure!.message)),
          );
        }
      },
      builder: (context, state) {
        final snap = state.snapshot;
        final contract =
            snap.homeContracts.isNotEmpty ? snap.homeContracts.first : null;

        return Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  const LifeOsTopBrandHeader(
                    title: 'Điện nước EVN & Nhà cửa',
                    subtitle:
                        'Biểu giá điện 5 bậc EVN (QĐ 2892/QĐ-BCT), chia phòng trọ & hợp đồng nhà.',
                    showBackButton: true,
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
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
                                        icon: Icons.bolt_rounded,
                                        tone: LifeOsAccentTone.amber,
                                        size: 42,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                      fontFeatures: const [FontFeature.tabularFigures()],
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
                                        label: '${calc.waterM3Consumed} m³ nước',
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
                                ('evn', 'Công tơ Điện · Nước', Icons.electric_bolt_rounded),
                                ('lease', 'Thuê nhà & Bảo trì', Icons.home_work_outlined),
                              ],
                            ),
                            const SizedBox(height: 14),

                            if (_tab == 'evn')
                              _buildEvnTab(
                                context,
                                c,
                                userId,
                                primaryWalletId,
                                monthKey,
                                calc,
                                snap.utilityReadings,
                              )
                            else
                              _buildHomeLeaseTab(
                                context,
                                c,
                                userId,
                                primaryWalletId,
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

  Widget _buildEvnTab(
    BuildContext context,
    TammySemanticColors c,
    String userId,
    String primaryWalletId,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chế độ tính giá Điện',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('EVN 5 bậc')),
                      ButtonSegment(value: false, label: Text('Phòng trọ')),
                    ],
                    selected: {_useEvnTiered},
                    onSelectionChanged: (s) => setState(() => _useEvnTiered = s.first),
                  ),
                ],
              ),
              if (_useEvnTiered) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<EvnTariffPolicy>(
                  isExpanded: true,
                  initialValue: _evnPolicy,
                  decoration: const InputDecoration(
                    labelText: 'Chính sách biểu giá Bộ Công Thương',
                    isDense: true,
                  ),
                  items: EvnTariffPolicy.values
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.title)))
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
                        style: TextStyle(fontSize: 12.5, color: c.textSecondary),
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
              ],
              const SizedBox(height: 12),

              _MeterSliderControl(
                title: 'Sản lượng Điện tiêu thụ trong tháng',
                trailing:
                    '$_prevKwh → $_currKwh (${calc.kwhConsumed} kWh)',
                value: calc.kwhConsumed.toDouble().clamp(20, 900),
                min: 20,
                max: 900,
                onChanged: (v) => setState(() => _currKwh = _prevKwh + v.round()),
              ),
              _MeterSliderControl(
                title: 'Khối lượng Nước sạch tiêu thụ',
                trailing:
                    '$_prevWater → $_currWater (${calc.waterM3Consumed} m³)',
                value: calc.waterM3Consumed.toDouble(),
                min: 1,
                max: 50,
                onChanged: (v) => setState(() => _currWater = _prevWater + v.round()),
              ),
              _MeterSliderControl(
                title: 'Internet cáp quang + Rác / Phí quản lý',
                trailing: VndAmount.format(_fixedInternetTrashMinor),
                value: (_fixedInternetTrashMinor / 10000).clamp(0, 150),
                min: 0,
                max: 150,
                onChanged: (v) =>
                    setState(() => _fixedInternetTrashMinor = v.round() * 10000),
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
                          style: TextStyle(fontSize: 12.5, color: c.textSecondary),
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
                          'Thuế GTGT Điện (VAT 8%)',
                          style: TextStyle(fontSize: 12.5, color: c.textSecondary),
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('save_utility_reading_btn'),
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
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: const Text('Lưu chỉ số tháng'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('pay_utility_to_wallet_btn'),
                      onPressed: userId.isEmpty
                          ? null
                          : () {
                              context.read<TransactionActionBloc>().add(
                                    TransactionCreateSubmitted(
                                      operationId:
                                          'evn_${DateTime.now().millisecondsSinceEpoch}',
                                      userId: userId,
                                      walletId: primaryWalletId,
                                      categoryId: 'cat_bills',
                                      categoryName: 'Điện nước',
                                      kind: TransactionKind.expense,
                                      amountMinor: _splitMembers > 1
                                          ? calc.perPersonShareMinor
                                          : calc.grandTotalMinor,
                                      merchant: 'Điện nước & Internet kỳ $monthKey',
                                      note:
                                          '${calc.kwhConsumed} kWh điện · ${calc.waterM3Consumed} m³ nước',
                                      occurredAt: DateTime.now(),
                                    ),
                                  );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '✓ Đã ghi hóa đơn Điện Nước vào Sổ cái Ví!',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Ghi vào Ví'),
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
          ...readings.take(4).map(
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
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                              Text(
                                'Điện: ${r.kwhUsed} kWh · Nước: ${r.waterM3Used} m³',
                                style: TextStyle(fontSize: 12, color: c.textSecondary),
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
    String primaryWalletId,
    HomeContractMaintenanceEntity? contract,
  ) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final display = contract ??
        HomeContractMaintenanceEntity(
          id: 'preview',
          ownerId: userId,
          homeName: 'Căn hộ chung cư / Phòng trọ hiện tại',
          monthlyRentMinor: 6500000,
          depositMinor: 13000000,
          paymentDayOfMonth: 5,
          leaseEndDate: DateTime.now().add(const Duration(days: 210)),
          wifiCredentials: 'VNPT_5G_Home / Pass: 88889999',
          nextApplianceMaintenanceNote:
              'Vệ sinh 2 máy lạnh & thay lõi lọc nước RO số 1–2–3 định kỳ',
        );

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
                          display.homeName,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          'Đóng tiền ngày ${display.paymentDayOfMonth} hằng tháng · Hết hạn HĐ: ${dateFmt.format(display.leaseEndDate)}',
                          style: TextStyle(fontSize: 12, color: c.textSecondary),
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
                        Text('Tiền thuê / tháng',
                            style: TextStyle(fontSize: 12, color: c.textSecondary)),
                        Text(
                          VndAmount.format(display.monthlyRentMinor),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tiền đặt cọc đang giữ',
                            style: TextStyle(fontSize: 12, color: c.textSecondary)),
                        Text(
                          VndAmount.format(display.depositMinor),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: c.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LifeOsStatusPill(
                icon: Icons.wifi_rounded,
                label: display.wifiCredentials.isEmpty
                    ? 'Chưa lưu Wi-Fi khách'
                    : display.wifiCredentials,
                tone: LifeOsAccentTone.purple,
              ),
              const SizedBox(height: 8),
              Text(
                '🔧 Bảo trì thiết bị nhà cửa: ${display.nextApplianceMaintenanceNote}',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: userId.isEmpty
                          ? null
                          : () => _showEditContractSheet(context, userId, display),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Cập nhật HĐ'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: userId.isEmpty || display.monthlyRentMinor <= 0
                          ? null
                          : () {
                              context.read<TransactionActionBloc>().add(
                                    TransactionCreateSubmitted(
                                      operationId:
                                          'rent_${DateTime.now().millisecondsSinceEpoch}',
                                      userId: userId,
                                      walletId: primaryWalletId,
                                      categoryId: 'cat_housing',
                                      categoryName: 'Nhà cửa',
                                      kind: TransactionKind.expense,
                                      amountMinor: display.monthlyRentMinor,
                                      merchant: 'Tiền thuê ${display.homeName}',
                                      note: 'Thanh toán tiền nhà định kỳ',
                                      occurredAt: DateTime.now(),
                                    ),
                                  );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✓ Đã ghi khoản Tiền nhà vào Sổ cái Ví!'),
                                ),
                              );
                            },
                      icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                      label: const Text('Đóng tiền nhà'),
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
    HomeContractMaintenanceEntity current,
  ) async {
    final nameCtrl = TextEditingController(text: current.homeName);
    final rentCtrl = TextEditingController(text: '${current.monthlyRentMinor}');
    final depCtrl = TextEditingController(text: '${current.depositMinor}');
    final wifiCtrl = TextEditingController(text: current.wifiCredentials);
    final maintCtrl = TextEditingController(text: current.nextApplianceMaintenanceNote);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cập nhật Hợp đồng Nhà & Bảo trì Tổ ấm',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên căn hộ / Phòng trọ'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: rentCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Tiền thuê/tháng (₫)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: depCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Tiền đặt cọc (₫)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: wifiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên & Mật khẩu Wi-Fi / Mã thẻ cư dân',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: maintCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú vệ sinh máy lạnh / lọc nước RO',
                  ),
                ),
                const SizedBox(height: 14),
                LifeOsPrimaryCtaButton(
                  label: 'Lưu Hợp đồng & Lịch Bảo trì',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    context.read<DailyLifeBloc>().add(
                          HomeContractSaved(
                            userId: userId,
                            homeName: nameCtrl.text.trim(),
                            monthlyRentMinor: int.tryParse(rentCtrl.text.trim()) ?? 0,
                            depositMinor: int.tryParse(depCtrl.text.trim()) ?? 0,
                            paymentDayOfMonth: current.paymentDayOfMonth,
                            leaseEndDate: current.leaseEndDate,
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
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.8, color: c.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
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
