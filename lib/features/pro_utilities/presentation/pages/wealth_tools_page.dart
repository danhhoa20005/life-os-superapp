import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/navigation/feature_registry.dart';
import '../../../../core/utils/smart_money_split_ai_engine.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../budgets/domain/usecases/budget_usecases.dart';
import '../../../budgets/presentation/bloc/budget_bloc.dart';
import '../../../calendar/domain/entities/calendar_entities.dart';
import '../../../calendar/domain/repositories/calendar_repository.dart';
import '../../../calendar/presentation/bloc/calendar_bloc.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../family/domain/entities/family_entities.dart';
import '../../../family/domain/usecases/family_usecases.dart';
import '../../../family/presentation/bloc/family_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../../transactions/presentation/bloc/transaction_event.dart';
import '../../../transactions/presentation/bloc/transaction_state.dart';
import '../../domain/entities/pro_utilities_entities.dart';

/// Financial Pro Tools: Smart Receipt AI Scanner, Loan Amortization & FIRE 6-Jars.
class WealthToolsPage extends StatefulWidget {
  final String? initialTab;

  const WealthToolsPage({super.key, this.initialTab});

  @override
  State<WealthToolsPage> createState() => _WealthToolsPageState();
}

class _WealthToolsPageState extends State<WealthToolsPage> {
  late String _activeTool; // 'receipt' | 'loan' | 'fire'

