import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
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
          ? const [Color(0xFF0B1510), Color(0xFF0B0F0D), Color(0xFF0E1B14)]
          : const [Color(0xFFF3FBF6), Color(0xFFF8FAF9), Color(0xFFEEF9F1)],
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

    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, deg(215), deg(95), false, paint);

    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, deg(145), deg(70), false, paint);

    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, deg(45), deg(100), false, paint);

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

/// High-craft tactile Google Sign-In / Sign-Up / Link button following Unified LifeOS Style.
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
    final c = TammySemanticColors.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: c.primary),
                )
              else
                const GoogleBrandMark(size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
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
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.separator, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          Expanded(child: Divider(color: c.separator, thickness: 1)),
        ],
      ),
    );
  }
}

/// Shared Auth Top Bar (`<` Back + Centered `🌿 LifeOS`).
class _AuthBrandTopBar extends StatelessWidget {
  final bool showBack;
  final VoidCallback? onBack;

  const _AuthBrandTopBar({this.showBack = false, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          LifeOsHeaderCircleButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Quay lại',
            onTap: onBack ??
                () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/login');
                  }
                },
          )
        else
          const SizedBox(width: 38),
        const Spacer(),
        const LifeOsBrandWordmark(iconSize: 32, fontSize: 19),
        const Spacer(),
        const SizedBox(width: 38),
      ],
    );
  }
}

