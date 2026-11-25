import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/utils/privacy_mask_formatter.dart';
import '../../../../core/utils/user_behavior_prefs.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../app_update/presentation/widgets/app_update_widgets.dart';
import '../../../family/domain/repositories/family_repository.dart';
import '../../../notifications/domain/repositories/notifications_repository.dart';
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

({int score, String label, Color color}) _evaluatePasswordStrength(String pwd) {
  if (pwd.isEmpty) {
    return (
      score: 0,
      label: 'Nhập tối thiểu 8 ký tự',
      color: const Color(0xFF98A2B3),
    );
  }
  var pts = 0;
  if (pwd.length >= 8) pts++;
  if (RegExp(r'[A-Z]').hasMatch(pwd) && RegExp(r'[a-z]').hasMatch(pwd)) {
    pts++;
  }
  if (RegExp(r'[0-9]').hasMatch(pwd)) pts++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(pwd) || pwd.length >= 12) pts++;

  return switch (pts) {
    0 || 1 => (
      score: 1,
      label: 'Độ mạnh: Yếu',
      color: const Color(0xFFDC2626),
    ),
    2 => (
      score: 2,
      label: 'Độ mạnh: Trung bình',
      color: const Color(0xFFD97706),
    ),
    3 => (
      score: 3,
      label: 'Độ mạnh: Mạnh',
      color: const Color(0xFF2563EB),
    ),
    _ => (
      score: 4,
      label: 'Độ mạnh: Rất mạnh',
      color: const Color(0xFF12B847),
    ),
  };
}

class _ChangePasswordSecurityDialog extends StatefulWidget {
  final bool hasPassword;
  final void Function(String? currentPwd, String newPwd, String confirmPwd)
  onSubmit;

  const _ChangePasswordSecurityDialog({
    required this.hasPassword,
    required this.onSubmit,
  });

  @override
  State<_ChangePasswordSecurityDialog> createState() =>
      _ChangePasswordSecurityDialogState();
}

