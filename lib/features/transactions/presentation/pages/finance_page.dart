import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/smart_quick_entry_parser.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../budgets/domain/entities/budget_entities.dart';
import '../../../budgets/domain/usecases/budget_usecases.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../domain/entities/transaction_entities.dart';
import '../bloc/transaction_bloc.dart';
import '../bloc/transaction_event.dart';
import '../bloc/transaction_state.dart';

class FinancePage extends StatelessWidget {
  const FinancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<TransactionActionBloc, TransactionActionState>(
          listener: (context, state) {
            if (state.status == ActionStatus.failure && state.failure != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('⚠ ${state.failure!.message}')),
              );
            } else if (state.status == ActionStatus.success && state.successMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✓ ${state.successMessage!}')),
              );
            }
          },
        ),
        BlocListener<BudgetBloc, BudgetState>(
          listenWhen: (p, c) => p.failure != c.failure || p.actionMessage != c.actionMessage,
          listener: (context, state) {
            if (state.failure != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('⚠ ${state.failure!.message}')),
              );
            } else if (state.actionMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✓ ${state.actionMessage!}')),
              );
            }
          },
        ),
      ],
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: LiquidGlassBar(
            title: const Text('Tài chính & Sổ quỹ'),
            actions: [
              IconButton(
                tooltip: 'Thêm ví / tài khoản mới',
                onPressed: () => _showCreateWalletDialog(context, user.id),
                icon: const Icon(Icons.account_balance_wallet_outlined),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: BlocBuilder<TransactionListBloc, TransactionListState>(
                  builder: (context, listState) {
                    return FilledButton.icon(
                      key: const Key('open_add_tx_button'),
                      onPressed: listState.wallets.isEmpty
                          ? null
                          : () => _showCreateTransactionDialog(
                                context,
                                userId: user.id,
                                wallets: listState.wallets,
                                categories: listState.categories,
                              ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Ghi giao dịch'),
                    );
                  },
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              const ProPillTabContainer(
                tabBar: TabBar(
                  tabs: [
                    Tab(text: 'Sổ giao dịch'),
                    Tab(text: 'Ngân sách'),
                    Tab(
                      key: Key('finance_analytics_tab'),
                      text: 'Phân tích',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _TransactionsTabView(userId: user.id),
                    _BudgetsAndFundsTabView(
                      userId: user.id,
                      userName: user.fullName,
                      familyId: user.activeFamilyId,
                    ),
                    _PersonalAnalyticsAndAllocationTabView(userId: user.id),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateWalletDialog(BuildContext context, String userId) async {
    final nameCtrl = TextEditingController();
    final openingCtrl = TextEditingController(text: '0');
    var selectedType = WalletType.bank;
    final actionBloc = context.read<TransactionActionBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Thêm Ví / Tài khoản Tham chiếu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Tên ví hoặc tài khoản'),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(hintText: 'VD: Vietcombank Lương'),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('Loại tài khoản'),
                const SizedBox(height: 6),
                DropdownButtonFormField<WalletType>(
                  isExpanded: true,
                  initialValue: selectedType,
                  items: const [
                    DropdownMenuItem(value: WalletType.cash, child: Text('Tiền mặt')),
                    DropdownMenuItem(value: WalletType.bank, child: Text('Tài khoản Ngân hàng')),
                    DropdownMenuItem(value: WalletType.creditCard, child: Text('Thẻ tín dụng')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('Số dư đầu kỳ ước tính (VND)'),
                const SizedBox(height: 6),
                TextField(
                  controller: openingCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '5000000'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                final opening = int.tryParse(openingCtrl.text.replaceAll('.', '').trim()) ?? 0;
                actionBloc.add(
                  WalletCreateSubmitted(
                    userId: userId,
                    name: nameCtrl.text,
                    type: selectedType,
                    openingBalanceMinor: opening,
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Lưu ví'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateTransactionDialog(
    BuildContext context, {
    required String userId,
    required List<WalletEntity> wallets,
    required List<CategoryEntity> categories,
  }) async {
    final opId = const Uuid().v4();
    final amountCtrl = TextEditingController();
    final merchantCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var kind = TransactionKind.expense;
    var sourceWalletId = wallets.first.id;
    String? targetWalletId = wallets.length > 1 ? wallets[1].id : null;

    final catNames = categories.isEmpty
        ? const [
            'Ăn uống',
            'Việc nhà & Gia dụng',
            'Nhà cửa & Thuê nhà',
            'Điện/Nước/Internet',
            'Xe cộ & Di chuyển',
            'Chi tiêu khác',
          ]
        : categories.map((c) => c.name).toSet().toList();

    var selectedCategory = catNames.first;
    var enableSplitCategories = false;
    var splitCat1 = catNames.first;
    var splitCat2 = catNames.contains('Việc nhà & Gia dụng')
        ? 'Việc nhà & Gia dụng'
        : (catNames.length > 1 ? catNames[1] : catNames.first);
    final splitAmt1Ctrl = TextEditingController();
    final splitAmt2Ctrl = TextEditingController();

    final actionBloc = context.read<TransactionActionBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isTransfer =
              kind == TransactionKind.transfer || kind == TransactionKind.creditCardPayment;
          return AlertDialog(
            title: const Text('Ghi nhận Giao dịch Sổ cái'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Loại bút toán'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<TransactionKind>(
                    isExpanded: true,
                    initialValue: kind,
                    items: const [
                      DropdownMenuItem(value: TransactionKind.expense, child: Text('Chi tiêu')),
                      DropdownMenuItem(value: TransactionKind.income, child: Text('Thu nhập')),
                      DropdownMenuItem(
                        value: TransactionKind.transfer,
                        child: Text(
                          'Chuyển ví nội bộ / Rút tiền mặt',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: TransactionKind.creditCardPayment,
                        child: Text(
                          'Trả dư nợ thẻ tín dụng',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() {
                          kind = v;
                          if (kind != TransactionKind.expense) {
                            enableSplitCategories = false;
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Ví nguồn'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: sourceWalletId,
                    items: wallets
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(
                                '${w.name} (${VndAmount.format(w.balanceMinor)})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => sourceWalletId = v);
                    },
                  ),
                  if (isTransfer) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Text('Ví / Thẻ đích'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: targetWalletId,
                      items: wallets
                          .map((w) => DropdownMenuItem(
                                value: w.id,
                                child: Text(w.name, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => targetWalletId = v),
                    ),
                  ] else ...[
                    if (kind == TransactionKind.expense) ...[
                      const SizedBox(height: AppSpacing.xs),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Tách hóa đơn vào nhiều khoản (Split)'),
                        subtitle: const Text('VD: Đi siêu thị gồm Ăn uống + Việc nhà'),
                        value: enableSplitCategories,
                        onChanged: (val) => setDialogState(() => enableSplitCategories = val),
                      ),
                    ],
                    if (!enableSplitCategories) ...[
                      const SizedBox(height: AppSpacing.xs),
                      const Text('Danh mục'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedCategory,
                        items: catNames
                            .map((name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => selectedCategory = v);
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Tổng số tiền (VND nguyên đồng)'),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('tx_amount_input'),
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '85000'),
                  ),
                  if (enableSplitCategories && kind == TransactionKind.expense) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Text('Khoản tách 1'),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: splitCat1,
                      items: catNames
                          .map((n) => DropdownMenuItem(
                                value: n,
                                child: Text(n, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => splitCat1 = v);
                      },
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: splitAmt1Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Số tiền khoản 1 (VD: 320000)'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('Khoản tách 2'),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: splitCat2,
                      items: catNames
                          .map((n) => DropdownMenuItem(
                                value: n,
                                child: Text(n, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => splitCat2 = v);
                      },
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: splitAmt2Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Số tiền khoản 2 (VD: 180000)'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Nội dung / Nơi giao dịch'),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('tx_merchant_input'),
                    controller: merchantCtrl,
                    decoration:
                        const InputDecoration(hintText: 'VD: Quán phở / Đi siêu thị / Dọn nhà'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Ghi chú (tùy chọn)'),
                  const SizedBox(height: 6),
                  TextField(controller: noteCtrl),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
              FilledButton(
                key: const Key('submit_tx_dialog_button'),
                onPressed: () {
                  final amt = VndAmount.tryParseInput(amountCtrl.text) ?? 0;
                  final splits = <TransactionSplitLine>[];
                  if (enableSplitCategories && kind == TransactionKind.expense) {
                    splits.add(
                      TransactionSplitLine(
                        categoryName: splitCat1,
                        amountMinor: VndAmount.tryParseInput(splitAmt1Ctrl.text) ?? 0,
                      ),
                    );
                    splits.add(
                      TransactionSplitLine(
                        categoryName: splitCat2,
                        amountMinor: VndAmount.tryParseInput(splitAmt2Ctrl.text) ?? 0,
                      ),
                    );
                  }
                  actionBloc.add(
                    TransactionCreateSubmitted(
                      operationId: opId,
                      userId: userId,
                      walletId: sourceWalletId,
                      targetWalletId: isTransfer ? targetWalletId : null,
                      categoryName: isTransfer
                          ? 'Chuyển khoản nội bộ'
                          : (splits.isNotEmpty ? splitCat1 : selectedCategory),
                      kind: kind,
                      amountMinor: amt,
                      merchant: merchantCtrl.text,
                      note: noteCtrl.text,
                      occurredAt: DateTime.now(),
                      splitLines: splits,
                    ),
                  );
                  Navigator.of(ctx).pop();
                },
                child: const Text('Ghi sổ'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TransactionsTabView extends StatelessWidget {
  final String userId;
  const _TransactionsTabView({required this.userId});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return BlocBuilder<TransactionListBloc, TransactionListState>(
      builder: (context, state) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: ListView(
              key: const Key('transactions_list_view'),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(
                  'Ví cá nhân & Số dư ước tính',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (state.wallets.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('Đang khởi tạo ví tiền mặt mặc định...'),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: state.wallets.map((w) {
                        return Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: ProWalletCreditCard(
                            name: w.name,
                            walletTypeKey: w.type.name,
                            balanceMinor: w.balanceMinor,
                            maskedAccount: w.maskedAccount,
                            isEstimatedBalance: w.isEstimatedBalance,
                            hasPendingWrites: w.hasPendingWrites,
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                if (state.provisionalTransactions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Gợi ý giao dịch chờ xác nhận (${state.provisionalTransactions.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ...state.provisionalTransactions.map(
                    (tx) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Card(
                        child: ListTile(
                          leading: Icon(Icons.hourglass_top_rounded, color: c.warning),
                          title: Text('${tx.merchant} · ${VndAmount.format(tx.amountMinor)}'),
                          subtitle: Text('Danh mục gợi ý: ${tx.categoryName} (PROVISIONAL)'),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              OutlinedButton(
                                onPressed: () => context.read<TransactionActionBloc>().add(
                                      ProvisionalTransactionDecisionSubmitted(
                                        userId: userId,
                                        transactionId: tx.id,
                                        approve: false,
                                      ),
                                    ),
                                child: const Text('Bỏ qua'),
                              ),
                              FilledButton(
                                onPressed: () => context.read<TransactionActionBloc>().add(
                                      ProvisionalTransactionDecisionSubmitted(
                                        userId: userId,
                                        transactionId: tx.id,
                                        approve: true,
                                      ),
                                    ),
                                child: const Text('Xác nhận'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),
                if (state.wallets.isNotEmpty) ...[
                  _SmartQuickEntryCard(
                    userId: userId,
                    defaultWalletId: state.wallets.first.id,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextField(
                  key: const Key('tx_search_field'),
                  onChanged: (q) =>
                      context.read<TransactionListBloc>().add(TransactionsSearchChanged(q)),
                  decoration: const InputDecoration(
                    labelText: 'Tìm kiếm giao dịch theo nội dung hoặc danh mục',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (state.filteredTransactions.isEmpty)
                  const EmptyStateView(
                    icon: Icons.receipt_long_outlined,
                    imageAsset: AppAssets.financeIllustration,
                    title: 'Chưa có giao dịch trong kỳ',
                    subtitle: 'Nhấn "Ghi giao dịch" ở góc trên để thêm thu/chi, tách khoản hoặc chuyển ví.',
                  )
                else
                  ...state.filteredTransactions.map((tx) {
                    final isCredit = tx.direction == 'credit';
                    final isInternal = tx.kind == TransactionKind.transfer ||
                        tx.kind == TransactionKind.creditCardPayment;
                    final amountColor = isInternal
                        ? c.secondary
                        : (isCredit ? c.success : c.textPrimary);

                    final catVisual = ProCategoryStyle.resolve(
                      tx.categoryName,
                      isTransfer: isInternal,
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Card(
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: (isCredit ? c.success : catVisual.color)
                                  .withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              isCredit ? Icons.south_west_rounded : catVisual.icon,
                              color: isCredit ? c.success : catVisual.color,
                              size: 21,
                            ),
                          ),
                          title: Text(
                            tx.merchant,
                            style: TextStyle(
                              decoration: tx.isReversed ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(tx.categoryName),
                                  SemanticStatusBadge(
                                    kind: tx.verification == TransactionVerification.verified
                                        ? SemanticStatusKind.success
                                        : tx.verification == TransactionVerification.provisional
                                            ? SemanticStatusKind.provisional
                                            : SemanticStatusKind.info,
                                    label: tx.isReversed
                                        ? 'Đã đảo bút toán'
                                        : tx.verification.name.toUpperCase(),
                                  ),
                                  CloudSyncIndicator(hasPendingWrites: tx.hasPendingWrites),
                                ],
                              ),
                              if (tx.splitLines.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Đã tách: ${tx.splitLines.map((l) => '${l.categoryName} (${VndAmount.format(l.amountMinor)})').join(' · ')}',
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                VndAmount.format(
                                  isCredit ? tx.amountMinor : -tx.amountMinor,
                                  showPlus: true,
                                ),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: amountColor,
                                ),
                              ),
                              if (tx.isConfirmedInLedger &&
                                  !tx.isReversed &&
                                  tx.kind != TransactionKind.reversal)
                                IconButton(
                                  tooltip: 'Đảo bút toán (Hoàn tiền / Hủy)',
                                  icon: const Icon(Icons.undo_rounded, size: 20),
                                  onPressed: () async {
                                    final ok = await showDestructiveConfirmDialog(
                                      context: context,
                                      title: 'Đảo bút toán giao dịch?',
                                      message:
                                          'Hệ thống không xóa lịch sử mà sẽ tạo một bút toán đảo đối ứng để hoàn lại số dư ví chính xác.',
                                      confirmLabel: 'Thực hiện đảo bút toán',
                                    );
                                    if (ok && context.mounted) {
                                      context.read<TransactionActionBloc>().add(
                                            TransactionReverseRequested(
                                              userId: userId,
                                              transactionId: tx.id,
                                            ),
                                          );
                                    }
                                  },
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

class _PersonalAnalyticsAndAllocationTabView extends StatefulWidget {
  final String userId;
  const _PersonalAnalyticsAndAllocationTabView({required this.userId});

  @override
  State<_PersonalAnalyticsAndAllocationTabView> createState() =>
      _PersonalAnalyticsAndAllocationTabViewState();
}

class _PersonalAnalyticsAndAllocationTabViewState
    extends State<_PersonalAnalyticsAndAllocationTabView> {
  final TextEditingController _incomeCtrl = TextEditingController(text: '20000000');
  AllocationPreset _preset = AllocationPreset.personal503020;

  @override
  void dispose() {
    _incomeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return BlocBuilder<TransactionListBloc, TransactionListState>(
      builder: (context, state) {
        final s = state.summary;
        final shares = s.sortedCategoryShares;
        final inputIncome = VndAmount.tryParseInput(_incomeCtrl.text) ??
            (s.monthlyIncomeMinor > 0 ? s.monthlyIncomeMinor : 20000000);
        final plan = IncomeAllocationEngine.allocate(
          totalIncomeMinor: inputIncome,
          preset: _preset,
        );

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: ListView(
              key: const Key('analytics_list_view'),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const BrandVisualBanner(
                  assetPath: AppAssets.financeIllustration,
                  height: 120,
                  semanticLabel: 'Minh họa phân tích tài chính và chia khoản sinh hoạt',
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Chỉ số Sức khỏe Tài chính Cá nhân (${state.monthKey})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _MetricMiniCard(
                      label: 'Dòng tiền ròng (Thu - Chi)',
                      value: VndAmount.format(s.netCashFlowMinor, showPlus: true),
                      subtitle: s.monthlyIncomeMinor > 0
                          ? 'Tỷ lệ tiết kiệm: ${s.savingsRatePct.toStringAsFixed(1)}%'
                          : 'Chưa ghi nhận thu nhập kỳ này',
                      accent: s.netCashFlowMinor >= 0 ? c.success : c.error,
                    ),
                    _MetricMiniCard(
                      label: 'Chi trung bình / ngày',
                      value: VndAmount.format(s.averageDailyExpenseMinor),
                      subtitle: 'Tổng chi thực: ${VndAmount.format(s.monthlyExpenseMinor)}',
                      accent: c.primary,
                    ),
                    _MetricMiniCard(
                      label: 'Độ tin cậy Nguồn (SePay Standard)',
                      value: '${s.verifiedCount} VERIFIED · ${s.userConfirmedCount} CONFIRMED',
                      subtitle: '${s.provisionalCount} tín hiệu PROVISIONAL chờ duyệt',
                      accent: c.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phân tích Cơ cấu Chi tiêu theo Khoản mục',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tự động loại trừ chuyển khoản nội bộ (${VndAmount.format(s.monthlyInternalTransferMinor)}) và phân bổ chính xác các giao dịch tách khoản (Ăn uống, Việc nhà, Hóa đơn...).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (shares.isEmpty)
                          const Text('Chưa có khoản chi đã xác nhận trong tháng này.')
                        else ...[
                          ProDonutChart(
                            totalExpenseMinor: s.monthlyExpenseMinor,
                            slices: shares
                                .map(
                                  (sh) => ProDonutSlice(
                                    label: sh.categoryName,
                                    amountMinor: sh.amountMinor,
                                    pct: sh.sharePct,
                                    color: ProCategoryStyle.resolve(sh.categoryName).color,
                                  ),
                                )
                                .toList(),
                          ),
                          const Divider(height: 28),
                          ...shares.map(
                            (item) {
                              final style = ProCategoryStyle.resolve(item.categoryName);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(style.icon, size: 16, color: style.color),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${item.categoryName} (${item.sharePct.toStringAsFixed(1)}%)',
                                              style: Theme.of(context).textTheme.labelLarge,
                                            ),
                                          ],
                                        ),
                                        Text(
                                          VndAmount.format(item.amountMinor),
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        minHeight: 7,
                                        value: (item.sharePct / 100.0).clamp(0.0, 1.0),
                                        color: style.color,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bộ Chia & Phân bổ Thu nhập Vào Các Khoản Sinh hoạt',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chia lương/ngân quỹ chính xác đến từng đồng VND (không sai số làm tròn) theo 3 mô hình: Cá nhân · Gia đình · Ở ghép.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text('Mô hình vận hành'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<AllocationPreset>(
                          isExpanded: true,
                          initialValue: _preset,
                          items: AllocationPreset.values
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    IncomeAllocationEngine.presetLabel(p),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _preset = v);
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text('Tổng thu nhập / Ngân quỹ cần chia (VND)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _incomeCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: '20000000',
                            suffixText: 'VND',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ...plan.buckets.map(
                          (b) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              b.isSavingsFund
                                  ? Icons.savings_outlined
                                  : Icons.pie_chart_outline_rounded,
                              color: b.isSavingsFund ? c.success : c.primary,
                            ),
                            title: Text('${b.categoryName} (${b.weightPct}%)'),
                            subtitle: Text(b.groupLabel),
                            trailing: Text(
                              VndAmount.format(b.amountMinor),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const Divider(height: 20),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Tổng đã phân bổ: ${VndAmount.format(plan.allocatedTotalMinor)}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            FilledButton.icon(
                              onPressed: plan.buckets.isEmpty
                                  ? null
                                  : () {
                                      final budgetBloc = context.read<BudgetBloc>();
                                      for (final b in plan.buckets) {
                                        if (!b.isSavingsFund && b.amountMinor > 0) {
                                          budgetBloc.add(
                                            BudgetUpsertSubmitted(
                                              UpsertBudgetParams(
                                                userId: widget.userId,
                                                categoryId: b.categoryId,
                                                categoryName: b.categoryName,
                                                monthKey: state.monthKey,
                                                limitMinor: b.amountMinor,
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '✓ Đã áp dụng bảng phân bổ vào Ngân sách tháng ${state.monthKey}.',
                                          ),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                              label: const Text('Áp dụng vào Ngân sách tháng'),
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
        );
      },
    );
  }
}

class _MetricMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color accent;

  const _MetricMiniCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetsAndFundsTabView extends StatelessWidget {
  final String userId;
  final String userName;
  final String? familyId;

  const _BudgetsAndFundsTabView({
    required this.userId,
    required this.userName,
    this.familyId,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final categories = context.watch<TransactionListBloc>().state.categories;
    final monthKey = context.watch<TransactionListBloc>().state.monthKey;

    return BlocBuilder<BudgetBloc, BudgetState>(
      builder: (context, state) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: ListView(
              key: const Key('budgets_list_view'),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Ngân sách tháng $monthKey',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showUpsertBudgetDialog(
                        context,
                        userId: userId,
                        monthKey: monthKey,
                        categories: categories,
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Đặt ngân sách'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (state.budgets.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('Chưa đặt hạn mức ngân sách cho tháng này.'),
                    ),
                  )
                else
                  ...state.budgets.map((b) {
                    final statusKind = b.isExceeded
                        ? SemanticStatusKind.error
                        : b.isWarning
                            ? SemanticStatusKind.warning
                            : SemanticStatusKind.success;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                alignment: WrapAlignment.spaceBetween,
                                children: [
                                  Text(b.categoryName,
                                      style: Theme.of(context).textTheme.titleMedium),
                                  SemanticStatusBadge(
                                    kind: statusKind,
                                    label: b.isExceeded
                                        ? 'Vượt ngân sách (${b.percentUsed}%)'
                                        : 'Đã dùng ${b.percentUsed}%',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: (b.percentUsed / 100.0).clamp(0.0, 1.0),
                                color:
                                    b.isExceeded ? c.error : (b.isWarning ? c.warning : c.primary),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Đã chi: ${VndAmount.format(b.spentMinor)} / Hạn mức: ${VndAmount.format(b.limitMinor)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quỹ Riêng & Quỹ Chung Gia đình / Nhóm',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            'Sổ phân bổ kế toán minh bạch — Không giữ tiền thật hay lộ số dư ví riêng.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showCreateFundDialog(context),
                      icon: const Icon(Icons.savings_outlined, size: 18),
                      label: const Text('Tạo quỹ'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (state.funds.isEmpty)
                  const EmptyStateView(
                    icon: Icons.savings_outlined,
                    imageAsset: AppAssets.financeIllustration,
                    title: 'Chưa có sổ quỹ nào',
                    subtitle: 'Tạo quỹ mục tiêu cá nhân hoặc quỹ chung gia đình (VD: Quỹ Sắm Tết).',
                  )
                else
                  ...state.funds.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                                    child: Text(f.name,
                                        style: Theme.of(context).textTheme.titleMedium),
                                  ),
                                  SemanticStatusBadge(
                                    kind: SemanticStatusKind.info,
                                    label:
                                        f.scope == FundScope.family ? 'Quỹ Chung' : 'Quỹ Riêng',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Số dư sổ quỹ: ${VndAmount.format(f.balanceMinor)} / Mục tiêu: ${VndAmount.format(f.targetAmountMinor)}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: AppSpacing.xs,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _showFundAmountDialog(
                                      context,
                                      fund: f,
                                      isContribution: true,
                                    ),
                                    icon: const Icon(Icons.add_circle_outline, size: 16),
                                    label: const Text('Góp quỹ'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _showFundAmountDialog(
                                      context,
                                      fund: f,
                                      isContribution: false,
                                    ),
                                    icon: const Icon(Icons.outbox_rounded, size: 16),
                                    label: const Text('Đề xuất chi'),
                                  ),
                                ],
                              ),
                              if (f.expenseRequests.isNotEmpty) ...[
                                const Divider(height: 20),
                                ...f.expenseRequests.take(3).map(
                                  (exp) => ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      '${exp.title} · ${VndAmount.format(exp.amountMinor)}',
                                    ),
                                    subtitle: Text('Đề xuất bởi: ${exp.requesterName}'),
                                    trailing: exp.status == FundExpenseStatus.pending &&
                                            f.scope == FundScope.family &&
                                            f.familyId != null
                                        ? TextButton(
                                            onPressed: () => context.read<BudgetBloc>().add(
                                                  FundExpenseDecisionSubmitted(
                                                    DecideFundExpenseParams(
                                                      familyId: f.familyId!,
                                                      fundId: f.id,
                                                      expenseId: exp.id,
                                                      approve: true,
                                                    ),
                                                  ),
                                                ),
                                            child: const Text('Duyệt chi'),
                                          )
                                        : SemanticStatusBadge(
                                            kind: exp.status == FundExpenseStatus.approved
                                                ? SemanticStatusKind.success
                                                : exp.status == FundExpenseStatus.rejected
                                                    ? SemanticStatusKind.error
                                                    : SemanticStatusKind.provisional,
                                            label: exp.status.name.toUpperCase(),
                                          ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showUpsertBudgetDialog(
    BuildContext context, {
    required String userId,
    required String monthKey,
    required List<CategoryEntity> categories,
  }) async {
    final debitCats = categories.where((c) => c.direction == 'debit').toList();
    if (debitCats.isEmpty) return;
    var selectedCat = debitCats.first;
    final limitCtrl = TextEditingController(text: '3000000');
    final bloc = context.read<BudgetBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Thiết lập Ngân sách Danh mục'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Danh mục chi tiêu'),
              const SizedBox(height: 6),
              DropdownButtonFormField<CategoryEntity>(
                isExpanded: true,
                initialValue: selectedCat,
                items: debitCats
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setStateDialog(() => selectedCat = v);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Hạn mức tháng (VND)'),
              const SizedBox(height: 6),
              TextField(controller: limitCtrl, keyboardType: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                final limit = VndAmount.tryParseInput(limitCtrl.text) ?? 0;
                bloc.add(
                  BudgetUpsertSubmitted(
                    UpsertBudgetParams(
                      userId: userId,
                      categoryId: selectedCat.id,
                      categoryName: selectedCat.name,
                      monthKey: monthKey,
                      limitMinor: limit,
                    ),
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateFundDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final targetCtrl = TextEditingController(text: '10000000');
    var scope = familyId != null && familyId!.isNotEmpty ? FundScope.family : FundScope.personal;
    final bloc = context.read<BudgetBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Tạo Quỹ Tiết kiệm / Quỹ Chung'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tên quỹ'),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(hintText: 'VD: Quỹ Sắm Tết 2027'),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Phạm vi quỹ'),
              const SizedBox(height: 6),
              DropdownButtonFormField<FundScope>(
                isExpanded: true,
                initialValue: scope,
                items: [
                  const DropdownMenuItem(value: FundScope.personal, child: Text('Quỹ Cá nhân riêng')),
                  if (familyId != null && familyId!.isNotEmpty)
                    const DropdownMenuItem(
                        value: FundScope.family, child: Text('Quỹ Chung Gia đình / Nhóm')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => scope = v);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Mục tiêu (VND)'),
              const SizedBox(height: 6),
              TextField(controller: targetCtrl, keyboardType: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                final target = VndAmount.tryParseInput(targetCtrl.text) ?? 0;
                bloc.add(
                  FundCreateSubmitted(
                    CreateFundParams(
                      userId: userId,
                      familyId: familyId,
                      scope: scope,
                      name: nameCtrl.text,
                      targetAmountMinor: target,
                    ),
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Tạo quỹ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFundAmountDialog(
    BuildContext context, {
    required FundEntity fund,
    required bool isContribution,
  }) async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final bloc = context.read<BudgetBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isContribution
              ? 'Ghi nhận Góp quỹ "${fund.name}"'
              : 'Đề xuất Chi quỹ "${fund.name}"',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isContribution ? 'Ghi chú đóng góp' : 'Mục đích khoản chi'),
            const SizedBox(height: 6),
            TextField(controller: titleCtrl),
            const SizedBox(height: AppSpacing.sm),
            const Text('Số tiền (VND)'),
            const SizedBox(height: 6),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final amt = VndAmount.tryParseInput(amountCtrl.text) ?? 0;
              if (isContribution) {
                bloc.add(
                  FundContributionSubmitted(
                    ContributeFundParams(
                      userId: userId,
                      userName: userName,
                      scope: fund.scope,
                      familyId: fund.familyId,
                      fundId: fund.id,
                      amountMinor: amt,
                      note: titleCtrl.text,
                    ),
                  ),
                );
              } else {
                bloc.add(
                  FundExpenseRequested(
                    RequestFundExpenseParams(
                      userId: userId,
                      userName: userName,
                      scope: fund.scope,
                      familyId: fund.familyId,
                      fundId: fund.id,
                      title: titleCtrl.text,
                      amountMinor: amt,
                      canAutoApprove: fund.scope == FundScope.personal,
                    ),
                  ),
                );
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }
}

class _SmartQuickEntryCard extends StatefulWidget {
  final String userId;
  final String defaultWalletId;

  const _SmartQuickEntryCard({
    required this.userId,
    required this.defaultWalletId,
  });

  @override
  State<_SmartQuickEntryCard> createState() => _SmartQuickEntryCardState();
}

class _SmartQuickEntryCardState extends State<_SmartQuickEntryCard> {
  final TextEditingController _ctrl = TextEditingController();
  ParsedSmartEntry? _preview;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submitQuickEntry() {
    final parsed = _preview ?? SmartQuickEntryParser.tryParse(_ctrl.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠ Hãy nhập nội dung kèm số tiền (VD: "ăn phở 65k", "tiền điện 850k", "lương 18tr").',
          ),
        ),
      );
      return;
    }
    context.read<TransactionActionBloc>().add(
          TransactionCreateSubmitted(
            operationId: const Uuid().v4(),
            userId: widget.userId,
            walletId: widget.defaultWalletId,
            categoryId: parsed.categoryId,
            categoryName: parsed.categoryName,
            kind: parsed.kind,
            amountMinor: parsed.amountMinor,
            merchant: parsed.merchant,
            occurredAt: DateTime.now(),
          ),
        );
    setState(() {
      _ctrl.clear();
      _preview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final p = _preview;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: c.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ghi nhanh 1 chạm bằng Ngôn ngữ Tự nhiên',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('smart_quick_entry_field'),
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    onChanged: (v) => setState(() => _preview = SmartQuickEntryParser.tryParse(v)),
                    onSubmitted: (_) => _submitQuickEntry(),
                    decoration: const InputDecoration(
                      hintText: 'VD: phở bò 65k, xăng 90k, nhận lương 18tr5',
                      isDense: true,
                      prefixIcon: Icon(Icons.auto_fix_high_rounded, size: 19),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('smart_quick_entry_submit_button'),
                  onPressed: _submitQuickEntry,
                  child: const Text('Ghi sổ'),
                ),
              ],
            ),
            if (p != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SemanticStatusBadge(
                    kind: p.kind == TransactionKind.income
                        ? SemanticStatusKind.success
                        : SemanticStatusKind.info,
                    label: p.kind == TransactionKind.income ? 'Thu nhập' : 'Chi tiêu',
                  ),
                  Text(
                    '${p.merchant} · ${p.categoryName} · ${VndAmount.format(p.amountMinor)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
}