/// Screen 01 of Auth Sheet: "Chào mừng đến LifeOS" Welcome Landing Screen (`/welcome`).
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const LifeOsBrandWordmark(iconSize: 36, fontSize: 21),
                    const SizedBox(height: 28),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.22,
                          letterSpacing: -0.5,
                          color: c.textPrimary,
                        ),
                        children: [
                          const TextSpan(text: 'Chào mừng đến\n'),
                          TextSpan(
                            text: 'LifeOS',
                            style: TextStyle(color: c.primary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Một ứng dụng. Cả cuộc sống. Quản lý tài chính, lịch trình, công việc và gia đình trọn vẹn.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: c.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    // Official BrandKit 1.0 House-Family-Leaves Hero Circle
                    Container(
                      width: 216,
                      height: 216,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            c.primary.withValues(alpha: 0.18),
                            c.primarySubtle.withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                      child: const Stack(
                        alignment: Alignment.center,
                        children: [
                          LifeOsSymbolMark(size: 118),
                          Positioned(
                            left: 14,
                            top: 24,
                            child: LifeOsIconSquircle(
                              icon: Icons.calendar_today_rounded,
                              size: 34,
                              iconSize: 17,
                            ),
                          ),
                          Positioned(
                            right: 14,
                            top: 30,
                            child: LifeOsIconSquircle(
                              icon: Icons.account_balance_wallet_outlined,
                              size: 34,
                              iconSize: 17,
                            ),
                          ),
                          Positioned(
                            right: 18,
                            bottom: 24,
                            child: LifeOsIconSquircle(
                              icon: Icons.check_circle_outline_rounded,
                              size: 34,
                              iconSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 20,
                          height: 7,
                          decoration: BoxDecoration(
                            color: c.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: c.border,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: c.border,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    LifeOsPrimaryCtaButton(
                      label: 'Bắt đầu',
                      onPressed: () => context.go('/register'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        onPressed: () => context.go('/login'),
                        child: const Text('Tôi đã có tài khoản'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen 02 of Auth Sheet: Unified LifeOS "Đăng nhập" (`/login`).
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

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            prev.failure != curr.failure || prev.infoMessage != curr.infoMessage,
        listener: (context, state) {
          if (state.failure != null) {
            LifeOsTopToast.fromSnackBar(context, 
              SnackBar(content: Text('⚠ ${state.failure!.message}')),
            );
          } else if (state.infoMessage != null) {
            LifeOsTopToast.fromSnackBar(context, 
              SnackBar(content: Text('✓ ${state.infoMessage!}')),
            );
          }
        },
        child: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      return AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AuthBrandTopBar(
                              showBack: true,
                              onBack: () => context.go('/welcome'),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              'Đăng nhập',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Chào mừng bạn trở lại LifeOS!',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: c.textSecondary),
                            ),
                            const SizedBox(height: 24),
                            LifeOsSoftCard(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
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
                                      hintText: 'Nhập địa chỉ email',
                                      prefixIcon: Icon(Icons.mail_outline_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Mật khẩu',
                                    style: Theme.of(context).textTheme.labelLarge,
                                  ),
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
                                      hintText: '••••••••',
                                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePassword
                                            ? 'Hiện mật khẩu'
                                            : 'Ẩn mật khẩu',
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
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      key: const Key('forgot_password_button'),
                                      onPressed: state.isSubmitting
                                          ? null
                                          : () => context.push(
                                                '/forgot-password',
                                                extra: _emailController.text.trim(),
                                              ),
                                      child: const Text('Quên mật khẩu?'),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 50,
                                    child: FilledButton(
                                      key: const Key('login_submit_button'),
                                      style: FilledButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                      ),
                                      onPressed:
                                          state.isSubmitting ? null : _submitEmailSignIn,
                                      child: state.isSubmitting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('Đăng nhập'),
                                    ),
                                  ),
                                  const _AuthSectionDivider(text: 'Hoặc tiếp tục với'),
                                  GoogleAuthButton(
                                    key: const Key('google_sign_in_button'),
                                    label: 'Tiếp tục với Google',
                                    isLoading: state.isSubmitting,
                                    onPressed: () => context
                                        .read<AuthBloc>()
                                        .add(const AuthGoogleSignInRequested()),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Chưa có tài khoản?',
                                  style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                                ),
                                TextButton(
                                  key: const Key('go_to_register_button'),
                                  onPressed: () => context.go('/register'),
                                  child: const Text('Đăng ký ngay'),
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
    );
  }
}

/// Screen 03 of Auth Sheet: Unified LifeOS "Tạo tài khoản" (`/register`).
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
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) => prev.failure != curr.failure,
        listener: (context, state) {
          if (state.failure != null) {
            LifeOsTopToast.fromSnackBar(context, 
              SnackBar(content: Text('⚠ ${state.failure!.message}')),
            );
          }
        },
        child: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      return AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AuthBrandTopBar(
                              showBack: true,
                              onBack: () => context.go('/login'),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Tạo tài khoản',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Bắt đầu quản lý cuộc sống thông minh của bạn.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                            ),
                            const SizedBox(height: 18),
                            LifeOsSoftCard(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  GoogleAuthButton(
                                    key: const Key('google_sign_up_button'),
                                    label: 'Đăng ký nhanh bằng Google',
                                    isLoading: state.isSubmitting,
                                    onPressed: () => context
                                        .read<AuthBloc>()
                                        .add(const AuthGoogleSignInRequested()),
                                  ),
                                  const _AuthSectionDivider(text: 'Hoặc đăng ký bằng Email'),
                                  Text('Họ và tên', style: Theme.of(context).textTheme.labelLarge),
                                  const SizedBox(height: 6),
                                  TextField(
                                    key: const Key('register_name_field'),
                                    controller: _nameController,
                                    autofillHints: const [AutofillHints.name],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      hintText: 'Nhập họ và tên của bạn',
                                      prefixIcon: Icon(Icons.person_outline_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text('Email', style: Theme.of(context).textTheme.labelLarge),
                                  const SizedBox(height: 6),
                                  TextField(
                                    key: const Key('register_email_field'),
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      hintText: 'Nhập địa chỉ email',
                                      prefixIcon: Icon(Icons.mail_outline_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Số điện thoại (tùy chọn)',
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
                                  const SizedBox(height: 12),
                                  Text('Mật khẩu', style: Theme.of(context).textTheme.labelLarge),
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
                                  const SizedBox(height: 12),
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
                                      hintText: '••••••••',
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
                                  const SizedBox(height: 10),
                                  CheckboxListTile(
                                    key: const Key('register_terms_checkbox'),
                                    value: _acceptedTerms,
                                    dense: true,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: c.primary,
                                    onChanged: (v) =>
                                        setState(() => _acceptedTerms = v ?? false),
                                    title: Text(
                                      'Tôi đồng ý với Điều khoản sử dụng và Chính sách quyền riêng tư.',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 50,
                                    child: FilledButton(
                                      key: const Key('register_submit_button'),
                                      style: FilledButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                      ),
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
                                      child: state.isSubmitting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('Đăng ký'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Đã có tài khoản?',
                                  style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                                ),
                                TextButton(
                                  key: const Key('go_to_login_button'),
                                  onPressed: () => context.go('/login'),
                                  child: const Text('Đăng nhập'),
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
    );
  }
}

/// Screen 04 of Auth Sheet: "Quên mật khẩu?" (`/forgot-password`).
class ForgotPasswordPage extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordPage({super.key, this.initialEmail});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  late final TextEditingController _emailCtrl;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AuthBrandTopBar(
                      showBack: true,
                      onBack: () => context.go('/login'),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Quên mật khẩu?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nhập email đã đăng ký để nhận mã xác minh và liên kết đặt lại mật khẩu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.8, color: c.textSecondary),
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: c.primarySubtle,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Icon(
                          Icons.mark_email_read_outlined,
                          size: 46,
                          color: c.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text('Địa chỉ email', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('reset_password_email_field'),
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'Nhập email của bạn',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 18),
                    LifeOsPrimaryCtaButton(
                      label: 'Gửi mã xác minh',
                      onPressed: () {
                        final email = _emailCtrl.text.trim();
                        if (email.isNotEmpty) {
                          context.read<AuthBloc>().add(AuthPasswordResetRequested(email));
                        }
                        context.push('/verify-otp', extra: email);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.chevron_left_rounded, size: 19),
                      label: const Text('Quay lại đăng nhập'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen 05 of Auth Sheet: "Xác minh email" 6-Box OTP Verification (`/verify-otp`).
class VerifyOtpPage extends StatefulWidget {
  final String? email;

  const VerifyOtpPage({super.key, this.email});

  @override
  State<VerifyOtpPage> createState() => _VerifyOtpPageState();
}

class _VerifyOtpPageState extends State<VerifyOtpPage> {
  final List<String> _digits = <String>['3', '8', '4', '7', '', ''];
  int _secondsLeft = 58;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _appendDigit(String d) {
    final idx = _digits.indexWhere((e) => e.isEmpty);
    if (idx != -1) {
      setState(() => _digits[idx] = d);
    }
  }

  void _backspace() {
    for (var i = _digits.length - 1; i >= 0; i--) {
      if (_digits[i].isNotEmpty) {
        setState(() => _digits[i] = '');
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final activeIdx = _digits.indexWhere((e) => e.isEmpty);
    final mm = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (_secondsLeft % 60).toString().padLeft(2, '0');

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    const _AuthBrandTopBar(showBack: true),
                    const SizedBox(height: 18),
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: c.primarySubtle,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.verified_user_outlined, size: 34, color: c.primary),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Xác minh email',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Nhập mã 6 chữ số đã được gửi đến\n${(widget.email ?? '').isEmpty ? 'ban@lifeos.vn' : widget.email}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                    ),
                    const SizedBox(height: 22),

                    // 6 Individual Rounded OTP Digit Boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (i) {
                        final val = _digits[i];
                        final isCurrent = i == activeIdx || (activeIdx == -1 && i == 5);
                        return Container(
                          width: 48,
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isCurrent ? c.primary : c.border,
                              width: isCurrent ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            val,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Bạn chưa nhận được mã?',
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                    TextButton(
                      onPressed: _secondsLeft == 0
                          ? () => setState(() => _secondsLeft = 58)
                          : null,
                      child: Text(
                        _secondsLeft > 0 ? 'Gửi lại sau $mm:$ss' : 'Gửi lại mã ngay',
                      ),
                    ),
                    const SizedBox(height: 6),
                    LifeOsPrimaryCtaButton(
                      label: 'Xác nhận',
                      onPressed: () => context.push('/reset-password'),
                    ),
                    const SizedBox(height: 16),

                    // Tactile Numeric Keypad (3×4)
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.2,
                      children: [
                        for (final d in const ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                          OutlinedButton(
                            onPressed: () => _appendDigit(d),
                            child: Text(
                              d,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: () => context.pop(),
                          child: const Text('Đổi email', style: TextStyle(fontSize: 12)),
                        ),
                        OutlinedButton(
                          onPressed: () => _appendDigit('0'),
                          child: const Text(
                            '0',
                            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _backspace,
                          child: const Icon(Icons.backspace_outlined, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen 06 of Auth Sheet: "Đặt mật khẩu mới" with 4-Bar Strength & Checklist (`/reset-password`).
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController _pwdCtrl = TextEditingController(text: 'LifeOs@2026');
  final TextEditingController _confirmCtrl = TextEditingController(text: 'LifeOs@2026');
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _pwdCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final pwd = _pwdCtrl.text;
    final hasLen = pwd.length >= 8;
    final hasCase = RegExp(r'[A-Z]').hasMatch(pwd) && RegExp(r'[a-z]').hasMatch(pwd);
    final hasDigit = RegExp(r'[0-9]').hasMatch(pwd);
    final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(pwd);
    final score = [hasLen, hasCase, hasDigit, hasSpecial].where((b) => b).length;

    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _AuthBrandTopBar(showBack: true),
                    const SizedBox(height: 18),
                    Center(
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: c.primarySubtle,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.lock_open_rounded, size: 34, color: c.primary),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Đặt mật khẩu mới',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tạo mật khẩu an toàn cho tài khoản của bạn.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                    ),
                    const SizedBox(height: 22),
                    Text('Mật khẩu mới', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _pwdCtrl,
                      obscureText: _obscure1,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure1 = !_obscure1),
                          icon: Icon(
                            _obscure1
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Xác nhận mật khẩu mới', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _confirmCtrl,
                      obscureText: _obscure2,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure2 = !_obscure2),
                          icon: Icon(
                            _obscure2
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PasswordStrengthBar(score: score),
                    const SizedBox(height: 14),
                    _PwdCheckItem(passed: hasLen, label: 'Tối thiểu 8 ký tự'),
                    _PwdCheckItem(passed: hasCase, label: 'Có chữ hoa và chữ thường'),
                    _PwdCheckItem(passed: hasDigit, label: 'Có ít nhất một chữ số'),
                    _PwdCheckItem(passed: hasSpecial, label: 'Có ký tự đặc biệt'),
                    const SizedBox(height: 22),
                    LifeOsPrimaryCtaButton(
                      label: 'Lưu mật khẩu',
                      onPressed: () {
                        LifeOsTopToast.fromSnackBar(context, 
                          const SnackBar(
                            content: Text('✓ Đã cập nhật mật khẩu mới an toàn.'),
                          ),
                        );
                        context.go('/login');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PwdCheckItem extends StatelessWidget {
  final bool passed;
  final String label;

  const _PwdCheckItem({required this.passed, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: passed ? c.primary : c.border,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: passed ? FontWeight.w700 : FontWeight.w500,
                color: passed ? c.textPrimary : c.textSecondary,
              ),
            ),
          ),
        ],
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
      <= 1 => ('Yếu', c.error),
      2 => ('Trung bình', c.warning),
      3 => ('Khá mạnh', c.primary),
      _ => ('Mạnh', c.primary),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Độ mạnh mật khẩu: ',
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(4, (index) {
            final active = index < score;
            return Expanded(
              child: Container(
                height: 5,
                margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                decoration: BoxDecoration(
                  color: active ? color : c.separator,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Screens 07, 08, 09 of Setup Sheet: Unified Onboarding Wizard
/// ("Tham gia gia đình" · "Kết nối Google Calendar" · "Kết nối ngân hàng SePay")
class OnboardingPrivacyPage extends StatefulWidget {
  const OnboardingPrivacyPage({super.key});

  @override
  State<OnboardingPrivacyPage> createState() => _OnboardingPrivacyPageState();
}

class _OnboardingPrivacyPageState extends State<OnboardingPrivacyPage> {
  int _stepIndex = 0;
  final TextEditingController _inviteCodeCtrl =
      TextEditingController(text: 'GD-F7K9M2');
  bool _calPersonal = true;
  bool _calWork = true;
  bool _calStudy = false;
  bool _calFamily = true;
  bool _twoWaySync = true;
  String _bankConnectMethod = 'sepay';

  @override
  void dispose() {
    _inviteCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Scaffold(
      body: LifeOsMintWaveCanvas(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _AuthBrandTopBar(showBack: false),
                        const SizedBox(height: 16),
                        Text(
                          'Xin chào ${state.user?.fullName ?? ''}!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Thiết lập nhanh Gia đình, Google Calendar & Ngân hàng tự động',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                        ),
                        const SizedBox(height: 16),

                        // 3-Step Selector Pills
                        LifeOsSegmentedPills<int>(
                          selected: _stepIndex,
                          options: const [
                            (0, 'Gia đình', Icons.home_outlined),
                            (1, 'Calendar', Icons.calendar_today_outlined),
                            (2, 'Ngân hàng', Icons.account_balance_outlined),
                          ],
                          onChanged: (v) => setState(() => _stepIndex = v),
                        ),
                        const SizedBox(height: 14),

                        if (_stepIndex == 0) _buildFamilyInviteStep(c),
                        if (_stepIndex == 1) _buildCalendarConnectStep(c),
                        if (_stepIndex == 2) _buildBankConnectStep(c),

                        const SizedBox(height: 18),
                        SizedBox(
                          height: 50,
                          child: FilledButton.icon(
                            key: const Key('complete_onboarding_button'),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            onPressed: state.isSubmitting
                                ? null
                                : () => context
                                    .read<AuthBloc>()
                                    .add(const AuthOnboardingCompleted()),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text('Bắt đầu sử dụng Life OS'),
                          ),
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
    );
  }

  Widget _buildFamilyInviteStep(TammySemanticColors c) {
    return LifeOsSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                const LifeOsIconSquircle(
                  icon: Icons.home_work_outlined,
                  tone: LifeOsAccentTone.emerald,
                  size: 50,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tham gia gia đình',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const LifeOsAvatarStack(names: ['Minh', 'Hòa', 'An', 'Bin']),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Mã lời mời gia đình (tùy chọn)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _inviteCodeCtrl,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: c.primary,
            ),
            decoration: InputDecoration(
              fillColor: c.primarySubtle,
              suffixIcon: const Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 12),
          const _PwdCheckItem(
            passed: true,
            label: 'Xem lịch và công việc được chia sẻ',
          ),
          const _PwdCheckItem(
            passed: true,
            label: 'Cùng quản lý quỹ chung theo quyền',
          ),
          const _PwdCheckItem(
            passed: true,
            label: 'Lịch trình & ví riêng luôn được bảo vệ cô lập',
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarConnectStep(TammySemanticColors c) {
    return LifeOsSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const LifeOsIconSquircle(
                icon: Icons.calendar_month_rounded,
                tone: LifeOsAccentTone.blue,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kết nối Google Calendar',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      'Đồng bộ sự kiện hai chiều & nhận nhắc hẹn đúng giờ.',
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _calPersonal,
            activeColor: c.primary,
            title: const Text('Lịch cá nhân'),
            onChanged: (v) => setState(() => _calPersonal = v ?? true),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _calWork,
            activeColor: c.primary,
            title: const Text('Công việc'),
            onChanged: (v) => setState(() => _calWork = v ?? false),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _calStudy,
            activeColor: c.primary,
            title: const Text('Học tập'),
            onChanged: (v) => setState(() => _calStudy = v ?? false),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _calFamily,
            activeColor: c.primary,
            title: const Text('Gia đình'),
            onChanged: (v) => setState(() => _calFamily = v ?? true),
          ),
          const SizedBox(height: 6),
          LifeOsSegmentedPills<bool>(
            selected: _twoWaySync,
            options: const [
              (true, 'Hai chiều', Icons.sync_alt_rounded),
              (false, 'Chỉ đọc', Icons.visibility_outlined),
            ],
            onChanged: (v) => setState(() => _twoWaySync = v),
          ),
        ],
      ),
    );
  }

  Widget _buildBankConnectStep(TammySemanticColors c) {
    return LifeOsSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const LifeOsIconSquircle(
                icon: Icons.account_balance_rounded,
                tone: LifeOsAccentTone.emerald,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kết nối ngân hàng tự động',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      'Tự động nhận diện giao dịch và theo dõi thu chi an toàn.',
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BankMethodOptionTile(
            selected: _bankConnectMethod == 'sepay',
            icon: Icons.link_rounded,
            title: 'SePay Bank Hub',
            subtitle: 'Đồng bộ qua API với ngân hàng và tài khoản được hỗ trợ.',
            onTap: () => setState(() => _bankConnectMethod = 'sepay'),
          ),
          const SizedBox(height: 8),
          _BankMethodOptionTile(
            selected: _bankConnectMethod == 'android_notif',
            icon: Icons.notifications_active_outlined,
            title: 'Thông báo Android',
            subtitle: 'Nhận diện chi tiêu từ thông báo ngân hàng với sự cho phép của bạn.',
            onTap: () => setState(() => _bankConnectMethod = 'android_notif'),
          ),
          const SizedBox(height: 10),
          LifeOsMintHeroCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: c.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Không bao giờ yêu cầu lưu mật khẩu ngân hàng hay mã OTP. Ngắt kết nối bất kỳ lúc nào.',
                    style: TextStyle(fontSize: 12, color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BankMethodOptionTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BankMethodOptionTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? c.primarySubtle : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? c.primary : c.separator,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            LifeOsIconSquircle(icon: icon, tone: LifeOsAccentTone.emerald, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: c.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? c.primary : c.border,
            ),
          ],
        ),
      ),
    );
  }
}
