import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/services/native_app_updater_bridge.dart';
import '../../../../core/utils/smart_quick_entry_parser.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/voice_smart_capture_sheet.dart';
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
              LifeOsTopToast.fromSnackBar(context, 
                SnackBar(content: Text('⚠ ${state.failure!.message}')),
              );
            } else if (state.status == ActionStatus.success && state.successMessage != null) {
              LifeOsTopToast.fromSnackBar(context, 
                SnackBar(content: Text('✓ ${state.successMessage!}')),
              );
            }
          },
        ),
        BlocListener<BudgetBloc, BudgetState>(
          listenWhen: (p, c) =>
              (c.failure != null && p.failure != c.failure) ||
              (c.actionMessage != null && p.actionMessage != c.actionMessage),
          listener: (context, state) {
            if (state.failure != null) {
              LifeOsTopToast.fromSnackBar(context, 
                SnackBar(content: Text('⚠ ${state.failure!.message}')),
              );
            } else if (state.actionMessage != null) {
              LifeOsTopToast.fromSnackBar(context, 
                SnackBar(content: Text('✓ ${state.actionMessage!}')),
              );
            }
          },
        ),
        BlocListener<TransactionListBloc, TransactionListState>(
          listenWhen: (p, c) => p.monthKey != c.monthKey,
          listener: (context, state) {
            context.read<BudgetBloc>().add(
              BudgetsSubscriptionRequested(
                userId: user.id,
                monthKey: state.monthKey,
                familyId: user.activeFamilyId,
              ),
            );
          },
        ),
      ],
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  LifeOsTopBrandHeader(
                    title: 'Tài chính',
                    extraBrandActions: [
                      BlocBuilder<TransactionListBloc, TransactionListState>(
                        builder: (context, listState) {
                          return LifeOsHeaderCircleButton(
                            buttonKey: const Key('export_statement_csv_button'),
                            icon: Icons.ios_share_rounded,
                            tooltip: 'Xuất Sao kê CSV thực tế',
                            onTap: listState.filteredTransactions.isEmpty
                                ? null
                                : () => _exportMonthlyStatementCsv(
                                      context,
                                      monthKey: listState.monthKey,
                                      transactions: listState.filteredTransactions,
                                      wallets: listState.wallets,
                                    ),
                          );
                        },
                      ),
                      LifeOsHeaderCircleButton(
                        buttonKey: const Key('open_financial_ai_assistant_btn'),
                        icon: Icons.edit_note_rounded,
                        tooltip: 'Nhập gộp nhiều khoản thu chi',
                        onTap: () => context.push('/financial-ai'),
                      ),
                      LifeOsHeaderCircleButton(
                        icon: Icons.account_balance_wallet_outlined,
                        tooltip: 'Thêm ví / tài khoản mới',
                        onTap: () => _showCreateWalletDialog(context, user.id),
                      ),
                    ],
                    trailingAction: BlocBuilder<TransactionListBloc, TransactionListState>(
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
                  const ProPillTabContainer(
                    tabBar: TabBar(
                      labelPadding: EdgeInsets.symmetric(horizontal: 6),
                      tabs: [
                        Tab(text: 'Sổ thu chi'),
                        Tab(text: 'Ngân sách'),
                        Tab(
                          key: Key('finance_analytics_tab'),
                          text: 'Phân tích',
                        ),
                        Tab(
                          key: Key('finance_tools_tab'),
                          text: 'Công cụ',
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
                        const _FinanceToolsHubTabView(),
                      ],
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

  Future<void> _exportMonthlyStatementCsv(
    BuildContext context, {
    required String monthKey,
    required List<TransactionEntity> transactions,
    required List<WalletEntity> wallets,
  }) async {
    final walletNames = <String, String>{for (final w in wallets) w.id: w.name};
    String esc(String input) {
      final cleaned = input.replaceAll('"', '""').replaceAll('\n', ' ');
      return '"$cleaned"';
    }

    final buf = StringBuffer()
      ..writeln(
        'ThoiGian,MaButToan,TaiKhoanVi,PhanLoai,HangMuc,NoiDung,SoTienVND,SoDuSauGD,TrangThai',
      );

    for (final tx in transactions) {
      final dt =
          '${tx.occurredAt.year}-${tx.occurredAt.month.toString().padLeft(2, '0')}-${tx.occurredAt.day.toString().padLeft(2, '0')} '
          '${tx.occurredAt.hour.toString().padLeft(2, '0')}:${tx.occurredAt.minute.toString().padLeft(2, '0')}';
      final wName = tx.walletName ?? walletNames[tx.walletId] ?? tx.walletId;
      final signedAmt = tx.direction == 'credit' ? tx.amountMinor : -tx.amountMinor;
      final balAfter = tx.balanceAfterMinor?.toString() ?? '';
      final status = tx.isReversed ? 'REVERSED' : tx.verification.name.toUpperCase();
      buf.writeln(
        '${esc(dt)},${esc(tx.id)},${esc(wName)},${esc(tx.kind.name)},${esc(tx.categoryName)},'
        '${esc(tx.merchant)},$signedAmt,$balAfter,${esc(status)}',
      );
    }

    final fileName = 'SaoKe_LifeOS_$monthKey.csv';
    final savedPath = await sl<NativeAppUpdaterBridge>().shareTextFile(
      fileName: fileName,
      content: buf.toString(),
      mimeType: 'text/csv',
      title: 'Sao kê Sổ cái Life OS ($monthKey)',
    );

    if (context.mounted) {
      LifeOsTopToast.fromSnackBar(context, 
        SnackBar(
          content: Text(
            savedPath != null
                ? '✓ Đã xuất sao kê $fileName (${transactions.length} giao dịch).'
                : '✓ Đã sao chép sao kê CSV (${transactions.length} giao dịch).',
          ),
        ),
      );
    }
  }

  Future<void> _showCreateWalletDialog(BuildContext context, String userId) async {
    final nameCtrl = TextEditingController();
    final bankCodeCtrl = TextEditingController();
    final maskedCtrl = TextEditingController();
    final openingCtrl = TextEditingController(text: '0');
    var selectedType = WalletType.bank;
    final actionBloc = context.read<TransactionActionBloc>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Thêm Ví / Tài khoản mới'),
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
                    DropdownMenuItem(
                      value: WalletType.bank,
                      child: Text('Tài khoản Ngân hàng'),
                    ),
                    DropdownMenuItem(
                      value: WalletType.savings,
                      child: Text('Sổ Tiết kiệm & Tích lũy'),
                    ),
                    DropdownMenuItem(value: WalletType.creditCard, child: Text('Thẻ tín dụng')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedType = val);
                  },
                ),
                if (selectedType == WalletType.bank || selectedType == WalletType.creditCard) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: bankCodeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Mã NH',
                            hintText: 'VCB / TCB',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: maskedCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Số đuôi TK',
                            hintText: '•••• 8868',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                const Text('Số dư đầu kỳ (VND)'),
                const SizedBox(height: 6),
                TextField(
                  controller: openingCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '5000000', suffixText: 'VND'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                final opening = VndAmount.tryParseInput(openingCtrl.text) ?? 0;
                actionBloc.add(
                  WalletCreateSubmitted(
                    userId: userId,
                    name: nameCtrl.text,
                    type: selectedType,
                    openingBalanceMinor: opening,
                    bankCode: bankCodeCtrl.text.trim().isEmpty ? null : bankCodeCtrl.text.trim(),
                    maskedAccount: maskedCtrl.text.trim().isEmpty ? null : maskedCtrl.text.trim(),
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
    var sourceWalletId = UserBehaviorPrefs.resolvePreferredWalletId(
      wallets.map((w) => w.id),
    );
    String? targetWalletId = wallets.length > 1
        ? wallets.firstWhere((w) => w.id != sourceWalletId, orElse: () => wallets.first).id
        : null;

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
            title: const Text('Ghi giao dịch mới'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Loại giao dịch'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<TransactionKind>(
                    isExpanded: true,
                    initialValue: kind,
                    items: const [
                      DropdownMenuItem(value: TransactionKind.expense, child: Text('Chi tiêu')),
                      DropdownMenuItem(value: TransactionKind.income, child: Text('Thu nhập')),
                      DropdownMenuItem(
                        value: TransactionKind.transfer,
                        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
                          'Chuyển ví nội bộ / Rút tiền mặt',
                        )),
                      ),
                      DropdownMenuItem(
                        value: TransactionKind.creditCardPayment,
                        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
                          'Trả dư nợ thẻ tín dụng',
                        )),
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
                              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
                                '${w.name} (${VndAmount.format(w.balanceMinor)})',
                              )),
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
                                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(w.name)),
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
                        title: const Text('Tách hóa đơn vào nhiều danh mục'),
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
                                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(name)),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => selectedCategory = v);
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Số tiền (VNĐ)'),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('tx_amount_input'),
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Gõ ngắn gọn (VD: 85 -> chọn 85.000 ₫)',
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final zeroPads =
                          UserBehaviorPrefs.vndZeroPadSuggestions(amountCtrl.text);
                      if (zeroPads.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final sug in zeroPads)
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(sug.$2),
                                onPressed: () => setDialogState(() {
                                  amountCtrl.text = '${sug.$1}';
                                  amountCtrl.selection = TextSelection.collapsed(
                                    offset: amountCtrl.text.length,
                                  );
                                }),
                              ),
                          ],
                        ),
                      );
                    },
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
                                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(n)),
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
                                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(n)),
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
                  UserBehaviorPrefs.rememberWallet(sourceWalletId);
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

