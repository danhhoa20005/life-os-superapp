import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../domain/entities/pro_utilities_entities.dart';
import '../bloc/pro_utilities_bloc.dart';

/// Replaces Rocket Money / Bobby: Tracks recurring subscription drains & appliance warranties.
class SubscriptionsWarrantyPage extends StatefulWidget {
  const SubscriptionsWarrantyPage({super.key});

  @override
  State<SubscriptionsWarrantyPage> createState() => _SubscriptionsWarrantyPageState();
}

class _SubscriptionsWarrantyPageState extends State<SubscriptionsWarrantyPage> {
  bool _showWarranties = false;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    final dateFmt = DateFormat('dd/MM/yyyy');
    final now = DateTime.now();

    return BlocListener<ProUtilitiesBloc, ProUtilitiesState>(
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
                LifeOsTopBrandHeader(
                  title: 'Gói Đăng ký & Bảo hành',
                  showBackButton: true,
                  trailingAction: IconButton.filledTonal(
                    tooltip: 'Thêm gói hoặc bảo hành',
                    onPressed: () => _showAddDialog(context, user.id),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
                Expanded(
                  child: BlocBuilder<ProUtilitiesBloc, ProUtilitiesState>(
                    builder: (context, state) {
                      final dueSoonCount = state.subscriptionsAndWarranties
                          .where((e) => e.isDueSoon(now))
                          .length;
                      final visible = _showWarranties
                          ? state.warrantiesOnly
                          : state.subscriptionsOnly;

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
                              // 1. Annual & Monthly Burn Radar Hero Card
                              LifeOsMintHeroCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.radar_rounded, size: 20, color: c.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Radar Chi phí Thuê bao Tự động',
                                            style: TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w800,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                        ),
                                        LifeOsStatusPill(
                                          icon: Icons.notifications_active_outlined,
                                          label: '$dueSoonCount sắp đến hạn',
                                          tone: dueSoonCount > 0
                                              ? LifeOsAccentTone.amber
                                              : LifeOsAccentTone.emerald,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    IntrinsicHeight(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Chi phí ngầm / tháng',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment: Alignment.centerLeft,
                                                  child: Text(
                                                    VndAmount.format(
                                                      state.totalMonthlySubBurnMinor,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 19,
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
                                          VerticalDivider(width: 16, color: c.separator),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Tổng phí / năm',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment: Alignment.centerLeft,
                                                  child: Text(
                                                    VndAmount.format(
                                                      state.totalAnnualSubBurnMinor,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 19,
                                                      fontWeight: FontWeight.w800,
                                                      color: c.error,
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
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 2. Segmented Toggle: Subscriptions vs Appliance Warranties
                              LifeOsSegmentedPills<bool>(
                                selected: _showWarranties,
                                options: const [
                                  (false, 'Gói đăng ký', Icons.autorenew_rounded),
                                  (true, 'Phiếu bảo hành', Icons.verified_user_outlined),
                                ],
                                onChanged: (v) => setState(() => _showWarranties = v),
                              ),
                              const SizedBox(height: 12),

                              // 3. 1-Tap Popular Presets
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: (_showWarranties
                                          ? const [
                                              (
                                                'Bảo hành iPhone / Laptop',
                                                'Apple / Thế Giới Di Động',
                                                SubscriptionCycle.warrantyOnly,
                                                0,
                                                365,
                                              ),
                                              (
                                                'Bảo hành Máy giặt / Tủ lạnh',
                                                'Điện Máy Xanh',
                                                SubscriptionCycle.warrantyOnly,
                                                0,
                                                730,
                                              ),
                                              (
                                                'Bảo hành Điều hòa Inverter',
                                                'Daikin / Panasonic',
                                                SubscriptionCycle.warrantyOnly,
                                                0,
                                                365,
                                              ),
                                            ]
                                          : const [
                                              (
                                                'YouTube Premium',
                                                'Google',
                                                SubscriptionCycle.monthly,
                                                79000,
                                                12,
                                              ),
                                              (
                                                'Netflix Gia đình',
                                                'Netflix',
                                                SubscriptionCycle.monthly,
                                                260000,
                                                5,
                                              ),
                                              (
                                                'iCloud+ 200GB',
                                                'Apple',
                                                SubscriptionCycle.monthly,
                                                79000,
                                                18,
                                              ),
                                              (
                                                'ChatGPT / AI Pro',
                                                'OpenAI',
                                                SubscriptionCycle.monthly,
                                                520000,
                                                3,
                                              ),
                                            ])
                                      .map(
                                        (preset) => Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: ActionChip(
                                            avatar: Icon(
                                              Icons.add_circle_outline_rounded,
                                              size: 16,
                                              color: c.primary,
                                            ),
                                            label: Text(preset.$1),
                                            onPressed: () {
                                              context.read<ProUtilitiesBloc>().add(
                                                    SubscriptionOrWarrantyAdded(
                                                      userId: user.id,
                                                      title: preset.$1,
                                                      providerOrStore: preset.$2,
                                                      cycle: preset.$3,
                                                      amountMinor: preset.$4,
                                                      nextBillingOrExpiryDate: now.add(
                                                        Duration(days: preset.$5),
                                                      ),
                                                    ),
                                                  );
                                            },
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 4. Active Items List
                              if (visible.isEmpty)
                                LifeOsSoftCard(
                                  child: Column(
                                    children: [
                                      LifeOsIconSquircle(
                                        icon: _showWarranties
                                            ? Icons.verified_user_outlined
                                            : Icons.subscriptions_outlined,
                                        tone: LifeOsAccentTone.emerald,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        _showWarranties
                                            ? 'Chưa có phiếu bảo hành thiết bị nào'
                                            : 'Chưa có gói đăng ký tự động nào',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _showWarranties
                                            ? 'Lưu ngày mua & hạn bảo hành đồ điện tử, gia dụng để không bỏ lỡ quyền bảo hành miễn phí.'
                                            : 'Chạm các gợi ý nhanh phía trên hoặc thêm gói đăng ký để kiểm soát các khoản trừ thẻ ngầm.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...visible.map((item) {
                                  final daysLeft = item.daysRemainingFrom(now);
                                  final dueSoon = item.isDueSoon(now);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LifeOsSoftCard(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              LifeOsIconSquircle(
                                                icon: item.isWarranty
                                                    ? Icons.shield_outlined
                                                    : Icons.autorenew_rounded,
                                                tone: dueSoon
                                                    ? LifeOsAccentTone.amber
                                                    : LifeOsAccentTone.emerald,
                                                size: 42,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.title,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 15,
                                                        color: c.textPrimary,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${item.providerOrStore.isEmpty ? item.cycle.labelVi : "${item.providerOrStore} · ${item.cycle.labelVi}"} · Hạn: ${dateFmt.format(item.nextBillingOrExpiryDate)}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: c.textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (!item.isWarranty)
                                                Text(
                                                  VndAmount.format(item.amountMinor),
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              LifeOsStatusPill(
                                                icon: daysLeft < 0
                                                    ? Icons.error_outline_rounded
                                                    : Icons.schedule_rounded,
                                                label: daysLeft < 0
                                                    ? 'Đã quá hạn ${daysLeft.abs()} ngày'
                                                    : 'Còn $daysLeft ngày',
                                                tone: daysLeft < 0
                                                    ? LifeOsAccentTone.coral
                                                    : dueSoon
                                                        ? LifeOsAccentTone.amber
                                                        : LifeOsAccentTone.emerald,
                                              ),
                                              const Spacer(),
                                              if (!item.isWarranty && wallets.isNotEmpty)
                                                TextButton.icon(
                                                  style: TextButton.styleFrom(
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                  onPressed: () {
                                                    context.read<TransactionActionBloc>().add(
                                                          TransactionCreateSubmitted(
                                                            operationId: const Uuid().v4(),
                                                            userId: user.id,
                                                            walletId: wallets.first.id,
                                                            categoryName: 'Điện/Nước/Internet',
                                                            kind: TransactionKind.expense,
                                                            amountMinor: item.amountMinor,
                                                            merchant: item.title,
                                                            note:
                                                                'Gia hạn gói ${item.cycle.labelVi}',
                                                            occurredAt: DateTime.now(),
                                                          ),
                                                        );
                                                    LifeOsTopToast.fromSnackBar(context, 
                                                      SnackBar(
                                                        content: Text(
                                                          '✓ Đã ghi chi tiêu gia hạn "${item.title}" vào Ví.',
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  icon: const Icon(
                                                    Icons.payments_outlined,
                                                    size: 16,
                                                  ),
                                                  label: const Text('Ghi vào Ví'),
                                                ),
                                              IconButton(
                                                visualDensity: VisualDensity.compact,
                                                tooltip: 'Xóa',
                                                onPressed: () => context
                                                    .read<ProUtilitiesBloc>()
                                                    .add(
                                                      SubscriptionOrWarrantyDeleted(
                                                        userId: user.id,
                                                        itemId: item.id,
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
                                        ],
                                      ),
                                    ),
                                  );
                                }),

                              const SizedBox(height: 14),
                              LifeOsPrimaryCtaButton(
                                icon: Icons.add_rounded,
                                label: _showWarranties
                                    ? 'Thêm phiếu bảo hành thiết bị'
                                    : 'Thêm gói đăng ký theo dõi',
                                onPressed: () => _showAddDialog(
                                  context,
                                  user.id,
                                  defaultWarranty: _showWarranties,
                                ),
                              ),
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

  Future<void> _showAddDialog(
    BuildContext context,
    String userId, {
    bool defaultWarranty = false,
  }) async {
    final titleCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final amountCtrl = TextEditingController(text: defaultWarranty ? '0' : '120000');
    final noteCtrl = TextEditingController();
    var cycle =
        defaultWarranty ? SubscriptionCycle.warrantyOnly : SubscriptionCycle.monthly;
    var targetDate = DateTime.now().add(Duration(days: defaultWarranty ? 365 : 30));
    final bloc = context.read<ProUtilitiesBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            cycle == SubscriptionCycle.warrantyOnly
                ? 'Thêm Phiếu Bảo hành'
                : 'Thêm Gói Đăng ký Tự động',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<SubscriptionCycle>(
                  isExpanded: true,
                  initialValue: cycle,
                  decoration: const InputDecoration(labelText: 'Loại chu kỳ'),
                  items: SubscriptionCycle.values
                      .map(
                        (e) => DropdownMenuItem(value: e, child: Text(e.labelVi)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => cycle = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('sub_title_input'),
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên dịch vụ / Thiết bị',
                    hintText: 'VD: Spotify / Tủ lạnh Samsung',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: providerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nhà cung cấp / Nơi mua',
                  ),
                ),
                if (cycle != SubscriptionCycle.warrantyOnly) ...[
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('sub_amount_input'),
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Số tiền mỗi kỳ (VND)',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Số Serial / Ghi chú hủy gia hạn',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: targetDate,
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2036),
                    );
                    if (picked != null) setDialogState(() => targetDate = picked);
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                    'Ngày gia hạn / hết hạn: ${DateFormat('dd/MM/yyyy').format(targetDate)}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton(
              key: const Key('submit_sub_button'),
              onPressed: () {
                final amt = VndAmount.tryParseInput(amountCtrl.text) ?? 0;
                bloc.add(
                  SubscriptionOrWarrantyAdded(
                    userId: userId,
                    title: titleCtrl.text,
                    providerOrStore: providerCtrl.text,
                    cycle: cycle,
                    amountMinor: amt,
                    nextBillingOrExpiryDate: targetDate,
                    serialOrNote: noteCtrl.text,
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Lưu theo dõi'),
            ),
          ],
        ),
      ),
    );
  }
}
