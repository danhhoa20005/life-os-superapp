import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

BoxDecoration proAuthCanvasDecoration(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [Color(0xFF04190B), Color(0xFF000000), Color(0xFF061A26)]
          : const [Color(0xFFEAF7EF), Color(0xFFF6F8FA), Color(0xFFEBF2FC)],
    ),
  );
}

/// Crisp vector Google "G" multi-color mark rendered at 60 FPS via CustomPainter.
class GoogleBrandMark extends StatelessWidget {
  final double size;

  const GoogleBrandMark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.21;
    final radius = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    double deg(double d) => d * math.pi / 180.0;

    // Red top arc
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, deg(215), deg(95), false, paint);

    // Yellow left arc
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, deg(145), deg(70), false, paint);

    // Green bottom arc
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, deg(45), deg(100), false, paint);

    // Blue right-bottom arc + horizontal bar
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, deg(-12), deg(58), false, paint);

    final barHeight = stroke * 0.92;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          center.dx - size.width * 0.02,
          center.dy - barHeight / 2,
          size.width * 0.49,
          barHeight,
        ),
        Radius.circular(barHeight * 0.22),
      ),
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF4285F4)
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// High-craft tactile Google Sign-In / Sign-Up / Link button following UI/UX Pro Max.
class GoogleAuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const GoogleAuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = TammySemanticColors.of(context);

    return Material(
      color: isDark ? const Color(0xFF1F242B) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : const Color(0xFFD0D5DD),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.primary,
                  ),
                )
              else
                Container(
                  width: 28,
                  height: 28,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: isDark
                        ? null
                        : Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: const GoogleBrandMark(size: 18),
                ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1D2939),
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

class _AuthSectionDivider extends StatelessWidget {
  final String text;

