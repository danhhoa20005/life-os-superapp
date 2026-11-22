import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../domain/entities/vehicle_entities.dart';
import '../bloc/vehicle_bloc.dart';

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
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('⚠ ${state.failure!.message}')));
        } else if (state.message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('✓ ${state.message!}')));
        }
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: LiquidGlassBar(
            title: const Text('Phương tiện & Hóa đơn Định kỳ'),
            actions: [
              IconButton(
                tooltip: 'Thêm hóa đơn định kỳ',
                onPressed: () => _showAddBillDialog(context, user.id, user.activeFamilyId),
                icon: const Icon(Icons.receipt_outlined),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: FilledButton.icon(
                  onPressed: () => _showAddVehicleDialog(context, user.id, user.activeFamilyId),
                  icon: const Icon(Icons.two_wheeler_rounded, size: 18),
                  label: const Text('Thêm xe'),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              const ProPillTabContainer(
                tabBar: TabBar(
                  tabs: [
                    Tab(text: 'Phương tiện & Bảo dưỡng'),
                    Tab(text: 'Hóa đơn & Gói đăng ký'),
                  ],
                ),
              ),
              Expanded(
                child: BlocBuilder<VehicleBloc, VehicleState>(
                  builder: (context, state) {
                    return TabBarView(
                      children: [
                        _VehiclesListTab(
                          userId: user.id,
                          vehicles: state.vehicles,
                          defaultWalletId: wallets.isNotEmpty ? wallets.first.id : null,
                        ),
                        _BillsListTab(
                          userId: user.id,
                          bills: state.bills,
                          defaultWalletId: wallets.isNotEmpty ? wallets.first.id : null,
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
    );
  }

  Future<void> _showAddVehicleDialog(
    BuildContext context,
    String userId,
    String? familyId,
  ) async {
    final nameCtrl = TextEditingController();
    final plateCtrl = TextEditingController();
    final odoCtrl = TextEditingController(text: '12000');
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
                const Text('Tên xe (Hãng / Dòng xe)'),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(hintText: 'VD: Honda AirBlade 160'),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('Biển kiểm soát (tự che khi chia sẻ gia đình)'),
                const SizedBox(height: 6),
                TextField(
                  controller: plateCtrl,
                  decoration: const InputDecoration(hintText: '59A-123.45'),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('Số Odometer hiện tại (km)'),
                const SizedBox(height: 6),
                TextField(controller: odoCtrl, keyboardType: TextInputType.number),
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
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
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
    final amountCtrl = TextEditingController(text: '540000');
    final bloc = context.read<VehicleBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Hóa đơn Định kỳ / Subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tên hóa đơn'),
            const SizedBox(height: 6),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(hintText: 'VD: Tiền điện EVN / Internet FPT'),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Nhà cung cấp'),
            const SizedBox(height: 6),
            TextField(controller: providerCtrl),
            const SizedBox(height: AppSpacing.sm),
            const Text('Số tiền dự kiến hằng tháng (VND)'),
            const SizedBox(height: 6),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
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

class _VehiclesListTab extends StatelessWidget {
  final String userId;
  final List<VehicleEntity> vehicles;
  final String? defaultWalletId;

  const _VehiclesListTab({
    required this.userId,
    required this.vehicles,
    this.defaultWalletId,
  });

  @override
  Widget build(BuildContext context) {
    if (vehicles.isEmpty) {
      return const EmptyStateView(
        icon: Icons.directions_car_outlined,
        imageAsset: AppAssets.planningAssetsIllustration,
        title: 'Chưa có hồ sơ phương tiện',
        subtitle:
            'Theo dõi Odometer, lịch thay nhớt & bảo dưỡng theo công thức min(km đến hạn, ngày đến hạn).',
      );
    }

    final now = DateTime.now();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: vehicles.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final v = vehicles[index];
            final due = v.dueStateAt(now);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${v.name} (${v.displayPlateForViewer(userId)})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        SemanticStatusBadge(
                          kind: switch (due) {
                            VehicleDueState.overdue => SemanticStatusKind.error,
                            VehicleDueState.dueSoon => SemanticStatusKind.warning,
                            VehicleDueState.healthy => SemanticStatusKind.success,
                          },
                          label: switch (due) {
                            VehicleDueState.overdue => 'Quá hạn bảo dưỡng',
                            VehicleDueState.dueSoon => 'Sắp đến hạn',
                            VehicleDueState.healthy => 'Đang tốt',
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Odometer hiện tại: ${v.currentOdometerKm} km · Hạn tiếp theo: ${v.nextDueKm} km (còn ${v.remainingKm} km hoặc ${v.remainingDaysFrom(now)} ngày)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: v.serviceIntervalKm > 0
                            ? ((v.currentOdometerKm - v.lastServiceOdometerKm) /
                                    v.serviceIntervalKm)
                                .clamp(0.0, 1.0)
                            : 0.0,
                        color: switch (due) {
                          VehicleDueState.overdue => TammySemanticColors.of(context).error,
                          VehicleDueState.dueSoon => TammySemanticColors.of(context).warning,
                          VehicleDueState.healthy => TammySemanticColors.of(context).primary,
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _showOdometerDialog(context, v),
                          icon: const Icon(Icons.speed_rounded, size: 16),
                          label: const Text('Cập nhật km'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _showMaintenanceDialog(context, v, defaultWalletId),
                          icon: const Icon(Icons.build_circle_outlined, size: 16),
                          label: const Text('Ghi bảo dưỡng + Chi phí'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showOdometerDialog(BuildContext context, VehicleEntity vehicle) async {
    final ctrl = TextEditingController(text: (vehicle.currentOdometerKm + 250).toString());
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              bloc.add(
                VehicleOdometerLogged(
                  vehicle: vehicle,
                  newOdometerKm: int.tryParse(ctrl.text) ?? vehicle.currentOdometerKm,
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
    String? walletId,
  ) async {
    final titleCtrl = TextEditingController(text: 'Thay nhớt định kỳ');
    final costCtrl = TextEditingController(text: '180000');
    final bloc = context.read<VehicleBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ghi nhận Bảo dưỡng · ${vehicle.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Hạng mục bảo dưỡng'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: costCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Chi phí (VND — tự động ghi vào Ví)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
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

class _BillsListTab extends StatelessWidget {
  final String userId;
  final List<RecurringBillEntity> bills;
  final String? defaultWalletId;

  const _BillsListTab({
    required this.userId,
    required this.bills,
    this.defaultWalletId,
  });

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) {
      return const EmptyStateView(
        icon: Icons.bolt_rounded,
        imageAsset: AppAssets.planningAssetsIllustration,
        title: 'Chưa có hóa đơn định kỳ',
        subtitle:
            'Quản lý tiền điện, nước, internet, thuê bao và phát hiện cảnh báo khi hóa đơn tăng bất thường >= 25%.',
      );
    }

    final fmt = DateFormat('dd/MM/yyyy');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: bills.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: (context, index) {
            final b = bills[index];
            return Card(
              child: ListTile(
                title: Text('${b.title} · ${VndAmount.format(b.estimatedAmountMinor)}'),
                subtitle: Text('Kỳ hạn tiếp theo: ${fmt.format(b.nextDueDate)}'),
                trailing: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (b.hasAbnormalSpike)
                      const SemanticStatusBadge(
                        kind: SemanticStatusKind.warning,
                        label: 'Tăng >= 25%',
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
            );
          },
        ),
      ),
    );
  }
}
