import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../app_update/presentation/widgets/app_update_widgets.dart';
import '../../domain/entities/user_entity.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'auth_pages.dart';

class AccountProfilePage extends StatefulWidget {
  const AccountProfilePage({super.key});

  @override
  State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  String? _boundUserId;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthBloc>().state.user;
    _boundUserId = user?.id;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _syncControllersIfUserChanged(UserEntity user) {
    if (_boundUserId != user.id) {
      _boundUserId = user.id;
      _nameController.text = user.fullName;
      _phoneController.text = user.phoneNumber ?? '';
    }
  }

  Future<void> _showChangePasswordDialog(
    BuildContext context,
    UserEntity user,
  ) async {
    final currentPwdCtrl = TextEditingController();
    final newPwdCtrl = TextEditingController();
    final confirmPwdCtrl = TextEditingController();
    final hasPassword = user.hasPasswordProvider;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        var obscureCurrent = true;
        var obscureNew = true;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text(
                hasPassword
                    ? 'Đổi mật khẩu đăng nhập'
                    : 'Thiết lập mật khẩu Email',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasPassword) ...[
                      TextField(
                        key: const Key('current_password_field'),
                        controller: currentPwdCtrl,
                        obscureText: obscureCurrent,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu hiện tại',
                          prefixIcon: const Icon(Icons.lock_clock_outlined),
                          suffixIcon: IconButton(
                            onPressed: () => setModalState(
                              () => obscureCurrent = !obscureCurrent,
                            ),
                            icon: Icon(
                              obscureCurrent
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    TextField(
                      key: const Key('new_password_field'),
                      controller: newPwdCtrl,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu mới (tối thiểu 8 ký tự)',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setModalState(() => obscureNew = !obscureNew),
                          icon: Icon(
                            obscureNew
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      key: const Key('confirm_new_password_field'),
                      controller: confirmPwdCtrl,
                      obscureText: obscureNew,
                      decoration: const InputDecoration(
                        labelText: 'Xác nhận mật khẩu mới',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton.icon(
                  key: const Key('submit_password_change_button'),
                  onPressed: () {
                    final curr = currentPwdCtrl.text;
                    final next = newPwdCtrl.text;
                    final confirm = confirmPwdCtrl.text;
                    Navigator.of(dialogCtx).pop();
                    context.read<AuthBloc>().add(
                      AuthPasswordChangeSubmitted(
                        currentPassword: hasPassword ? curr : null,
                        newPassword: next,
                        confirmPassword: confirm,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    hasPassword ? 'Cập nhật mật khẩu' : 'Tạo mật khẩu',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    currentPwdCtrl.dispose();
    newPwdCtrl.dispose();
    confirmPwdCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (prev, curr) =>
          prev.failure != curr.failure ||
          prev.infoMessage != curr.infoMessage ||
          prev.status != curr.status,
      listener: (context, state) {
        if (state.status == AuthStatus.unauthenticated) {
          context.go('/login');
          return;
        }
        if (state.failure != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('⚠ ${state.failure!.message}')),
          );
        } else if (state.infoMessage != null) {
          LifeOsTopToast.fromSnackBar(
            context,
            SnackBar(content: Text('✓ ${state.infoMessage!}')),
          );
        }
      },
      builder: (context, state) {
        final user = state.user;
        if (user == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        _syncControllersIfUserChanged(user);

        final providerSummary = user.isGoogleLinked && user.hasPasswordProvider
            ? 'Google + Email'
            : user.isGoogleLinked
            ? 'Tài khoản Google'
            : 'Email & Mật khẩu';

        return Scaffold(
          appBar: const LiquidGlassBar(
            title: Text('Hồ sơ & Bảo mật Tài khoản'),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.maxContentWidth,
                ),
                child: ListView(
                  key: const Key('account_profile_list_view'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xxl,
                  ),
                  children: [
                    // 1. Hero Identity Card
                    ProHeroGradientCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              UserAvatarBadge(user: user, radius: 30),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.fullName,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      user.email,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: Colors.white.withValues(
                                          alpha: 0.86,
                                        ),
                                      ),
                                    ),
                                    if (user.phoneNumber != null &&
                                        user.phoneNumber!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        user.phoneNumber!,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Colors.white.withValues(
                                            alpha: 0.78,
                                          ),
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (user.isGoogleLinked)
                                const ProGlassStatPill(
                                  icon: Icons.verified_rounded,
                                  label: 'Google',
                                  value: 'Đã liên kết',
                                  iconColor: Color(0xFF86EFAC),
                                ),
                              if (user.hasPasswordProvider)
                                const ProGlassStatPill(
                                  icon: Icons.password_rounded,
                                  label: 'Mật khẩu',
                                  value: 'Đang bảo vệ',
                                  iconColor: Color(0xFF93C5FD),
                                ),
                              ProGlassStatPill(
                                icon: user.emailVerified
                                    ? Icons.mark_email_read_rounded
                                    : Icons.mark_email_unread_rounded,
                                label: 'Xác thực Email',
                                value: user.emailVerified
                                    ? 'Đã xác minh'
                                    : 'Chờ xác minh',
                                iconColor: user.emailVerified
                                    ? const Color(0xFF86EFAC)
                                    : const Color(0xFFFDE047),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // 2. Email Verification Banner (if pending)
                    if (!user.emailVerified) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SemanticStatusBadge(
                                kind: SemanticStatusKind.warning,
                                label: 'Khuyến nghị xác thực địa chỉ Email',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Xác thực email giúp bạn khôi phục tài khoản và nhận cảnh báo bảo mật khi đăng nhập trên thiết bị mới.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.tonalIcon(
                                    key: const Key(
                                      'resend_verification_email_button',
                                    ),
                                    onPressed: state.isSubmitting
                                        ? null
                                        : () => context.read<AuthBloc>().add(
                                            const AuthEmailVerificationRequested(),
                                          ),
                                    icon: const Icon(
                                      Icons.outgoing_mail,
                                      size: 18,
                                    ),
                                    label: const Text('Gửi lại email xác thực'),
                                  ),
                                  OutlinedButton.icon(
                                    key: const Key(
                                      'refresh_verification_status_button',
                                    ),
                                    onPressed: state.isSubmitting
                                        ? null
                                        : () => context.read<AuthBloc>().add(
                                            const AuthUserReloadRequested(),
                                          ),
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Tôi đã xác nhận'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // 3. 2x2 Security Bento Grid
                    Row(
                      children: [
                        Expanded(
                          child: ProBentoTile(
                            icon: Icons.fingerprint_rounded,
                            accentColor: c.primary,
                            title: 'Phương thức đăng nhập',
                            metric: providerSummary,
                            badgeText: 'Đa thiết bị',
                            statusKind: SemanticStatusKind.success,
                            onTap: () =>
                                _showChangePasswordDialog(context, user),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ProBentoTile(
                            icon: Icons.shield_moon_rounded,
                            accentColor: c.secondary,
                            title: 'Quyền riêng tư',
                            metric: 'Đã bảo vệ',
                            badgeText: 'An toàn',
                            statusKind: SemanticStatusKind.info,
                            onTap: () => context.push('/notifications-privacy'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // 4. Personal Profile Information Editor
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Thông tin Hồ sơ Cá nhân',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tên hiển thị của bạn xuất hiện trên bảng công việc và sổ chia tiền Gia đình / Hội nhóm.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              key: const Key('profile_name_field'),
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Họ và tên hiển thị',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(
                              key: const Key('profile_phone_field'),
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Số điện thoại liên hệ',
                                hintText: '0901 234 567',
                                prefixIcon: Icon(Icons.phone_iphone_rounded),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FilledButton.icon(
                              key: const Key('save_profile_button'),
                              onPressed: state.isSubmitting
                                  ? null
                                  : () {
                                      context.read<AuthBloc>().add(
                                        AuthProfileUpdateSubmitted(
                                          fullName: _nameController.text,
                                          phoneNumber: _phoneController.text,
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.save_outlined, size: 18),
                              label: const Text('Lưu cập nhật hồ sơ'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // 5. Sign-in Providers & Password Security
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Liên kết Tài khoản & Mật khẩu',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            if (user.isGoogleLinked)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: c.successSubtle,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: const GoogleBrandMark(size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Tài khoản Google đã được liên kết',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          Text(
                                            'Đăng nhập nhanh 1 chạm bằng ${user.email}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: c.success,
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              Text(
                                'Liên kết Google để đăng nhập 1 chạm mà không cần nhớ mật khẩu:',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 10),
                              GoogleAuthButton(
                                key: const Key('link_google_account_button'),
                                label: 'Liên kết tài khoản Google',
                                isLoading: state.isSubmitting,
                                onPressed: () => context.read<AuthBloc>().add(
                                  const AuthGoogleLinkRequested(),
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: [
                                OutlinedButton.icon(
                                  key: const Key('open_change_password_button'),
                                  onPressed: state.isSubmitting
                                      ? null
                                      : () => _showChangePasswordDialog(
                                          context,
                                          user,
                                        ),
                                  icon: const Icon(Icons.lock_reset_rounded),
                                  label: Text(
                                    user.hasPasswordProvider
                                        ? 'Đổi mật khẩu'
                                        : 'Thiết lập mật khẩu Email',
                                  ),
                                ),
                                if (user.email.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: state.isSubmitting
                                        ? null
                                        : () => context.read<AuthBloc>().add(
                                            AuthPasswordResetRequested(
                                              user.email,
                                            ),
                                          ),
                                    icon: const Icon(
                                      Icons.mail_lock_outlined,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Gửi link đặt lại qua Email',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // 6. App Version & OTA Self-Update Card
                    const AppUpdateSettingsCard(),
                    const SizedBox(height: AppSpacing.md),

                    // 7. Privacy Center & Sign Out
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: c.primarySubtle,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.shield_outlined,
                                  color: c.primary,
                                ),
                              ),
                              title: const Text('Ngân hàng & Quyền riêng tư'),
                              subtitle: const Text(
                                'Quyền thông báo, sao lưu & xóa tài khoản',
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () =>
                                  context.push('/notifications-privacy'),
                            ),
                            const Divider(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                key: const Key('profile_sign_out_button'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.error,
                                ),
                                onPressed: () => context.read<AuthBloc>().add(
                                  const AuthSignOutRequested(),
                                ),
                                icon: const Icon(Icons.logout_rounded),
                                label: const Text(
                                  'Đăng xuất khỏi thiết bị này',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Reusable circular avatar showing Google photoUrl (with error fallback) or crisp initials.
class UserAvatarBadge extends StatelessWidget {
  final UserEntity user;
  final double radius;

  const UserAvatarBadge({super.key, required this.user, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final photo = user.photoUrl;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.primary, c.secondary],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: photo != null && photo.isNotEmpty
          ? Image.network(
              photo,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _InitialsCenter(
                initials: user.initials,
                fontSize: radius * 0.78,
              ),
            )
          : _InitialsCenter(initials: user.initials, fontSize: radius * 0.78),
    );
  }
}

class _InitialsCenter extends StatelessWidget {
  final String initials;
  final double fontSize;

  const _InitialsCenter({required this.initials, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}