  const _AuthSectionDivider({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.separator, thickness: 0.8)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: c.textSecondary,
                  ),
            ),
          ),
          Expanded(child: Divider(color: c.separator, thickness: 0.8)),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submitEmailSignIn() {
    context.read<AuthBloc>().add(
          AuthSignInSubmitted(
            email: _emailController.text,
            password: _passwordController.text,
          ),
        );
  }

  Future<void> _showForgotPasswordDialog(BuildContext context) async {
    final resetEmailCtrl = TextEditingController(text: _emailController.text.trim());
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Khôi phục mật khẩu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nhập địa chỉ email đã đăng ký. Life OS sẽ gửi liên kết đặt lại mật khẩu an toàn tới hộp thư của bạn.',
                style: Theme.of(dialogCtx).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('reset_password_email_field'),
                controller: resetEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Email nhận liên kết',
                  hintText: 'ban@gmail.com',
                  prefixIcon: Icon(Icons.mark_email_read_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Đóng'),
            ),
            FilledButton.icon(
              key: const Key('submit_reset_password_button'),
              onPressed: () {
                final email = resetEmailCtrl.text;
                Navigator.of(dialogCtx).pop();
                context.read<AuthBloc>().add(AuthPasswordResetRequested(email));
              },
              icon: const Icon(Icons.send_rounded, size: 17),
              label: const Text('Gửi liên kết'),
            ),
          ],
        );
      },
    );
    resetEmailCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            prev.failure != curr.failure || prev.infoMessage != curr.infoMessage,
        listener: (context, state) {
          if (state.failure != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('⚠ ${state.failure!.message}')),
            );
          } else if (state.infoMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('✓ ${state.infoMessage!}')),
            );
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: proAuthCanvasDecoration(context),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448),
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: c.separator.withValues(alpha: 0.6)),
                      boxShadow: [
                        BoxShadow(
                          color: c.primary.withValues(alpha: 0.09),
                          blurRadius: 32,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        return AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const BrandLogoMark(size: 50, borderRadius: 15),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Life OS',
                                          style: Theme.of(context).textTheme.headlineMedium,
                                        ),
                                        Text(
                                          'Tài chính · Hội nhóm · Gia đình',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SemanticStatusBadge(
                                    kind: SemanticStatusKind.success,
                                    label: 'Bảo mật Cloud',
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const BrandVisualBanner(
                                assetPath: AppAssets.authHero,
                                height: 112,
                                semanticLabel:
                                    'Minh họa lá chắn bảo vệ ví riêng và kết nối gia đình',
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              GoogleAuthButton(
                                key: const Key('google_sign_in_button'),
                                label: 'Tiếp tục với Google',
                                isLoading: state.isSubmitting,
                                onPressed: () => context
                                    .read<AuthBloc>()
                                    .add(const AuthGoogleSignInRequested()),
                              ),
                              const _AuthSectionDivider(text: 'HOẶC ĐĂNG NHẬP BẰNG EMAIL'),
                              Text(
                                'Email đăng nhập',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('login_email_field'),
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  hintText: 'ban@gmail.com',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text('Mật khẩu', style: Theme.of(context).textTheme.labelLarge),
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('login_password_field'),
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!state.isSubmitting) _submitEmailSignIn();
                                },
                                decoration: InputDecoration(
                                  hintText: 'Nhập mật khẩu tài khoản',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    tooltip:
                                        _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                                    onPressed: () => setState(
                                      () => _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              FilledButton.icon(
                                key: const Key('login_submit_button'),
                                onPressed: state.isSubmitting ? null : _submitEmailSignIn,
                                icon: state.isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.login_rounded, size: 19),
                                label: const Text('Đăng nhập vào Không gian Riêng'),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: AppSpacing.xs,
                                runSpacing: AppSpacing.xxs,
                                children: [
                                  TextButton(
                                    key: const Key('forgot_password_button'),
                                    onPressed: state.isSubmitting
                                        ? null
                                        : () => _showForgotPasswordDialog(context),
                                    child: const Text('Quên mật khẩu?'),
                                  ),
                                  TextButton(
                                    key: const Key('go_to_register_button'),
                                    onPressed: () => context.go('/register'),
                                    child: const Text('Tạo tài khoản mới →'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  static int _passwordScore(String password) {
    if (password.isEmpty) return 0;
    var score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password) || password.length >= 12) {
      score++;
    }
    return score.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final pwdScore = _passwordScore(_passwordController.text);

    return Scaffold(
      appBar: const LiquidGlassBar(title: Text('Đăng ký Tài khoản Life OS')),
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) => prev.failure != curr.failure,
        listener: (context, state) {
          if (state.failure != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('⚠ ${state.failure!.message}')),
            );
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: proAuthCanvasDecoration(context),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 472),
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: c.separator.withValues(alpha: 0.6)),
                      boxShadow: [
                        BoxShadow(
                          color: c.primary.withValues(alpha: 0.08),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        return AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const BrandVisualBanner(
                                assetPath: AppAssets.authHero,
                                height: 96,
                                semanticLabel:
                                    'Không gian tài chính cá nhân và gia đình bảo mật',
                              ),
                              const SizedBox(height: AppSpacing.md),
                              GoogleAuthButton(
                                key: const Key('google_sign_up_button'),
                                label: 'Đăng ký nhanh bằng Google',
                                isLoading: state.isSubmitting,
                                onPressed: () => context
                                    .read<AuthBloc>()
                                    .add(const AuthGoogleSignInRequested()),
                              ),
                              const _AuthSectionDivider(text: 'HOẶC TẠO TÀI KHOẢN EMAIL'),
                              Text(
                                'Họ và tên hiển thị',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('register_name_field'),
                                controller: _nameController,
                                autofillHints: const [AutofillHints.name],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  hintText: 'Nguyễn Minh',
                                  prefixIcon: Icon(Icons.person_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Địa chỉ Email',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('register_email_field'),
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  hintText: 'minh@gmail.com',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Số điện thoại (Tùy chọn)',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('register_phone_field'),
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                autofillHints: const [AutofillHints.telephoneNumber],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  hintText: '0901 234 567',
                                  prefixIcon: Icon(Icons.phone_iphone_rounded),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Mật khẩu (tối thiểu 8 ký tự)',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('register_password_field'),
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.newPassword],
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: '••••••••',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () => _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              if (_passwordController.text.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _PasswordStrengthBar(score: pwdScore),
                              ],
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Xác nhận mật khẩu',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('register_confirm_password_field'),
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirmPassword,
                                autofillHints: const [AutofillHints.newPassword],
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  hintText: 'Nhập lại mật khẩu ở trên',
                                  prefixIcon: const Icon(Icons.verified_user_outlined),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                                    ),
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Material(
                                color: c.surfaceRaised,
                                borderRadius: BorderRadius.circular(14),
                                clipBehavior: Clip.antiAlias,
                                child: CheckboxListTile(
                                  key: const Key('register_terms_checkbox'),
                                  value: _acceptedTerms,
                                  dense: true,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  onChanged: (v) =>
                                      setState(() => _acceptedTerms = v ?? false),
                                  title: Text(
                                    'Đồng ý Chính sách Bảo vệ Dữ liệu Cá nhân (Luật 91/2025) & Cam kết Zero-OTP',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              FilledButton.icon(
                                key: const Key('register_submit_button'),
                                onPressed: state.isSubmitting
                                    ? null
                                    : () {
                                        context.read<AuthBloc>().add(
                                              AuthSignUpSubmitted(
                                                email: _emailController.text,
                                                password: _passwordController.text,
                                                confirmPassword:
                                                    _confirmPasswordController.text,
                                                fullName: _nameController.text,
                                                phoneNumber: _phoneController.text,
                                                acceptedTerms: _acceptedTerms,
                                              ),
                                            );
                                      },
                                icon: state.isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                                label: const Text('Hoàn tất Đăng ký Tài khoản'),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              TextButton(
                                key: const Key('go_to_login_button'),
                                onPressed: () => context.go('/login'),
                                child: const Text('Đã có tài khoản? Quay lại Đăng nhập'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordStrengthBar extends StatelessWidget {
  final int score;

  const _PasswordStrengthBar({required this.score});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final (label, color) = switch (score) {
      <= 1 => ('Yếu (cần tối thiểu 8 ký tự)', c.error),
      2 => ('Trung bình', c.warning),
      3 => ('Khá mạnh', c.secondary),
      _ => ('Rất mạnh', c.success),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (index) {
            final active = index < score;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                decoration: BoxDecoration(
                  color: active ? color : c.separator,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(
          'Độ mạnh mật khẩu: $label',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class OnboardingPrivacyPage extends StatelessWidget {
  const OnboardingPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Scaffold(
      appBar: const LiquidGlassBar(title: Text('Thiết lập Quyền riêng tư Mặc định')),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: proAuthCanvasDecoration(context),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const BrandVisualBanner(
                              assetPath: AppAssets.onboardingPrivacy,
                              height: 108,
                              semanticLabel: 'Ba nguyên tắc bảo mật mặc định của Life OS',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Xin chào ${state.user?.fullName ?? ''}!',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Life OS vận hành theo chuẩn Privacy-by-Default cho Cá nhân, Hội nhóm và Gia đình:',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _PrivacyPrincipleTile(
                              icon: Icons.lock_person_rounded,
                              title: 'Lịch riêng & Ví riêng bất khả xâm phạm',
                              subtitle:
                                  'Chủ gia đình hoặc bạn cùng phòng không bao giờ đọc được lịch cá nhân hay tài khoản ngân hàng của bạn.',
                              color: c.primary,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _PrivacyPrincipleTile(
                              icon: Icons.shield_outlined,
                              title: 'Zero-OTP · Kiểm duyệt thông báo chủ động',
                              subtitle:
                                  'Mặc định TẮT đọc thông báo. Tuyệt đối không lưu mã OTP, PIN hay mật khẩu ngân hàng.',
                              color: c.secondary,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _PrivacyPrincipleTile(
                              icon: Icons.pie_chart_rounded,
                              title: 'Chia tiền & Sổ quỹ nguyên đồng VND',
                              subtitle:
                                  'Tách hóa đơn ăn uống/việc nhà và tối giản công nợ nhóm chính xác 100%, không tự động rút tiền thật.',
                              color: c.success,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FilledButton.icon(
                              key: const Key('complete_onboarding_button'),
                              onPressed: state.isSubmitting
                                  ? null
                                  : () => context
                                      .read<AuthBloc>()
                                      .add(const AuthOnboardingCompleted()),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Bắt đầu sử dụng Life OS'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyPrincipleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _PrivacyPrincipleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