class _TransactionsTabView extends StatefulWidget {
  final String userId;
  const _TransactionsTabView({required this.userId});

  @override
  State<_TransactionsTabView> createState() => _TransactionsTabViewState();
}

class _TransactionsTabViewState extends State<_TransactionsTabView> {
  late final TextEditingController _searchCtrl;
  bool _obscureBalances = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(
      text: context.read<TransactionListBloc>().state.searchQuery,
    );
    UserBehaviorPrefs.loadLastWalletId();
    UserBehaviorPrefs.loadHideBalances().then((hide) {
      if (mounted && hide != _obscureBalances) {
        setState(() => _obscureBalances = hide);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDateHeader(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    if (diff == 0) return 'HÔM NAY · $dd/$mm/${date.year}';
    if (diff == 1) return 'HÔM QUA · $dd/$mm/${date.year}';
    return 'NGÀY $dd/$mm/${date.year}';
  }

  String _formatTimeLabel(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _showTransactionReceiptSheet(
    BuildContext context,
    TransactionEntity tx,
    String resolvedWalletName,
  ) async {
    final c = TammySemanticColors.of(context);
    final isCredit = tx.direction == 'credit';
    final isInternal =
        tx.kind == TransactionKind.transfer || tx.kind == TransactionKind.creditCardPayment;
    final amountColor =
        isInternal ? c.secondary : (isCredit ? c.success : c.textPrimary);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProCategoryStyle.buildCategoryBadge(
                  tx.categoryName,
                  isCredit: isCredit,
                  isTransfer: isInternal,
                  size: 58,
                ),
                const SizedBox(height: 10),
                Text(
                  tx.merchant,
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  isInternal
                      ? '⇄ ${VndAmount.format(tx.amountMinor)}'
                      : VndAmount.format(
                          isCredit ? tx.amountMinor : -tx.amountMinor,
                          showPlus: true,
                        ),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: amountColor,
                    letterSpacing: -0.6,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                SemanticStatusBadge(
                  kind: tx.isReversed
                      ? SemanticStatusKind.warning
                      : SemanticStatusKind.success,
                  label: tx.isReversed ? 'Đã hoàn tác' : 'Đã ghi nhận',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.separator.withValues(alpha: 0.7), width: 0.8),
                  ),
                  child: Column(
                    children: [
                      _ReceiptRow(label: 'Danh mục', value: tx.categoryName),
                      const Divider(height: 16),
                      _ReceiptRow(label: 'Ví', value: resolvedWalletName),
                      if (tx.balanceAfterMinor != null) ...[
                        const Divider(height: 16),
                        _ReceiptRow(
                          label: 'Số dư sau giao dịch',
                          value: VndAmount.format(tx.balanceAfterMinor!),
                        ),
                      ],
                      const Divider(height: 16),
                      _ReceiptRow(
                        label: 'Thời gian',
                        value:
                            '${tx.occurredAt.day.toString().padLeft(2, '0')}/${tx.occurredAt.month.toString().padLeft(2, '0')}/${tx.occurredAt.year} · ${_formatTimeLabel(tx.occurredAt)}',
                      ),
                      if (tx.referenceCode != null && tx.referenceCode!.trim().isNotEmpty) ...[
                        const Divider(height: 16),
                        _ReceiptRow(
                          label: 'Mã tham chiếu',
                          value: tx.referenceCode!,
                        ),
                      ],
                      if (tx.note != null && tx.note!.trim().isNotEmpty) ...[
                        const Divider(height: 16),
                        _ReceiptRow(label: 'Ghi chú', value: tx.note!),
                      ],
                      if (tx.splitLines.isNotEmpty) ...[
                        const Divider(height: 16),
                        _ReceiptRow(
                          label: 'Tách khoản',
                          value: tx.splitLines
                              .map((l) => '${l.categoryName}: ${VndAmount.format(l.amountMinor)}')
                              .join('\n'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        child: const Text('Đóng'),
                      ),
                    ),
                    if (tx.isConfirmedInLedger &&
                        !tx.isReversed &&
                        tx.kind != TransactionKind.reversal) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.undo_rounded, size: 18),
                          label: const Text('Hoàn tác'),
                          onPressed: () async {
                            Navigator.of(sheetCtx).pop();
                            final ok = await showDestructiveConfirmDialog(
                              context: context,
                              title: 'Hoàn tác giao dịch này?',
                              message: 'Số tiền sẽ được cộng trả lại vào ví của bạn.',
                              confirmLabel: 'Hoàn tác',
                            );
                            if (ok && context.mounted) {
                              context.read<TransactionActionBloc>().add(
                                    TransactionReverseRequested(
                                      userId: widget.userId,
                                      transactionId: tx.id,
                                    ),
                                  );
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return BlocConsumer<TransactionListBloc, TransactionListState>(
      listenWhen: (p, c) => p.searchQuery != c.searchQuery,
      listener: (_, state) {
        if (state.searchQuery.isEmpty && _searchCtrl.text.isNotEmpty) {
          _searchCtrl.clear();
        }
      },
      builder: (context, state) {
        final walletMap = <String, WalletEntity>{
          for (final w in state.wallets) w.id: w,
        };

        final visibleTxs = state.filteredTransactions;

        // Group visible transactions chronologically by calendar day
        final now = DateTime.now();
        final groupedByDay = <String, List<TransactionEntity>>{};
        final dayHeaders = <String, String>{};
        for (final tx in visibleTxs) {
          final dayKey =
              '${tx.occurredAt.year}-${tx.occurredAt.month.toString().padLeft(2, '0')}-${tx.occurredAt.day.toString().padLeft(2, '0')}';
          groupedByDay.putIfAbsent(dayKey, () => <TransactionEntity>[]).add(tx);
          dayHeaders.putIfAbsent(dayKey, () => _formatDateHeader(tx.occurredAt, now));
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: ListView(
              key: const Key('transactions_list_view'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.dockClearance,
              ),
              children: [
                // 1. Unified LifeOS Month & 3-Column Budget Progress Card
                _LifeOsSpendingOverviewDeck(state: state, onlyTopSummary: true),

                // 2. Clearly Separated Section: Ví & Tài khoản
                LifeOsSectionHeader(
                  title: 'Ví của bạn (${state.wallets.length})',
                  padding: const EdgeInsets.only(top: 10, bottom: 4, left: 2, right: 2),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.selectedWalletId != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            context.read<TransactionListBloc>().add(
                              const TransactionsWalletFilterChanged(null),
                            );
                          },
                          icon: const Icon(
                            Icons.filter_alt_off_rounded,
                            size: 15,
                          ),
                          label: const Text('Tất cả ví'),
                        ),
                      IconButton(
                        key: const Key('finance_toggle_privacy_btn'),
                        tooltip: _obscureBalances
                            ? 'Hiện lại số dư'
                            : 'Ẩn số dư riêng tư',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          final next = !_obscureBalances;
                          setState(() => _obscureBalances = next);
                          UserBehaviorPrefs.saveHideBalances(next);
                        },
                        icon: Icon(
                          _obscureBalances
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.wallets.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('Đang khởi tạo danh mục ví mặc định...'),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: state.wallets.map((w) {
                        final selected = state.selectedWalletId == w.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: ProWalletCreditCard(
                            name: w.name,
                            walletTypeKey: w.type.name,
                            balanceMinor: w.balanceMinor,
                            bankCode: w.bankCode,
                            maskedAccount: w.maskedAccount,
                            isEstimatedBalance: w.isEstimatedBalance,
                            hasPendingWrites: w.hasPendingWrites,
                            obscureBalance: _obscureBalances,
                            isSelected: selected,
                            onTap: () {
                              context.read<TransactionListBloc>().add(
                                TransactionsWalletFilterChanged(w.id),
                              );
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                if (state.provisionalTransactions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Giao dịch mới chờ duyệt (${state.provisionalTransactions.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ...state.provisionalTransactions.map(
                    (tx) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.hourglass_top_rounded,
                                    color: c.warning,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${tx.merchant} · ${VndAmount.format(tx.amountMinor)}',
                                          softWrap: true,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Gợi ý: ${tx.categoryName}',
                                          softWrap: true,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => context
                                        .read<TransactionActionBloc>()
                                        .add(
                                          ProvisionalTransactionDecisionSubmitted(
                                            userId: widget.userId,
                                            transactionId: tx.id,
                                            approve: false,
                                          ),
                                        ),
                                    child: const Text('Bỏ qua'),
                                  ),
                                  FilledButton(
                                    onPressed: () => context
                                        .read<TransactionActionBloc>()
                                        .add(
                                          ProvisionalTransactionDecisionSubmitted(
                                            userId: widget.userId,
                                            transactionId: tx.id,
                                            approve: true,
                                          ),
                                        ),
                                    child: const Text('Xác nhận'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                LifeOsSectionHeader(
                  title: 'Sổ thu chi & Sao kê',
                  padding: const EdgeInsets.only(top: 10, bottom: 6, left: 2, right: 2),
                  trailing: state.hasActiveFilters
                      ? TextButton.icon(
                          key: const Key('tx_header_clear_filters_btn'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            context.read<TransactionListBloc>().add(
                              const TransactionsFiltersReset(),
                            );
                          },
                          icon: const Icon(
                            Icons.filter_alt_off_rounded,
                            size: 15,
                          ),
                          label: const Text('Xóa lọc'),
                        )
                      : null,
                ),
                if (state.wallets.isNotEmpty) ...[
                  _SmartQuickEntryCard(
                    userId: widget.userId,
                    defaultWalletId:
                        state.selectedWalletId ??
                        UserBehaviorPrefs.resolvePreferredWalletId(
                          state.wallets.map((w) => w.id),
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextField(
                  key: const Key('tx_search_field'),
                  controller: _searchCtrl,
                  onChanged: (q) => context
                      .read<TransactionListBloc>()
                      .add(TransactionsSearchChanged(q)),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Tìm giao dịch, danh mục',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: state.searchQuery.isEmpty &&
                            _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('tx_search_clear_btn'),
                            tooltip: 'Xóa tìm kiếm',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _searchCtrl.clear();
                              context.read<TransactionListBloc>().add(
                                const TransactionsSearchChanged(''),
                              );
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                  ),
                ),
                const SizedBox(height: 10),

                // Statement Type Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _StatementKindChip(
                        label: 'Tất cả sao kê',
                        selected: !state.hasActiveFilters,
                        onSelected: () {
                          _searchCtrl.clear();
                          context.read<TransactionListBloc>().add(
                            const TransactionsFiltersReset(),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _StatementKindChip(
                        label: '↓ Thu nhập',
                        selected: state.kindFilter == TransactionKind.income,
                        onSelected: () => context
                            .read<TransactionListBloc>()
                            .add(const TransactionsKindFilterChanged(TransactionKind.income)),
                      ),
                      const SizedBox(width: 8),
                      _StatementKindChip(
                        label: '↑ Chi tiêu',
                        selected: state.kindFilter == TransactionKind.expense,
                        onSelected: () => context
                            .read<TransactionListBloc>()
                            .add(const TransactionsKindFilterChanged(TransactionKind.expense)),
                      ),
                      const SizedBox(width: 8),
                      _StatementKindChip(
                        label: '⇄ Chuyển ví',
                        selected: state.kindFilter == TransactionKind.transfer,
                        onSelected: () => context
                            .read<TransactionListBloc>()
                            .add(const TransactionsKindFilterChanged(TransactionKind.transfer)),
                      ),
                      if (state.categoryFilter != null) ...[
                        const SizedBox(width: 8),
                        InputChip(
                          visualDensity: VisualDensity.compact,
                          selected: true,
                          label: Text('Danh mục: ${state.categoryFilter}'),
                          onDeleted: () => context
                              .read<TransactionListBloc>()
                              .add(const TransactionsCategoryFilterChanged(null)),
                          onPressed: () => context
                              .read<TransactionListBloc>()
                              .add(const TransactionsCategoryFilterChanged(null)),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),
                if (visibleTxs.isEmpty && state.hasActiveFilters)
                  LifeOsSoftCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        Icon(
                          Icons.filter_alt_off_rounded,
                          size: 36,
                          color: c.textSecondary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Không tìm thấy giao dịch khớp bộ lọc',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bấm nút bên dưới để hiển thị lại toàn bộ giao dịch trong tháng.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          key: const Key('tx_reset_all_filters_btn'),
                          onPressed: () {
                            _searchCtrl.clear();
                            context.read<TransactionListBloc>().add(
                              const TransactionsFiltersReset(),
                            );
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 17),
                          label: const Text('Xóa tất cả bộ lọc'),
                        ),
                      ],
                    ),
                  )
                else if (visibleTxs.isEmpty)
                  const EmptyStateView(
                    icon: Icons.receipt_long_outlined,
                    imageAsset: AppAssets.financeIllustration,
                    title: 'Chưa có giao dịch nào',
                    subtitle: 'Nhấn "Ghi giao dịch" để thêm khoản thu chi mới.',
                  )
                else
                  ...groupedByDay.entries.map((entry) {
                    final dayKey = entry.key;
                    final dayTxs = entry.value;
                    var dayNetMinor = 0;
                    for (final tx in dayTxs) {
                      if (tx.isReversed ||
                          tx.kind == TransactionKind.transfer ||
                          tx.kind == TransactionKind.creditCardPayment ||
                          tx.kind == TransactionKind.reversal) {
                        continue;
                      }
                      dayNetMinor += tx.direction == 'credit' ? tx.amountMinor : -tx.amountMinor;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 6,
                            bottom: 8,
                            left: 2,
                            right: 2,
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                dayHeaders[dayKey] ?? dayKey,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: c.textSecondary,
                                ),
                              ),
                              if (dayNetMinor != 0 && !_obscureBalances)
                                Text(
                                  VndAmount.format(dayNetMinor, showPlus: true),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: dayNetMinor > 0
                                        ? c.success
                                        : c.textSecondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ...dayTxs.map((tx) {
                          final isCredit = tx.direction == 'credit';
                          final isInternal = tx.kind == TransactionKind.transfer ||
                              tx.kind == TransactionKind.creditCardPayment;
                          final wName = tx.walletName ?? walletMap[tx.walletId]?.name;
                          final splitSummary = tx.splitLines.isNotEmpty
                              ? 'Tách khoản: ${tx.splitLines.map((l) => '${l.categoryName} (${VndAmount.format(l.amountMinor)})').join(' · ')}'
                              : null;

                          final canUndo = tx.isConfirmedInLedger &&
                              !tx.isReversed &&
                              tx.kind != TransactionKind.reversal;
                          final statementTile = ProFintechStatementTile(
                            merchant: tx.merchant,
                            categoryName: tx.categoryName,
                            walletName: wName,
                            timeLabel: _formatTimeLabel(tx.occurredAt),
                            amountMinor: tx.amountMinor,
                            balanceAfterMinor: tx.balanceAfterMinor,
                            isCredit: isCredit,
                            isTransfer: isInternal,
                            isReversed: tx.isReversed,
                            isVerified: tx.verification == TransactionVerification.verified ||
                                tx.verification == TransactionVerification.matchedPaymentOrder ||
                                tx.verification == TransactionVerification.userConfirmed,
                            hasPendingWrites: tx.hasPendingWrites,
                            splitSummary: splitSummary,
                            obscureAmounts: _obscureBalances,
                            onTap: () => _showTransactionReceiptSheet(
                              context,
                              tx,
                              wName ?? 'Ví cá nhân',
                            ),
                          );

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: canUndo
                                ? Dismissible(
                                    key: ValueKey('swipe_tx_${tx.id}'),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.symmetric(horizontal: 18),
                                      decoration: BoxDecoration(
                                        color: c.warning.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: c.warning.withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.undo_rounded, color: c.warning, size: 19),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Hoàn tác',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: c.warning,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    confirmDismiss: (_) async {
                                      final ok = await showDestructiveConfirmDialog(
                                        context: context,
                                        title: 'Hoàn tác giao dịch này?',
                                        message: 'Số tiền sẽ được cộng trả lại vào ví của bạn.',
                                        confirmLabel: 'Hoàn tác',
                                      );
                                      if (ok && context.mounted) {
                                        context.read<TransactionActionBloc>().add(
                                              TransactionReverseRequested(
                                                userId: widget.userId,
                                                transactionId: tx.id,
                                              ),
                                            );
                                      }
                                      return false;
                                    },
                                    child: statementTile,
                                  )
                                : statementTile,
                          );
                        }),
                      ],
                    );
                  }),
                const SizedBox(height: 14),
                _LifeOsSpendingOverviewDeck(state: state, onlyCharts: true),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatementKindChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _StatementKindChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiptRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
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
    final budgetState = context.watch<BudgetBloc>().state;
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

        // Compute real 7-day Income & Expense series anchored to current date (or latest tx date in past month).
        final now = DateTime.now();
        final currentMk =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
        DateTime anchorDate = DateTime(now.year, now.month, now.day);
        if (state.monthKey != currentMk) {
          if (state.filteredTransactions.isNotEmpty) {
            var latest = state.filteredTransactions.first.occurredAt;
            for (final tx in state.filteredTransactions) {
              if (tx.occurredAt.isAfter(latest)) latest = tx.occurredAt;
            }
            anchorDate = DateTime(latest.year, latest.month, latest.day);
          } else {
            final parts = state.monthKey.split('-');
            final y = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? now.year) : now.year;
            final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? now.month) : now.month;
            anchorDate = DateTime(y, m + 1, 0);
          }
        }

        final dailyIncomes = List<int>.filled(7, 0);
        final dailyExpenses = List<int>.filled(7, 0);
        for (final tx in state.filteredTransactions) {
          if (tx.isReversed) continue;
          final txDay = DateTime(
            tx.occurredAt.year,
            tx.occurredAt.month,
            tx.occurredAt.day,
          );
          final diffDays = anchorDate.difference(txDay).inDays;
          if (diffDays >= 0 && diffDays < 7) {
            final idx = 6 - diffDays;
            if (tx.kind == TransactionKind.income) {
              dailyIncomes[idx] += tx.amountMinor;
            } else if (tx.kind == TransactionKind.expense) {
              dailyExpenses[idx] += tx.amountMinor;
            }
          }
        }

        var liquidAssets = 0;
        var savingsAssets = 0;
        for (final w in state.wallets) {
          if (w.type == WalletType.savings) {
            savingsAssets += math.max(0, w.balanceMinor);
          } else if (w.type == WalletType.cash || w.type == WalletType.bank) {
            liquidAssets += math.max(0, w.balanceMinor);
          }
        }

        final totalBudgetLimit = budgetState.budgets.fold<int>(
          0,
          (sum, b) => sum + b.limitMinor,
        );
        final daysInMonth = DateTime(anchorDate.year, anchorDate.month + 1, 0).day;
        final remainingDays = math.max(1, daysInMonth - now.day + 1);
        final safeDaily = totalBudgetLimit > 0
            ? math.max(0, totalBudgetLimit - s.monthlyExpenseMinor) ~/ remainingDays
            : math.max(0, s.monthlyIncomeMinor - s.monthlyExpenseMinor) ~/ remainingDays;

        var healthScore = 70;
        if (s.netCashFlowMinor > 0) healthScore += 14;
        if (s.savingsRatePct >= 20) healthScore += 12;
        if (s.monthlyIncomeMinor > 0 && s.monthlyExpenseMinor > s.monthlyIncomeMinor) {
          healthScore -= 18;
        }
        healthScore = healthScore.clamp(42, 98);

        final maxCashflowCompare = math.max(
          1,
          math.max(s.monthlyIncomeMinor, math.max(s.monthlyExpenseMinor, s.netCashFlowMinor.abs())),
        );

        const allocationPalette = <Color>[
          Color(0xFF0D9488),
          Color(0xFF2563EB),
          Color(0xFF16A34A),
          Color(0xFFF59E0B),
          Color(0xFF7C3AED),
          Color(0xFFEC4899),
        ];

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: ListView(
              key: const Key('analytics_list_view'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.dockClearance,
              ),
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fullW = constraints.maxWidth;
                    final cardW = fullW < 540
                        ? fullW
                        : (fullW - AppSpacing.sm) / 2;
                    return Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _MetricMiniCard(
                          width: cardW,
                          label: 'Dòng tiền ròng (Thu - Chi)',
                          value: VndAmount.format(
                            s.netCashFlowMinor,
                            showPlus: true,
                          ),
                          subtitle: s.monthlyIncomeMinor > 0
                              ? 'Tỷ lệ tiết kiệm: ${s.savingsRatePct.toStringAsFixed(1)}%'
                              : 'Chưa ghi nhận thu nhập kỳ này',
                          accent: s.netCashFlowMinor >= 0 ? c.success : c.error,
                        ),
                        _MetricMiniCard(
                          width: cardW,
                          label: 'Chi trung bình / ngày',
                          value: VndAmount.format(s.averageDailyExpenseMinor),
                          subtitle:
                              'Tổng chi thực: ${VndAmount.format(s.monthlyExpenseMinor)}',
                          accent: c.primary,
                        ),
                        _MetricMiniCard(
                          width: cardW,
                          label: 'Giao dịch đã xác nhận',
                          value:
                              '${s.verifiedCount + s.userConfirmedCount} giao dịch',
                          subtitle: s.provisionalCount > 0
                              ? '${s.provisionalCount} khoản đang chờ duyệt'
                              : 'Không có khoản chờ duyệt',
                          accent: c.secondary,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cơ cấu Chi tiêu theo Danh mục',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (shares.isEmpty)
                          const Text('Chưa có khoản chi trong tháng này.')
                        else ...[
                          RepaintBoundary(
                            child: ProDonutChart(
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
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: [FontFeature.tabularFigures()],
                                          ),
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
                          'Bộ Chia & Phân bổ Thu nhập',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text('Mô hình phân bổ'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<AllocationPreset>(
                          isExpanded: true,
                          initialValue: _preset,
                          items: AllocationPreset.values
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
                                    IncomeAllocationEngine.presetLabel(p),
                                  )),
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
                        if (plan.buckets.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              height: 12,
                              child: Row(
                                children: [
                                  for (var i = 0; i < plan.buckets.length; i++)
                                    if (plan.buckets[i].weightPct > 0)
                                      Expanded(
                                        flex: plan.buckets[i].weightPct,
                                        child: Container(
                                          margin: EdgeInsets.only(
                                            right: i < plan.buckets.length - 1 ? 2 : 0,
                                          ),
                                          color: allocationPalette[i % allocationPalette.length],
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        for (var i = 0; i < plan.buckets.length; i++)
                          Builder(
                            builder: (context) {
                              final b = plan.buckets[i];
                              final bucketColor =
                                  allocationPalette[i % allocationPalette.length];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: bucketColor.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Icon(
                                        b.isSavingsFund
                                            ? Icons.savings_outlined
                                            : Icons.pie_chart_outline_rounded,
                                        size: 17,
                                        color: bucketColor,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${b.categoryName} (${b.weightPct}%)',
                                            softWrap: true,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                          Text(
                                            b.groupLabel,
                                            softWrap: true,
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 120),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          VndAmount.format(b.amountMinor),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
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
                                      LifeOsTopToast.fromSnackBar(context, 
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
                const SizedBox(height: AppSpacing.lg),
                RepaintBoundary(
                  child: ProCashflowPulseCard(
                    dailyIncomesMinor: dailyIncomes,
                    dailyExpensesMinor: dailyExpenses,
                    liquidAssetsMinor: liquidAssets,
                    savingsAssetsMinor: savingsAssets,
                    dailySafeToSpendMinor: safeDaily,
                    financialHealthScore: healthScore,
                    referenceDate: anchorDate,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tương quan Thu · Chi · Tích lũy',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _ProportionalCashflowRow(
                          label: 'Tổng thu nhập',
                          amountText: VndAmount.format(s.monthlyIncomeMinor),
                          ratio: s.monthlyIncomeMinor <= 0
                              ? 0.0
                              : (s.monthlyIncomeMinor / maxCashflowCompare).clamp(0.0, 1.0),
                          color: c.success,
                        ),
                        const SizedBox(height: 10),
                        _ProportionalCashflowRow(
                          label: 'Tổng chi tiêu',
                          amountText: VndAmount.format(s.monthlyExpenseMinor),
                          ratio: s.monthlyExpenseMinor <= 0
                              ? 0.0
                              : (s.monthlyExpenseMinor / maxCashflowCompare).clamp(0.0, 1.0),
                          color: const Color(0xFFF59F00),
                        ),
                        const SizedBox(height: 10),
                        _ProportionalCashflowRow(
                          label: s.netCashFlowMinor >= 0 ? 'Thặng dư ròng' : 'Thâm hụt kỳ này',
                          amountText: VndAmount.format(s.netCashFlowMinor, showPlus: true),
                          ratio: s.netCashFlowMinor == 0
                              ? 0.0
                              : (s.netCashFlowMinor.abs() / maxCashflowCompare).clamp(0.0, 1.0),
                          color: s.netCashFlowMinor >= 0 ? c.primary : c.error,
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

class _ProportionalCashflowRow extends StatelessWidget {
  final String label;
  final String amountText;
  final double ratio;
  final Color color;

  const _ProportionalCashflowRow({
    required this.label,
    required this.amountText,
    required this.ratio,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 2,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: c.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              amountText,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: ratio.clamp(0.0, 1.0),
            backgroundColor: c.surfaceRaised,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _MetricMiniCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final String subtitle;
  final Color accent;

  const _MetricMiniCard({
    this.width = 260,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.dockClearance,
              ),
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
                      child: Text(
                        'Quỹ Riêng & Quỹ Chung',
                        style: Theme.of(context).textTheme.titleMedium,
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
                                  (exp) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 5),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${exp.title} · ${VndAmount.format(exp.amountMinor)}',
                                                softWrap: true,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                              ),
                                              Text(
                                                'Đề xuất bởi: ${exp.requesterName}',
                                                softWrap: true,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        exp.status == FundExpenseStatus.pending &&
                                                f.scope == FundScope.family &&
                                                f.familyId != null
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  TextButton(
                                                    onPressed: () => context
                                                        .read<BudgetBloc>()
                                                        .add(
                                                          FundExpenseDecisionSubmitted(
                                                            DecideFundExpenseParams(
                                                              familyId: f.familyId!,
                                                              fundId: f.id,
                                                              expenseId: exp.id,
                                                              approve: false,
                                                            ),
                                                          ),
                                                        ),
                                                    child: Text(
                                                      'Từ chối',
                                                      style: TextStyle(color: c.error),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => context
                                                        .read<BudgetBloc>()
                                                        .add(
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
                                                  ),
                                                ],
                                              )
                                            : SemanticStatusBadge(
                                                kind: exp.status ==
                                                        FundExpenseStatus.approved
                                                    ? SemanticStatusKind.success
                                                    : exp.status ==
                                                            FundExpenseStatus
                                                                .rejected
                                                        ? SemanticStatusKind.error
                                                        : SemanticStatusKind
                                                            .provisional,
                                                label: exp.status ==
                                                        FundExpenseStatus.approved
                                                    ? 'ĐÃ DUYỆT'
                                                    : exp.status ==
                                                            FundExpenseStatus
                                                                .rejected
                                                        ? 'ĐÃ TỪ CHỐI'
                                                        : 'CHỜ DUYỆT',
                                              ),
                                      ],
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
    var debitCats = categories.where((c) => c.direction == 'debit').toList();
    if (debitCats.isEmpty) {
      debitCats = <CategoryEntity>[
        CategoryEntity(
          id: 'cat_food',
          ownerId: userId,
          name: 'Ăn uống',
          direction: 'debit',
          iconKey: 'food',
        ),
        CategoryEntity(
          id: 'cat_transport',
          ownerId: userId,
          name: 'Di chuyển',
          direction: 'debit',
          iconKey: 'transport',
        ),
        CategoryEntity(
          id: 'cat_shopping',
          ownerId: userId,
          name: 'Mua sắm',
          direction: 'debit',
          iconKey: 'shopping',
        ),
        CategoryEntity(
          id: 'cat_bills',
          ownerId: userId,
          name: 'Hóa đơn',
          direction: 'debit',
          iconKey: 'bills',
        ),
        CategoryEntity(
          id: 'cat_family',
          ownerId: userId,
          name: 'Gia đình',
          direction: 'debit',
          iconKey: 'family',
        ),
      ];
    }
    final bloc = context.read<BudgetBloc>();
    final existingBudgets = bloc.state.budgets;
    var selectedCat = debitCats.first;
    final initialExisting = existingBudgets
        .where((b) => b.categoryName == selectedCat.name)
        .firstOrNull;
    final limitCtrl = TextEditingController(
      text: '${initialExisting?.limitMinor ?? 3000000}',
    );

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
                  if (v != null) {
                    setStateDialog(() {
                      selectedCat = v;
                      final match = existingBudgets
                          .where((b) => b.categoryName == v.name)
                          .firstOrNull;
                      if (match != null) {
                        limitCtrl.text = '${match.limitMinor}';
                      }
                    });
                  }
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
                if (limit <= 0) {
                  LifeOsTopToast.show(
                    ctx,
                    'Hãy nhập hạn mức ngân sách lớn hơn 0 ₫.',
                    kind: LifeOsToastKind.warning,
                  );
                  return;
                }
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
      LifeOsTopToast.fromSnackBar(context, 
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
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 18, color: c.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Ghi nhanh tự nhiên',
                        softWrap: true,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key('finance_voice_capture_button'),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Ghi thu chi bằng giọng nói',
                      onPressed: () => showVoiceSmartCaptureSheet(context),
                      icon: Icon(Icons.mic_rounded, size: 20, color: c.primary),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonal(
                      key: const Key('smart_quick_entry_submit_button'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onPressed: _submitQuickEntry,
                      child: const Text('Ghi sổ'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('smart_quick_entry_field'),
              controller: _ctrl,
              textInputAction: TextInputAction.send,
              onChanged: (v) => setState(
                () => _preview = SmartQuickEntryParser.tryParse(v),
              ),
              onSubmitted: (_) => _submitQuickEntry(),
              decoration: const InputDecoration(
                hintText: 'VD: phở 65k',
                hintMaxLines: 2,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
              ),
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

/// Unified LifeOS Spending Overview Deck matching `04_Chi_tieu.png`.
class _LifeOsSpendingOverviewDeck extends StatelessWidget {
  final TransactionListState state;
  final bool onlyTopSummary;
  final bool onlyCharts;

  const _LifeOsSpendingOverviewDeck({
    required this.state,
    this.onlyTopSummary = false,
    this.onlyCharts = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final budgetState = context.watch<BudgetBloc>().state;

    final spentMinor = state.summary.monthlyExpenseMinor;
    final totalBudgetLimit = budgetState.budgets.fold<int>(
      0,
      (sum, b) => sum + b.limitMinor,
    );
    final hasBudget = totalBudgetLimit > 0;
    final remainingSignedMinor = hasBudget ? (totalBudgetLimit - spentMinor) : 0;
    final pctUsed = hasBudget
        ? ((spentMinor * 100) / totalBudgetLimit).clamp(0, 999).round()
        : 0;
    final isOverBudget = hasBudget && spentMinor > totalBudgetLimit;

    // Aggregate confirmed expenses into 7 exact date-range buckets across the month (`Chi tiêu theo ngày`)
    final buckets = List<int>.filled(7, 0);
    final catTotals = <String, int>{};
    for (final tx in state.allTransactions) {
      if (!tx.isConfirmedInLedger ||
          tx.isReversed ||
          tx.kind != TransactionKind.expense) {
        continue;
      }
      final d = tx.occurredAt.day;
      final idx = d <= 5
          ? 0
          : (d <= 10
                ? 1
                : (d <= 15
                      ? 2
                      : (d <= 20 ? 3 : (d <= 25 ? 4 : (d <= 28 ? 5 : 6)))));
      buckets[idx] += tx.amountMinor;
      if (tx.splitLines.isNotEmpty) {
        for (final sl in tx.splitLines) {
          catTotals[sl.categoryName] =
              (catTotals[sl.categoryName] ?? 0) + sl.amountMinor;
        }
      } else {
        catTotals[tx.categoryName] =
            (catTotals[tx.categoryName] ?? 0) + tx.amountMinor;
      }
    }

    String stepMonthKey(String mk, int deltaMonths) {
      final parts = mk.split('-');
      final y = int.tryParse(parts.firstOrNull ?? '') ?? DateTime.now().year;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? DateTime.now().month;
      final next = DateTime(y, m + deltaMonths, 1);
      return '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}';
    }
    final currentMk = TransactionListBloc.currentMonthKey();
    final authUserId = context.read<AuthBloc>().state.user?.id;

    int catPct(int amt) {
      if (spentMinor <= 0 || amt <= 0) return 0;
      return ((amt * 100) / spentMinor).clamp(1, 100).round();
    }

    // Rank actual top spending categories dynamically, filling up to 4 cards with defaults if needed.
    final sortedActualCats = catTotals.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    const fallbackCategoryNames = <String>[
      'Ăn uống',
      'Di chuyển',
      'Gia đình',
      'Hóa đơn',
    ];
    final topCategoryEntries = <MapEntry<String, int>>[];
    for (final entry in sortedActualCats) {
      if (topCategoryEntries.length >= 4) break;
      topCategoryEntries.add(entry);
    }
    for (final defName in fallbackCategoryNames) {
      if (topCategoryEntries.length >= 4) break;
      final alreadyIncluded = topCategoryEntries.any(
        (e) => e.key.toLowerCase() == defName.toLowerCase(),
      );
      if (!alreadyIncluded) {
        topCategoryEntries.add(MapEntry(defName, 0));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!onlyCharts) ...[
          // Unified Compact Month & 3-Column Budget Progress Card (`04_Chi_tieu.png`)
          LifeOsMintHeroCard(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (authUserId != null)
                          InkWell(
                            key: const Key('finance_prev_month_btn'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => context.read<TransactionListBloc>().add(
                              TransactionsSubscriptionRequested(
                                userId: authUserId,
                                monthKey: stepMonthKey(state.monthKey, -1),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Icon(
                                Icons.chevron_left_rounded,
                                size: 19,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        Icon(Icons.calendar_today_rounded, size: 15, color: c.primary),
                        const SizedBox(width: 5),
                        Flexible(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: (authUserId != null && state.monthKey != currentMk)
                                ? () => context.read<TransactionListBloc>().add(
                                      TransactionsSubscriptionRequested(
                                        userId: authUserId,
                                        monthKey: currentMk,
                                      ),
                                    )
                                : null,
                            child: Text(
                              hasBudget
                                  ? 'Kỳ ${state.monthKey} · Đã chi $pctUsed%'
                                  : 'Kỳ ${state.monthKey} · Thực chi tháng',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        if (authUserId != null)
                          InkWell(
                            key: const Key('finance_next_month_btn'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => context.read<TransactionListBloc>().add(
                              TransactionsSubscriptionRequested(
                                userId: authUserId,
                                monthKey: stepMonthKey(state.monthKey, 1),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 19,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.push('/auto-tx-review'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              '✨ Tự động',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.push('/finance-report'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              '📊 Báo cáo',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Đã chi',
                              style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                VndAmount.format(spentMinor),
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      VerticalDivider(width: 12, color: c.separator),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hạn mức',
                              style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                hasBudget ? VndAmount.format(totalBudgetLimit) : 'Chưa đặt',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: hasBudget ? c.textPrimary : c.textSecondary,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      VerticalDivider(width: 12, color: c.separator),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOverBudget ? 'Vượt mức' : 'Còn lại',
                              style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                hasBudget
                                    ? VndAmount.format(remainingSignedMinor)
                                    : 'Chưa đặt',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: !hasBudget
                                      ? c.textSecondary
                                      : (isOverBudget ? c.error : c.primary),
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: !hasBudget || spentMinor <= 0
                        ? 0.0
                        : (spentMinor / totalBudgetLimit).clamp(0.02, 1.0),
                    backgroundColor: c.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isOverBudget ? c.error : c.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!onlyTopSummary) ...[
          if (!onlyCharts) const SizedBox(height: 12),

          // 3. Interactive "Chi tiêu theo ngày" Precision Chart Card (`04_Chi_tieu.png`)
          _DailySpendingChartCard(
            buckets: buckets,
            totalSpentMinor: spentMinor,
            onOpenReport: () => context.push('/finance-report'),
          ),
          const SizedBox(height: 12),

          // 4. "Chi tiêu theo danh mục" Dynamic Top-4 Spacious 2x2 Bento Grid
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.push('/finance-report'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.sell_outlined, size: 18, color: c.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Chi tiêu theo danh mục',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 19, color: c.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var rowIdx = 0; rowIdx < topCategoryEntries.length; rowIdx += 2) ...[
            if (rowIdx > 0) const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final idx = rowIdx + col;
                          if (idx >= topCategoryEntries.length) {
                            return const SizedBox.shrink();
                          }
                          final entry = topCategoryEntries[idx];
                          final style = ProCategoryStyle.resolve(entry.key);
                          final pctNum = catPct(entry.value);
                          return _MiniCategoryCard(
                            icon: style.icon,
                            accentColor: style.color,
                            highlighted: idx == 0 && entry.value > 0,
                            title: entry.key,
                            amount: VndAmount.formatCompact(entry.value),
                            pct: '($pctNum%)',
                            shareRatio: spentMinor > 0
                                ? (entry.value / spentMinor).clamp(0.0, 1.0)
                                : 0.0,
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _DailySpendingChartCard extends StatefulWidget {
  final List<int> buckets;
  final int totalSpentMinor;
  final VoidCallback onOpenReport;

  const _DailySpendingChartCard({
    required this.buckets,
    required this.totalSpentMinor,
    required this.onOpenReport,
  });

  @override
  State<_DailySpendingChartCard> createState() => _DailySpendingChartCardState();
}

class _DailySpendingChartCardState extends State<_DailySpendingChartCard> {
  static const List<String> _shortAxisLabels = [
    '01',
    '06',
    '11',
    '16',
    '21',
    '26',
    '29+',
  ];
  static const List<String> _rangeTitles = [
    'Ngày 01–05',
    'Ngày 06–10',
    'Ngày 11–15',
    'Ngày 16–20',
    'Ngày 21–25',
    'Ngày 26–28',
    'Cuối tháng (29+)',
  ];

  int? _selectedIdx;

  void _selectFromDx(double dx, double width, {required bool toggle}) {
    if (width <= 0) return;
    final idx = ((dx / width) * 7).floor().clamp(0, 6);
    if (toggle && _selectedIdx == idx) {
      HapticFeedback.selectionClick();
      setState(() => _selectedIdx = null);
      return;
    }
    if (_selectedIdx != idx) {
      HapticFeedback.selectionClick();
      setState(() => _selectedIdx = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final maxBucket = widget.buckets.fold<int>(0, (a, b) => a > b ? a : b);
    final sel = _selectedIdx;
    final selVal = (sel != null && sel < widget.buckets.length)
        ? widget.buckets[sel]
        : 0;
    final selPct = (widget.totalSpentMinor > 0 && selVal > 0)
        ? ((selVal * 100) / widget.totalSpentMinor).clamp(1, 100).round()
        : 0;

    return LifeOsSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onOpenReport,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_rounded, size: 19, color: c.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Chi tiêu theo ngày',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: c.textSecondary,
                    ),
                  ],
                ),
              ),
              LifeOsStatusPill(
                label: 'Tổng chi: ${VndAmount.format(widget.totalSpentMinor)}',
                tone: LifeOsAccentTone.emerald,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (sel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selectedIdx = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_rangeTitles[sel]}: ${VndAmount.format(selVal)}'
                    '${selPct > 0 ? ' ($selPct%)' : ''}',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: c.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(
            height: 114,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 44,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            maxBucket > 0
                                ? VndAmount.formatCompact(maxBucket)
                                : '0 ₫',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: c.textSecondary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        if (maxBucket > 0)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              VndAmount.formatCompact(maxBucket ~/ 2),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: c.textSecondary.withValues(alpha: 0.78),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        Text(
                          '0 ₫',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              key: const Key('daily_spending_chart_canvas'),
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (d) => _selectFromDx(
                                d.localPosition.dx,
                                constraints.maxWidth,
                                toggle: true,
                              ),
                              onHorizontalDragUpdate: (d) => _selectFromDx(
                                d.localPosition.dx,
                                constraints.maxWidth,
                                toggle: false,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox.expand(
                                    child: CustomPaint(
                                      painter: _DailySpendingChartPainter(
                                        buckets: widget.buckets,
                                        selectedIdx: _selectedIdx,
                                        barColor: c.primary,
                                        highlightBg: c.primary.withValues(
                                          alpha: 0.08,
                                        ),
                                        gridColor: c.separator.withValues(
                                          alpha: 0.65,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (widget.totalSpentMinor == 0)
                                    IgnorePointer(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.surface.withValues(
                                            alpha: 0.90,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(color: c.separator),
                                        ),
                                        child: Text(
                                          'Chưa có chi tiêu trong kỳ',
                                          softWrap: true,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: List.generate(7, (i) {
                          final isSelected = _selectedIdx == i;
                          final isPeak = maxBucket > 0 &&
                              widget.buckets[i] == maxBucket;
                          return Expanded(
                            child: InkWell(
                              key: Key('daily_spending_bucket_$i'),
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _selectedIdx = isSelected ? null : i;
                                });
                              },
                              child: Text(
                                _shortAxisLabels[i],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: (isSelected || isPeak)
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? c.primary
                                      : c.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailySpendingChartPainter extends CustomPainter {
  final List<int> buckets;
  final int? selectedIdx;
  final Color barColor;
  final Color highlightBg;
  final Color gridColor;

  const _DailySpendingChartPainter({
    required this.buckets,
    required this.selectedIdx,
    required this.barColor,
    required this.highlightBg,
    required this.gridColor,
  });

  void _drawDashedLine(Canvas canvas, double y, double width, Paint paint) {
    const dashW = 4.0;
    const gapW = 4.0;
    var x = 0.0;
    while (x < width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(width, x + dashW), y),
        paint,
      );
      x += dashW + gapW;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.85;

    _drawDashedLine(canvas, 3.0, size.width, gridPaint);
    _drawDashedLine(canvas, size.height * 0.5, size.width, gridPaint);
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      gridPaint,
    );

    final maxBucket = buckets.fold<int>(0, (a, b) => a > b ? a : b);
    final count = math.min(7, buckets.length);
    if (count == 0) return;

    final slotW = size.width / count;
    final barW = math.min(22.0, math.max(10.0, slotW * 0.54));
    final usableH = math.max(12.0, size.height - 8.0);

    if (selectedIdx != null && selectedIdx! >= 0 && selectedIdx! < count) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            slotW * selectedIdx! + 2,
            0,
            math.max(6.0, slotW - 4),
            size.height,
          ),
          const Radius.circular(8),
        ),
        Paint()..color = highlightBg,
      );
    }

    final barTopPoints = <Offset>[];

    for (var i = 0; i < count; i++) {
      final val = buckets[i];
      final cx = slotW * i + slotW / 2;
      final isPeak = maxBucket > 0 && val == maxBucket;
      final isSelected = selectedIdx == i;
      final dimmed = selectedIdx != null && !isSelected;

      // Strictly proportional height; 0 VND renders a flat 2px baseline tick (never fake bars!).
      final barH = (maxBucket <= 0 || val <= 0)
          ? 2.0
          : math.max(6.0, (val / maxBucket) * usableH);
      final topY = size.height - 1 - barH;
      barTopPoints.add(Offset(cx, topY));

      final rect = Rect.fromLTWH(cx - barW / 2, topY, barW, barH);
      final paint = Paint();
      if (val > 0 && maxBucket > 0) {
        final baseAlpha = dimmed ? 0.32 : (isSelected || isPeak ? 1.0 : 0.68);
        paint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            barColor.withValues(alpha: baseAlpha),
            barColor.withValues(alpha: baseAlpha * 0.58),
          ],
        ).createShader(rect);
      } else {
        paint.color = gridColor;
      }

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        paint,
      );
    }

    // Subtle smooth trend spline connecting bucket tops when real spending exists
    if (maxBucket > 0 && barTopPoints.length >= 2) {
      final spline = Path()..moveTo(barTopPoints.first.dx, barTopPoints.first.dy);
      for (var i = 0; i < barTopPoints.length - 1; i++) {
        final p0 = barTopPoints[i];
        final p1 = barTopPoints[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        spline.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
      }
      canvas.drawPath(
        spline,
        Paint()
          ..color = barColor.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );

      for (var i = 0; i < count; i++) {
        if (buckets[i] <= 0) continue;
        final isFocus = selectedIdx == i || (selectedIdx == null && buckets[i] == maxBucket);
        if (isFocus) {
          canvas.drawCircle(
            barTopPoints[i],
            3.6,
            Paint()..color = Colors.white,
          );
          canvas.drawCircle(
            barTopPoints[i],
            2.6,
            Paint()..color = barColor,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DailySpendingChartPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.selectedIdx != selectedIdx ||
        oldDelegate.barColor != barColor;
  }
}

class _MiniCategoryCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String amount;
  final String pct;
  final double shareRatio;
  final bool highlighted;

  const _MiniCategoryCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.amount,
    required this.pct,
    this.shareRatio = 0.0,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted ? c.primarySubtle : c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? c.primary.withValues(alpha: 0.35) : c.separator,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16.5, color: accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 12.4,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        amount,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    pct,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: highlighted ? c.primary : c.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 4.5,
                  value: shareRatio.clamp(0.0, 1.0),
                  backgroundColor: c.surfaceRaised,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinanceToolsHubTabView extends StatelessWidget {
  const _FinanceToolsHubTabView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          key: const Key('finance_tools_hub_list_view'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.dockClearance,
          ),
          children: [
            const LifeOsSectionHeader(
              title: 'Kết nối Ngân hàng & Báo cáo',
              subtitle: 'Đồng bộ biến động tự động, mã QR thu tiền và sao kê',
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_bank_qr_tile'),
                      icon: Icons.qr_code_2_rounded,
                      tone: LifeOsAccentTone.emerald,
                      title: 'Ngân hàng & QR',
                      subtitle: 'Biến động tự động',
                      onTap: () => context.push('/notifications-privacy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_report_tile'),
                      icon: Icons.bar_chart_rounded,
                      tone: LifeOsAccentTone.blue,
                      title: 'Báo cáo thu chi',
                      subtitle: 'Thống kê theo tuần',
                      onTap: () => context.push('/finance-report'),
                    ),
                  ),
                ],
              ),
            ),
            const LifeOsSectionHeader(
              title: 'Thu nhập, Lãi vay & Chi định kỳ',
              subtitle: 'Tính lương Gross–Net, trả góp, hóa đơn & thuê bao tháng',
              tone: LifeOsAccentTone.purple,
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_salary_tax_tile'),
                      icon: Icons.request_quote_outlined,
                      tone: LifeOsAccentTone.purple,
                      title: 'Lương & Thuế',
                      subtitle: 'Gross–Net 2026',
                      onTap: () => context.push('/smart-notes-hub'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_wealth_tools_tile'),
                      icon: Icons.calculate_outlined,
                      tone: LifeOsAccentTone.blue,
                      title: 'Lãi vay & Bill',
                      subtitle: 'Trả góp & tích lũy',
                      onTap: () => context.push('/wealth-tools'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_subs_tile'),
                      icon: Icons.radar_rounded,
                      tone: LifeOsAccentTone.amber,
                      title: 'Gói thuê bao',
                      subtitle: 'Gia hạn & bảo hành',
                      onTap: () => context.push('/subscriptions-warranty'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LifeOsFeatureBentoTile(
                      tileKey: const Key('finance_hub_auto_tx_tile'),
                      icon: Icons.bolt_rounded,
                      tone: LifeOsAccentTone.emerald,
                      title: 'Duyệt GD tự động',
                      subtitle: 'Đối soát biến động',
                      onTap: () => context.push('/auto-tx-review'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
