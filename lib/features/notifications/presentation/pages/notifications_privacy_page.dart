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
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('⚠ ${state.failure!.message}')));
        } else if (state.infoMessage != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('✓ ${state.infoMessage!}')));
        }
      },
      child: Scaffold(
        appBar: const LiquidGlassBar(
          title: Text('Kết nối Ngân hàng SePay & Quyền riêng tư'),
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
                            'Hồ sơ & Bảo mật (${user.fullName})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            'Liên kết Google, xác thực Email (${user.email}) & đổi mật khẩu',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => context.push('/account-profile'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 2. REAL SEPAY OFFICIAL REST API LIVE SYNC CARD
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
                                        'Đồng bộ Trực tiếp SePay Banking API',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        state.savedSePayMaskedToken != null
                                            ? 'Đã lưu Token: ${state.savedSePayMaskedToken}'
                                            : 'Kết nối thực tới my.sepay.vn/userapi/transactions/list',
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
                                  labelText: 'Ví nhận giao dịch đối soát SePay',
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
                                    ? 'Nhập API Token mới (hoặc để trống dùng Token đã lưu)'
                                    : 'SePay API Token (từ my.sepay.vn → API Access)',
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
                                state.isSyncingSePay
                                    ? 'Đang tải sao kê thực từ SePay...'
                                    : 'Đồng bộ Giao dịch Thực từ SePay',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 3. REAL ANDROID NOTIFICATION LISTENER SERVICE CARD
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  const SemanticStatusBadge(
                                    kind: SemanticStatusKind.info,
                                    label: 'Tuân thủ Google Play & Luật BVDLCN 91/2025',
                                  ),
                                  SemanticStatusBadge(
                                    kind: state.isNativePermissionGranted
                                        ? SemanticStatusKind.success
                                        : SemanticStatusKind.warning,
                                    label: state.isNativePermissionGranted
                                        ? 'Quyền Hệ thống Android: ĐÃ CẤP'
                                        : 'Quyền Hệ thống Android: CHƯA CẤP',
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Tự động bắt thông báo biến động số dư Android',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '• Dịch vụ nền BankNotificationListenerService tự động bắt thông báo thực từ VCB, MB, Techcombank, BIDV, VietinBank, ACB, VPBank, TPBank, MoMo.\n'
                                '• Lọc chặn cứng mã OTP, SmartOTP, CVV, PIN ngay trên thiết bị trước khi xử lý.\n'
                                '• Ghi nhận trạng thái PROVISIONAL và tự động nâng cấp lên VERIFIED khi đồng bộ SePay.',
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
                                      ? 'Quản lý Quyền Truy cập Thông báo Android'
                                      : 'Bước 1: Cấp quyền Đọc Thông báo trên Android',
                                ),
                              ),
                              const Divider(height: 24),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Bước 2: Bật lắng nghe theo danh sách ngân hàng'),
                                subtitle: Text(
                                  enabled
                                      ? 'Đang hoạt động trên toàn ứng dụng'
                                      : 'Đang tắt mặc định (An toàn)',
                                ),
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
                                    label: Text(
                                      '${bank.displayName} (${bank.supportsDebit ? "Vào/Ra" : "Chỉ tiền vào"})',
                                    ),
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

                      // 4. Live Parser & OTP Redactor Sandbox
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Kiểm thử Pipeline Phân tích SMS & Chặn OTP',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _selectedPkg,
                                items: kSupportedVnBanks
                                    .map((b) => DropdownMenuItem(
                                          value: b.packageName,
                                          child: Text(
                                            '${b.displayName} (${b.packageName})',
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
                                  labelText: 'Nội dung thông báo ngân hàng',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              FilledButton.icon(
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
                                label: const Text('Gửi qua Pipeline Nhận diện'),
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
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 5. CSV Statement Import
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Nhập Sao kê Ngân hàng CSV (Khử trùng lặp SHA-256)',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Dùng trên mọi thiết bị Android & iOS. Nhập lại cùng tệp CSV sẽ tự động bỏ qua các dòng đã ghi sổ.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextField(
                                controller: _csvCtrl,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Dữ liệu CSV (YYYY-MM-DD,debit|credit,amount,description)',
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
                                label: const Text('Nhập Sao kê CSV vào Sổ cái'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 6. Privacy Controls, JSON Export & Account Deletion
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quyền Chia sẻ Lịch, Giao diện, Xuất & Xóa Dữ liệu Cá nhân',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Chia sẻ khung giờ Bận/Rảnh (Free/Busy Opt-in)'),
                                subtitle: const Text(
                                  'Tắt mặc định. Khi bật, gia đình chỉ thấy khung giờ bận mà không thấy tiêu đề sự kiện riêng.',
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
                                    title: const Text(
                                      'Chế độ Tăng độ tương phản (WCAG High Contrast)',
                                    ),
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
                                    label: const Text('Xuất dữ liệu cá nhân (JSON)'),
                                  ),
                                  if (state.exportedJson != null)
                                    FilledButton.tonalIcon(
                                      onPressed: () {
                                        sl<NativeAppUpdaterBridge>().shareTextFile(
                                          fileName: 'LifeOS_Data_${user.id.substring(0, 6)}.json',
                                          content: state.exportedJson!,
                                          mimeType: 'application/json',
                                          title: 'Xuất Dữ liệu Cá nhân Life OS',
                                        );
                                      },
                                      icon: const Icon(Icons.share_rounded, size: 18),
                                      label: const Text('Chia sẻ / Lưu tệp JSON'),
                                    ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: c.error),
                                    onPressed: () async {
                                      final ok = await showDestructiveConfirmDialog(
                                        context: context,
                                        title: 'Xóa vĩnh viễn tài khoản & dữ liệu cá nhân?',
                                        message:
                                            'Toàn bộ ví, lịch riêng, thiết lập và quyền thành viên gia đình của bạn sẽ bị xóa theo Luật BVDLCN 91/2025/QH15. Thao tác không thể hoàn tác.',
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
