import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/theme_bloc.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../bloc/notification_ingestion_bloc.dart';

class NotificationsPrivacyPage extends StatefulWidget {
  const NotificationsPrivacyPage({super.key});

  @override
  State<NotificationsPrivacyPage> createState() => _NotificationsPrivacyPageState();
}

class _NotificationsPrivacyPageState extends State<NotificationsPrivacyPage> {
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

  @override
  void dispose() {
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

    final defaultWalletId = wallets.isNotEmpty ? wallets.first.id : 'wallet_cash_default';

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
        appBar: const LiquidGlassBar(title: Text('Tự động hóa Ngân hàng & Quyền riêng tư')),
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SemanticStatusBadge(
                                kind: SemanticStatusKind.info,
                                label: 'Prominent Disclosure · Tuân thủ Google Play & Luật 91/2025',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Nhận diện biến động số dư trên Android',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '• Chỉ lắng nghe những ứng dụng ngân hàng bạn chủ động bật bên dưới.\n'
                                '• Tự động chặn và hủy ngay trên thiết bị mọi thông báo chứa mã OTP, PIN, CVV hoặc mật khẩu.\n'
                                '• Dữ liệu trích xuất được gắn nhãn PROVISIONAL để bạn xác nhận trước khi tính vào sổ cái.\n'
                                '• Khi tắt quyền, hệ thống dừng thu thập ngay lập tức.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const Divider(height: 24),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Cho phép nhận diện thông báo ngân hàng'),
                                subtitle: Text(
                                  enabled
                                      ? 'Đang bật theo allowlist'
                                      : 'Đang tắt mặc định (An toàn)',
                                ),
                                value: enabled,
                                onChanged: (next) {
                                  final pkgs = next && allowedSet.isEmpty
                                      ? <String>[kSupportedVnBanks.first.packageName]
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Kiểm thử Pipeline Phân tích & Chặn OTP Trực tiếp',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _selectedPkg,
                                items: kSupportedVnBanks
                                    .map((b) => DropdownMenuItem(
                                          value: b.packageName,
                                          child: Text('${b.displayName} (${b.packageName})'),
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
                                          defaultWalletId: defaultWalletId,
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
                                'Phương án dự phòng chuẩn cho cả Android & iOS. Nhập lại cùng tệp CSV sẽ tự động bỏ qua các dòng đã ghi sổ.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextField(
                                controller: _csvCtrl,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Dữ liệu CSV (YYYY-MM-DD,debit|credit,amount,description)',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              OutlinedButton.icon(
                                onPressed: () {
                                  context.read<NotificationIngestionBloc>().add(
                                        CsvStatementImportSubmitted(
                                          userId: user.id,
                                          walletId: defaultWalletId,
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
                                    onPressed: () => context
                                        .read<NotificationIngestionBloc>()
                                        .add(PersonalDataExportRequested(user.id)),
                                    icon: const Icon(Icons.download_rounded),
                                    label: const Text('Xuất dữ liệu cá nhân (JSON)'),
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
