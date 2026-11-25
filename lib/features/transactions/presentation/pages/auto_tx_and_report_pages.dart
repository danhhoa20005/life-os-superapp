import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/services/native_app_updater_bridge.dart';
import '../../../../core/utils/csv_sanitizer.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/trust_ux_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../notifications/domain/entities/notification_entities.dart';
import '../../../notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../../../vehicles/presentation/bloc/vehicle_bloc.dart';
import '../../domain/entities/transaction_entities.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../bloc/transaction_bloc.dart';
import '../bloc/transaction_event.dart';
import '../bloc/transaction_state.dart';
import '../widgets/life_insights_cross_domain_card.dart';

/// Screen 05: "Chi tiết giao dịch (Tự động)" (`05_Giao_dich_tu_dong.png`).
/// Strictly operates on REAL pending provisional or push-targeted transactions — never fabricates charges.
class AutoTransactionReviewPage extends StatefulWidget {
  final TransactionEntity? initialTransaction;
  final String? initialTransactionId;

  const AutoTransactionReviewPage({
    super.key,
    this.initialTransaction,
    this.initialTransactionId,
  });

  @override
  State<AutoTransactionReviewPage> createState() =>
      _AutoTransactionReviewPageState();
}

class _AutoTransactionReviewPageState extends State<AutoTransactionReviewPage> {
  static const List<String> _categories = [
    'Ăn uống',
    'Mua sắm',
    'Sinh hoạt',
    'Di chuyển',
    'Gia đình',
    'Hóa đơn',
    'Điện/Nước/Internet',
    'Sức khỏe & Y tế',
    'Bảo dưỡng & Sửa xe',
    'Lương & Thu nhập',
  ];

