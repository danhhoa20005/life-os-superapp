import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../domain/entities/vehicle_entities.dart';
import '../bloc/vehicle_bloc.dart';

/// Screen 09: "Xe cộ" (`09_Xe_co.png`) following Unified LifeOS Design System.
class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BlocListener<VehicleBloc, VehicleState>(
      listenWhen: (p, c) => p.failure != c.failure || p.message != c.message,
      listener: (context, state) {
        if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('⚠ ${state.failure!.message}')),
          );
        } else if (state.message != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('✓ ${state.message!}')),
          );
        }
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  LifeOsTopBrandHeader(
                    title: 'Xe cộ & Hóa đơn',
                    showBackButton: true,
                    extraBrandActions: [
                      LifeOsHeaderCircleButton(
                        icon: Icons.receipt_long_outlined,
                        tooltip: 'Thêm hóa đơn định kỳ',
                        onTap: () => _showAddBillDialog(
                          context,
                          user.id,
                          user.activeFamilyId,
                        ),
                      ),
                    ],
                    trailingAction: FilledButton.icon(
                      onPressed: () => _showAddVehicleDialog(
                        context,
                        user.id,
                        user.activeFamilyId,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Thêm xe'),
                    ),
                  ),
                  const ProPillTabContainer(
                    tabBar: TabBar(
                      tabs: [
                        Tab(text: 'Xe & Bảo dưỡng'),
                        Tab(text: 'Hóa đơn định kỳ'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: BlocBuilder<VehicleBloc, VehicleState>(
                      builder: (context, state) {
                        return TabBarView(
                          children: [
                            _UnifiedVehiclesTab(
                              userId: user.id,
                              familyId: user.activeFamilyId,
                              vehicles: state.vehicles,
                              defaultWalletId: wallets.isNotEmpty
                                  ? wallets.first.id
                                  : null,
                              onAddVehicle: () => _showAddVehicleDialog(
                                context,
                                user.id,
                                user.activeFamilyId,
                              ),
                            ),
                            _UnifiedRecurringBillsTab(
                              userId: user.id,
                              bills: state.bills,
                              defaultWalletId: wallets.isNotEmpty
                                  ? wallets.first.id
                                  : null,
                              onAddBill: () => _showAddBillDialog(
                                context,
                                user.id,
                                user.activeFamilyId,
                              ),
                            ),
                          ],
                        );
                      },
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

  Future<void> _showAddVehicleDialog(
    BuildContext context,
    String userId,
    String? familyId,
  ) async {
    final nameCtrl = TextEditingController();
    final plateCtrl = TextEditingController();
    final odoCtrl = TextEditingController();
    var shared = false;
    final bloc = context.read<VehicleBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Thêm Hồ sơ Phương tiện'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên xe (Hãng / Dòng xe)',
                    hintText: 'VD: Toyota Corolla Cross / Honda AirBlade',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: plateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Biển kiểm soát',
                    hintText: '30H-123.45',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: odoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số ODO hiện tại (km)',
                    hintText: 'VD: 15000',
                  ),
                ),
                if (familyId != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Chia sẻ hồ sơ xe với gia đình'),
                    value: shared,
                    onChanged: (v) => setDialogState(() => shared = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                bloc.add(
                  VehicleCreated(
                    userId: userId,
                    familyId: familyId,
                    isFamilyShared: shared,
                    name: nameCtrl.text,
                    plateNumber: plateCtrl.text,
                    currentOdometerKm: int.tryParse(odoCtrl.text) ?? 0,
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Lưu xe'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddBillDialog(
    BuildContext context,
    String userId,
    String? familyId,
  ) async {
    final titleCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final bloc = context.read<VehicleBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Hóa đơn Định kỳ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên hóa đơn',
                hintText: 'VD: Tiền điện EVN / Internet FPT',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: providerCtrl,
              decoration: const InputDecoration(
                labelText: 'Nhà cung cấp',
                hintText: 'VD: EVN / FPT / VNPT',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền dự kiến (VND)',
                hintText: 'VD: 350000',
              ),
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
              final amt = VndAmount.tryParseInput(amountCtrl.text) ?? 0;
              bloc.add(
                RecurringBillCreated(
                  userId: userId,
                  familyId: familyId,
                  title: titleCtrl.text,
                  providerName: providerCtrl.text,
                  estimatedAmountMinor: amt,
                  nextDueDate: DateTime.now().add(const Duration(days: 5)),
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Lưu hóa đơn'),
          ),
        ],
      ),
    );
  }
}

class _UnifiedVehiclesTab extends StatefulWidget {
  final String userId;
  final String? familyId;
  final List<VehicleEntity> vehicles;
  final String? defaultWalletId;
  final VoidCallback onAddVehicle;

  const _UnifiedVehiclesTab({
    required this.userId,
    this.familyId,
    required this.vehicles,
    this.defaultWalletId,
    required this.onAddVehicle,
  });

  @override
  State<_UnifiedVehiclesTab> createState() => _UnifiedVehiclesTabState();
}

class _UnifiedVehiclesTabState extends State<_UnifiedVehiclesTab> {
  int _selectedIdx = 0;

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final now = DateTime.now();
    final numFmt = NumberFormat('#,###', 'vi_VN');
    final dateFmt = DateFormat('dd \'tháng\' M, yyyy');

    final activeVehicle = widget.vehicles.isNotEmpty
        ? widget.vehicles[_selectedIdx.clamp(0, widget.vehicles.length - 1)]
        : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            6,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            if (widget.vehicles.length > 1) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(widget.vehicles.length, (i) {
                    final v = widget.vehicles[i];
                    final picked = i == _selectedIdx;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 10),
                      child: ChoiceChip(
                        selected: picked,
                        label: Text(v.name),
                        onSelected: (_) => setState(() => _selectedIdx = i),
                      ),
                    );
                  }),
                ),
              ),
            ],

            // 1. Hero Vehicle Card (`09_Xe_co.png`)
            if (activeVehicle == null)
              LifeOsMintHeroCard(
                child: Column(
                  children: [
                    const LifeOsIconSquircle(
                      icon: Icons.directions_car_filled_outlined,
                      tone: LifeOsAccentTone.emerald,
                      size: 56,
                      iconSize: 30,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Chưa có hồ sơ phương tiện',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Thêm xe để theo dõi lịch thay dầu, bảo hiểm và đăng kiểm.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: widget.onAddVehicle,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Thêm phương tiện đầu tiên'),
                    ),
                  ],
                ),
              )
            else ...[
              Builder(
                builder: (context) {
                  final due = activeVehicle.dueStateAt(now);
                  final remDays = activeVehicle
                      .remainingDaysFrom(now)
                      .clamp(0, 999);
                  final nextServiceDate = now.add(Duration(days: remDays));
                  final insuranceDate = activeVehicle.insuranceExpiryDate;
                  final insuranceRemDays = insuranceDate
                      ?.difference(now)
                      .inDays;

                  final (pillTone, pillLabel) = switch (due) {
                    VehicleDueState.overdue => (
                      LifeOsAccentTone.coral,
                      'Quá hạn',
                    ),
                    VehicleDueState.dueSoon => (
                      LifeOsAccentTone.amber,
                      'Sắp đến hạn',
                    ),
                    VehicleDueState.healthy => (
                      LifeOsAccentTone.emerald,
                      'Đang tốt',
                    ),
                  };

                  return LifeOsSoftCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Vehicle Thumbnail Squircle
                            Container(
                              width: 88,
                              height: 66,
                              decoration: BoxDecoration(
                                color: c.primarySubtle,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.directions_car_filled_rounded,
                                size: 42,
                                color: c.primary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      activeVehicle.displayPlateForViewer(
                                        widget.userId,
                                      ),
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                        color: c.textPrimary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    activeVehicle.name,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            LifeOsStatusPill(
                              icon: Icons.check_circle_rounded,
                              label: pillLabel,
                              tone: pillTone,
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.event_available_outlined,
                                      size: 20,
                                      color: c.primary,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Bảo dưỡng tiếp theo',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        dateFmt.format(nextServiceDate),
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Còn $remDays ngày',
                                      style: TextStyle(
                                        fontSize: 11.8,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              VerticalDivider(width: 16, color: c.separator),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _showOdometerDialog(
                                    context,
                                    activeVehicle,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.speed_rounded,
                                        size: 20,
                                        color: c.primary,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Số ODO (chạm sửa)',
                                        style: TextStyle(
                                          fontSize: 11.8,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '${numFmt.format(activeVehicle.currentOdometerKm)} km',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Mốc kế: ${numFmt.format(activeVehicle.nextDueKm)} km',
                                        softWrap: true,
                                        style: TextStyle(
                                          fontSize: 11.8,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              VerticalDivider(width: 16, color: c.separator),
                              Expanded(
                                child: InkWell(
                                  onTap: () =>
                                      context.push('/family-documents'),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.verified_user_outlined,
                                        size: 20,
                                        color: c.primary,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Bảo hiểm TNDS',
                                        style: TextStyle(
                                          fontSize: 11.8,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          insuranceDate != null
                                              ? dateFmt.format(insuranceDate)
                                              : 'Chưa cập nhật',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        insuranceRemDays != null
                                            ? (insuranceRemDays >= 0
                                                  ? 'Còn $insuranceRemDays ngày'
                                                  : 'Quá hạn ${-insuranceRemDays} ngày')
                                            : 'Chạm lưu giấy tờ',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 2. "Hạng mục dịch vụ" Card (`09_Xe_co.png`)
              LifeOsSoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.layers_outlined, size: 20, color: c.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Hạng mục dịch vụ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ServiceChecklistTile(
                      icon: Icons.oil_barrel_outlined,
                      title: 'Thay dầu động cơ',
                      subtitle: 'Mỗi 5.000 – 10.000 km',
                      pillLabel: 'Đã hoàn thành',
                      pillIcon: Icons.check_circle_outline_rounded,
                      pillTone: LifeOsAccentTone.emerald,
                      onTap: () => _showMaintenanceDialog(
                        context,
                        activeVehicle,
                        widget.defaultWalletId,
                        defaultTitle: 'Thay dầu động cơ',
                      ),
                    ),
                    const Divider(height: 22),
                    _ServiceChecklistTile(
                      icon: Icons.tire_repair_outlined,
                      title: 'Kiểm tra lốp & phanh',
                      subtitle:
                          'Mỗi 10.000 km · Còn ${activeVehicle.remainingKm} km',
                      pillLabel: 'Sắp đến hạn',
                      pillIcon: Icons.schedule_rounded,
                      pillTone: LifeOsAccentTone.amber,
                      onTap: () => _showMaintenanceDialog(
                        context,
                        activeVehicle,
                        widget.defaultWalletId,
                        defaultTitle: 'Kiểm tra lốp & phanh',
                      ),
                    ),
                    const Divider(height: 22),
                    _ServiceChecklistTile(
                      icon: Icons.fact_check_outlined,
                      title: 'Hạn đăng kiểm định kỳ',
                      subtitle: activeVehicle.inspectionExpiryDate != null
                          ? 'Hạn: ${dateFmt.format(activeVehicle.inspectionExpiryDate!)}'
                          : 'Chưa khai báo hạn đăng kiểm của xe này',
                      pillLabel: activeVehicle.inspectionExpiryDate != null
                          ? 'Còn ${activeVehicle.inspectionExpiryDate!.difference(now).inDays} ngày'
                          : 'Chưa cập nhật',
                      pillIcon: Icons.calendar_today_outlined,
                      pillTone: activeVehicle.inspectionExpiryDate != null
                          ? LifeOsAccentTone.emerald
                          : LifeOsAccentTone.neutral,
                      onTap: () => context.push('/family-documents'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Full-width Emerald CTA ("🔔 Đặt nhắc bảo dưỡng")
              LifeOsPrimaryCtaButton(
                icon: Icons.notifications_none_rounded,
                label: 'Đặt nhắc bảo dưỡng',
                onPressed: () => _showMaintenanceDialog(
                  context,
                  activeVehicle,
                  widget.defaultWalletId,
                ),
              ),
              const SizedBox(height: 14),

              // 4. Bottom 3-Column Quick Action Grid ("Lịch bảo dưỡng | Bảo hiểm | Đăng kiểm")
              Row(
                children: [
                  Expanded(
                    child: LifeOsFeatureGridTile(
                      icon: Icons.calendar_month_outlined,
                      label: 'Lịch bảo dưỡng',
                      tone: LifeOsAccentTone.emerald,
                      onTap: () => _showOdometerDialog(context, activeVehicle),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LifeOsFeatureGridTile(
                      icon: Icons.verified_user_outlined,
                      label: 'Bảo hiểm',
                      tone: LifeOsAccentTone.emerald,
                      onTap: () => context.push('/family-documents'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LifeOsFeatureGridTile(
                      icon: Icons.badge_outlined,
                      label: 'Đăng kiểm',
                      tone: LifeOsAccentTone.emerald,
                      onTap: () => context.push('/family-documents'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showOdometerDialog(
    BuildContext context,
    VehicleEntity vehicle,
  ) async {
    final ctrl = TextEditingController(
      text: (vehicle.currentOdometerKm + 250).toString(),
    );
    final bloc = context.read<VehicleBloc>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cập nhật Odometer · ${vehicle.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Số km hiện tại'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              bloc.add(
                VehicleOdometerLogged(
                  vehicle: vehicle,
                  newOdometerKm:
                      int.tryParse(ctrl.text) ?? vehicle.currentOdometerKm,
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMaintenanceDialog(
    BuildContext context,
    VehicleEntity vehicle,
    String? walletId, {
    String defaultTitle = 'Thay nhớt định kỳ',
  }) async {
    final titleCtrl = TextEditingController(text: defaultTitle);
    final costCtrl = TextEditingController(text: '350000');
    final bloc = context.read<VehicleBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bảo dưỡng & Chi phí · ${vehicle.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Hạng mục bảo dưỡng',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: costCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Chi phí (VND — tự động ghi vào Ví)',
              ),
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
              final cost = VndAmount.tryParseInput(costCtrl.text) ?? 0;
              bloc.add(
                VehicleMaintenanceLogged(
                  vehicle: vehicle,
                  serviceTitle: titleCtrl.text,
                  odometerKm: vehicle.currentOdometerKm,
                  costMinor: cost,
                  walletIdForExpense: walletId,
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Lưu & Ghi chi tiêu'),
          ),
        ],
      ),
    );
  }
}

class _ServiceChecklistTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String pillLabel;
  final IconData pillIcon;
  final LifeOsAccentTone pillTone;
  final VoidCallback onTap;

  const _ServiceChecklistTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.pillLabel,
    required this.pillIcon,
    required this.pillTone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Row(
        children: [
          LifeOsIconSquircle(
            icon: icon,
            tone: LifeOsAccentTone.emerald,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          LifeOsStatusPill(icon: pillIcon, label: pillLabel, tone: pillTone),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 19, color: c.textSecondary),
        ],
      ),
    );
  }
}

class _UnifiedRecurringBillsTab extends StatelessWidget {
  final String userId;
  final List<RecurringBillEntity> bills;
  final String? defaultWalletId;
  final VoidCallback onAddBill;

  const _UnifiedRecurringBillsTab({
    required this.userId,
    required this.bills,
    this.defaultWalletId,
    required this.onAddBill,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final fmt = DateFormat('dd/MM/yyyy');

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (bills.isEmpty)
              LifeOsMintHeroCard(
                child: Column(
                  children: [
                    const LifeOsIconSquircle(
                      icon: Icons.bolt_rounded,
                      tone: LifeOsAccentTone.purple,
                      size: 50,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Chưa có hóa đơn định kỳ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Theo dõi tiền điện, nước, internet và nhận cảnh báo khi hóa đơn tăng bất thường >= 25%.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onAddBill,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Thêm hóa đơn định kỳ'),
                    ),
                  ],
                ),
              )
            else
              ...bills.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LifeOsSoftCard(
                    child: Row(
                      children: [
                        const LifeOsIconSquircle(
                          icon: Icons.bolt_rounded,
                          tone: LifeOsAccentTone.purple,
                          size: 42,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${b.title} · ${VndAmount.format(b.estimatedAmountMinor)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                'Kỳ hạn kế tiếp: ${fmt.format(b.nextDueDate)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                ),
                              ),
                              if (b.hasAbnormalSpike) ...[
                                const SizedBox(height: 4),
                                const LifeOsStatusPill(
                                  icon: Icons.warning_amber_rounded,
                                  label: 'Tăng >= 25%',
                                  tone: LifeOsAccentTone.amber,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (defaultWalletId != null)
                          FilledButton.tonal(
                            onPressed: () {
                              context.read<VehicleBloc>().add(
                                RecurringBillPaid(
                                  userId: userId,
                                  bill: b,
                                  paidAmountMinor: b.estimatedAmountMinor,
                                  walletId: defaultWalletId!,
                                ),
                              );
                            },
                            child: const Text('Thanh toán'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