  @override
  void initState() {
    super.initState();
    _activeTool = FeatureRegistry.normalizeWealthToolTab(widget.initialTab);
    SmartMoneySplitAiEngine.ensureModelLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant WealthToolsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _activeTool = FeatureRegistry.normalizeWealthToolTab(widget.initialTab);
    }
  }

  // 1. Receipt Scanner State (preserves default Co.opmart 280.000 ₫ sample for tests)
  final TextEditingController _receiptCtrl = TextEditingController(
    text:
        'Siêu thị Co.opmart Quận 7\n'
        'Thịt bò Úc 300g 145.000\n'
        'Sữa tươi TH True Milk 42.000\n'
        'Rau củ hữu cơ Đà Lạt 58.000\n'
        'Nước rửa chén Sunlight 35.000\n'
        'Tổng thanh toán: 280.000đ',
  );
  String? _selectedWalletId;
  String? _manualSelectedCategory;
  bool _isCommittingReceipt = false;

  // 2. Loan Calculator State
  final TextEditingController _loanPrincipalCtrl = TextEditingController(
    text: '1200000000',
  );
  double _loanRatePct = 8.5;
  int _loanTermMonths = 180; // 15 years
  bool _decliningBalance = true;
  bool _isSchedulingLoan = false;

  // 3. FIRE Simulator & Smart AI Allocation State
  double _expectedReturnPct = 10.0;
  bool _isApplyingBudgets = false;
  final TextEditingController _aiAllocPromptCtrl = TextEditingController(
    text: 'Lương 25 triệu thuê nhà 5 triệu muốn tiết kiệm mua xe & đầu tư FIRE',
  );
  AllocationStrategyKind? _forcedAiStrategy;

  @override
  void dispose() {
    _receiptCtrl.dispose();
    _loanPrincipalCtrl.dispose();
    _aiAllocPromptCtrl.dispose();
    super.dispose();
  }

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
  }

  T? _maybeWatch<T>(BuildContext context) {
    try {
      return context.watch<T>();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = TammySemanticColors.of(context);
    final txListState = _maybeWatch<TransactionListBloc>(context)?.state;
    final wallets = txListState?.wallets ?? const <WalletEntity>[];
    final categories = txListState?.categories ?? const <CategoryEntity>[];
    final dash = _maybeWatch<DashboardBloc>(context)?.state.data;
    final rawMonthlyIncome = dash?.monthlyIncomeMinor ?? 0;
    final rawMonthlyExpense = dash?.monthlyExpenseMinor ?? 0;
    final netWorthMinor = dash?.netWorthMinor ?? 0;

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              const LifeOsTopBrandHeader(
                title: 'Công cụ Tài chính Pro',
                showBackButton: true,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.maxContentWidth,
                  ),
                  child: LifeOsSegmentedPills<String>(
                    selected: _activeTool,
                    options: const [
                      ('receipt', 'Quét Bill AI', null),
                      ('loan', 'Lãi Vay', null),
                      ('fire', 'FIRE & 6 Lọ', null),
                    ],
                    onChanged: (v) => setState(() => _activeTool = v),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        2,
                        AppSpacing.md,
                        AppSpacing.xxl,
                      ),
                      children: [
                        if (_activeTool == 'receipt')
                          _buildReceiptScannerView(
                            context,
                            c,
                            userId: user.id,
                            userName: user.fullName,
                            wallets: wallets,
                            categories: categories,
                          ),
                        if (_activeTool == 'loan')
                          _buildLoanCalculatorView(
                            context,
                            c,
                            userId: user.id,
                            userName: user.fullName,
                          ),
                        if (_activeTool == 'fire')
                          _buildFireAndSixJarsView(
                            context,
                            c,
                            userId: user.id,
                            netWorthMinor: netWorthMinor,
                            rawMonthlyIncomeMinor: rawMonthlyIncome,
                            monthlyIncomeMinor: rawMonthlyIncome > 0
                                ? rawMonthlyIncome
                                : 25000000,
                            monthlyExpenseMinor: rawMonthlyExpense > 0
                                ? rawMonthlyExpense
                                : 12000000,
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
  }

  List<CategoryEntity> _resolveDebitCategories(
    String userId,
    List<CategoryEntity> categories,
    String suggestedCategory,
  ) {
    final defaults = <CategoryEntity>[
      CategoryEntity(
        id: 'cat_food',
        ownerId: userId,
        name: 'Ăn uống',
        direction: 'debit',
        iconKey: 'restaurant',
      ),
      CategoryEntity(
        id: 'cat_housework',
        ownerId: userId,
        name: 'Việc nhà & Gia dụng',
        direction: 'debit',
        iconKey: 'cleaning_services',
      ),
      CategoryEntity(
        id: 'cat_utilities',
        ownerId: userId,
        name: 'Điện/Nước/Internet',
        direction: 'debit',
        iconKey: 'bolt',
      ),
      CategoryEntity(
        id: 'cat_shopping',
        ownerId: userId,
        name: 'Chợ & Mua sắm',
        direction: 'debit',
        iconKey: 'shopping_bag',
      ),
      CategoryEntity(
        id: 'cat_vehicle',
        ownerId: userId,
        name: 'Xe cộ & Di chuyển',
        direction: 'debit',
        iconKey: 'two_wheeler',
      ),
      CategoryEntity(
        id: 'cat_health',
        ownerId: userId,
        name: 'Sức khỏe & Giáo dục',
        direction: 'debit',
        iconKey: 'favorite',
      ),
      CategoryEntity(
        id: 'cat_entertainment',
        ownerId: userId,
        name: 'Giải trí & Đăng ký',
        direction: 'debit',
        iconKey: 'subscriptions',
      ),
      CategoryEntity(
        id: 'cat_other_exp',
        ownerId: userId,
        name: 'Chi tiêu khác',
        direction: 'debit',
        iconKey: 'category',
      ),
    ];

    final debitList = categories.where((c) => c.direction == 'debit').toList();
    final mapByName = <String, CategoryEntity>{
      for (final d in defaults) d.name: d,
      for (final c in debitList) c.name: c,
    };
    if (suggestedCategory.trim().isNotEmpty &&
        !mapByName.containsKey(suggestedCategory)) {
      mapByName[suggestedCategory] = CategoryEntity(
        id: 'cat_suggested',
        ownerId: userId,
        name: suggestedCategory,
        direction: 'debit',
        iconKey: 'category',
      );
    }
    return mapByName.values.toList();
  }

  Widget _buildReceiptScannerView(
    BuildContext context,
    TammySemanticColors c, {
    required String userId,
    required String userName,
    required List<WalletEntity> wallets,
    required List<CategoryEntity> categories,
  }) {
    final parsed = SmartReceiptParserEngine.parse(_receiptCtrl.text);
    final debitCats = _resolveDebitCategories(
      userId,
      categories,
      parsed.suggestedCategory,
    );
    final activeWalletId = wallets.any((w) => w.id == _selectedWalletId)
        ? _selectedWalletId
        : (wallets.isNotEmpty ? wallets.first.id : null);
    final activeCategoryName =
        (_manualSelectedCategory != null &&
            debitCats.any((cat) => cat.name == _manualSelectedCategory))
        ? _manualSelectedCategory!
        : (debitCats.any((cat) => cat.name == parsed.suggestedCategory)
              ? parsed.suggestedCategory
              : debitCats.first.name);
    final matchedCat = debitCats
        .where((cat) => cat.name == activeCategoryName)
        .firstOrNull;
    final txActionBloc = _maybeRead<TransactionActionBloc>(context);
    final txActionState = _maybeWatch<TransactionActionBloc>(context)?.state;
    final isSubmittingTx =
        _isCommittingReceipt ||
        txActionState?.status == ActionStatus.submitting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LifeOsMintHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BananaGlassIcon(
                    assetPath: AppAssets.icToolReceiptAi,
                    fallbackIcon: Icons.document_scanner_outlined,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bóc tách Hóa đơn & Bill Siêu thị / GrabFood',
                      softWrap: true,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    key: const Key('receipt_paste_clipboard_chip'),
                    avatar: Icon(
                      Icons.content_paste_rounded,
                      size: 16,
                      color: c.primary,
                    ),
                    label: const Text('Dán hóa đơn từ bộ nhớ tạm'),
                    onPressed: () async {
                      final clip = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      final raw = clip?.text?.trim() ?? '';
                      if (!context.mounted) return;
                      if (raw.isEmpty) {
                        LifeOsTopToast.show(
                          context,
                          'Bộ nhớ tạm hiện đang trống.',
                          kind: LifeOsToastKind.warning,
                        );
                        return;
                      }
                      setState(() {
                        _receiptCtrl.text = raw;
                        _manualSelectedCategory = null;
                      });
                      LifeOsTopToast.show(
                        context,
                        'Đã dán nội dung hóa đơn để phân tích.',
                        kind: LifeOsToastKind.info,
                      );
                    },
                  ),
                  ActionChip(
                    key: const Key('receipt_clear_text_chip'),
                    avatar: Icon(
                      Icons.clear_rounded,
                      size: 16,
                      color: c.textSecondary,
                    ),
                    label: const Text('Xóa nội dung'),
                    onPressed: () => setState(() {
                      _receiptCtrl.clear();
                      _manualSelectedCategory = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('receipt_raw_text_input'),
                controller: _receiptCtrl,
                maxLines: 5,
                onChanged: (_) => setState(() {
                  _manualSelectedCategory = null;
                }),
                decoration: const InputDecoration(
                  hintMaxLines: 3,
                  hintText: 'Dán nội dung hóa đơn',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Parsed Line Items Card
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    parsed.merchant,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      VndAmount.format(parsed.totalMinor),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: c.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LifeOsStatusPill(
                icon: Icons.auto_awesome_rounded,
                label:
                    '$activeCategoryName · ${parsed.items.length} món bóc tách',
                tone: LifeOsAccentTone.emerald,
              ),
              if (parsed.items.isNotEmpty) ...[
                const Divider(height: 22),
                ...parsed.items.map(
                  (it) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '• ${it.name}',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          VndAmount.format(it.amountMinor),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Wallet & Category Selector Card
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wallets.isEmpty) ...[
                const SemanticStatusBadge(
                  kind: SemanticStatusKind.warning,
                  label: 'Chưa có ví thanh toán để ghi giao dịch',
                ),
                const SizedBox(height: 6),
                Text(
                  'Hãy tạo ví tiền mặt hoặc tài khoản ngân hàng ở tab Tài chính trước khi ghi hóa đơn vào Sổ cái.',
                  softWrap: true,
                  style: TextStyle(fontSize: 12.2, color: c.textSecondary),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  key: const Key('receipt_wallet_dropdown'),
                  isExpanded: true,
                  initialValue: activeWalletId,
                  decoration: const InputDecoration(
                    labelText: 'Ví thanh toán',
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
                  onChanged: isSubmittingTx
                      ? null
                      : (v) => setState(() => _selectedWalletId = v),
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                key: const Key('receipt_category_dropdown'),
                isExpanded: true,
                initialValue: activeCategoryName,
                decoration: const InputDecoration(
                  labelText: 'Danh mục chi tiêu',
                  isDense: true,
                ),
                items: debitCats
                    .map(
                      (cat) => DropdownMenuItem(
                        value: cat.name,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(cat.name),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: isSubmittingTx
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() => _manualSelectedCategory = v);
                        }
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('receipt_split_group_button'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: parsed.totalMinor <= 0
                      ? () {
                          LifeOsTopToast.show(
                            context,
                            'Hóa đơn chưa có tổng tiền hợp lệ để chia nhóm.',
                            kind: LifeOsToastKind.warning,
                          );
                        }
                      : () => _showSplitReceiptToFamilySheet(
                          context,
                          userId: userId,
                          userName: userName,
                          parsed: parsed,
                        ),
                  icon: const Icon(Icons.call_split_rounded, size: 17),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Chia nhóm'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('commit_scanned_receipt_button'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed:
                      (isSubmittingTx ||
                          activeWalletId == null ||
                          parsed.totalMinor <= 0 ||
                          txActionBloc == null)
                      ? null
                      : () async {
                          setState(() => _isCommittingReceipt = true);
                          final res = await txActionBloc.submitAndAwaitCreate(
                            TransactionCreateSubmitted(
                              operationId: const Uuid().v4(),
                              userId: userId,
                              walletId: activeWalletId,
                              categoryId: matchedCat?.id,
                              categoryName: activeCategoryName,
                              kind: TransactionKind.expense,
                              amountMinor: parsed.totalMinor,
                              merchant: parsed.merchant,
                              note: 'Quét Bill AI (${parsed.items.length} món)',
                              occurredAt: DateTime.now(),
                            ),
                          );
                          if (!context.mounted) return;
                          setState(() => _isCommittingReceipt = false);
                          if (res.status == ActionStatus.success &&
                              res.lastCreatedTransaction != null) {
                            final createdTx = res.lastCreatedTransaction!;
                            LifeOsTopToast.show(
                              context,
                              'Đã ghi hóa đơn "${parsed.merchant}" (${VndAmount.format(parsed.totalMinor)}) vào Sổ cái.',
                              kind: LifeOsToastKind.success,
                              actionLabel: 'Hoàn tác',
                              onAction: () {
                                txActionBloc.add(
                                  TransactionReverseRequested(
                                    userId: userId,
                                    transactionId: createdTx.id,
                                    reason: 'Hoàn tác hóa đơn Quét Bill AI',
                                  ),
                                );
                              },
                            );
                          } else {
                            LifeOsTopToast.show(
                              context,
                              res.failure?.message ??
                                  'Không thể ghi hóa đơn vào Ví. Vui lòng thử lại.',
                              kind: LifeOsToastKind.error,
                            );
                          }
                        },
                  icon: isSubmittingTx
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Ghi vào Ví'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  SharedExpenseTopic _inferTopicFromCategory(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('ăn') || lower.contains('uống')) {
      return SharedExpenseTopic.dining;
    }
    if (lower.contains('điện') ||
        lower.contains('nước') ||
        lower.contains('internet')) {
      return SharedExpenseTopic.utilities;
    }
    if (lower.contains('nhà cửa') || lower.contains('thuê')) {
      return SharedExpenseTopic.housing;
    }
    if (lower.contains('việc nhà') || lower.contains('gia dụng')) {
      return SharedExpenseTopic.housework;
    }
    if (lower.contains('chợ') || lower.contains('mua sắm')) {
      return SharedExpenseTopic.shopping;
    }
    return SharedExpenseTopic.other;
  }

  Future<void> _showSplitReceiptToFamilySheet(
    BuildContext context, {
    required String userId,
    required String userName,
    required ParsedReceiptResult parsed,
  }) async {
    final famBloc = _maybeRead<FamilyBloc>(context);
    if (famBloc == null) {
      LifeOsTopToast.show(
        context,
        'Không tìm thấy thông tin Nhóm gia đình hiện tại.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    final activeFamily = famBloc.state.activeFamily;
    if (activeFamily == null) {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          final c = TammySemanticColors.of(sheetCtx);
          return LiquidGlassSheetFrame(
            showHandle: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Chưa có Nhóm để chia hóa đơn',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hãy tạo hoặc tham gia nhóm ở tab Gia đình trước để chia đều hóa đơn "${parsed.merchant}" (${VndAmount.format(parsed.totalMinor)}).',
                    softWrap: true,
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                          child: const Text('Đóng'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            context.go('/family');
                          },
                          icon: const Icon(Icons.groups_outlined, size: 18),
                          label: const Text('Tạo / Vào nhóm'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    final topic = _inferTopicFromCategory(parsed.suggestedCategory);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SplitReceiptToFamilySheet(
        parentContext: context,
        famBloc: famBloc,
        activeFamily: activeFamily,
        userId: userId,
        userName: userName,
        parsed: parsed,
        topic: topic,
      ),
    );
  }

  Widget _buildLoanCalculatorView(
    BuildContext context,
    TammySemanticColors c, {
    required String userId,
    required String userName,
  }) {
    final principal = VndAmount.tryParseInput(_loanPrincipalCtrl.text) ?? 0;
    final preview = LoanAmortizationEngine.calculate(
      principalMinor: principal,
      annualRatePct: _loanRatePct,
      termMonths: _loanTermMonths,
      decliningBalance: _decliningBalance,
    );
    final calBloc = _maybeRead<CalendarBloc>(context);
    final famId = _maybeRead<FamilyBloc>(context)?.state.activeFamily?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Máy tính Vay Mua Nhà / Mua Xe Ngân hàng',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              LifeOsSegmentedPills<bool>(
                selected: _decliningBalance,
                options: const [
                  (true, 'Dư nợ giảm dần', null),
                  (false, 'Trả đều hằng tháng', null),
                ],
                onChanged: (v) => setState(() => _decliningBalance = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _loanPrincipalCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Số tiền gốc vay (VND)',
                  suffixText: 'VND',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Lãi suất năm: ${_loanRatePct.toStringAsFixed(1)}% / năm',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Slider(
                value: _loanRatePct,
                min: 4.0,
                max: 16.0,
                divisions: 24,
                activeColor: c.primary,
                onChanged: (v) => setState(() => _loanRatePct = v),
              ),
              Text(
                'Kỳ hạn vay: $_loanTermMonths tháng (${(_loanTermMonths / 12).toStringAsFixed(0)} năm)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Slider(
                value: _loanTermMonths.toDouble(),
                min: 12,
                max: 300,
                divisions: 24,
                activeColor: c.primary,
                onChanged: (v) => setState(() => _loanTermMonths = v.round()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LifeOsMintHeroCard(
          child: Column(
            children: [
              _ResultMetricRow(
                label: 'Gốc + Lãi tháng đầu tiên',
                value: VndAmount.format(preview.firstMonthPaymentMinor),
                highlightColor: c.primary,
              ),
              const Divider(height: 20),
              _ResultMetricRow(
                label: 'Gốc + Lãi tháng cuối cùng',
                value: VndAmount.format(preview.lastMonthPaymentMinor),
              ),
              const Divider(height: 20),
              _ResultMetricRow(
                label: 'Tổng tiền lãi phải trả',
                value: VndAmount.format(preview.totalInterestMinor),
                highlightColor: c.error,
              ),
              const Divider(height: 20),
              _ResultMetricRow(
                label: 'Tổng gốc + lãi toàn kỳ',
                value: VndAmount.format(preview.totalPayableMinor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          key: const Key('schedule_loan_repayment_btn'),
          onPressed:
              (_isSchedulingLoan ||
                  principal <= 0 ||
                  preview.firstMonthPaymentMinor <= 0 ||
                  calBloc == null)
              ? null
              : () => _showScheduleLoanReminderDialog(
                  context,
                  calBloc: calBloc,
                  userId: userId,
                  userName: userName,
                  familyId: famId,
                  principal: principal,
                  preview: preview,
                ),
          icon: _isSchedulingLoan
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.event_repeat_rounded, size: 18),
          label: const Text('Tạo lịch nhắc trả góp hàng tháng'),
        ),
      ],
    );
  }

  Future<void> _showScheduleLoanReminderDialog(
    BuildContext context, {
    required CalendarBloc calBloc,
    required String userId,
    required String userName,
    required String? familyId,
    required int principal,
    required LoanSchedulePreview preview,
  }) async {
    final now = DateTime.now();
    final initialDue = SubscriptionWarrantyEntity.addMonthsSafely(
      DateTime(now.year, now.month, now.day, 9, 0),
      1,
    );
    final dateFmt = DateFormat('dd/MM/yyyy');

    final picked = await showDialog<(String, DateTime)>(
      context: context,
      builder: (_) => _ScheduleLoanReminderDialog(
        initialTitle:
            'Trả góp khoản vay (${VndAmount.format(preview.firstMonthPaymentMinor)})',
        initialDueDate: initialDue,
        minDate: now,
        loanTermMonths: _loanTermMonths,
      ),
    );
    if (picked == null || !context.mounted) return;
    final (title, firstDueDate) = picked;
    setState(() => _isSchedulingLoan = true);
    final waiter = calBloc.stream
        .firstWhere(
          (s) =>
              s.failure != null ||
              (s.message != null &&
                  (s.message!.contains('sự kiện') ||
                      s.message!.contains('lịch'))),
        )
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => calBloc.state,
        );
    calBloc.add(
      CalendarEventCreated(
        CreateCalendarEventParams(
          userId: userId,
          userName: userName,
          familyId: familyId,
          visibility: CalendarEventVisibility.privateEvent,
          title: title,
          description:
              'Gốc vay: ${VndAmount.format(principal)} · Lãi suất ${_loanRatePct.toStringAsFixed(1)}%/năm · $_loanTermMonths tháng (${_decliningBalance ? "Dư nợ giảm dần" : "Trả đều hằng tháng"}).',
          startsAt: firstDueDate,
          endsAt: firstDueDate.add(const Duration(minutes: 30)),
          reminderMinutesBefore: 60,
          recurrence: CalendarRecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            count: _loanTermMonths,
          ),
        ),
      ),
    );
    final resState = await waiter;
    if (!context.mounted) return;
    setState(() => _isSchedulingLoan = false);
    if (resState.failure != null) {
      LifeOsTopToast.show(
        context,
        resState.failure!.message,
        kind: LifeOsToastKind.error,
      );
    } else {
      LifeOsTopToast.show(
        context,
        'Đã tạo lịch nhắc trả góp hằng tháng từ ${dateFmt.format(firstDueDate)}.',
        kind: LifeOsToastKind.success,
      );
    }
  }

  Widget _buildFireAndSixJarsView(
    BuildContext context,
    TammySemanticColors c, {
    required String userId,
    required int netWorthMinor,
    required int rawMonthlyIncomeMinor,
    required int monthlyIncomeMinor,
    required int monthlyExpenseMinor,
  }) {
    final isSimulatedSample = rawMonthlyIncomeMinor == 0;
    final sim = FireWealthSimulatorEngine.simulate(
      currentNetWorthMinor: netWorthMinor,
      monthlyIncomeMinor: monthlyIncomeMinor,
      monthlyExpenseMinor: monthlyExpenseMinor,
      expectedAnnualReturnPct: _expectedReturnPct,
    );
    final budgetBloc = _maybeRead<BudgetBloc>(context);
    final budgetState = _maybeWatch<BudgetBloc>(context)?.state;
    final isSavingBudget =
        _isApplyingBudgets || (budgetState?.isSaving ?? false);
    final aiPlan = SmartMoneySplitAiEngine.recommendIncomeAllocation(
      prompt: _aiAllocPromptCtrl.text,
      explicitIncomeMinor: rawMonthlyIncomeMinor > 0
          ? rawMonthlyIncomeMinor
          : null,
      forcedStrategy: _forcedAiStrategy,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LifeOsSoftCard(
          key: const Key('ai_smart_income_allocation_card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const BananaGlassIcon(
                    assetPath: AppAssets.ic3dAiSpark,
                    fallbackIcon: Icons.auto_awesome_rounded,
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Phân chia & Phân bổ Thu nhập Tối ưu',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          'FastText INT8 Offline · Chia chính xác từng đồng VND',
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
              const SizedBox(height: 10),
              TextField(
                key: const Key('ai_alloc_prompt_input'),
                controller: _aiAllocPromptCtrl,
                maxLines: 2,
                onChanged: (_) => setState(() => _forcedAiStrategy = null),
                decoration: const InputDecoration(
                  labelText: 'Mục tiêu & ràng buộc thu nhập của bạn',
                  hintText:
                      'VD: Lương 25tr thuê nhà 5tr trả góp 3tr muốn tiết kiệm...',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: AllocationStrategyKind.values.map((st) {
                  final selected = aiPlan.strategy == st;
                  return ChoiceChip(
                    key: Key('ai_alloc_strategy_${st.name}'),
                    label: Text(
                      st.displayNameVi.split('(').first.trim(),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      setState(() => _forcedAiStrategy = st);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              LifeOsStatusPill(
                icon: Icons.verified_rounded,
                label:
                    '${aiPlan.strategy.displayNameVi} · Tin cậy ${(aiPlan.modelConfidence * 100).toStringAsFixed(0)}%',
                tone: LifeOsAccentTone.emerald,
              ),
              const SizedBox(height: 6),
              Text(
                aiPlan.rationaleVi,
                softWrap: true,
                style: TextStyle(fontSize: 12.4, color: c.textSecondary),
              ),
              const Divider(height: 18),
              ...aiPlan.buckets.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ResultMetricRow(
                    label: b.titleVi,
                    value: VndAmount.format(b.amountMinor),
                    highlightColor: b.isSavingsOrInvestment
                        ? c.primary
                        : c.textPrimary,
                  ),
                ),
              ),
              const Divider(height: 16),
              _ResultMetricRow(
                label: 'Chi tiêu linh hoạt an toàn / ngày',
                value: VndAmount.format(aiPlan.safeDailySpendMinor),
                highlightColor: c.primary,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                key: const Key('apply_ai_allocation_budget_btn'),
                onPressed: (isSavingBudget || budgetBloc == null)
                    ? null
                    : () => _applyAiPlanToMonthlyBudget(
                        context,
                        budgetBloc: budgetBloc,
                        userId: userId,
                        plan: aiPlan,
                      ),
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('Áp dụng Phân bổ AI vào Ngân sách'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LifeOsMintHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up_rounded, size: 20, color: c.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mốc Tự do Tài chính FIRE (Quy tắc 4%)',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (isSimulatedSample) ...[
                const SizedBox(height: 8),
                const LifeOsStatusPill(
                  key: Key('fire_simulated_income_pill'),
                  icon: Icons.info_outline_rounded,
                  label: 'Đang mô phỏng thu nhập mẫu',
                  tone: LifeOsAccentTone.amber,
                ),
              ],
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  VndAmount.format(sim.fireNumberMinor),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: c.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Thời gian ước tính đạt tự do tài chính: ${sim.yearsToFire.toStringAsFixed(1)} năm · Dự phóng 10 năm tới: ${VndAmount.formatCompact(sim.projected10YearNetWorthMinor)}',
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.5,
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tỷ suất sinh lời kỳ vọng: ${_expectedReturnPct.toStringAsFixed(1)}% / năm',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Slider(
                value: _expectedReturnPct,
                min: 5.0,
                max: 18.0,
                divisions: 26,
                activeColor: c.primary,
                onChanged: (v) => setState(() => _expectedReturnPct = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Phân bổ Thu nhập 6 Chiếc Lọ Chuẩn Quốc tế (${VndAmount.format(monthlyIncomeMinor)}/tháng)',
                softWrap: true,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 12),
              ...sim.sixJarsMonthlyAllocation.entries.map(
                (jar) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ResultMetricRow(
                    label: jar.key,
                    value: VndAmount.format(jar.value),
                    highlightColor: c.primary,
                  ),
                ),
              ),
              const Divider(height: 18),
              FilledButton.icon(
                key: const Key('apply_six_jars_budget_btn'),
                onPressed: (isSavingBudget || budgetBloc == null)
                    ? null
                    : () => _applySixJarsToMonthlyBudget(
                        context,
                        budgetBloc: budgetBloc,
                        userId: userId,
                        monthlyIncomeMinor: monthlyIncomeMinor,
                      ),
                icon: isSavingBudget
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('Áp dụng 6 Lọ vào Ngân sách tháng'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _applySixJarsToMonthlyBudget(
    BuildContext context, {
    required BudgetBloc budgetBloc,
    required String userId,
    required int monthlyIncomeMinor,
  }) async {
    final monthKey = TransactionListBloc.currentMonthKey();
    final allocations = <({String id, String name, int limitMinor})>[
      (
        id: 'cat_food',
        name: 'Ăn uống',
        limitMinor: (monthlyIncomeMinor * 30) ~/ 100,
      ),
      (
        id: 'cat_housing',
        name: 'Nhà cửa & Thuê nhà',
        limitMinor: (monthlyIncomeMinor * 15) ~/ 100,
      ),
      (
        id: 'cat_utilities',
        name: 'Điện/Nước/Internet',
        limitMinor: (monthlyIncomeMinor * 10) ~/ 100,
      ),
      (
        id: 'cat_health',
        name: 'Sức khỏe & Giáo dục',
        limitMinor: (monthlyIncomeMinor * 10) ~/ 100,
      ),
      (
        id: 'cat_entertainment',
        name: 'Giải trí & Đăng ký',
        limitMinor: (monthlyIncomeMinor * 10) ~/ 100,
      ),
      (
        id: 'cat_family_social',
        name: 'Hiếu hỉ & Đối ngoại',
        limitMinor: (monthlyIncomeMinor * 5) ~/ 100,
      ),
    ];

    setState(() => _isApplyingBudgets = true);
    Failure? firstFailure;
    for (final item in allocations) {
      if (item.limitMinor <= 0) continue;
      final waiter = budgetBloc.stream
          .firstWhere(
            (s) => !s.isSaving && (s.failure != null || s.actionMessage != null),
          )
          .timeout(const Duration(seconds: 6), onTimeout: () => budgetBloc.state);
      budgetBloc.add(
        BudgetUpsertSubmitted(
          UpsertBudgetParams(
            userId: userId,
            categoryId: item.id,
            categoryName: item.name,
            monthKey: monthKey,
            limitMinor: item.limitMinor,
          ),
        ),
      );
      final done = await waiter;
      if (done.failure != null) {
        firstFailure = done.failure;
        break;
      }
    }

    if (!context.mounted) return;
    setState(() => _isApplyingBudgets = false);
    if (firstFailure != null) {
      LifeOsTopToast.show(
        context,
        firstFailure.message,
        kind: LifeOsToastKind.error,
      );
    } else {
      LifeOsTopToast.show(
        context,
        'Đã áp dụng phân bổ 6 Lọ (80% chi tiêu & 20% tích lũy) vào Ngân sách tháng $monthKey.',
        kind: LifeOsToastKind.success,
      );
    }
  }

  Future<void> _applyAiPlanToMonthlyBudget(
    BuildContext context, {
    required BudgetBloc budgetBloc,
    required String userId,
    required SmartIncomeAllocationPlan plan,
  }) async {
    final monthKey = TransactionListBloc.currentMonthKey();
    setState(() => _isApplyingBudgets = true);
    Failure? firstFailure;
    for (final draft in plan.budgetDrafts) {
      if (draft.limitMinor <= 0) continue;
      final waiter = budgetBloc.stream
          .firstWhere(
            (s) =>
                !s.isSaving && (s.failure != null || s.actionMessage != null),
          )
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () => budgetBloc.state,
          );
      budgetBloc.add(
        BudgetUpsertSubmitted(
          UpsertBudgetParams(
            userId: userId,
            categoryId: draft.categoryId,
            categoryName: draft.categoryName,
            monthKey: monthKey,
            limitMinor: draft.limitMinor,
          ),
        ),
      );
      final done = await waiter;
      if (done.failure != null) {
        firstFailure = done.failure;
        break;
      }
    }
    if (!context.mounted) return;
    setState(() => _isApplyingBudgets = false);
    if (firstFailure != null) {
      LifeOsTopToast.show(
        context,
        firstFailure.message,
        kind: LifeOsToastKind.error,
      );
    } else {
      LifeOsTopToast.show(
        context,
        'Đã áp dụng chiến lược "${plan.strategy.displayNameVi}" vào Ngân sách tháng $monthKey.',
        kind: LifeOsToastKind.success,
      );
    }
  }
}

class _ResultMetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? highlightColor;

  const _ResultMetricRow({
    required this.label,
    required this.value,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            softWrap: true,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: highlightColor ?? c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _SplitReceiptToFamilySheet extends StatefulWidget {
  const _SplitReceiptToFamilySheet({
    required this.parentContext,
    required this.famBloc,
    required this.activeFamily,
    required this.userId,
    required this.userName,
    required this.parsed,
    required this.topic,
  });

  final BuildContext parentContext;
  final FamilyBloc famBloc;
  final FamilyEntity activeFamily;
  final String userId;
  final String userName;
  final ParsedReceiptResult parsed;
  final SharedExpenseTopic topic;

  @override
  State<_SplitReceiptToFamilySheet> createState() =>
      _SplitReceiptToFamilySheetState();
}

class _SplitReceiptToFamilySheetState
    extends State<_SplitReceiptToFamilySheet> {
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.parsed.merchant,
  );
  late final Set<String> _selectedIds = <String>{
    for (final m in widget.activeFamily.members) m.userId,
  };
  bool _isSubmittingLocal = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FamilyBloc>.value(
      value: widget.famBloc,
      child: BlocBuilder<FamilyBloc, FamilyState>(
        buildWhen: (p, n) => p.isSubmitting != n.isSubmitting,
        builder: (ctx, famState) {
          final c = TammySemanticColors.of(ctx);
          final viewInsets = MediaQuery.viewInsetsOf(ctx);
          final isBusy = famState.isSubmitting || _isSubmittingLocal;
          final perPerson = _selectedIds.isEmpty
              ? 0
              : widget.parsed.totalMinor ~/ _selectedIds.length;

          return LiquidGlassSheetFrame(
            showHandle: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                6,
                18,
                20 + viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const BananaGlassIcon(
                          assetPath: AppAssets.icQuickSplit,
                          fallbackIcon: Icons.call_split_rounded,
                          size: 40,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chia đều vào "${widget.activeFamily.name}"',
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                'Tổng hóa đơn: ${VndAmount.format(widget.parsed.totalMinor)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nội dung khoản chia',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Thành viên chia đều (~${VndAmount.format(perPerson)}/người)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    ...widget.activeFamily.members.map(
                      (m) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _selectedIds.contains(m.userId),
                        title: Text(m.fullName),
                        onChanged: isBusy
                            ? null
                            : (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedIds.add(m.userId);
                                  } else if (_selectedIds.length > 1) {
                                    _selectedIds.remove(m.userId);
                                  }
                                });
                              },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isBusy
                                ? null
                                : () => Navigator.of(ctx).pop(),
                            child: const Text('Hủy'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            key: const Key('confirm_receipt_split_group_btn'),
                            onPressed: isBusy
                                ? null
                                : () async {
                                    final cleanTitle = _titleCtrl.text.trim();
                                    if (cleanTitle.length < 2) {
                                      LifeOsTopToast.show(
                                        ctx,
                                        'Vui lòng nhập nội dung khoản chia (>= 2 ký tự).',
                                        kind: LifeOsToastKind.warning,
                                      );
                                      return;
                                    }
                                    setState(() => _isSubmittingLocal = true);
                                    final waiter = widget.famBloc.stream
                                        .firstWhere(
                                          (s) =>
                                              !s.isSubmitting &&
                                              (s.failure != null ||
                                                  s.message != null),
                                        )
                                        .timeout(
                                          const Duration(seconds: 8),
                                          onTimeout: () => widget.famBloc.state,
                                        );
                                    widget.famBloc.add(
                                      SharedBillSplitCreated(
                                        CreateSharedBillSplitParams(
                                          familyId: widget.activeFamily.id,
                                          title: cleanTitle,
                                          topic: widget.topic,
                                          paidByUserId: widget.userId,
                                          paidByName: widget.userName,
                                          totalAmountMinor:
                                              widget.parsed.totalMinor,
                                          splitMethod: SplitMethod.equal,
                                          participantIds:
                                              _selectedIds.toList(),
                                          participantNames: {
                                            for (final m
                                                in widget.activeFamily.members)
                                              m.userId: m.fullName,
                                          },
                                          choreOrTaskNote:
                                              'Quét Bill AI (${widget.parsed.items.length} món)',
                                        ),
                                      ),
                                    );
                                    final resultState = await waiter;
                                    if (!ctx.mounted) return;
                                    if (resultState.failure != null) {
                                      setState(
                                        () => _isSubmittingLocal = false,
                                      );
                                      LifeOsTopToast.show(
                                        ctx,
                                        resultState.failure!.message,
                                        kind: LifeOsToastKind.error,
                                      );
                                      return;
                                    }
                                    Navigator.of(ctx).pop();
                                    if (widget.parentContext.mounted) {
                                      LifeOsTopToast.show(
                                        widget.parentContext,
                                        'Đã chia đều "$cleanTitle" (${VndAmount.format(widget.parsed.totalMinor)}) vào nhóm "${widget.activeFamily.name}".',
                                        kind: LifeOsToastKind.success,
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Xác nhận chia đều'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ScheduleLoanReminderDialog extends StatefulWidget {
  const _ScheduleLoanReminderDialog({
    required this.initialTitle,
    required this.initialDueDate,
    required this.minDate,
    required this.loanTermMonths,
  });

  final String initialTitle;
  final DateTime initialDueDate;
  final DateTime minDate;
  final int loanTermMonths;

  @override
  State<_ScheduleLoanReminderDialog> createState() =>
      _ScheduleLoanReminderDialogState();
}

class _ScheduleLoanReminderDialogState
    extends State<_ScheduleLoanReminderDialog> {
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.initialTitle,
  );
  late DateTime _firstDueDate = widget.initialDueDate;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    return AlertDialog(
      title: const Text('Lịch nhắc Trả góp Hàng tháng'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên sự kiện nhắc lịch',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _firstDueDate,
                  firstDate: widget.minDate,
                  lastDate: DateTime(widget.minDate.year + 30),
                );
                if (picked != null && mounted) {
                  setState(() {
                    _firstDueDate = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      9,
                      0,
                    );
                  });
                }
              },
              icon: const Icon(Icons.calendar_today_rounded, size: 17),
              label: Text(
                'Ngày trả kỳ đầu: ${dateFmt.format(_firstDueDate)}',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lặp lại hằng tháng trong ${widget.loanTermMonths} kỳ · Nhắc trước 60 phút.',
              softWrap: true,
              style: TextStyle(
                fontSize: 12.2,
                color: TammySemanticColors.of(context).textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('confirm_schedule_loan_btn'),
          onPressed: () {
            final title = _titleCtrl.text.trim();
            if (title.length < 2) {
              LifeOsTopToast.show(
                context,
                'Tên sự kiện phải có ít nhất 2 ký tự.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            Navigator.of(context).pop((title, _firstDueDate));
          },
          child: const Text('Tạo lịch nhắc'),
        ),
      ],
    );
  }
}