  late String _selectedCategory;
  late TextEditingController _merchantCtrl;
  late TextEditingController _amountCtrl;
  late TextEditingController _noteCtrl;
  String? _boundTxId;
  int _pendingCountAtAction = 0;
  bool _isEditing = false;
  bool _userChangedCategory = false;
  bool _dismissedVehiclePrompt = false;
  bool _dismissedRecurringPrompt = false;
  String? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    final tx = widget.initialTransaction;
    final initialCat = (tx?.categoryName ?? '').trim();
    _selectedCategory = initialCat.isNotEmpty ? initialCat : 'Ăn uống';
    _merchantCtrl = TextEditingController(text: tx?.merchant ?? '');
    _amountCtrl = TextEditingController(
      text: tx != null ? '${tx.amountMinor}' : '',
    );
    _noteCtrl = TextEditingController(text: tx?.note ?? '');
    _boundTxId = tx?.id;
  }

  void _syncControllersFromTransaction(TransactionEntity tx) {
    if (_boundTxId == tx.id) return;
    _boundTxId = tx.id;
    final cat = tx.categoryName.trim();
    _selectedCategory = cat.isNotEmpty ? cat : 'Ăn uống';
    _merchantCtrl.text = tx.merchant;
    _amountCtrl.text = '${tx.amountMinor}';
    _noteCtrl.text = tx.note ?? '';
    _isEditing = false;
    _userChangedCategory = false;
    _dismissedVehiclePrompt = false;
    _dismissedRecurringPrompt = false;
    _selectedVehicleId = null;
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final listState = context.watch<TransactionListBloc>().state;

    final pendingQueue = listState.provisionalTransactions;
    final byTargetId =
        (widget.initialTransactionId != null &&
            widget.initialTransactionId!.trim().isNotEmpty)
        ? listState.allTransactions
              .where((t) => t.id == widget.initialTransactionId!.trim())
              .firstOrNull
        : null;
    final tx =
        widget.initialTransaction ?? byTargetId ?? pendingQueue.firstOrNull;
    if (tx != null) {
      _syncControllersFromTransaction(tx);
    }

    final recentAutoVerified = listState.allTransactions
        .where(
          (t) =>
              (t.sourceKind == TransactionSourceKind.androidNotification ||
                  t.sourceKind == TransactionSourceKind.bankApi) &&
              t.verification != TransactionVerification.provisional &&
              t.verification != TransactionVerification.rejected,
        )
        .take(3)
        .toList(growable: false);

    return BlocListener<TransactionActionBloc, TransactionActionState>(
      listener: (context, state) {
        if (state.status == ActionStatus.success &&
            state.successMessage != null) {
          LifeOsTopToast.show(
            context,
            state.successMessage!,
            kind: LifeOsToastKind.success,
          );
          if (widget.initialTransaction != null || _pendingCountAtAction <= 1) {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/finance');
            }
          }
        } else if (state.status == ActionStatus.failure &&
            state.failure != null) {
          LifeOsTopToast.show(
            context,
            state.failure!.message,
            kind: LifeOsToastKind.error,
          );
        }
      },
      child: Scaffold(
        body: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Column(
              children: [
                LifeOsTopBrandHeader(
                  title: 'Chi tiết giao dịch (Tự động)',
                  showBackButton: true,
                  trailingAction: TextButton.icon(
                    onPressed: () => context.push('/notifications-privacy'),
                    icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                    label: const Text('Cổng QR'),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSpacing.maxContentWidth,
                      ),
                      child: tx == null
                          ? _buildHonestEmptyQueue(
                              context,
                              c,
                              recentAutoVerified,
                            )
                          : _buildActiveReviewBody(
                              context,
                              c,
                              userId: user?.id,
                              tx: tx,
                              pendingCount: pendingQueue.length,
                              wallets: listState.wallets,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHonestEmptyQueue(
    BuildContext context,
    TammySemanticColors c,
    List<TransactionEntity> recentAutoVerified,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        8,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        LifeOsMintHeroCard(
          child: Column(
            children: [
              const LifeOsLottieAnimation(
                assetPath: AppAssets.lottieWalletSyncRadar,
                size: 68,
                maxCycles: 1,
              ),
              const SizedBox(height: 12),
              Text(
                'Chưa có giao dịch tự động chờ duyệt',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Khi điện thoại nhận thông báo biến động số dư ngân hàng hoặc quét VietQR, giao dịch mới sẽ tự động hiện tại đây để bạn duyệt trong 1 chạm.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              const LifeOsStatusPill(
                icon: Icons.check_circle_outline_rounded,
                label: 'Đã đồng bộ · Không có giao dịch chờ duyệt',
                tone: LifeOsAccentTone.emerald,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('auto_tx_open_bank_setup_btn'),
          onPressed: () => context.push('/notifications-privacy'),
          icon: const Icon(Icons.account_balance_rounded, size: 19),
          label: const Text('Cài đặt nhận diện ngân hàng & VietQR'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('auto_tx_open_quick_add_btn'),
          onPressed: () => showLifeOsQuickCreateHub(context),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
          label: const Text('Thêm thu chi thủ công'),
        ),
        if (recentAutoVerified.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'Đã nhận diện & ghi sổ gần đây',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in recentAutoVerified) ...[
            LifeOsSoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  const LifeOsIconSquircle(
                    icon: Icons.bolt_rounded,
                    tone: LifeOsAccentTone.emerald,
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.merchant,
                          softWrap: true,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          '${item.categoryName} · ${DateFormat('dd/MM HH:mm').format(item.occurredAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${item.direction == 'credit' ? '+' : '-'}${VndAmount.format(item.amountMinor)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: item.direction == 'credit'
                          ? c.primary
                          : c.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildActiveReviewBody(
    BuildContext context,
    TammySemanticColors c, {
    required String? userId,
    required TransactionEntity tx,
    required int pendingCount,
    required List<WalletEntity> wallets,
  }) {
    final isSubmitting = context.select(
      (TransactionActionBloc b) => b.state.status == ActionStatus.submitting,
    );
    final vehicles = context.select((VehicleBloc b) => b.state.vehicles);
    final parsedAmt =
        VndAmount.tryParseInput(_amountCtrl.text) ?? tx.amountMinor;
    final now = DateTime.now();
    final isToday =
        tx.occurredAt.year == now.year &&
        tx.occurredAt.month == now.month &&
        tx.occurredAt.day == now.day;
    final timeDisplay = isToday
        ? 'Hôm nay, ${DateFormat('HH:mm').format(tx.occurredAt)}'
        : DateFormat('dd/MM/yyyy, HH:mm').format(tx.occurredAt);
    final matchedWallet =
        wallets.where((w) => w.id == tx.walletId).firstOrNull ??
        wallets.where((w) => w.type == WalletType.bank).firstOrNull;
    final sourceLabel =
        tx.walletName ??
        (matchedWallet != null
            ? '${matchedWallet.bankCode ?? matchedWallet.name}${matchedWallet.maskedAccount != null ? " ${matchedWallet.maskedAccount}" : ""}'
            : 'Ví ngân hàng liên kết');
    final isCredit = tx.direction == 'credit';
    final isTransfer =
        tx.kind == TransactionKind.transfer ||
        tx.kind == TransactionKind.creditCardPayment;
    final trustStatus = _resolveTransactionTrustStatus(tx);
    final (sourceText, sourceIcon) = _resolveTransactionSourceMeta(
      tx.sourceKind,
    );
    final isAutoDetected =
        tx.sourceKind == TransactionSourceKind.androidNotification ||
        tx.sourceKind == TransactionSourceKind.bankWebhook ||
        tx.sourceKind == TransactionSourceKind.bankApi;
    final rawSmsPreview = isAutoDetected
        ? 'Ngân hàng: Đã ghi nhận ${isCredit ? "tiền vào" : "thanh toán"} ${VndAmount.format(tx.amountMinor)} · ${tx.merchant}.'
        : '$sourceText: ${isCredit ? "Khoản thu" : "Khoản chi"} ${VndAmount.format(tx.amountMinor)} · ${tx.merchant}.';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        4,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        if (pendingCount > 1) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: LifeOsStatusPill(
              icon: Icons.playlist_add_check_circle_outlined,
              label: 'Còn $pendingCount giao dịch chờ duyệt',
              tone: LifeOsAccentTone.amber,
            ),
          ),
          const SizedBox(height: 8),
        ],
        // 1. Pastel Mint Source Box
        LifeOsMintHeroCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LifeOsIconSquircle(
                icon: isAutoDetected
                    ? Icons.account_balance_rounded
                    : sourceIcon,
                tone: LifeOsAccentTone.emerald,
                solidFill: true,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          sourceText,
                          softWrap: true,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.8,
                            height: 1.22,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          timeDisplay,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rawSmsPreview,
                      style: TextStyle(
                        fontSize: 12.8,
                        height: 1.35,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. Connector Arrow + Real Verification Pill
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(Icons.arrow_downward_rounded, color: c.primary, size: 22),
              const SizedBox(height: 6),
              FinancialTrustStatusBadge(
                status: trustStatus,
                customLabel: tx.verification == TransactionVerification.rejected
                    ? 'Đã bỏ qua'
                    : null,
              ),
            ],
          ),
        ),

        // 3. Parsed Transaction Card
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isAutoDetected
                            ? Icons.auto_awesome_rounded
                            : sourceIcon,
                        size: 18,
                        color: c.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isAutoDetected
                              ? 'Thông tin giao dịch nhận diện'
                              : 'Thông tin giao dịch',
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
                  FinancialTrustStatusBadge(
                    status: trustStatus,
                    customLabel:
                        tx.verification == TransactionVerification.rejected
                        ? 'Đã bỏ qua'
                        : null,
                  ),
                ],
              ),
              const Divider(height: 22),
              if (_isEditing) ...[
                TextField(
                  controller: _merchantCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Đơn vị / Cửa hàng',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số tiền giao dịch (VND)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ] else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ProCategoryStyle.buildCategoryBadge(
                          _selectedCategory.trim().isNotEmpty
                              ? _selectedCategory
                              : tx.categoryName,
                          isCredit: isCredit,
                          isTransfer: isTransfer,
                          size: 42,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _merchantCtrl.text,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  height: 1.22,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _selectedCategory,
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
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${isCredit ? "+" : "-"}${VndAmount.format(parsedAmt)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: isCredit ? c.primary : c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              const Divider(height: 24),
              _TxMetaLine(
                icon: Icons.schedule_rounded,
                label: 'Thời gian',
                value: DateFormat('dd/MM/yyyy · HH:mm').format(tx.occurredAt),
              ),
              const SizedBox(height: 12),
              _TxMetaLine(
                icon: Icons.credit_card_rounded,
                label: 'Nguồn tiền',
                value: sourceLabel,
              ),
              const SizedBox(height: 12),
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
                        Icons.verified_outlined,
                        size: 18,
                        color: c.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Nguồn & Xác minh',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      LifeOsStatusPill(
                        icon: sourceIcon,
                        label: sourceText,
                        tone: isAutoDetected
                            ? LifeOsAccentTone.blue
                            : LifeOsAccentTone.neutral,
                      ),
                      FinancialTrustStatusBadge(
                        status: trustStatus,
                        customLabel:
                            tx.verification == TransactionVerification.rejected
                            ? 'Đã bỏ qua'
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4. Category Selector + Smart Suggestion Chips
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.layers_outlined, size: 19, color: c.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Danh mục chi tiêu',
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
              DropdownButtonFormField<String>(
                key: ValueKey('auto_tx_cat_${tx.id}_$_selectedCategory'),
                isExpanded: true,
                initialValue: _selectedCategory,
                items:
                    <String>{
                          ..._categories,
                          ...context
                              .watch<TransactionListBloc>()
                              .state
                              .categories
                              .map((e) => e.name.trim())
                              .where((s) => s.isNotEmpty),
                          if (_selectedCategory.trim().isNotEmpty)
                            _selectedCategory.trim(),
                        }
                        .map(
                          (cat) => DropdownMenuItem(
                            value: cat,
                            child: Text(
                              cat,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _selectedCategory = v;
                      _userChangedCategory = true;
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 15,
                        color: c.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Chọn nhanh',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  ...const ['Ăn uống', 'Mua sắm', 'Sinh hoạt'].map((sug) {
                    final picked = _selectedCategory == sug;
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _selectedCategory = sug),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: picked ? c.primarySubtle : c.surfaceRaised,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: picked ? c.primary : c.separator,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (picked) ...[
                              Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: c.primary,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              sug,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: picked ? c.primary : c.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Section 17: Vehicle Maintenance Link Suggestion (Never assumes automatically!)
        if (tx.isVehicleMaintenanceHint && !_dismissedVehiclePrompt) ...[
          LifeOsMintHeroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const LifeOsIconSquircle(
                      icon: Icons.build_circle_outlined,
                      tone: LifeOsAccentTone.amber,
                      size: 38,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Có vẻ bạn vừa chi ${VndAmount.format(tx.amountMinor)} cho bảo dưỡng xe.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.8,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                if (vehicles.length > 1) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: const Key('auto_tx_vehicle_selector'),
                    isExpanded: true,
                    initialValue:
                        vehicles.any((v) => v.id == _selectedVehicleId)
                        ? _selectedVehicleId
                        : vehicles.first.id,
                    decoration: const InputDecoration(
                      labelText: 'Chọn xe cần ghi lịch sử bảo dưỡng',
                      isDense: true,
                    ),
                    items: vehicles
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.id,
                            child: Text(
                              v.plateNumber.trim().isNotEmpty
                                  ? '${v.name} · ${v.plateNumber}'
                                  : v.name,
                              softWrap: true,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedVehicleId = v);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        key: const Key('link_tx_to_vehicle_maintenance_btn'),
                        onPressed: () {
                          if (vehicles.isEmpty) {
                            context.push('/assets');
                            return;
                          }
                          final targetVehicle = vehicles.firstWhere(
                            (v) => v.id == _selectedVehicleId,
                            orElse: () => vehicles.first,
                          );
                          context.read<VehicleBloc>().add(
                            VehicleMaintenanceLogged(
                              vehicle: targetVehicle,
                              serviceTitle: tx.merchant,
                              odometerKm: targetVehicle.currentOdometerKm,
                              costMinor: tx.amountMinor,
                            ),
                          );
                          setState(() => _dismissedVehiclePrompt = true);
                          LifeOsTopToast.show(
                            context,
                            'Đã ghi vào lịch sử bảo dưỡng ${targetVehicle.name}!',
                            kind: LifeOsToastKind.success,
                          );
                        },
                        icon: const Icon(
                          Icons.directions_car_rounded,
                          size: 17,
                        ),
                        label: const Text('Ghi vào lịch sử bảo dưỡng'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () =>
                          setState(() => _dismissedVehiclePrompt = true),
                      child: const Text('Bỏ qua'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Section 17: Recurring Expense Detection Suggestion (Suggests only, never auto-creates!)
        Builder(
          builder: (context) {
            final recLabel =
                ExplainableBankingRuleEngine.detectRecurringSuggestionLabel(
                  tx.merchant,
                  tx.direction,
                );
            if ((recLabel == null && !tx.isRecurringCandidate) ||
                _dismissedRecurringPrompt) {
              return const SizedBox.shrink();
            }
            final suggestedTitle = recLabel ?? tx.categoryName;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LifeOsSoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.event_repeat_rounded,
                          size: 19,
                          color: c.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đề xuất khoản chi định kỳ: $suggestedTitle',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.8,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bạn có muốn lưu thành lời nhắc hóa đơn hàng tháng (dự kiến ${VndAmount.format(tx.amountMinor)})?',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: userId == null
                              ? null
                              : () {
                                  context.read<VehicleBloc>().add(
                                    RecurringBillCreated(
                                      userId: userId,
                                      title: suggestedTitle,
                                      providerName: tx.merchant,
                                      estimatedAmountMinor: tx.amountMinor,
                                      nextDueDate: DateTime.now().add(
                                        const Duration(days: 30),
                                      ),
                                    ),
                                  );
                                  setState(
                                    () => _dismissedRecurringPrompt = true,
                                  );
                                  LifeOsTopToast.show(
                                    context,
                                    'Đã lưu lời nhắc định kỳ "$suggestedTitle".',
                                  );
                                },
                          icon: const Icon(Icons.add_alert_rounded, size: 16),
                          label: const Text('Lưu nhắc định kỳ'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              setState(() => _dismissedRecurringPrompt = true),
                          child: const Text('Bỏ qua'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // 5. Note Card
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.notes_rounded, size: 19, color: c.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Ghi chú',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                maxLength: 100,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Nhập ghi chú (không bắt buộc)...',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 6. Bottom 3-Button Action Row: "Bỏ qua" | "Chỉnh sửa" | "✓ Xác nhận"
        Row(
          children: [
            SizedBox(
              height: 50,
              child: OutlinedButton(
                key: const Key('reject_auto_tx_button'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: (userId == null || isSubmitting)
                    ? null
                    : () {
                        _pendingCountAtAction = pendingCount;
                        context.read<TransactionActionBloc>().add(
                          ProvisionalTransactionDecisionSubmitted(
                            userId: userId,
                            transactionId: tx.id,
                            approve: false,
                          ),
                        );
                      },
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Bỏ qua'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () => setState(() => _isEditing = !_isEditing),
                  icon: Icon(
                    _isEditing ? Icons.check_rounded : Icons.edit_outlined,
                    size: 17,
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_isEditing ? 'Xong sửa' : 'Chỉnh sửa'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 50,
                child: FilledButton.icon(
                  key: const Key('confirm_auto_tx_button'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: (userId == null || isSubmitting)
                      ? null
                      : () {
                          _pendingCountAtAction = pendingCount;
                          // Remember user's explicit category correction as an explainable merchant rule (Section 17)
                          if (_userChangedCategory &&
                              _selectedCategory != tx.categoryName &&
                              tx.merchant.trim().length >= 3) {
                            try {
                              context.read<NotificationIngestionBloc>().add(
                                SaveMerchantRuleSubmitted(
                                  userId: userId,
                                  keyword: tx.merchant
                                      .trim()
                                      .split(' ')
                                      .take(2)
                                      .join(' '),
                                  categoryName: _selectedCategory,
                                ),
                              );
                            } catch (_) {}
                          }
                          if (tx.verification ==
                                  TransactionVerification.provisional ||
                              tx.verification ==
                                  TransactionVerification.needsReview) {
                            final editedAmt =
                                VndAmount.tryParseInput(_amountCtrl.text) ??
                                tx.amountMinor;
                            context.read<TransactionActionBloc>().add(
                              ProvisionalTransactionDecisionSubmitted(
                                userId: userId,
                                transactionId: tx.id,
                                approve: true,
                                updatedCategoryName: _selectedCategory,
                                updatedMerchant: _merchantCtrl.text.trim(),
                                updatedAmountMinor: editedAmt > 0
                                    ? editedAmt
                                    : tx.amountMinor,
                                updatedNote: _noteCtrl.text.trim(),
                              ),
                            );
                          } else {
                            LifeOsTopToast.show(
                              context,
                              'Giao dịch này đã được ghi vào Sổ cái.',
                              kind: LifeOsToastKind.success,
                            );
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/finance');
                            }
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(isSubmitting ? 'Đang xử lý...' : 'Xác nhận'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  FinancialTrustStatus _resolveTransactionTrustStatus(TransactionEntity tx) {
    if (tx.isReversed) return FinancialTrustStatus.reversed;
    if (tx.reconciliationStatus == 'disputed') {
      return FinancialTrustStatus.disputed;
    }
    if (tx.hasPendingWrites) return FinancialTrustStatus.syncing;
    return switch (tx.verification) {
      TransactionVerification.provisional =>
        FinancialTrustStatus.pendingConfirmation,
      TransactionVerification.needsReview => FinancialTrustStatus.needsReview,
      TransactionVerification.verified ||
      TransactionVerification.matchedPaymentOrder =>
        FinancialTrustStatus.reconciled,
      TransactionVerification.userConfirmed => FinancialTrustStatus.saved,
      TransactionVerification.rejected => FinancialTrustStatus.syncFailed,
    };
  }

  (String label, IconData icon) _resolveTransactionSourceMeta(
    TransactionSourceKind kind,
  ) {
    return switch (kind) {
      TransactionSourceKind.androidNotification => (
        'Từ thông báo ngân hàng',
        Icons.notifications_active_outlined,
      ),
      TransactionSourceKind.bankWebhook => (
        'Đồng bộ tự động ngân hàng',
        Icons.sync_rounded,
      ),
      TransactionSourceKind.bankApi => (
        'Đối soát ngân hàng',
        Icons.account_balance_outlined,
      ),
      TransactionSourceKind.csv => (
        'Nhập từ sao kê CSV',
        Icons.table_view_rounded,
      ),
      TransactionSourceKind.manual => (
        'Ghi chép thủ công',
        Icons.edit_note_rounded,
      ),
    };
  }
}

class _TxMetaLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TxMetaLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: c.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 13.5, color: c.textSecondary),
            ),
          ],
        ),
        Text(
          value,
          softWrap: true,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Screen 18: "Báo cáo chi tiêu / Báo cáo gia đình" (Multi-Period `Tuần · Tháng · Năm` Dual-Bar + Donut + CSV Export).
class FinanceReportPage extends StatefulWidget {
  final DateTime? referenceDate;

  const FinanceReportPage({super.key, this.referenceDate});

  @override
  State<FinanceReportPage> createState() => _FinanceReportPageState();
}

class _FinanceReportPageState extends State<FinanceReportPage> {
  String _period = 'month';
  int? _selectedBucketIdx;
  String? _overrideMonthKey;
  String? _cachedRangeKey;
  Stream<Result<List<TransactionEntity>>>? _cachedRangeStream;

  static String _stepMonthKey(String mk, int deltaMonths) {
    final parts = mk.split('-');
    final now = DateTime.now();
    final y = int.tryParse(parts.firstOrNull ?? '') ?? now.year;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? now.month;
    final next = DateTime(y, m + deltaMonths, 1);
    return '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}';
  }

  String? _resolveUserId(BuildContext context, TransactionListState listState) {
    try {
      final authUser = context.read<AuthBloc>().state.user;
      if (authUser != null && authUser.id.isNotEmpty) return authUser.id;
    } catch (_) {
      // Standalone widget test without AuthBloc provider.
    }
    if (listState.allTransactions.isNotEmpty) {
      return listState.allTransactions.first.ownerId;
    }
    if (listState.wallets.isNotEmpty) {
      return listState.wallets.first.ownerId;
    }
    return null;
  }

  Stream<Result<List<TransactionEntity>>>? _resolveRangeStream({
    required String? userId,
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) {
    if (userId == null ||
        userId.isEmpty ||
        !sl.isRegistered<TransactionRepository>()) {
      return null;
    }
    final key =
        '$userId|${startInclusive.millisecondsSinceEpoch}|${endExclusive.millisecondsSinceEpoch}';
    if (_cachedRangeKey != key || _cachedRangeStream == null) {
      _cachedRangeKey = key;
      _cachedRangeStream = sl<TransactionRepository>().watchTransactionsRange(
        userId: userId,
        startInclusive: startInclusive,
        endExclusive: endExclusive,
        limit: 800,
      );
    }
    return _cachedRangeStream;
  }

  static String _ddMm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  void _selectBucketFromDx(
    double dx,
    double width,
    int bucketCount, {
    required bool toggle,
  }) {
    if (width <= 0 || bucketCount <= 0) return;
    final idx = ((dx / width) * bucketCount).floor().clamp(0, bucketCount - 1);
    if (toggle && _selectedBucketIdx == idx) {
      HapticFeedback.selectionClick();
      setState(() => _selectedBucketIdx = null);
      return;
    }
    if (_selectedBucketIdx != idx) {
      HapticFeedback.selectionClick();
      setState(() => _selectedBucketIdx = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listState = context.watch<TransactionListBloc>().state;
    final refNow = widget.referenceDate ?? DateTime.now();
    final currentRefMonthKey =
        '${refNow.year.toString().padLeft(4, '0')}-${refNow.month.toString().padLeft(2, '0')}';
    final activeMonthKey = _overrideMonthKey ?? listState.monthKey;

    final mkParts = activeMonthKey.split('-');
    final selectedYear = mkParts.isNotEmpty
        ? (int.tryParse(mkParts[0]) ?? refNow.year)
        : refNow.year;
    final selectedMonth = mkParts.length > 1
        ? (int.tryParse(mkParts[1]) ?? refNow.month)
        : refNow.month;

    late final DateTime startInclusive;
    late final DateTime endExclusive;
    late final String periodHeaderLabel;
    late final String exportTag;

    if (_period == 'week') {
      final anchorDay = DateTime(refNow.year, refNow.month, refNow.day);
      startInclusive = anchorDay.subtract(
        Duration(days: anchorDay.weekday - DateTime.monday),
      );
      endExclusive = startInclusive.add(const Duration(days: 7));
      final sunday = startInclusive.add(const Duration(days: 6));
      periodHeaderLabel = 'Kỳ tuần: ${_ddMm(startInclusive)}–${_ddMm(sunday)}';
      exportTag =
          'Tuan_${startInclusive.year}${startInclusive.month.toString().padLeft(2, '0')}${startInclusive.day.toString().padLeft(2, '0')}';
    } else if (_period == 'year') {
      startInclusive = DateTime(selectedYear, 1, 1);
      endExclusive = DateTime(selectedYear + 1, 1, 1);
      periodHeaderLabel = 'Kỳ năm: $selectedYear';
      exportTag = 'Nam_$selectedYear';
    } else {
      startInclusive = DateTime(selectedYear, selectedMonth, 1);
      endExclusive = DateTime(selectedYear, selectedMonth + 1, 1);
      periodHeaderLabel = 'Kỳ báo cáo: $activeMonthKey';
      exportTag = activeMonthKey;
    }

    List<TransactionEntity> filterInWindow(List<TransactionEntity> source) {
      return source
          .where(
            (t) =>
                t.isConfirmedInLedger &&
                !t.isReversed &&
                !t.occurredAt.isBefore(startInclusive) &&
                t.occurredAt.isBefore(endExclusive),
          )
          .toList(growable: false);
    }

    if (_period == 'month' && activeMonthKey == listState.monthKey) {
      final monthTxs = listState.allTransactions
          .where((t) => t.isConfirmedInLedger && !t.isReversed)
          .toList(growable: false);
      return _buildReportScaffold(
        context: context,
        periodTxs: monthTxs,
        startInclusive: startInclusive,
        selectedYear: selectedYear,
        selectedMonth: selectedMonth,
        activeMonthKey: activeMonthKey,
        currentRefMonthKey: currentRefMonthKey,
        periodHeaderLabel: periodHeaderLabel,
        exportTag: exportTag,
      );
    }

    final userId = _resolveUserId(context, listState);
    final rangeStream = _resolveRangeStream(
      userId: userId,
      startInclusive: startInclusive,
      endExclusive: endExclusive,
    );
    final fallbackTxs = filterInWindow(listState.allTransactions);

    if (rangeStream == null) {
      return _buildReportScaffold(
        context: context,
        periodTxs: fallbackTxs,
        startInclusive: startInclusive,
        selectedYear: selectedYear,
        selectedMonth: selectedMonth,
        activeMonthKey: activeMonthKey,
        currentRefMonthKey: currentRefMonthKey,
        periodHeaderLabel: periodHeaderLabel,
        exportTag: exportTag,
      );
    }

    return StreamBuilder<Result<List<TransactionEntity>>>(
      stream: rangeStream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final resolvedTxs = data is Success<List<TransactionEntity>>
            ? filterInWindow(data.value)
            : fallbackTxs;
        return _buildReportScaffold(
          context: context,
          periodTxs: resolvedTxs,
          startInclusive: startInclusive,
          selectedYear: selectedYear,
          selectedMonth: selectedMonth,
          activeMonthKey: activeMonthKey,
          currentRefMonthKey: currentRefMonthKey,
          periodHeaderLabel: periodHeaderLabel,
          exportTag: exportTag,
        );
      },
    );
  }

  Widget _buildReportScaffold({
    required BuildContext context,
    required List<TransactionEntity> periodTxs,
    required DateTime startInclusive,
    required int selectedYear,
    required int selectedMonth,
    required String activeMonthKey,
    required String currentRefMonthKey,
    required String periodHeaderLabel,
    required String exportTag,
  }) {
    final c = TammySemanticColors.of(context);
    const expenseBarColor = Color(0xFFF59F00);

    late final List<String> axisLabels;
    late final List<String> fullBucketTitles;
    if (_period == 'week') {
      const wdShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
      const wdFull = [
        'Thứ 2',
        'Thứ 3',
        'Thứ 4',
        'Thứ 5',
        'Thứ 6',
        'Thứ 7',
        'Chủ nhật',
      ];
      axisLabels = wdShort;
      fullBucketTitles = List<String>.generate(7, (i) {
        final d = startInclusive.add(Duration(days: i));
        return '${wdFull[i]} (${_ddMm(d)})';
      });
    } else if (_period == 'year') {
      axisLabels = List<String>.generate(12, (i) => 'T${i + 1}');
      fullBucketTitles = List<String>.generate(
        12,
        (i) => 'Tháng ${(i + 1).toString().padLeft(2, '0')}/$selectedYear',
      );
    } else {
      axisLabels = const ['01–07', '08–14', '15–21', '22–28', '29+'];
      fullBucketTitles = const [
        'Tuần 1 (01–07)',
        'Tuần 2 (08–14)',
        'Tuần 3 (15–21)',
        'Tuần 4 (22–28)',
        'Cuối tháng (29+)',
      ];
    }

    final bucketCount = axisLabels.length;
    final incomeBuckets = List<int>.filled(bucketCount, 0);
    final expenseBuckets = List<int>.filled(bucketCount, 0);
    final expenseByCat = <String, int>{};

    var totalIncome = 0;
    var totalExpense = 0;

    for (final t in periodTxs) {
      final int bIdx;
      if (_period == 'week') {
        final txDay = DateTime(
          t.occurredAt.year,
          t.occurredAt.month,
          t.occurredAt.day,
        );
        bIdx = txDay
            .difference(startInclusive)
            .inDays
            .clamp(0, bucketCount - 1);
      } else if (_period == 'year') {
        bIdx = (t.occurredAt.month - 1).clamp(0, bucketCount - 1);
      } else {
        bIdx = ((t.occurredAt.day - 1) ~/ 7).clamp(0, bucketCount - 1);
      }

      if (t.kind == TransactionKind.income) {
        totalIncome += t.amountMinor;
        incomeBuckets[bIdx] += t.amountMinor;
      } else if (t.kind == TransactionKind.expense) {
        totalExpense += t.amountMinor;
        expenseBuckets[bIdx] += t.amountMinor;
        if (t.splitLines.isNotEmpty) {
          for (final sl in t.splitLines) {
            expenseByCat[sl.categoryName] =
                (expenseByCat[sl.categoryName] ?? 0) + sl.amountMinor;
          }
        } else {
          expenseByCat[t.categoryName] =
              (expenseByCat[t.categoryName] ?? 0) + t.amountMinor;
        }
      }
    }

    final netDiff = totalIncome - totalExpense;
    var maxBucketVal = 0;
    for (final v in incomeBuckets) {
      if (v > maxBucketVal) maxBucketVal = v;
    }
    for (final v in expenseBuckets) {
      if (v > maxBucketVal) maxBucketVal = v;
    }

    final sel =
        (_selectedBucketIdx != null && _selectedBucketIdx! < bucketCount)
        ? _selectedBucketIdx
        : null;
    final selInc = sel != null ? incomeBuckets[sel] : 0;
    final selExp = sel != null ? expenseBuckets[sel] : 0;

    final sortedCatEntries =
        expenseByCat.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final donutSlices = sortedCatEntries
        .map(
          (e) => ProDonutSlice(
            label: e.key,
            amountMinor: e.value,
            pct: totalExpense > 0 ? (e.value * 100.0) / totalExpense : 0.0,
            color: ProCategoryStyle.resolve(e.key).color,
          ),
        )
        .toList(growable: false);

    final savingsRatePct = totalIncome > 0
        ? (((totalIncome - totalExpense) * 100.0) / totalIncome).clamp(
            -999.0,
            100.0,
          )
        : 0.0;

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Column(
            children: [
              const LifeOsTopBrandHeader(
                title: 'Báo cáo chi tiêu',
                showBackButton: true,
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: ListView(
                      key: const Key('finance_report_list_view'),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        4,
                        AppSpacing.md,
                        AppSpacing.xxl,
                      ),
                      children: [
                        LifeOsSegmentedPills<String>(
                          selected: _period,
                          options: const [
                            ('month', 'Tháng', null),
                            ('week', 'Tuần', null),
                            ('year', 'Năm', null),
                          ],
                          onChanged: (v) => setState(() {
                            _period = v;
                            _selectedBucketIdx = null;
                          }),
                        ),
                        if (_period == 'month') ...[
                          const SizedBox(height: 8),
                          LifeOsSoftCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    key: const Key('report_prev_month_btn'),
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => setState(() {
                                      _overrideMonthKey = _stepMonthKey(
                                        activeMonthKey,
                                        -1,
                                      );
                                      _selectedBucketIdx = null;
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.chevron_left_rounded,
                                              size: 18,
                                              color: c.primary,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              'Tháng trước',
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                fontWeight: FontWeight.w700,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: InkWell(
                                    key: const Key('report_current_month_btn'),
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => setState(() {
                                      _overrideMonthKey = null;
                                      _selectedBucketIdx = null;
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.center,
                                        child: Text(
                                          activeMonthKey == currentRefMonthKey
                                              ? 'Tháng hiện tại'
                                              : 'Thg ${selectedMonth.toString().padLeft(2, '0')}/$selectedYear',
                                          style: TextStyle(
                                            fontSize: 12.4,
                                            fontWeight: FontWeight.w800,
                                            color: c.primary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: InkWell(
                                    key: const Key('report_next_month_btn'),
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => setState(() {
                                      _overrideMonthKey = _stepMonthKey(
                                        activeMonthKey,
                                        1,
                                      );
                                      _selectedBucketIdx = null;
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Tháng sau',
                                              style: TextStyle(
                                                fontSize: 12.2,
                                                fontWeight: FontWeight.w700,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: c.primary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        LifeOsMaterialContentSwitcher(
                          child: Column(
                            key: ValueKey<String>(
                              'finance_report_period_${_period}_$activeMonthKey',
                            ),
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LifeInsightsCrossDomainCard(
                                periodCode: _period,
                                incomeMinor: totalIncome,
                                expenseMinor: totalExpense,
                                expenseByCategory: expenseByCat,
                              ),
                              const SizedBox(height: 12),
                              // Multi-Period Dual Income vs Expense Bar Chart Card
                              LifeOsSoftCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          periodHeaderLabel,
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: c.textPrimary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                        LifeOsStatusPill(
                                          label:
                                              '${periodTxs.length} giao dịch',
                                          tone: LifeOsAccentTone.emerald,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 6,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _ReportLegendBadge(
                                              color: c.success,
                                              label: 'Thu',
                                            ),
                                            const SizedBox(width: 10),
                                            const _ReportLegendBadge(
                                              color: expenseBarColor,
                                              label: 'Chi',
                                            ),
                                          ],
                                        ),
                                        if (sel != null)
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            onTap: () => setState(
                                              () => _selectedBucketIdx = null,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: c.primary.withValues(
                                                  alpha: 0.10,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                '${fullBucketTitles[sel]}: '
                                                'Thu +${VndAmount.formatCompact(selInc)} · '
                                                'Chi -${VndAmount.formatCompact(selExp)}',
                                                softWrap: true,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: c.textPrimary,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          Text(
                                            maxBucketVal > 0
                                                ? 'Đỉnh: ${VndAmount.formatCompact(maxBucketVal)}'
                                                : 'Chưa phát sinh',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: c.textSecondary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 158,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          SizedBox(
                                            width: 44,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 22,
                                              ),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      maxBucketVal > 0
                                                          ? VndAmount.formatCompact(
                                                              maxBucketVal,
                                                            )
                                                          : '0 ₫',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: c.textSecondary,
                                                        fontFeatures: const [
                                                          FontFeature.tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  if (maxBucketVal > 0)
                                                    FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      child: Text(
                                                        VndAmount.formatCompact(
                                                          maxBucketVal ~/ 2,
                                                        ),
                                                        style: TextStyle(
                                                          fontSize: 9.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: c.textSecondary
                                                              .withValues(
                                                                alpha: 0.8,
                                                              ),
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
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: c.textSecondary,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
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
                                                        key: const Key(
                                                          'report_dual_bar_canvas',
                                                        ),
                                                        behavior:
                                                            HitTestBehavior
                                                                .opaque,
                                                        onTapUp: (d) =>
                                                            _selectBucketFromDx(
                                                              d
                                                                  .localPosition
                                                                  .dx,
                                                              constraints
                                                                  .maxWidth,
                                                              bucketCount,
                                                              toggle: true,
                                                            ),
                                                        onHorizontalDragUpdate:
                                                            (
                                                              d,
                                                            ) => _selectBucketFromDx(
                                                              d
                                                                  .localPosition
                                                                  .dx,
                                                              constraints
                                                                  .maxWidth,
                                                              bucketCount,
                                                              toggle: false,
                                                            ),
                                                        child: Stack(
                                                          alignment:
                                                              Alignment.center,
                                                          children: [
                                                            SizedBox.expand(
                                                              child: CustomPaint(
                                                                painter: _ReportDualBarChartPainter(
                                                                  incomes:
                                                                      incomeBuckets,
                                                                  expenses:
                                                                      expenseBuckets,
                                                                  selectedIdx:
                                                                      sel,
                                                                  incomeColor:
                                                                      c.success,
                                                                  expenseColor:
                                                                      expenseBarColor,
                                                                  highlightBg: c
                                                                      .primary
                                                                      .withValues(
                                                                        alpha:
                                                                            0.08,
                                                                      ),
                                                                  gridColor: c
                                                                      .separator
                                                                      .withValues(
                                                                        alpha:
                                                                            0.65,
                                                                      ),
                                                                ),
                                                              ),
                                                            ),
                                                            if (maxBucketVal ==
                                                                0)
                                                              IgnorePointer(
                                                                child: Container(
                                                                  padding:
                                                                      const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            10,
                                                                        vertical:
                                                                            4,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    color: c
                                                                        .surface
                                                                        .withValues(
                                                                          alpha:
                                                                              0.90,
                                                                        ),
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          10,
                                                                        ),
                                                                    border: Border.all(
                                                                      color: c
                                                                          .separator,
                                                                    ),
                                                                  ),
                                                                  child: Text(
                                                                    'Chưa có giao dịch thu chi trong kỳ',
                                                                    softWrap:
                                                                        true,
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      color: c
                                                                          .textSecondary,
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
                                                const SizedBox(height: 6),
                                                SizedBox(
                                                  height: 16,
                                                  child: Row(
                                                    children: List.generate(bucketCount, (
                                                      i,
                                                    ) {
                                                      final isSelected =
                                                          sel == i;
                                                      return Expanded(
                                                        child: InkWell(
                                                          key: Key(
                                                            'report_bucket_label_$i',
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                          onTap: () {
                                                            HapticFeedback.selectionClick();
                                                            setState(() {
                                                              _selectedBucketIdx =
                                                                  isSelected
                                                                  ? null
                                                                  : i;
                                                            });
                                                          },
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 1,
                                                                ),
                                                            child: Center(
                                                              child: FittedBox(
                                                                fit: BoxFit
                                                                    .scaleDown,
                                                                child: Text(
                                                                  axisLabels[i],
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        10.5,
                                                                    fontWeight:
                                                                        isSelected
                                                                        ? FontWeight
                                                                              .w800
                                                                        : FontWeight
                                                                              .w700,
                                                                    color:
                                                                        isSelected
                                                                        ? c.primary
                                                                        : c.textSecondary,
                                                                    fontFeatures:
                                                                        const [
                                                                          FontFeature.tabularFigures(),
                                                                        ],
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }),
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

                              // Category Composition Donut Card for active period
                              LifeOsSoftCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Cơ cấu danh mục chi tiêu',
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    if (donutSlices.isEmpty)
                                      Text(
                                        'Chưa có khoản chi tiêu theo danh mục trong kỳ này.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: c.textSecondary,
                                        ),
                                      )
                                    else
                                      RepaintBoundary(
                                        child: ProDonutChart(
                                          totalExpenseMinor: totalExpense,
                                          slices: donutSlices,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Tổng thu | Tổng chi | Chênh lệch Card
                              LifeOsSoftCard(
                                child: Column(
                                  children: [
                                    _ReportSummaryRow(
                                      label: 'Tổng thu',
                                      value: VndAmount.format(totalIncome),
                                      valueColor: c.success,
                                    ),
                                    const Divider(height: 22),
                                    _ReportSummaryRow(
                                      label: 'Tổng chi',
                                      value: VndAmount.format(totalExpense),
                                      valueColor: c.error,
                                    ),
                                    const Divider(height: 22),
                                    _ReportSummaryRow(
                                      label: 'Chênh lệch ròng',
                                      value: VndAmount.format(
                                        netDiff,
                                        showPlus: true,
                                      ),
                                      valueColor: netDiff >= 0
                                          ? c.primary
                                          : c.error,
                                    ),
                                    if (totalIncome > 0) ...[
                                      const Divider(height: 22),
                                      _ReportSummaryRow(
                                        label: 'Tỷ lệ tích lũy',
                                        value:
                                            '${savingsRatePct.toStringAsFixed(1)}%',
                                        valueColor: savingsRatePct >= 0
                                            ? c.primary
                                            : c.error,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Insight Banner
                              LifeOsMintHeroCard(
                                child: Row(
                                  children: [
                                    LifeOsIconSquircle(
                                      icon:
                                          totalIncome == 0 && totalExpense == 0
                                          ? Icons.insights_rounded
                                          : (netDiff >= 0
                                                ? Icons.check_circle_rounded
                                                : Icons.warning_amber_rounded),
                                      tone: netDiff >= 0
                                          ? LifeOsAccentTone.emerald
                                          : LifeOsAccentTone.amber,
                                      size: 38,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        totalIncome == 0 && totalExpense == 0
                                            ? 'Chưa có phát sinh thu chi trong kỳ đang chọn. Ghi giao dịch mới để xem phân tích tự động.'
                                            : (netDiff >= 0
                                                  ? 'Dòng tiền thặng dư tích cực trong kỳ này! Hãy trích một phần sang Quỹ gia đình.'
                                                  : 'Chi tiêu đang vượt thu nhập trong kỳ. Kiểm tra các danh mục lớn để cân đối.'),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              LifeOsPrimaryCtaButton(
                                icon: Icons.file_download_outlined,
                                label: 'Xuất báo cáo (CSV)',
                                onPressed: periodTxs.isEmpty
                                    ? null
                                    : () async {
                                        final buf = StringBuffer()
                                          ..writeln(
                                            'ThoiGian,HangMuc,DonVi,Loai,SoTienVND',
                                          );
                                        for (final tx in periodTxs) {
                                          final signed =
                                              tx.direction == 'credit'
                                              ? tx.amountMinor
                                              : -tx.amountMinor;
                                          buf.writeln(
                                            '${CsvSanitizer.escapeQuotedCell(tx.occurredAt.toIso8601String())},'
                                            '${CsvSanitizer.escapeQuotedCell(tx.categoryName)},'
                                            '${CsvSanitizer.escapeQuotedCell(tx.merchant)},'
                                            '${CsvSanitizer.escapeQuotedCell(tx.kind.name)},'
                                            '$signed',
                                          );
                                        }
                                        final fileName =
                                            'BaoCao_LifeOS_$exportTag.csv';
                                        await sl<NativeAppUpdaterBridge>()
                                            .shareTextFile(
                                              fileName: fileName,
                                              content: buf.toString(),
                                              mimeType: 'text/csv',
                                              title:
                                                  'Báo cáo Tài chính LifeOS ($periodHeaderLabel)',
                                            );
                                        if (context.mounted) {
                                          LifeOsTopToast.show(
                                            context,
                                            'Đã xuất báo cáo $fileName.',
                                            kind: LifeOsToastKind.success,
                                          );
                                        }
                                      },
                              ),
                              if (periodTxs.isEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Chưa có giao dịch trong kỳ này để xuất CSV.',
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 12,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportLegendBadge extends StatelessWidget {
  final Color color;
  final String label;

  const _ReportLegendBadge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8.5,
          height: 8.5,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ReportDualBarChartPainter extends CustomPainter {
  final List<int> incomes;
  final List<int> expenses;
  final int? selectedIdx;
  final Color incomeColor;
  final Color expenseColor;
  final Color highlightBg;
  final Color gridColor;

  const _ReportDualBarChartPainter({
    required this.incomes,
    required this.expenses,
    required this.selectedIdx,
    required this.incomeColor,
    required this.expenseColor,
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

    final count = math.min(incomes.length, expenses.length);
    if (count <= 0) return;

    var maxVal = 0;
    for (var i = 0; i < count; i++) {
      if (incomes[i] > maxVal) maxVal = incomes[i];
      if (expenses[i] > maxVal) maxVal = expenses[i];
    }

    final slotW = size.width / count;
    final pairGap = count >= 10 ? 1.5 : 2.5;
    final barW = math.min(
      14.0,
      math.max(4.0, (slotW * (count >= 10 ? 0.68 : 0.56) - pairGap) / 2),
    );
    final usableH = math.max(14.0, size.height - 8.0);

    if (selectedIdx != null && selectedIdx! >= 0 && selectedIdx! < count) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            slotW * selectedIdx! + 1.5,
            0,
            math.max(6.0, slotW - 3.0),
            size.height,
          ),
          const Radius.circular(8),
        ),
        Paint()..color = highlightBg,
      );
    }

    double heightFor(int val) {
      if (maxVal <= 0 || val <= 0) return 2.0;
      final ratio = (val / maxVal).clamp(0.0, 1.0);
      return math.max(6.0, math.pow(ratio, 0.72).toDouble() * usableH);
    }

    for (var i = 0; i < count; i++) {
      final inc = incomes[i];
      final exp = expenses[i];
      final cx = slotW * i + slotW / 2;
      final dimmed = selectedIdx != null && selectedIdx != i;

      final incH = heightFor(inc);
      final expH = heightFor(exp);

      final incRect = Rect.fromLTWH(
        cx - pairGap / 2 - barW,
        size.height - 1 - incH,
        barW,
        incH,
      );
      final expRect = Rect.fromLTWH(
        cx + pairGap / 2,
        size.height - 1 - expH,
        barW,
        expH,
      );

      final incPaint = Paint();
      if (inc > 0 && maxVal > 0) {
        final a = dimmed ? 0.36 : 0.96;
        incPaint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            incomeColor.withValues(alpha: a),
            incomeColor.withValues(alpha: a * 0.65),
          ],
        ).createShader(incRect);
      } else {
        incPaint.color = gridColor;
      }

      final expPaint = Paint();
      if (exp > 0 && maxVal > 0) {
        final a = dimmed ? 0.36 : 0.96;
        expPaint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            expenseColor.withValues(alpha: a),
            expenseColor.withValues(alpha: a * 0.65),
          ],
        ).createShader(expRect);
      } else {
        expPaint.color = gridColor;
      }

      final cornerR = Radius.circular(count >= 10 ? 3.2 : 5.0);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          incRect,
          topLeft: cornerR,
          topRight: cornerR,
          bottomLeft: const Radius.circular(1.5),
          bottomRight: const Radius.circular(1.5),
        ),
        incPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          expRect,
          topLeft: cornerR,
          topRight: cornerR,
          bottomLeft: const Radius.circular(1.5),
          bottomRight: const Radius.circular(1.5),
        ),
        expPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReportDualBarChartPainter oldDelegate) {
    return oldDelegate.incomes != incomes ||
        oldDelegate.expenses != expenses ||
        oldDelegate.selectedIdx != selectedIdx ||
        oldDelegate.incomeColor != incomeColor ||
        oldDelegate.expenseColor != expenseColor;
  }
}

class _ReportSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _ReportSummaryRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: c.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