class _ChangePasswordSecurityDialogState
    extends State<_ChangePasswordSecurityDialog> {
  final TextEditingController _currentPwdCtrl = TextEditingController();
  final TextEditingController _newPwdCtrl = TextEditingController();
  final TextEditingController _confirmPwdCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  @override
  void dispose() {
    _currentPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final strength = _evaluatePasswordStrength(_newPwdCtrl.text);

    return AlertDialog(
      title: Text(
        widget.hasPassword
            ? 'Đổi mật khẩu đăng nhập'
            : 'Thiết lập mật khẩu Email',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.hasPassword) ...[
              TextField(
                key: const Key('current_password_field'),
                controller: _currentPwdCtrl,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu hiện tại',
                  prefixIcon: const Icon(Icons.lock_clock_outlined),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                    icon: Icon(
                      _obscureCurrent
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
              controller: _newPwdCtrl,
              obscureText: _obscureNew,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Mật khẩu mới',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  icon: Icon(
                    _obscureNew
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(4, (idx) {
                final active = idx < strength.score;
                return Expanded(
                  child: Container(
                    height: 5,
                    margin: EdgeInsets.only(right: idx < 3 ? 5 : 0),
                    decoration: BoxDecoration(
                      color: active ? strength.color : c.separator,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 4),
            Text(
              strength.label,
              style: TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                color: strength.score == 0 ? c.textSecondary : strength.color,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('confirm_new_password_field'),
              controller: _confirmPwdCtrl,
              obscureText: _obscureNew,
              decoration: const InputDecoration(
                labelText: 'Nhập lại mật khẩu',
                prefixIcon: Icon(Icons.verified_user_outlined),
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
        FilledButton.icon(
          key: const Key('submit_password_change_button'),
          onPressed: () {
            final curr = _currentPwdCtrl.text;
            final next = _newPwdCtrl.text;
            final confirm = _confirmPwdCtrl.text;
            if (widget.hasPassword && curr.isEmpty) {
              LifeOsTopToast.show(
                context,
                'Vui lòng nhập mật khẩu hiện tại.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            if (next.length < 8) {
              LifeOsTopToast.show(
                context,
                'Mật khẩu mới cần tối thiểu 8 ký tự.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            if (next != confirm) {
              LifeOsTopToast.show(
                context,
                'Mật khẩu xác nhận không khớp.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            Navigator.of(context).pop();
            widget.onSubmit(widget.hasPassword ? curr : null, next, confirm);
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(
            widget.hasPassword ? 'Cập nhật mật khẩu' : 'Tạo mật khẩu',
          ),
        ),
      ],
    );
  }
}

class _AppPinSecurityDialog extends StatefulWidget {
  final bool hadPin;
  final ValueChanged<bool> onPinChanged;

  const _AppPinSecurityDialog({
    required this.hadPin,
    required this.onPinChanged,
  });

  @override
  State<_AppPinSecurityDialog> createState() => _AppPinSecurityDialogState();
}

class _AppPinSecurityDialogState extends State<_AppPinSecurityDialog> {
  final TextEditingController _currentPinCtrl = TextEditingController();
  final TextEditingController _newPinCtrl = TextEditingController();
  final TextEditingController _confirmPinCtrl = TextEditingController();

  @override
  void dispose() {
    _currentPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.hadPin ? 'Quản lý mã PIN bảo vệ' : 'Thiết lập mã PIN 4–6 số',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thiết lập mã số cá nhân để khóa nhanh dữ liệu riêng tư trên ứng dụng.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (widget.hadPin) ...[
              TextField(
                key: const Key('pin_current_input'),
                controller: _currentPinCtrl,
                obscureText: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Mã PIN hiện tại',
                  counterText: '',
                  prefixIcon: Icon(Icons.lock_clock_outlined),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              key: const Key('pin_new_input'),
              controller: _newPinCtrl,
              obscureText: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: widget.hadPin ? 'Mã PIN mới' : 'Mã PIN (4–6 số)',
                counterText: '',
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('pin_confirm_input'),
              controller: _confirmPinCtrl,
              obscureText: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Nhập lại mã PIN',
                counterText: '',
                prefixIcon: Icon(Icons.verified_user_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.hadPin)
          TextButton(
            key: const Key('disable_pin_btn'),
            onPressed: () async {
              final ok = await UserBehaviorPrefs.verifyAppPinCode(
                _currentPinCtrl.text,
              );
              if (!context.mounted) return;
              if (!ok) {
                LifeOsTopToast.show(
                  context,
                  'Vui lòng nhập đúng mã PIN hiện tại để tắt khóa.',
                  kind: LifeOsToastKind.warning,
                );
                return;
              }
              await UserBehaviorPrefs.saveAppPinCode(null);
              if (context.mounted) Navigator.of(context).pop();
              widget.onPinChanged(false);
            },
            child: const Text('Tắt mã PIN'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
        FilledButton.icon(
          key: const Key('submit_pin_setup_btn'),
          onPressed: () async {
            if (widget.hadPin) {
              final ok = await UserBehaviorPrefs.verifyAppPinCode(
                _currentPinCtrl.text,
              );
              if (!context.mounted) return;
              if (!ok) {
                LifeOsTopToast.show(
                  context,
                  'Mã PIN hiện tại không chính xác.',
                  kind: LifeOsToastKind.warning,
                );
                return;
              }
            }
            final nextPin = _newPinCtrl.text.trim();
            final confirmPin = _confirmPinCtrl.text.trim();
            if (nextPin.length < 4 || nextPin.length > 6) {
              LifeOsTopToast.show(
                context,
                'Mã PIN cần từ 4 đến 6 chữ số.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            if (nextPin != confirmPin) {
              LifeOsTopToast.show(
                context,
                'Mã PIN xác nhận không khớp.',
                kind: LifeOsToastKind.warning,
              );
              return;
            }
            await UserBehaviorPrefs.saveAppPinCode(nextPin);
            if (context.mounted) Navigator.of(context).pop();
            widget.onPinChanged(true);
          },
          icon: const Icon(Icons.shield_rounded, size: 18),
          label: Text(widget.hadPin ? 'Đổi mã PIN' : 'Lưu mã PIN'),
        ),
      ],
    );
  }
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  String? _boundUserId;
  String _selectedTimezone = 'Asia/Ho_Chi_Minh';
  bool _hasAppPin = false;
  bool _hideBalances = false;
  bool _revealSensitiveProfile = false;
  bool _securitySectionExpanded = false;
  bool _isDeletingAccount = false;

  static const List<(String id, String label)> _supportedTimezones = [
    ('Asia/Ho_Chi_Minh', 'Việt Nam (GMT+7)'),
    ('Asia/Singapore', 'Singapore (GMT+8)'),
    ('Asia/Tokyo', 'Nhật Bản (GMT+9)'),
    ('Europe/London', 'Anh Quốc (GMT+0)'),
    ('America/Los_Angeles', 'Bờ Tây Mỹ (GMT-8)'),
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthBloc>().state.user;
    _boundUserId = user?.id;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
    if (user != null &&
        _supportedTimezones.any((tz) => tz.$1 == user.timezone)) {
      _selectedTimezone = user.timezone;
    }
    _hydrateLocalSecurityPrefs();
  }

  Future<void> _hydrateLocalSecurityPrefs() async {
    final hasPin = await UserBehaviorPrefs.hasAppPinCode();
    final hideBal = await UserBehaviorPrefs.loadHideBalances();
    if (!mounted) return;
    setState(() {
      _hasAppPin = hasPin;
      _hideBalances = hideBal;
    });
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
      if (_supportedTimezones.any((tz) => tz.$1 == user.timezone)) {
        _selectedTimezone = user.timezone;
      }
    }
  }

  Future<void> _showChangePasswordDialog(
    BuildContext context,
    UserEntity user,
  ) async {
    final authBloc = context.read<AuthBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => _ChangePasswordSecurityDialog(
        hasPassword: user.hasPasswordProvider,
        onSubmit: (curr, next, confirm) {
          authBloc.add(
            AuthPasswordChangeSubmitted(
              currentPassword: curr,
              newPassword: next,
              confirmPassword: confirm,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAppPinSetupDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AppPinSecurityDialog(
        hadPin: _hasAppPin,
        onPinChanged: (enabled) {
          if (!mounted) return;
          setState(() => _hasAppPin = enabled);
          LifeOsTopToast.show(
            this.context,
            enabled
                ? 'Đã bật mã PIN bảo vệ ứng dụng thành công!'
                : 'Đã tắt khóa mã PIN bảo vệ ứng dụng.',
          );
        },
      ),
    );
  }

  Future<void> _handleDeleteAccountTap(
    BuildContext context,
    UserEntity user,
  ) async {
    if (_isDeletingAccount) return;

    if (sl.isRegistered<FamilyRepository>()) {
      try {
        final famRes = await sl<FamilyRepository>()
            .watchMyFamilies(user.id)
            .first
            .timeout(const Duration(seconds: 3));
        final ownedMulti = famRes.fold(
          (_) => null,
          (families) => families
              .where(
                (f) =>
                    f.members.length > 1 &&
                    (f.isOwnerUser(user.id) || f.createdBy == user.id),
              )
              .firstOrNull,
        );
        if (ownedMulti != null && context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (dlgCtx) => AlertDialog(
              key: const Key('delete_account_owner_blocked_dialog'),
              title: const Text('Cần chuyển quyền Nhóm gia đình'),
              content: Text(
                'Bạn đang là chủ sở hữu của "${ownedMulti.name}" (${ownedMulti.members.length} thành viên). Vui lòng chuyển quyền chủ sở hữu hoặc xóa các thành viên khác trước khi xóa vĩnh viễn tài khoản.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dlgCtx).pop(),
                  child: const Text('Đóng'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dlgCtx).pop();
                    context.push('/family');
                  },
                  child: const Text('Mở Tổ ấm & Nhóm'),
                ),
              ],
            ),
          );
          return;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    final confirmed = await showDestructiveConfirmDialog(
      context: context,
      title: 'Xóa tài khoản & Dữ liệu cá nhân?',
      message:
          'Toàn bộ ví, giao dịch, lịch hẹn, tài liệu và dữ liệu trên thiết bị sẽ bị xóa vĩnh viễn và không thể khôi phục.',
      confirmLabel: 'Xóa vĩnh viễn',
    );
    if (!confirmed || !context.mounted) return;

    if (!sl.isRegistered<NotificationsRepository>()) {
      context.push('/notifications-privacy');
      return;
    }

    setState(() => _isDeletingAccount = true);
    final res = await sl<NotificationsRepository>()
        .deleteAccountAndPersonalData(user.id);
    if (!context.mounted) return;

    res.fold(
      (failure) {
        setState(() => _isDeletingAccount = false);
        LifeOsTopToast.show(
          context,
          failure.message,
          kind: LifeOsToastKind.error,
        );
      },
      (_) {
        LifeOsTopToast.show(
          context,
          'Đã xóa tài khoản và toàn bộ dữ liệu cá nhân.',
        );
        context.read<AuthBloc>().add(const AuthSignOutRequested());
      },
    );
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
          LifeOsTopToast.show(
            context,
            state.failure!.message,
            kind: LifeOsToastKind.error,
          );
        } else if (state.infoMessage != null) {
          LifeOsTopToast.show(context, state.infoMessage!);
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

        final shortUid = user.id.length > 10
            ? '${user.id.substring(0, 6)}…${user.id.substring(user.id.length - 4)}'
            : user.id;
        final displayEmail = _revealSensitiveProfile
            ? user.email
            : PrivacyMaskFormatter.maskEmail(user.email);
        final rawPhone = (user.phoneNumber ?? '').trim();
        final displayPhone = _revealSensitiveProfile
            ? rawPhone
            : PrivacyMaskFormatter.maskPhone(rawPhone);
        final displayUidLabel = _revealSensitiveProfile
            ? 'Mã TK: $shortUid'
            : 'Mã TK: ${PrivacyMaskFormatter.maskUid(user.id)}';
        final joinedDate = DateFormat('MM/yyyy').format(user.createdAt);

        return Scaffold(
          body: LifeOsMintWaveCanvas(
            child: SafeArea(
              child: Column(
                children: [
                  const LifeOsTopBrandHeader(
                    title: 'Hồ sơ & Bảo mật Tài khoản',
                    showBackButton: true,
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppSpacing.maxContentWidth,
                        ),
                        child: ListView(
                          key: const Key('account_profile_list_view'),
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            4,
                            AppSpacing.md,
                            AppSpacing.xxl,
                          ),
                          children: [
                            // 1. Discreet Identity Hero Card (masks email/phone/UID & tucks security away)
                            LifeOsMintHeroCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      UserAvatarBadge(user: user, radius: 28),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              user.fullName,
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 18.5,
                                                height: 1.2,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            if (displayEmail.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  displayEmail,
                                                  style: TextStyle(
                                                    fontSize: 12.8,
                                                    color: c.textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (displayPhone.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                displayPhone,
                                                style: TextStyle(
                                                  fontSize: 12.2,
                                                  color: c.textSecondary,
                                                  fontFeatures: const [
                                                    FontFeature
                                                        .tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        key: const Key(
                                          'toggle_profile_sensitive_btn',
                                        ),
                                        tooltip: _revealSensitiveProfile
                                            ? 'Ẩn thông tin nhạy cảm'
                                            : 'Hiện thông tin cá nhân',
                                        onPressed: () => setState(() {
                                          _revealSensitiveProfile =
                                              !_revealSensitiveProfile;
                                        }),
                                        icon: Icon(
                                          _revealSensitiveProfile
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          size: 20,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      Material(
                                        color: c.surface,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          side: BorderSide(color: c.separator),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          key: const Key(
                                            'copy_account_uid_btn',
                                          ),
                                          onTap: () async {
                                            await Clipboard.setData(
                                              ClipboardData(text: user.id),
                                            );
                                            if (!context.mounted) return;
                                            LifeOsTopToast.show(
                                              context,
                                              'Đã sao chép mã định danh tài khoản.',
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.copy_rounded,
                                                  size: 13,
                                                  color: c.primary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  displayUidLabel,
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: c.textPrimary,
                                                    fontFeatures: const [
                                                      FontFeature
                                                          .tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      LifeOsStatusPill(
                                        icon: Icons.calendar_today_outlined,
                                        label: 'Tham gia $joinedDate',
                                        tone: LifeOsAccentTone.neutral,
                                      ),
                                      if (user.isGoogleLinked)
                                        const LifeOsStatusPill(
                                          icon: Icons.verified_rounded,
                                          label: 'Đã liên kết',
                                          tone: LifeOsAccentTone.emerald,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Discreet Collapsible Security Entry Bar (collapsed by default)
                                  Material(
                                    key: const Key(
                                      'account_security_score_card',
                                    ),
                                    color: c.surface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: c.border.withValues(alpha: 0.7),
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      key: const Key(
                                        'toggle_security_controls_btn',
                                      ),
                                      onTap: () => setState(() {
                                        _securitySectionExpanded =
                                            !_securitySectionExpanded;
                                      }),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 11,
                                        ),
                                        child: Row(
                                          children: [
                                            const LifeOsIconSquircle(
                                              icon: Icons.lock_outline_rounded,
                                              tone: LifeOsAccentTone.emerald,
                                              size: 36,
                                              iconSize: 18,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Tùy chọn bảo mật & đăng nhập',
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontSize: 13.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: c.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    _securitySectionExpanded
                                                        ? 'Nhấn để ẩn gọn cài đặt mật khẩu & mã PIN'
                                                        : 'Đã ẩn gọn mật khẩu, mã PIN & liên kết đăng nhập',
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontSize: 11.6,
                                                      color: c.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            AnimatedRotation(
                                              turns: _securitySectionExpanded
                                                  ? 0.5
                                                  : 0.0,
                                              duration: LifeOsMotionScope.of(
                                                context,
                                              ).resolveDuration(
                                                LifeOsMotionTokens.micro,
                                              ),
                                              child: Icon(
                                                Icons.expand_more_rounded,
                                                color: c.textSecondary,
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

                            // 2. Collapsible Security Controls (Email Verification, Google, Password, App PIN)
                            LifeOsAnimatedVisibility(
                              visible: _securitySectionExpanded,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_hasAppPin) ...[
                                    const SizedBox(height: 10),
                                    const Align(
                                      alignment: Alignment.centerLeft,
                                      child: LifeOsStatusPill(
                                        icon: Icons.pin_rounded,
                                        label: 'Mã PIN bật',
                                        tone: LifeOsAccentTone.emerald,
                                      ),
                                    ),
                                  ],
                                  if (!user.emailVerified) ...[
                                    const SizedBox(height: 12),
                                    LifeOsSoftCard(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SemanticStatusBadge(
                                            kind: SemanticStatusKind.warning,
                                            label:
                                                'Khuyến nghị xác thực địa chỉ Email',
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Xác thực email giúp khôi phục mật khẩu nhanh khi đổi thiết bị.',
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 12.2,
                                              color: c.textSecondary,
                                            ),
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
                                                    : () => context
                                                          .read<AuthBloc>()
                                                          .add(
                                                            const AuthEmailVerificationRequested(),
                                                          ),
                                                icon: const Icon(
                                                  Icons.outgoing_mail,
                                                  size: 17,
                                                ),
                                                label: const Text(
                                                  'Gửi lại email xác thực',
                                                ),
                                              ),
                                              OutlinedButton.icon(
                                                key: const Key(
                                                  'refresh_verification_status_button',
                                                ),
                                                onPressed: state.isSubmitting
                                                    ? null
                                                    : () => context
                                                          .read<AuthBloc>()
                                                          .add(
                                                            const AuthUserReloadRequested(),
                                                          ),
                                                icon: const Icon(
                                                  Icons.refresh_rounded,
                                                  size: 17,
                                                ),
                                                label: const Text(
                                                  'Tôi đã xác nhận',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const LifeOsSectionHeader(
                                    title: 'Cài đặt Đăng nhập & Khóa Mã PIN',
                                    subtitle:
                                        'Liên kết tài khoản, đổi mật khẩu và mã khóa cá nhân',
                                    tone: LifeOsAccentTone.blue,
                                  ),
                                  LifeOsSoftCard(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (user.isGoogleLinked)
                                          Material(
                                            color: c.surfaceRaised,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 34,
                                                    height: 34,
                                                    padding:
                                                        const EdgeInsets.all(7),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                    child:
                                                        const GoogleBrandMark(
                                                          size: 18,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Tài khoản Google đã liên kết',
                                                          softWrap: true,
                                                          style: TextStyle(
                                                            fontSize: 13.8,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color:
                                                                c.textPrimary,
                                                          ),
                                                        ),
                                                        Text(
                                                          'Đăng nhập nhanh qua $displayEmail',
                                                          softWrap: true,
                                                          style: TextStyle(
                                                            fontSize: 11.8,
                                                            color:
                                                                c.textSecondary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.check_circle_rounded,
                                                    color: c.success,
                                                    size: 20,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        else ...[
                                          Text(
                                            'Liên kết Google để đăng nhập nhanh 1 chạm trên mọi thiết bị:',
                                            softWrap: true,
                                            style: TextStyle(
                                              fontSize: 12.2,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          GoogleAuthButton(
                                            key: const Key(
                                              'link_google_account_button',
                                            ),
                                            label: 'Liên kết tài khoản Google',
                                            isLoading: state.isSubmitting,
                                            onPressed: () => context
                                                .read<AuthBloc>()
                                                .add(
                                                  const AuthGoogleLinkRequested(),
                                                ),
                                          ),
                                        ],
                                        const Divider(height: 22),

                                        // Password row + Reset link
                                        Row(
                                          children: [
                                            const LifeOsIconSquircle(
                                              icon: Icons.password_rounded,
                                              tone: LifeOsAccentTone.blue,
                                              size: 38,
                                              iconSize: 18,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Mật khẩu đăng nhập',
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: c.textPrimary,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Cập nhật mật khẩu định kỳ hoặc khôi phục qua email',
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: c.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilledButton.tonalIcon(
                                              key: const Key(
                                                'open_change_password_button',
                                              ),
                                              onPressed: state.isSubmitting
                                                  ? null
                                                  : () =>
                                                        _showChangePasswordDialog(
                                                          context,
                                                          user,
                                                        ),
                                              icon: const Icon(
                                                Icons.lock_reset_rounded,
                                                size: 17,
                                              ),
                                              label: Text(
                                                user.hasPasswordProvider
                                                    ? 'Đổi mật khẩu'
                                                    : 'Tạo mật khẩu Email',
                                              ),
                                            ),
                                            if (user.email.isNotEmpty)
                                              OutlinedButton.icon(
                                                key: const Key(
                                                  'send_password_reset_email_btn',
                                                ),
                                                onPressed: state.isSubmitting
                                                    ? null
                                                    : () => context
                                                          .read<AuthBloc>()
                                                          .add(
                                                            AuthPasswordResetRequested(
                                                              user.email,
                                                            ),
                                                          ),
                                                icon: const Icon(
                                                  Icons.mail_lock_outlined,
                                                  size: 17,
                                                ),
                                                label: const Text(
                                                  'Gửi link qua Email',
                                                ),
                                              ),
                                          ],
                                        ),
                                        const Divider(height: 22),

                                        // App Security PIN Row
                                        Material(
                                          color: c.surfaceRaised,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          clipBehavior: Clip.antiAlias,
                                          child: InkWell(
                                            key: const Key(
                                              'open_app_pin_dialog_btn',
                                            ),
                                            onTap: () =>
                                                _showAppPinSetupDialog(context),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Row(
                                                children: [
                                                  LifeOsIconSquircle(
                                                    icon: _hasAppPin
                                                        ? Icons.shield_rounded
                                                        : Icons.dialpad_rounded,
                                                    tone: _hasAppPin
                                                        ? LifeOsAccentTone
                                                              .emerald
                                                        : LifeOsAccentTone
                                                              .neutral,
                                                    size: 38,
                                                    iconSize: 18,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Khóa mã PIN ứng dụng',
                                                          softWrap: true,
                                                          style: TextStyle(
                                                            fontSize: 13.8,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color:
                                                                c.textPrimary,
                                                          ),
                                                        ),
                                                        Text(
                                                          _hasAppPin
                                                              ? 'Đang bật khóa mã PIN ứng dụng'
                                                              : 'Thiết lập mã PIN 4–6 số cho ứng dụng',
                                                          softWrap: true,
                                                          style: TextStyle(
                                                            fontSize: 11.8,
                                                            color:
                                                                c.textSecondary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.chevron_right_rounded,
                                                    color: c.textSecondary,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 3. Personal Profile Information Editor
                            const LifeOsSectionHeader(
                              title: 'Thông tin Hồ sơ Cá nhân',
                              subtitle:
                                  'Hiển thị trên bảng công việc và sổ chia tiền nhóm',
                            ),
                            LifeOsSoftCard(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    key: const Key('profile_name_field'),
                                    controller: _nameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Họ và tên',
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    key: const Key('profile_phone_field'),
                                    controller: _phoneController,
                                    obscureText: !_revealSensitiveProfile &&
                                        _phoneController.text.trim().isNotEmpty,
                                    keyboardType: TextInputType.phone,
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      labelText: 'Số điện thoại',
                                      hintText: '0901 234 567',
                                      prefixIcon: const Icon(
                                        Icons.phone_iphone_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: _revealSensitiveProfile
                                            ? 'Ẩn số điện thoại'
                                            : 'Hiện số điện thoại',
                                        onPressed: () => setState(() {
                                          _revealSensitiveProfile =
                                              !_revealSensitiveProfile;
                                        }),
                                        icon: Icon(
                                          _revealSensitiveProfile
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          size: 19,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    key: const Key('profile_timezone_dropdown'),
                                    isExpanded: true,
                                    initialValue: _selectedTimezone,
                                    decoration: const InputDecoration(
                                      labelText: 'Múi giờ',
                                      prefixIcon: Icon(Icons.public_rounded),
                                    ),
                                    items: _supportedTimezones
                                        .map(
                                          (tz) => DropdownMenuItem<String>(
                                            value: tz.$1,
                                            child: Text(tz.$2),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => _selectedTimezone = v);
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton.icon(
                                    key: const Key('save_profile_button'),
                                    onPressed: state.isSubmitting
                                        ? null
                                        : () {
                                            context.read<AuthBloc>().add(
                                              AuthProfileUpdateSubmitted(
                                                fullName: _nameController.text,
                                                phoneNumber:
                                                    _phoneController.text,
                                                timezone: _selectedTimezone,
                                              ),
                                            );
                                          },
                                    icon: const Icon(
                                      Icons.save_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Lưu cập nhật hồ sơ'),
                                  ),
                                ],
                              ),
                            ),

                            // 5. Privacy & Data Sharing Controls
                            const LifeOsSectionHeader(
                              title: 'Quyền riêng tư & Chia sẻ Dữ liệu',
                              tone: LifeOsAccentTone.purple,
                            ),
                            LifeOsSoftCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.visibility_off_outlined,
                                        tone: LifeOsAccentTone.purple,
                                        size: 38,
                                        iconSize: 18,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Ẩn số dư trên Trang chủ',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 13.8,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'Che số tiền nhạy cảm khi mở ở nơi đông người',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 11.8,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        key: const Key(
                                          'profile_hide_balances_switch',
                                        ),
                                        value: _hideBalances,
                                        onChanged: (val) async {
                                          setState(() => _hideBalances = val);
                                          await UserBehaviorPrefs
                                              .saveHideBalances(val);
                                        },
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 18),
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.event_available_outlined,
                                        tone: LifeOsAccentTone.emerald,
                                        size: 38,
                                        iconSize: 18,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Chia sẻ khung giờ rảnh/bận',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 13.8,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'Chỉ hiện trạng thái trống lịch cho thành viên nhóm',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 11.8,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        key: const Key(
                                          'profile_availability_opt_in_switch',
                                        ),
                                        value: user.availabilityOptIn,
                                        onChanged: (val) => context
                                            .read<AuthBloc>()
                                            .add(
                                              AuthAvailabilitySharingToggled(
                                                val,
                                              ),
                                            ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 18),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      key: const Key(
                                        'profile_open_privacy_center_row',
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => context.push(
                                        '/notifications-privacy',
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: Row(
                                          children: [
                                            const LifeOsIconSquircle(
                                              icon: Icons.shield_outlined,
                                              tone: LifeOsAccentTone.emerald,
                                              size: 38,
                                              iconSize: 18,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Ngân hàng & Quyền dữ liệu',
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontSize: 13.8,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: c.textPrimary,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Quyền đọc biến động, mã QR & quản lý dữ liệu',
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      fontSize: 11.8,
                                                      color: c.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color: c.textSecondary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 6. App Version & Active Device Session
                            const LifeOsSectionHeader(
                              title: 'Phiên bản & Thiết bị đăng nhập',
                              tone: LifeOsAccentTone.amber,
                            ),
                            const AppUpdateSettingsCard(),
                            const SizedBox(height: 10),
                            LifeOsSoftCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.smartphone_rounded,
                                        tone: LifeOsAccentTone.emerald,
                                        size: 38,
                                        iconSize: 18,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Thiết bị hiện tại',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 13.8,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              displayEmail.isNotEmpty
                                                  ? 'Đang đăng nhập · $displayEmail'
                                                  : 'Thiết bị đang sử dụng',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 11.8,
                                                color: c.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const LifeOsStatusPill(
                                        label: 'Đang dùng',
                                        tone: LifeOsAccentTone.emerald,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    key: const Key('profile_sign_out_button'),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                      foregroundColor: c.error,
                                      side: BorderSide(
                                        color: c.error.withValues(alpha: 0.45),
                                      ),
                                    ),
                                    onPressed: _isDeletingAccount
                                        ? null
                                        : () => context.read<AuthBloc>().add(
                                            const AuthSignOutRequested(),
                                          ),
                                    icon: const Icon(Icons.logout_rounded),
                                    label: const Text(
                                      'Đăng xuất khỏi thiết bị này',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            LifeOsSoftCard(
                              key: const Key('profile_delete_account_section'),
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const LifeOsIconSquircle(
                                        icon: Icons.delete_forever_outlined,
                                        tone: LifeOsAccentTone.coral,
                                        size: 38,
                                        iconSize: 18,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Xóa tài khoản & Dữ liệu cá nhân',
                                              softWrap: true,
                                              style: TextStyle(
                                                fontSize: 13.8,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'Xóa vĩnh viễn toàn bộ ví, giao dịch, lịch hẹn và dữ liệu riêng trên máy',
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
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    key: const Key(
                                      'profile_delete_account_button',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                      foregroundColor: c.error,
                                      side: BorderSide(
                                        color: c.error.withValues(alpha: 0.55),
                                      ),
                                    ),
                                    onPressed:
                                        (_isDeletingAccount ||
                                            state.isSubmitting)
                                        ? null
                                        : () => _handleDeleteAccountTap(
                                            context,
                                            user,
                                          ),
                                    icon: Icon(
                                      _isDeletingAccount
                                          ? Icons.hourglass_top_rounded
                                          : Icons.delete_forever_rounded,
                                    ),
                                    label: Text(
                                      _isDeletingAccount
                                          ? 'Đang xóa dữ liệu...'
                                          : 'Xóa tài khoản & Dữ liệu cá nhân',
                                      softWrap: true,
                                    ),
                                  ),
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
