import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/services/native_app_updater_bridge.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../notifications/domain/entities/notification_entities.dart';
import '../../../notifications/presentation/bloc/notification_ingestion_bloc.dart';
import '../../../vehicles/presentation/bloc/vehicle_bloc.dart';
import '../../domain/entities/transaction_entities.dart';
import '../bloc/transaction_bloc.dart';
import '../bloc/transaction_event.dart';
import '../bloc/transaction_state.dart';

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
  ];

  late String _selectedCategory;
  late TextEditingController _merchantCtrl;
  late TextEditingController _amountCtrl;
  late TextEditingController _noteCtrl;
  String? _boundTxId;
  int _pendingCountAtAction = 0;
  bool _isEditing = false;
  bool _dismissedVehiclePrompt = false;
  bool _dismissedRecurringPrompt = false;

  @override
  void initState() {
    super.initState();
    final tx = widget.initialTransaction;
    final initialCat = tx?.categoryName ?? 'Ăn uống';
    _selectedCategory = _categories.contains(initialCat)
        ? initialCat
        : 'Ăn uống';
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
    _selectedCategory = _categories.contains(tx.categoryName)
        ? tx.categoryName
        : 'Ăn uống';
    _merchantCtrl.text = tx.merchant;
    _amountCtrl.text = '${tx.amountMinor}';
    _noteCtrl.text = tx.note ?? '';
    _isEditing = false;
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
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('✓ ${state.successMessage!}')),
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
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('⚠ ${state.failure!.message}')),
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
              const LifeOsIconSquircle(
                icon: Icons.verified_rounded,
                tone: LifeOsAccentTone.emerald,
                solidFill: true,
                size: 56,
                iconSize: 28,
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
                label: 'Sổ cái đã đồng bộ · 0 chờ duyệt',
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    final parsedAmt =
        VndAmount.tryParseInput(_amountCtrl.text) ?? tx.amountMinor;
    final timeStr = DateFormat('HH:mm').format(tx.occurredAt);
    final matchedWallet =
        wallets.where((w) => w.id == tx.walletId).firstOrNull ??
        wallets.where((w) => w.type == WalletType.bank).firstOrNull;
    final sourceLabel =
        tx.walletName ??
        (matchedWallet != null
            ? '${matchedWallet.bankCode ?? matchedWallet.name}${matchedWallet.maskedAccount != null ? " ${matchedWallet.maskedAccount}" : ""}'
            : 'Ví ngân hàng liên kết');
    final isCredit = tx.direction == 'credit';
    final rawSmsPreview =
        'Ngân hàng: Đã ghi nhận ${isCredit ? "tiền vào" : "thanh toán"} ${VndAmount.format(tx.amountMinor)} · ${tx.merchant}.';

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
        // 1. Pastel Mint Bank Notification Source Box
        LifeOsMintHeroCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LifeOsIconSquircle(
                icon: Icons.account_balance_rounded,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Thông báo ngân hàng (đã nhận diện)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.8,
                              height: 1.22,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          'Hôm nay, $timeStr',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: c.textSecondary,
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
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. Green Arrow + Auto-Detected Pill
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(Icons.arrow_downward_rounded, color: c.primary, size: 22),
              const SizedBox(height: 6),
              const LifeOsStatusPill(
                icon: Icons.auto_awesome_rounded,
                label: 'Đã tự động nhận diện giao dịch',
                tone: LifeOsAccentTone.emerald,
              ),
            ],
          ),
        ),

        // 3. Parsed Transaction Card
        LifeOsSoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 18, color: c.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Đã nhận diện giao dịch',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  const LifeOsStatusPill(
                    icon: Icons.rule_folder_outlined,
                    label: 'Khớp mẫu · Chờ duyệt',
                    tone: LifeOsAccentTone.amber,
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
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isCredit ? c.primary : const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _merchantCtrl.text.trim().isEmpty
                            ? 'G'
                            : _merchantCtrl.text
                                  .trim()
                                  .characters
                                  .first
                                  .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _merchantCtrl.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            _selectedCategory,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${isCredit ? "+" : "-"}${VndAmount.format(parsedAmt)}',
                        style: TextStyle(
                          fontSize: 21,
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
              Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 18,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Xác minh',
                      style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                    ),
                  ),
                  const LifeOsStatusPill(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Từ thông báo ngân hàng',
                    tone: LifeOsAccentTone.emerald,
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
                  Text(
                    'Danh mục chi tiêu',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedCategory,
                items: _categories
                    .map(
                      (cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(
                          cat,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedCategory = v);
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
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        key: const Key('link_tx_to_vehicle_maintenance_btn'),
                        onPressed: () {
                          final vehicles = context
                              .read<VehicleBloc>()
                              .state
                              .vehicles;
                          if (vehicles.isEmpty) {
                            context.go('/assets');
                            return;
                          }
                          final targetVehicle = vehicles.first;
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
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
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
                onPressed: userId == null
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
                child: const Text('Bỏ qua'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _isEditing = !_isEditing),
                  icon: Icon(
                    _isEditing ? Icons.check_rounded : Icons.edit_outlined,
                    size: 18,
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
                  onPressed: userId == null
                      ? null
                      : () {
                          _pendingCountAtAction = pendingCount;
                          // Remember user's category correction as an explainable merchant rule (Section 17)
                          if (_selectedCategory != tx.categoryName &&
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
                            context.read<TransactionActionBloc>().add(
                              ProvisionalTransactionDecisionSubmitted(
                                userId: userId,
                                transactionId: tx.id,
                                approve: true,
                                updatedCategoryName: _selectedCategory,
                                updatedMerchant: _merchantCtrl.text.trim(),
                              ),
                            );
                          } else {
                            LifeOsTopToast.fromSnackBar(
                              context,
                              const SnackBar(
                                content: Text(
                                  '✓ Giao dịch này đã được ghi vào Sổ cái.',
                                ),
                              ),
                            );
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/finance');
                            }
                          }
                        },
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Xác nhận'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
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
    return Row(
      children: [
        Icon(icon, size: 18, color: c.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13.5, color: c.textSecondary),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Screen 18: "Báo cáo chi tiêu / Báo cáo gia đình" (`W1–W4` Bar Chart + CSV Export).
class FinanceReportPage extends StatefulWidget {
  const FinanceReportPage({super.key});

  @override
  State<FinanceReportPage> createState() => _FinanceReportPageState();
}

class _FinanceReportPageState extends State<FinanceReportPage> {
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final listState = context.watch<TransactionListBloc>().state;
    final txs = listState.filteredTransactions
        .where((t) => !t.isReversed)
        .toList();

    var totalIncome = 0;
    var totalExpense = 0;
    final weekBuckets = <int>[0, 0, 0, 0];

    for (final t in txs) {
      if (t.kind == TransactionKind.income) {
        totalIncome += t.amountMinor;
      } else if (t.kind == TransactionKind.expense) {
        totalExpense += t.amountMinor;
        final wIdx = ((t.occurredAt.day - 1) ~/ 7).clamp(0, 3);
        weekBuckets[wIdx] += t.amountMinor;
      }
    }

    final netDiff = totalIncome - totalExpense;
    final maxBucket = weekBuckets.fold<int>(1, (a, b) => a > b ? a : b);

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
                          onChanged: (v) => setState(() => _period = v),
                        ),
                        const SizedBox(height: 12),

                        // Weekly W1–W4 Bar Chart Card
                        LifeOsSoftCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Kỳ báo cáo: ${listState.monthKey}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  LifeOsStatusPill(
                                    label: '${txs.length} giao dịch',
                                    tone: LifeOsAccentTone.emerald,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 156,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: List.generate(4, (i) {
                                    final val = weekBuckets[i];
                                    final ratio = totalExpense == 0
                                        ? (0.28 + i * 0.14)
                                        : (val / maxBucket).clamp(0.12, 1.0);
                                    final isPeak = val > 0 && val == maxBucket;
                                    return Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Text(
                                              val > 0
                                                  ? VndAmount.formatCompact(val)
                                                  : '0 ₫',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 240,
                                              ),
                                              height: 108 * ratio,
                                              decoration: BoxDecoration(
                                                color: isPeak
                                                    ? c.primary
                                                    : c.primary.withValues(
                                                        alpha: 0.48,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'W${i + 1}',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),
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
                                valueColor: c.primary,
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
                                valueColor: netDiff >= 0 ? c.primary : c.error,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Insight Banner
                        LifeOsMintHeroCard(
                          child: Row(
                            children: [
                              const LifeOsIconSquircle(
                                icon: Icons.check_circle_rounded,
                                tone: LifeOsAccentTone.emerald,
                                size: 38,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  netDiff >= 0
                                      ? 'Dòng tiền thặng dư tích cực trong kỳ này! Hãy trích một phần sang Quỹ gia đình.'
                                      : 'Chi tiêu đang vượt thu nhập trong kỳ. Kiểm tra các danh mục lớn để cân đối.',
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
                          onPressed: () async {
                            final buf = StringBuffer()
                              ..writeln(
                                'ThoiGian,HangMuc,DonVi,Loai,SoTienVND',
                              );
                            for (final tx in txs) {
                              final signed = tx.direction == 'credit'
                                  ? tx.amountMinor
                                  : -tx.amountMinor;
                              buf.writeln(
                                '"${tx.occurredAt.toIso8601String()}","${tx.categoryName}","${tx.merchant}","${tx.kind.name}",$signed',
                              );
                            }
                            final fileName =
                                'BaoCao_LifeOS_${listState.monthKey}.csv';
                            await sl<NativeAppUpdaterBridge>().shareTextFile(
                              fileName: fileName,
                              content: buf.toString(),
                              mimeType: 'text/csv',
                              title:
                                  'Báo cáo Tài chính LifeOS (${listState.monthKey})',
                            );
                            if (context.mounted) {
                              LifeOsTopToast.fromSnackBar(
                                context,
                                SnackBar(
                                  content: Text('✓ Đã xuất báo cáo $fileName.'),
                                ),
                              );
                            }
                          },
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
