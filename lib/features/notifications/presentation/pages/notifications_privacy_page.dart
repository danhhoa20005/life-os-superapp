import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/theme_bloc.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/services/native_app_updater_bridge.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../bloc/notification_ingestion_bloc.dart';

class NotificationsPrivacyPage extends StatefulWidget {
  const NotificationsPrivacyPage({super.key});

  @override
  State<NotificationsPrivacyPage> createState() => _NotificationsPrivacyPageState();
}

class _NotificationsPrivacyPageState extends State<NotificationsPrivacyPage>
    with WidgetsBindingObserver {
  final TextEditingController _sePayTokenCtrl = TextEditingController();
  final TextEditingController _sampleBodyCtrl = TextEditingController(
    text:
        'TK 1029***88 GD: -85.000VND 22/11/2026 12:15. ND: Quan Com Tam Cali. SD: 9.200.000VND',
  );
  final TextEditingController _csvCtrl = TextEditingController(
    text: 'date,direction,amount,description\n'
        '2026-11-22,debit,125000,Siêu thị Co.opmart\n'
        '2026-11-22,credit,2500000,Thưởng dự án tháng 11',
  );
  String _selectedPkg = kSupportedVnBanks.first.packageName;
  String? _selectedWalletId;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context
          .read<NotificationIngestionBloc>()
          .add(const NativePermissionStatusRefreshed());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sePayTokenCtrl.dispose();
    _sampleBodyCtrl.dispose();
    _csvCtrl.dispose();
    super.dispose();
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

    final preferredBankWallet = wallets.where((w) => w.type == WalletType.bank).firstOrNull;
    final activeWalletId = _selectedWalletId != null &&
            wallets.any((w) => w.id == _selectedWalletId)
        ? _selectedWalletId!
        : (preferredBankWallet?.id ??
            (wallets.isNotEmpty ? wallets.first.id : 'wallet_cash_default'));

    return BlocListener<NotificationIngestionBloc, NotificationIngestionState>(
      listenWhen: (p, c) =>
          p.infoMessage != c.infoMessage ||
          p.failure != c.failure ||
          p.accountDeleted != c.accountDeleted,
      listener: (context, state) {
        if (state.accountDeleted) {
          context.go('/login');
          return;
        }
        if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(context, SnackBar(content: Text('⚠ ${state.failure!.message}')));
        } else if (state.infoMessage != null) {
          LifeOsTopToast.fromSnackBar(context, SnackBar(content: Text('✓ ${state.infoMessage!}')));
        }
      },
      child: Scaffold(
        appBar: const LiquidGlassBar(
          title: Text('Ngân hàng & Quyền riêng tư'),
        ),
        body: SafeArea(
          child: BlocBuilder<NotificationIngestionBloc, NotificationIngestionState>(
            builder: (context, state) {
              final consent = state.consent;
              final enabled = consent?.enabled ?? false;
              final allowedSet = (consent?.allowedPackages ?? const <String>[]).toSet();

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      // 1. Account Security & Profile Shortcut
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: c.primarySubtle,
                            child: Icon(Icons.manage_accounts_rounded, color: c.primary),
                          ),
                          title: Text(
                            'Tài khoản (${user.fullName})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(user.email),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => context.push('/account-profile'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 2. SEPAY LIVE SYNC CARD
                      ProHeroGradientCard(
                        gradientColors: const [
                          Color(0xFF0A2240),
                          Color(0xFF14427A),
                          Color(0xFF0B7A2A),
                        ],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const BananaGlassIcon(
                                  assetPath: AppAssets.icSysVietQr,
                                  fallbackIcon: Icons.sync_lock_rounded,
                                  fallbackColor: Colors.white,
                                  size: 42,
                                  borderRadius: 12,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Kết nối ngân hàng tự động (SePay)',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        state.savedSePayMaskedToken != null
                                            ? 'Đã kết nối: ${state.savedSePayMaskedToken}'
                                            : 'Tự động cập nhật giao dịch ngân hàng mới vào ví',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.82),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (wallets.isNotEmpty) ...[
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: activeWalletId,
                                dropdownColor: const Color(0xFF0F294A),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Ví nhận giao dịch',
                                  labelStyle:
                                      TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.12),
                                  isDense: true,
                                ),
                                items: wallets
                                    .map(
                                      (w) => DropdownMenuItem(
                                        value: w.id,
                                        child: Text(
                                          w.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setState(() => _selectedWalletId = v);
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                            TextField(
                              key: const Key('sepay_api_token_field'),
                              controller: _sePayTokenCtrl,
                              obscureText: _obscureToken,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: state.savedSePayMaskedToken != null
                                    ? 'Đổi mã kết nối (để trống nếu giữ nguyên)'
                                    : 'Mã kết nối SePay',
                                labelStyle:
                                    TextStyle(color: Colors.white.withValues(alpha: 0.82)),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.12),
                                isDense: true,
                                suffixIcon: IconButton(
                                  onPressed: () =>
                                      setState(() => _obscureToken = !_obscureToken),
                                  icon: Icon(
                                    _obscureToken
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const Key('sepay_sync_now_button'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(46),
                              ),
                              onPressed: state.isSyncingSePay
                                  ? null
                                  : () {
                                      context.read<NotificationIngestionBloc>().add(
                                            SePayLiveSyncSubmitted(
                                              userId: user.id,
                                              walletId: activeWalletId,
                                              apiTokenOverride:
                                                  _sePayTokenCtrl.text.trim().isEmpty
                                                      ? null
                                                      : _sePayTokenCtrl.text.trim(),
                                            ),
                                          );
                                      _sePayTokenCtrl.clear();
                                    },
                              icon: state.isSyncingSePay
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.cloud_sync_rounded),
                              label: Text(
                                state.isSyncingSePay ? 'Đang đồng bộ...' : 'Đồng bộ ngay',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 3. ANDROID BANK NOTIFICATION CARD
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
                                'Đọc thông báo biến động số dư',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tự động ghi nhận chi tiêu từ ứng dụng ngân hàng và bỏ qua tin nhắn chứa mã OTP.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key('open_android_notif_settings_button'),
                                onPressed: () => context
                                    .read<NotificationIngestionBloc>()
                                    .add(const OpenNativePermissionSettingsRequested()),
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
                              const Divider(height: 24),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Tự động nhận diện giao dịch mới'),
                                subtitle: Text(enabled ? 'Đang bật' : 'Đang tắt'),
                                value: enabled,
                                onChanged: (next) {
                                  final pkgs = next && allowedSet.isEmpty
                                      ? kSupportedVnBanks.map((b) => b.packageName).toList()
                                      : allowedSet.toList();
                                  context.read<NotificationIngestionBloc>().add(
                                        ConsentConfigUpdated(
                                          userId: user.id,
                                          enabled: next,
                                          allowedPackages: pkgs,
                                        ),
                                      );
                                },
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: kSupportedVnBanks.map((bank) {
                                  final selected = allowedSet.contains(bank.packageName);
                                  return FilterChip(
                                    label: Text(bank.displayName),
                                    selected: selected,
                                    onSelected: !enabled
                                        ? null
                                        : (val) {
                                            final updated = Set<String>.from(allowedSet);
                                            if (val) {
                                              updated.add(bank.packageName);
                                            } else {
                                              updated.remove(bank.packageName);
                                            }
                                            context.read<NotificationIngestionBloc>().add(
                                                  ConsentConfigUpdated(
                                                    userId: user.id,
                                                    enabled: enabled,
                                                    allowedPackages: updated.toList(),
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

                      // 4. Advanced Tools (CSV Import & Notification Test) — Cleanly Collapsed
                      Card(
                        child: ExpansionTile(
                          shape: const Border(),
                          collapsedShape: const Border(),
                          leading: Icon(Icons.tune_rounded, color: c.primary),
                          title: const Text('Nhập sao kê CSV & Thử nghiệm nâng cao'),
                          subtitle: const Text('Nhập tệp sao kê ngân hàng hoặc thử mẫu tin nhắn'),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.lg,
                          ),
                          children: [
                            Text(
                              'Nhập sao kê CSV',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            TextField(
                              controller: _csvCtrl,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Nội dung CSV sao kê',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            OutlinedButton.icon(
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
                              label: const Text('Nhập sao kê'),
                            ),
                            const Divider(height: 24),
                            Text(
                              'Thử nhận diện nội dung thông báo',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _selectedPkg,
                              items: kSupportedVnBanks
                                  .map((b) => DropdownMenuItem(
                                        value: b.packageName,
                                        child: Text(
                                          b.displayName,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedPkg = v);
                              },
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(
                              controller: _sampleBodyCtrl,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Nội dung tin nhắn mẫu',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                context.read<NotificationIngestionBloc>().add(
                                      BankNotificationSignalReceived(
                                        userId: user.id,
                                        defaultWalletId: activeWalletId,
                                        packageName: _selectedPkg,
                                        title: 'Biến động số dư',
                                        body: _sampleBodyCtrl.text,
                                      ),
                                    );
                              },
                              icon: const Icon(Icons.bolt_rounded),
                              label: const Text('Kiểm tra thử'),
                            ),
                            if (state.lastOutcome != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              SemanticStatusBadge(
                                kind: state.lastOutcome!.kind.name.contains('blocked')
                                    ? SemanticStatusKind.error
                                    : SemanticStatusKind.success,
                                label: state.lastOutcome!.message,
                              ),
                            ],
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
                                onChanged: (v) => context
                                    .read<AuthBloc>()
                                    .add(AuthAvailabilitySharingToggled(v)),
                              ),
                              BlocBuilder<ThemeBloc, ThemeState>(
                                builder: (context, themeState) {
                                  return SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Tăng độ tương phản chữ'),
                                    value: themeState.highContrast,
                                    onChanged: (v) =>
                                        context.read<ThemeBloc>().add(HighContrastToggled(v)),
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
                                          .add(PersonalDataExportRequested(user.id));
                                    },
                                    icon: const Icon(Icons.download_rounded),
                                    label: const Text('Sao lưu dữ liệu'),
                                  ),
                                  if (state.exportedJson != null)
                                    FilledButton.tonalIcon(
                                      onPressed: () {
                                        sl<NativeAppUpdaterBridge>().shareTextFile(
                                          fileName: 'LifeOS_Data_${user.id.substring(0, 6)}.json',
                                          content: state.exportedJson!,
                                          mimeType: 'application/json',
                                          title: 'Sao lưu dữ liệu LifeOS',
                                        );
                                      },
                                      icon: const Icon(Icons.share_rounded, size: 18),
                                      label: const Text('Lưu tệp sao lưu'),
                                    ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: c.error),
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
                                            .add(AccountDeletionConfirmed(user.id));
                                      }
                                    },
                                    icon: const Icon(Icons.delete_forever_outlined),
                                    label: const Text('Xóa tài khoản'),
                                  ),
                                ],
                              ),
                              if (state.exportedJson != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                    border: Border.all(color: Colors.grey.shade400),
                                  ),
                                  child: SelectableText(
                                    state.exportedJson!,
                                    maxLines: 8,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
