import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/theme_bloc.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/services/android_notification_bridge.dart';
import '../../../../core/services/native_app_updater_bridge.dart';
import '../../../../core/utils/vietqr_emv_builder.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_top_toast.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../domain/entities/notification_entities.dart';
import '../bloc/notification_ingestion_bloc.dart';

class NotificationsPrivacyPage extends StatefulWidget {
  const NotificationsPrivacyPage({super.key});

  @override
  State<NotificationsPrivacyPage> createState() =>
      _NotificationsPrivacyPageState();
}

class _NotificationsPrivacyPageState extends State<NotificationsPrivacyPage>
    with WidgetsBindingObserver {
  final TextEditingController _csvCtrl = TextEditingController();
  String? _selectedWalletId;
  String? _lastShownOrderId;
  String _historyFilter = 'all'; // 'all' | 'credit' | 'debit'
  bool _showRawExportPreview = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<NotificationIngestionBloc>().add(
        const NativePermissionStatusRefreshed(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _csvCtrl.dispose();
    super.dispose();
  }

  Future<void> _showLinkBankAccountSheet({
    required BuildContext context,
    required String userId,
    required String userFullName,
    required List<WalletEntity> wallets,
    required String defaultWalletId,
  }) async {
    var selectedBin = kLifeOsVietQrBanks.first.bin;
    var pickedWalletId = defaultWalletId;
    final accNumberCtrl = TextEditingController();
    final holderCtrl = TextEditingController(
      text: VietQrEmvBuilder.toBankSafeAscii(userFullName),
    );
    final bloc = context.read<NotificationIngestionBloc>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Thêm tài khoản ngân hàng nhận tiền',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Chỉ cần số tài khoản để tạo mã VietQR và tự định tuyến biến động số dư (không cần mật khẩu).',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedBin,
                        decoration: const InputDecoration(
                          labelText: 'Ngân hàng',
                        ),
                        items: kLifeOsVietQrBanks
                            .map(
                              (b) => DropdownMenuItem(
                                value: b.bin,
                                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
                                  '${b.shortName} · ${b.fullName}',
                                )),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setModalState(() => selectedBin = v);
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const Key('link_bank_account_number_input'),
                        controller: accNumberCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Số tài khoản nhận tiền',
                          hintText: 'VD: 0071000886868',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const Key('link_bank_holder_input'),
                        controller: holderCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Tên chủ tài khoản (không dấu)',
                        ),
                      ),
                      if (wallets.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: pickedWalletId,
                          decoration: const InputDecoration(
                            labelText: 'Cộng tiền vào ví',
                          ),
                          items: wallets
                              .map(
                                (w) => DropdownMenuItem(
                                  value: w.id,
                                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
                                    w.name,
                                  )),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() => pickedWalletId = v);
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        key: const Key('save_linked_bank_account_button'),
                        onPressed: () {
                          final bank = kLifeOsVietQrBanks.firstWhere(
                            (b) => b.bin == selectedBin,
                            orElse: () => kLifeOsVietQrBanks.first,
                          );
                          bloc.add(
                            LinkedBankAccountSaved(
                              userId: userId,
                              walletId: pickedWalletId,
                              bankBin: bank.bin,
                              bankCode: bank.shortName,
                              bankName: bank.fullName,
                              accountNumber: accNumberCtrl.text,
                              accountHolderName: holderCtrl.text,
                            ),
                          );
                          Navigator.of(sheetCtx).pop();
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Lưu tài khoản'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    accNumberCtrl.dispose();
    holderCtrl.dispose();
  }

  Future<void> _showConnectSePayServerSheet({
    required BuildContext context,
    required String userId,
    required List<WalletEntity> wallets,
    required String defaultWalletId,
  }) async {
    final sepayBanks = BankIntegrationCapability.catalog
        .where((b) => b.supportsWebhookCredit)
        .toList();
    var selectedBankCode = sepayBanks.first.bankCode;
    var pickedWalletId = defaultWalletId;
    final accCtrl = TextEditingController();
    final subAccCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final bloc = context.read<NotificationIngestionBloc>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final selectedCap = BankIntegrationCapability.forBankCode(
              selectedBankCode,
            );
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Liên kết đồng bộ tự động ngân hàng',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Xác minh quyền sở hữu tài khoản ngân hàng an toàn — thông tin kết nối được mã hóa bảo mật.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedBankCode,
                        decoration: const InputDecoration(
                          labelText: 'Chọn ngân hàng liên kết',
                        ),
                        items: sepayBanks
                            .map(
                              (b) => DropdownMenuItem(
                                value: b.bankCode,
                                child: Text('${b.bankCode} · ${b.bankName}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setModalState(() => selectedBankCode = v);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            ctx,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '• Tiền vào: ${selectedCap.creditSupportSummary}\n'
                          '• Tiền ra: ${selectedCap.debitSupportSummary}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const Key('sepay_connect_account_input'),
                        controller: accCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Số tài khoản ngân hàng',
                          hintText: 'VD: 1017588888',
                        ),
                      ),
                      if (selectedCap.supportsWebhookDebit) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          key: const Key('sepay_connect_subaccount_input'),
                          controller: subAccCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'Mã tài khoản phụ (nếu đăng ký nhận cả tiền ra)',
                            hintText: 'Không bắt buộc nếu chỉ nhận tiền vào',
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const Key('sepay_connect_token_input'),
                        controller: tokenCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Mã xác minh liên kết ngân hàng',
                          hintText: 'Nhập mã xác minh của bạn',
                        ),
                      ),
                      if (wallets.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: pickedWalletId,
                          decoration: const InputDecoration(
                            labelText: 'Gắn vào Ví trong ứng dụng',
                          ),
                          items: wallets
                              .map(
                                (w) => DropdownMenuItem(
                                  value: w.id,
                                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
                                    w.name,
                                  )),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() => pickedWalletId = v);
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        key: const Key('submit_sepay_verified_link_button'),
                        onPressed: () {
                          bloc.add(
                            VerifiedSePayBankLinkSubmitted(
                              userId: userId,
                              bankCode: selectedBankCode,
                              accountNumber: accCtrl.text,
                              subAccount: subAccCtrl.text,
                              linkedWalletId: pickedWalletId,
                              sepayApiToken: tokenCtrl.text,
                            ),
                          );
                          Navigator.of(sheetCtx).pop();
                        },
                        icon: const Icon(Icons.verified_user_rounded),
                        label: const Text('Xác minh & Kết nối'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    accCtrl.dispose();
    subAccCtrl.dispose();
    tokenCtrl.dispose();
  }

  Future<void> _showCreateQrOrderSheet({
    required BuildContext context,
    required String userId,
    required LinkedBankAccountEntity account,
  }) async {
    final amountCtrl = TextEditingController(text: '250000');
    final descCtrl = TextEditingController(text: 'Thu tiền nhóm');
    final bloc = context.read<NotificationIngestionBloc>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              MediaQuery.of(sheetCtx).viewInsets.bottom + AppSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tạo mã QR thu tiền tự động',
                    style: Theme.of(sheetCtx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nhận về ${account.bankName} (${account.maskedAccount}) · Tự gạch nợ khi tiền vào.',
                    style: Theme.of(sheetCtx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('qr_order_amount_input'),
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Số tiền cần thu (VND)',
                      suffixText: '₫',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('qr_order_desc_input'),
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nội dung khoản thu',
                      hintText: 'VD: Tiền điện tháng 11 / Quỹ ăn trưa',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    key: const Key('submit_create_qr_order_button'),
                    onPressed: () {
                      final amt = VndAmount.tryParseInput(amountCtrl.text) ?? 0;
                      if (amt <= 0) {
                        LifeOsTopToast.show(
                          sheetCtx,
                          'Vui lòng nhập số tiền lớn hơn 0 ₫.',
                          kind: LifeOsToastKind.warning,
                        );
                        return;
                      }
                      bloc.add(
                        PaymentOrderCreated(
                          userId: userId,
                          walletId: account.walletId,
                          bankBin: account.bankBin,
                          bankCode: account.bankCode,
                          bankName: account.bankName,
                          accountNumber: account.accountNumber,
                          accountHolderName: account.accountHolderName,
                          amountMinor: amt,
                          description: descCtrl.text,
                        ),
                      );
                      Navigator.of(sheetCtx).pop();
                    },
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Sinh mã QR thu tiền'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    amountCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _showOrderQrDetailSheet({
    required BuildContext context,
    required String userId,
    required PaymentOrderEntity order,
  }) async {
    final bloc = context.read<NotificationIngestionBloc>();
    final memoText =
        '${order.paymentCode} ${VietQrEmvBuilder.toBankSafeAscii(order.description, maxLength: 28)}'
            .trim();
    final qrUrl = VietQrEmvBuilder.buildVisualQrUrl(
      bankBin: order.bankBin,
      accountNumber: order.accountNumber,
      accountHolderName: order.accountHolderName,
      amountVnd: order.amountMinor,
      memo: memoText,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        final c = TammySemanticColors.of(sheetCtx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.description,
                              style: Theme.of(sheetCtx).textTheme.titleLarge,
                            ),
                            Text(
                              '${order.bankName} · ${order.maskedAccountLabel} (${order.accountHolderName})',
                              style: Theme.of(sheetCtx).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      SemanticStatusBadge(
                        kind: order.isPaid
                            ? SemanticStatusKind.success
                            : SemanticStatusKind.warning,
                        label: order.status.displayLabel,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: c.surfaceRaised,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.separator),
                    ),
                    child: Column(
                      children: [
                        Text(
                          VndAmount.format(order.amountMinor),
                          style: Theme.of(sheetCtx).textTheme.headlineMedium
                              ?.copyWith(
                                color: c.primary,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: order.paymentCode),
                            );
                            LifeOsTopToast.show(
                              sheetCtx,
                              'Đã sao chép mã nội dung ${order.paymentCode}',
                              kind: LifeOsToastKind.success,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: c.secondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Mã đối soát: ${order.paymentCode}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                    color: c.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.separator),
                      ),
                      child: Image.network(
                        qrUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.qr_code_2_rounded,
                                size: 54,
                                color: Colors.black54,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                order.paymentCode,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: order.emvQrPayload),
                      );
                      LifeOsTopToast.show(
                        sheetCtx,
                        'Đã sao chép nội dung mã QR.',
                        kind: LifeOsToastKind.info,
                      );
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                    label: const Text('Sao chép dữ liệu mã QR'),
                  ),
                  if (!order.isPaid) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () {
                        bloc.add(
                          PaymentOrderStatusMarked(
                            userId: userId,
                            orderId: order.id,
                            status: PaymentOrderStatus.paid,
                          ),
                        );
                        Navigator.of(sheetCtx).pop();
                      },
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Đánh dấu đã nhận tiền'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final authState = context.watch<AuthBloc>().state;
    final user = authState.user;
    final wallets = context.watch<TransactionListBloc>().state.wallets;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final preferredBankWallet = wallets
        .where((w) => w.type == WalletType.bank)
        .firstOrNull;
    final activeWalletId =
        _selectedWalletId != null &&
            wallets.any((w) => w.id == _selectedWalletId)
        ? _selectedWalletId!
        : (preferredBankWallet?.id ??
              (wallets.isNotEmpty ? wallets.first.id : 'wallet_cash_default'));

    return BlocListener<NotificationIngestionBloc, NotificationIngestionState>(
      listenWhen: (p, n) =>
          p.infoMessage != n.infoMessage ||
          p.failure != n.failure ||
          p.accountDeleted != n.accountDeleted ||
          p.latestCreatedOrder?.id != n.latestCreatedOrder?.id,
      listener: (context, state) {
        if (state.accountDeleted) {
          context.go('/login');
          return;
        }
        if (state.failure != null) {
          LifeOsTopToast.show(
            context,
            state.failure!.message,
            kind: LifeOsToastKind.error,
          );
        } else if (state.infoMessage != null) {
          LifeOsTopToast.show(
            context,
            state.infoMessage!,
            kind: LifeOsToastKind.success,
          );
        }
        final created = state.latestCreatedOrder;
        if (created != null && created.id != _lastShownOrderId) {
          _lastShownOrderId = created.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showOrderQrDetailSheet(
                context: context,
                userId: user.id,
                order: created,
              );
            }
          });
        }
      },
      child: Scaffold(
        appBar: const LiquidGlassBar(
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Ngân hàng & Đồng bộ giao dịch'),
          ),
        ),
        body: SafeArea(
          child: BlocBuilder<NotificationIngestionBloc, NotificationIngestionState>(
            builder: (context, state) {
              final consent = state.consent;
              final enabled = consent?.enabled ?? false;
              final autoConfirm = consent?.autoConfirmSignals ?? false;
              final soundboxEnabled = consent?.voiceSoundboxEnabled ?? false;
              final allowedSet = (consent?.allowedPackages ?? const <String>[])
                  .toSet();
              final defaultAccount = state.defaultBankAccount;
              final prefs =
                  state.notificationPreferences ??
                  BankingNotificationPreferencesEntity(ownerId: user.id);
              final allTx = context
                  .watch<TransactionListBloc>()
                  .state
                  .allTransactions;
              final bankMovements = allTx
                  .where(
                    (t) =>
                        t.sourceKind == TransactionSourceKind.bankWebhook ||
                        t.sourceKind == TransactionSourceKind.bankApi ||
                        t.sourceKind ==
                            TransactionSourceKind.androidNotification,
                  )
                  .where(
                    (t) =>
                        _historyFilter == 'all' ||
                        t.direction == _historyFilter,
                  )
                  .take(8)
                  .toList(growable: false);
              final timeFmt = DateFormat('dd/MM · HH:mm');

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.maxContentWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      // 1. NATIVE IN-APP VIETQR PAYMENT GATEWAY & RECEIVING ACCOUNT HERO
                      ProHeroGradientCard(
                        gradientColors: const [
                          Color(0xFF0A2240),
                          Color(0xFF124634),
                          Color(0xFF0B7A2A),
                        ],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const BananaGlassIcon(
                                  assetPath: AppAssets.icSysVietQr,
                                  fallbackIcon: Icons.qr_code_2_rounded,
                                  fallbackColor: Colors.white,
                                  size: 42,
                                  borderRadius: 12,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Cổng QR Thu Tiền & Tự Động Gạch Nợ',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        defaultAccount != null
                                            ? '${defaultAccount.bankName} · ${defaultAccount.maskedAccount}'
                                            : 'Tích hợp trực tiếp trong ứng dụng — không cần tài khoản bên thứ ba',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.85,
                                          ),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (defaultAccount == null)
                              FilledButton.icon(
                                key: const Key('open_link_bank_account_button'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF0B3B24),
                                  minimumSize: const Size.fromHeight(46),
                                ),
                                onPressed: () => _showLinkBankAccountSheet(
                                  context: context,
                                  userId: user.id,
                                  userFullName: user.fullName,
                                  wallets: wallets,
                                  defaultWalletId: activeWalletId,
                                ),
                                icon: const Icon(Icons.add_card_rounded),
                                label: const Text(
                                  'Thêm tài khoản ngân hàng nhận tiền',
                                ),
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: FilledButton.icon(
                                      key: const Key(
                                        'open_create_qr_order_button',
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: const Color(
                                          0xFF0B3B24,
                                        ),
                                        minimumSize: const Size.fromHeight(46),
                                      ),
                                      onPressed: () => _showCreateQrOrderSheet(
                                        context: context,
                                        userId: user.id,
                                        account: defaultAccount,
                                      ),
                                      icon: const Icon(
                                        Icons.qr_code_2_rounded,
                                        size: 19,
                                      ),
                                      label: const Text('Tạo mã QR thu tiền'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                        minimumSize: const Size.fromHeight(46),
                                      ),
                                      onPressed: () =>
                                          _showLinkBankAccountSheet(
                                            context: context,
                                            userId: user.id,
                                            userFullName: user.fullName,
                                            wallets: wallets,
                                            defaultWalletId:
                                                defaultAccount.walletId,
                                          ),
                                      icon: const Icon(
                                        Icons.swap_horiz_rounded,
                                        size: 17,
                                      ),
                                      label: const Text('Đổi TK'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 2. RECENT QR COLLECTION ORDERS ("Chờ nhận tiền" -> "Đã nhận đủ")
                      if (state.paymentOrders.isNotEmpty) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mã QR thu tiền gần đây (${state.paymentOrders.length})',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                ...state.paymentOrders.take(6).map((order) {
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _showOrderQrDetailSheet(
                                      context: context,
                                      userId: user.id,
                                      order: order,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            radius: 19,
                                            backgroundColor: order.isPaid
                                                ? c.successSubtle
                                                : c.warningSubtle,
                                            child: Icon(
                                              order.isPaid
                                                  ? Icons.check_circle_rounded
                                                  : Icons.qr_code_2_rounded,
                                              color: order.isPaid
                                                  ? c.success
                                                  : c.warning,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  alignment: WrapAlignment
                                                      .spaceBetween,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    Text(
                                                      '${order.description} · ${VndAmount.format(order.amountMinor)}',
                                                      softWrap: true,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    SemanticStatusBadge(
                                                      kind: order.isPaid
                                                          ? SemanticStatusKind
                                                                .success
                                                          : SemanticStatusKind
                                                                .warning,
                                                      label: order
                                                          .status
                                                          .displayLabel,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Mã: ${order.paymentCode} · ${order.bankName} ${order.maskedAccountLabel}',
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
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // 2B. NGÂN HÀNG ĐÃ KẾT NỐI (SePay Server Webhook + Local Routing)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
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
                                    'NGÂN HÀNG ĐÃ KẾT NỐI',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                        ),
                                  ),
                                  SemanticStatusBadge(
                                    kind:
                                        state.bankConnections.any(
                                          (b) => b.isVerifiedConnected,
                                        )
                                        ? SemanticStatusKind.success
                                        : SemanticStatusKind.info,
                                    label:
                                        state.bankConnections.any(
                                          (b) => b.isVerifiedConnected,
                                        )
                                        ? 'Đã liên kết tự động'
                                        : 'Qua thông báo & QR',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (state.bankConnections.isEmpty &&
                                  state.linkedBankAccounts.isEmpty)
                                Text(
                                  'Chưa có tài khoản ngân hàng nào được liên kết. Bạn có thể bật đồng bộ tự động hoặc cấp quyền đọc thông báo ngân hàng bên dưới.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ...state.bankConnections.map((conn) {
                                final walletLabel =
                                    wallets
                                        .where(
                                          (w) => w.id == conn.linkedWalletId,
                                        )
                                        .firstOrNull
                                        ?.name ??
                                    conn.linkedWalletId;
                                return Container(
                                  margin: const EdgeInsets.only(top: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: c.surfaceRaised,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: c.separator),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${conn.bankName}  ${conn.accountMasked}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14.5,
                                              ),
                                            ),
                                          ),
                                          SemanticStatusBadge(
                                            kind: conn.isVerifiedConnected
                                                ? SemanticStatusKind.success
                                                : SemanticStatusKind.warning,
                                            label: conn.status.displayLabel,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Ví liên kết: $walletLabel\n'
                                        'Tiền vào: ${conn.capabilities.creditSupportSummary}\n'
                                        'Tiền ra: ${conn.capabilities.debitSupportSummary}'
                                        '${conn.lastSyncedAt != null ? "\nĐồng bộ gần nhất: ${timeFmt.format(conn.lastSyncedAt!)}" : ""}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                      if (conn
                                          .capabilities
                                          .limitations
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '⚠ ${conn.capabilities.limitations.first}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: c.warning,
                                          ),
                                        ),
                                      ],
                                      if (conn.isVerifiedConnected)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () => context
                                                .read<
                                                  NotificationIngestionBloc
                                                >()
                                                .add(
                                                  BankConnectionDisconnected(
                                                    userId: user.id,
                                                    connectionId: conn.id,
                                                  ),
                                                ),
                                            child: const Text('Ngắt kết nối'),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                              ...state.linkedBankAccounts.map((acc) {
                                final cap =
                                    BankIntegrationCapability.forBankCode(
                                      acc.bankCode,
                                      fallbackName: acc.bankName,
                                    );
                                // Never display "Đã kết nối" for unverified manual input (Section 12 & T23)!
                                return Container(
                                  margin: const EdgeInsets.only(top: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: c.surfaceRaised,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: c.separator),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${acc.bankName}  ${acc.maskedAccount}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          SemanticStatusBadge(
                                            kind:
                                                enabled &&
                                                    state
                                                        .isNativePermissionGranted
                                                ? SemanticStatusKind.info
                                                : SemanticStatusKind.warning,
                                            label:
                                                enabled &&
                                                    state
                                                        .isNativePermissionGranted
                                                ? 'Qua Android & QR'
                                                : 'Chỉ tạo mã QR',
                                          ),
                                          IconButton(
                                            key: Key('delete_bank_acc_${acc.id}'),
                                            tooltip: 'Gỡ tài khoản ngân hàng',
                                            visualDensity: VisualDensity.compact,
                                            onPressed: () async {
                                              final ok =
                                                  await showDestructiveConfirmDialog(
                                                    context: context,
                                                    title: 'Gỡ tài khoản này?',
                                                    message:
                                                        'Tài khoản ${acc.bankName} ${acc.maskedAccount} sẽ được gỡ khỏi danh sách nhận QR.',
                                                    confirmLabel: 'Gỡ tài khoản',
                                                  );
                                              if (ok && context.mounted) {
                                                context
                                                    .read<
                                                      NotificationIngestionBloc
                                                    >()
                                                    .add(
                                                      LinkedBankAccountDeleted(
                                                        userId: user.id,
                                                        accountId: acc.id,
                                                      ),
                                                    );
                                              }
                                            },
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 19,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tiền vào: ${enabled ? "Thông báo Android & Đối soát QR" : "Chưa bật đọc thông báo"}\n'
                                        'Tiền ra: ${cap.supportsAndroidDebit && enabled ? "Tự động qua Android" : "Cần bật quyền đọc thông báo Android"}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key(
                                  'open_sepay_server_connect_button',
                                ),
                                onPressed: () => _showConnectSePayServerSheet(
                                  context: context,
                                  userId: user.id,
                                  wallets: wallets,
                                  defaultWalletId: activeWalletId,
                                ),
                                icon: const Icon(Icons.add_link_rounded),
                                label: const Text('+ Liên kết đồng bộ tự động'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 2C. LỊCH SỬ BIẾN ĐỘNG NGÂN HÀNG (Tất cả | Tiền vào | Tiền ra)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Lịch sử biến động ngân hàng',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final tab in const [
                                    ('all', 'Tất cả'),
                                    ('credit', 'Tiền vào'),
                                    ('debit', 'Tiền ra'),
                                  ])
                                    ChoiceChip(
                                      label: Text(tab.$2),
                                      selected: _historyFilter == tab.$1,
                                      onSelected: (_) => setState(
                                        () => _historyFilter = tab.$1,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (bankMovements.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'Chưa có biến động ngân hàng nào trong bộ lọc này.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                )
                              else
                                ...bankMovements.map((tx) {
                                  final isCredit = tx.direction == 'credit';
                                  final wName =
                                      tx.walletName ??
                                      wallets
                                          .where((w) => w.id == tx.walletId)
                                          .firstOrNull
                                          ?.name ??
                                      'Ví liên kết';
                                  final srcText = switch (tx.sourceKind) {
                                    TransactionSourceKind.bankWebhook =>
                                      'Đồng bộ tự động',
                                    TransactionSourceKind.bankApi =>
                                      'Đối soát ngân hàng',
                                    TransactionSourceKind.androidNotification =>
                                      'Thông báo điện thoại',
                                    _ => 'Ghi thủ công',
                                  };
                                  final verText = switch (tx.verification) {
                                    TransactionVerification.verified =>
                                      'Đã đối soát ngân hàng',
                                    TransactionVerification.matchedPaymentOrder =>
                                      'Đã khớp đơn QR',
                                    TransactionVerification.userConfirmed =>
                                      'Đã xác nhận',
                                    TransactionVerification.needsReview =>
                                      'Cần kiểm tra',
                                    _ => 'Tạm ghi nhận',
                                  };
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    onTap: () => context.push(
                                      '/auto-tx-review',
                                      extra: tx,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: isCredit
                                          ? c.successSubtle
                                          : c.warningSubtle,
                                      child: Icon(
                                        isCredit
                                            ? Icons.south_west_rounded
                                            : Icons.north_east_rounded,
                                        color: isCredit ? c.success : c.error,
                                      ),
                                    ),
                                    title: Text(
                                      '${isCredit ? "+" : "-"}${VndAmount.format(tx.amountMinor)} · ${tx.bankCode ?? ""} ${tx.accountMasked ?? ""}'
                                          .trim(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: isCredit
                                            ? c.success
                                            : c.textPrimary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${tx.merchant}\nVí: $wName · ${timeFmt.format(tx.occurredAt)} · $verText · $srcText',
                                    ),
                                    isThreeLine: true,
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 2D. CÀI ĐẶT THÔNG BÁO ĐẨY (FCM) & TÙY CHỌN RIÊNG TƯ MÀN HÌNH KHÓA
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Thông báo biến động & Màn hình khóa',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  SemanticStatusBadge(
                                    kind: state.isPushPermissionGranted
                                        ? SemanticStatusKind.success
                                        : SemanticStatusKind.info,
                                    label: state.isPushPermissionGranted
                                        ? 'Đã bật'
                                        : 'Chờ cấp quyền',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Thông báo khi có tiền vào'),
                                value: prefs.notifyCredit,
                                onChanged: (v) => context
                                    .read<NotificationIngestionBloc>()
                                    .add(
                                      BankingPrivacyPreferencesUpdated(
                                        prefs.copyWith(notifyCredit: v),
                                      ),
                                    ),
                              ),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Thông báo khi có tiền ra'),
                                value: prefs.notifyDebit,
                                onChanged: (v) => context
                                    .read<NotificationIngestionBloc>()
                                    .add(
                                      BankingPrivacyPreferencesUpdated(
                                        prefs.copyWith(notifyDebit: v),
                                      ),
                                    ),
                              ),
                              SwitchListTile.adaptive(
                                key: const Key('hide_lockscreen_amount_switch'),
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Ẩn số tiền trên màn hình khóa (Khuyên dùng)',
                                ),
                                subtitle: const Text(
                                  'Mặc định bật để bảo vệ số tiền nhạy cảm khi điện thoại đang khóa',
                                ),
                                value: prefs.hideAmountOnLockscreen,
                                onChanged: (v) => context
                                    .read<NotificationIngestionBloc>()
                                    .add(
                                      BankingPrivacyPreferencesUpdated(
                                        prefs.copyWith(
                                          hideAmountOnLockscreen: v,
                                        ),
                                      ),
                                    ),
                              ),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Ẩn tên người chuyển & nội dung giao dịch',
                                ),
                                value: prefs.hideCounterpartyAndContent,
                                onChanged: (v) => context
                                    .read<NotificationIngestionBloc>()
                                    .add(
                                      BankingPrivacyPreferencesUpdated(
                                        prefs.copyWith(
                                          hideCounterpartyAndContent: v,
                                        ),
                                      ),
                                    ),
                              ),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Bật âm thanh thông báo'),
                                value: prefs.soundEnabled,
                                onChanged: (v) => context
                                    .read<NotificationIngestionBloc>()
                                    .add(
                                      BankingPrivacyPreferencesUpdated(
                                        prefs.copyWith(soundEnabled: v),
                                      ),
                                    ),
                              ),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Nhận thông báo cho giao dịch chưa xác minh',
                                ),
                                subtitle: const Text(
                                  'Giao dịch tạm thời từ Thông báo Android',
                                ),
                                value: prefs.notifyUnverified,
                                onChanged: (v) => context
                                    .read<NotificationIngestionBloc>()
                                    .add(
                                      BankingPrivacyPreferencesUpdated(
                                        prefs.copyWith(notifyUnverified: v),
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Chỉ thông báo giao dịch từ mức tiền:',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final minOpt in const [
                                    (0, 'Mọi mức tiền'),
                                    (50000, '≥ 50.000 ₫'),
                                    (200000, '≥ 200.000 ₫'),
                                    (1000000, '≥ 1.000.000 ₫'),
                                  ])
                                    ChoiceChip(
                                      label: Text(minOpt.$2),
                                      selected:
                                          prefs.minAmountMinor == minOpt.$1,
                                      onSelected: (_) => context
                                          .read<NotificationIngestionBloc>()
                                          .add(
                                            BankingPrivacyPreferencesUpdated(
                                              prefs.copyWith(
                                                minAmountMinor: minOpt.$1,
                                              ),
                                            ),
                                          ),
                                    ),
                                ],
                              ),
                              if (!state.isPushPermissionGranted) ...[
                                const Divider(height: 22),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      sl<AndroidNotificationBridge>()
                                          .requestPostNotificationsPermission(),
                                  icon: const Icon(
                                    Icons.notifications_active_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Bật quyền nhận thông báo'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 3. NATIVE BANK NOTIFICATION RECOGNITION & VOICE SOUNDBOX CARD
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SemanticStatusBadge(
                                kind: state.isNativePermissionGranted
                                    ? SemanticStatusKind.success
                                    : SemanticStatusKind.warning,
                                label: state.isNativePermissionGranted
                                    ? 'Đã cấp quyền thông báo'
                                    : 'Chưa cấp quyền thông báo',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Tự động nhận diện tiền ra vào & Loa báo tiền',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Đọc thông báo từ 18 ngân hàng, MoMo, ZaloPay và SMS để tự cộng trừ ví, đồng bộ số dư và gạch nợ mã QR.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key(
                                  'open_android_notif_settings_button',
                                ),
                                onPressed: () => context
                                    .read<NotificationIngestionBloc>()
                                    .add(
                                      const OpenNativePermissionSettingsRequested(),
                                    ),
                                icon: Icon(
                                  state.isNativePermissionGranted
                                      ? Icons.verified_user_rounded
                                      : Icons.settings_applications_rounded,
                                ),
                                label: Text(
                                  state.isNativePermissionGranted
                                      ? 'Quản lý quyền thông báo'
                                      : 'Cấp quyền đọc thông báo',
                                ),
                              ),
                              const Divider(height: 22),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Bật nhận diện giao dịch ngân hàng',
                                ),
                                subtitle: Text(
                                  enabled ? 'Đang hoạt động' : 'Đang tắt',
                                ),
                                value: enabled,
                                onChanged: (next) {
                                  final pkgs = next && allowedSet.isEmpty
                                      ? kSupportedVnBanks
                                            .map((b) => b.packageName)
                                            .toList()
                                      : allowedSet.toList();
                                  context.read<NotificationIngestionBloc>().add(
                                    ConsentConfigUpdated(
                                      userId: user.id,
                                      enabled: next,
                                      allowedPackages: pkgs,
                                      autoConfirmSignals: autoConfirm,
                                      voiceSoundboxEnabled: soundboxEnabled,
                                    ),
                                  );
                                },
                              ),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Tự động cộng/trừ thẳng vào số dư ví',
                                ),
                                subtitle: const Text(
                                  'Tự đồng bộ cả số dư thực tế sau giao dịch',
                                ),
                                value: autoConfirm,
                                onChanged: (next) {
                                  final pkgs = allowedSet.isEmpty
                                      ? kSupportedVnBanks
                                            .map((b) => b.packageName)
                                            .toList()
                                      : allowedSet.toList();
                                  context.read<NotificationIngestionBloc>().add(
                                    ConsentConfigUpdated(
                                      userId: user.id,
                                      enabled: next ? true : enabled,
                                      allowedPackages: pkgs,
                                      autoConfirmSignals: next,
                                      voiceSoundboxEnabled: soundboxEnabled,
                                    ),
                                  );
                                },
                              ),
                              SwitchListTile.adaptive(
                                key: const Key('voice_soundbox_switch'),
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Loa đọc số tiền khi nhận chuyển khoản',
                                ),
                                subtitle: const Text(
                                  'Phát giọng đọc Tiếng Việt ngay cả khi tắt màn hình',
                                ),
                                value: soundboxEnabled,
                                onChanged: (next) {
                                  final pkgs = allowedSet.isEmpty
                                      ? kSupportedVnBanks
                                            .map((b) => b.packageName)
                                            .toList()
                                      : allowedSet.toList();
                                  context.read<NotificationIngestionBloc>().add(
                                    ConsentConfigUpdated(
                                      userId: user.id,
                                      enabled: next ? true : enabled,
                                      allowedPackages: pkgs,
                                      autoConfirmSignals: autoConfirm,
                                      voiceSoundboxEnabled: next,
                                    ),
                                  );
                                },
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: const Key('test_voice_soundbox_button'),
                                  onPressed: () => context
                                      .read<NotificationIngestionBloc>()
                                      .add(const SoundboxTestRequested()),
                                  icon: const Icon(
                                    Icons.volume_up_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Nghe thử loa báo tiền về'),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: kSupportedVnBanks.map((bank) {
                                  final selected = allowedSet.contains(
                                    bank.packageName,
                                  );
                                  return FilterChip(
                                    label: Text(bank.displayName),
                                    selected: selected,
                                    onSelected: !enabled
                                        ? null
                                        : (val) {
                                            final updated = Set<String>.from(
                                              allowedSet,
                                            );
                                            if (val) {
                                              updated.add(bank.packageName);
                                            } else {
                                              updated.remove(bank.packageName);
                                            }
                                            context
                                                .read<
                                                  NotificationIngestionBloc
                                                >()
                                                .add(
                                                  ConsentConfigUpdated(
                                                    userId: user.id,
                                                    enabled: enabled,
                                                    allowedPackages: updated
                                                        .toList(),
                                                    autoConfirmSignals:
                                                        autoConfirm,
                                                    voiceSoundboxEnabled:
                                                        soundboxEnabled,
                                                  ),
                                                );
                                          },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 4. Bank CSV Statement Import (Clean Consumer Tool — Zero Debug Sandbox)
                      Card(
                        child: ExpansionTile(
                          shape: const Border(),
                          collapsedShape: const Border(),
                          leading: Icon(
                            Icons.upload_file_rounded,
                            color: c.primary,
                          ),
                          title: const Text('Nhập sao kê ngân hàng (CSV)'),
                          subtitle: const Text(
                            'Bổ sung lịch sử giao dịch từ tệp sao kê ngân hàng',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.lg,
                          ),
                          children: [
                            TextField(
                              controller: _csvCtrl,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Dán nội dung sao kê CSV',
                                hintText: 'date,direction,amount,description',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                context.read<NotificationIngestionBloc>().add(
                                  CsvStatementImportSubmitted(
                                    userId: user.id,
                                    walletId: activeWalletId,
                                    csvContent: _csvCtrl.text,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.upload_file_rounded),
                              label: const Text('Nhập sao kê vào ví'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 5. Privacy Controls, Backup & Account Deletion
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quyền riêng tư & Dữ liệu cá nhân',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Chia sẻ khung giờ Bận/Rảnh'),
                                subtitle: const Text(
                                  'Gia đình chỉ thấy giờ bận, không thấy tên sự kiện riêng.',
                                ),
                                value: user.availabilityOptIn,
                                onChanged: (v) => context.read<AuthBloc>().add(
                                  AuthAvailabilitySharingToggled(v),
                                ),
                              ),
                              BlocBuilder<ThemeBloc, ThemeState>(
                                builder: (context, themeState) {
                                  return SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Tăng độ tương phản chữ'),
                                    value: themeState.highContrast,
                                    onChanged: (v) => context
                                        .read<ThemeBloc>()
                                        .add(HighContrastToggled(v)),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      context
                                          .read<NotificationIngestionBloc>()
                                          .add(
                                            PersonalDataExportRequested(
                                              user.id,
                                            ),
                                          );
                                    },
                                    icon: const Icon(Icons.download_rounded),
                                    label: const Text('Sao lưu dữ liệu'),
                                  ),
                                  if (state.exportedJson != null)
                                    FilledButton.tonalIcon(
                                      onPressed: () {
                                        sl<NativeAppUpdaterBridge>().shareTextFile(
                                          fileName:
                                              'LifeOS_Data_${user.id.substring(0, user.id.length < 6 ? user.id.length : 6)}.json',
                                          content: state.exportedJson!,
                                          mimeType: 'application/json',
                                          title: 'Sao lưu dữ liệu LifeOS',
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.share_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Lưu tệp sao lưu'),
                                    ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: c.error,
                                    ),
                                    onPressed: () async {
                                      final ok = await showDestructiveConfirmDialog(
                                        context: context,
                                        title: 'Xóa vĩnh viễn tài khoản?',
                                        message:
                                            'Toàn bộ ví, lịch, dữ liệu cá nhân và quyền thành viên gia đình sẽ bị xóa và không thể khôi phục.',
                                        confirmLabel: 'Xóa vĩnh viễn',
                                      );
                                      if (ok && context.mounted) {
                                        context
                                            .read<NotificationIngestionBloc>()
                                            .add(
                                              AccountDeletionConfirmed(user.id),
                                            );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.delete_forever_outlined,
                                    ),
                                    label: const Text('Xóa tài khoản'),
                                  ),
                                ],
                              ),
                              if (state.exportedJson != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Tệp sao lưu đã sẵn sàng để lưu trữ riêng tư.',
                                        softWrap: true,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                    TextButton.icon(
                                      key: const Key(
                                        'toggle_raw_export_preview_btn',
                                      ),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => setState(() {
                                        _showRawExportPreview =
                                            !_showRawExportPreview;
                                      }),
                                      icon: Icon(
                                        _showRawExportPreview
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 16,
                                      ),
                                      label: Text(
                                        _showRawExportPreview
                                            ? 'Ẩn nội dung'
                                            : 'Xem trước tệp',
                                      ),
                                    ),
                                  ],
                                ),
                                if (_showRawExportPreview)
                                  Container(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.sm,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusSm,
                                      ),
                                      border: Border.all(
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    child: SelectableText(
                                      state.exportedJson!,
                                      maxLines: 8,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

extension on PaymentOrderEntity {
  String get maskedAccountLabel {
    final clean = accountNumber.trim();
    if (clean.length <= 4) return '••••';
    return '•••• ${clean.substring(clean.length - 4)}';
  }
}
