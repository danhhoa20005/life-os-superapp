import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/services/native_device_calendar_bridge.dart';
import '../../../../core/services/native_secure_vault_bridge.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/trust_ux_widgets.dart';
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.primary,
                  ),
                )
              else
                const GoogleBrandMark(size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
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
            onTap:
                onBack ??
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
                      'Tài chính, lịch trình và gia đình trọn vẹn trong một chạm.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: c.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    // Mint Pastel Ecosystem Showcase Circle (#EAFBF0 + Center LeafMark + 4 Domain Squircles)
                    SizedBox(
                      width: 214,
                      height: 214,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 196,
                            height: 196,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? c.primarySubtle
                                  : const Color(0xFFEAFBF0),
                              border: Border.all(
                                color: c.primary.withValues(alpha: 0.20),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: c.primary.withValues(alpha: 0.12),
                                  blurRadius: 28,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 146,
                            height: 146,
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(34),
                              border: Border.all(
                                color: c.primary.withValues(alpha: 0.22),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: c.primary.withValues(alpha: 0.18),
                                  blurRadius: 22,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.asset(
                              AppAssets.hero3dWelcomeEcosystem,
                              width: 146,
                              height: 146,
                              cacheWidth: 438,
                              cacheHeight: 438,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: LifeOsLeafMark(
                                  size: 56,
                                  borderRadius: 16,
                                ),
                              ),
                            ),
                          ),
                          const Positioned(
                            top: 12,
                            left: 16,
                            child: _WelcomeOrbitBadge(
                              icon: Icons.account_balance_wallet_outlined,
                              tone: LifeOsAccentTone.emerald,
                            ),
                          ),
                          const Positioned(
                            top: 12,
                            right: 16,
                            child: _WelcomeOrbitBadge(
                              icon: Icons.calendar_month_rounded,
                              tone: LifeOsAccentTone.blue,
                            ),
                          ),
                          const Positioned(
                            bottom: 12,
                            left: 16,
                            child: _WelcomeOrbitBadge(
                              icon: Icons.groups_rounded,
                              tone: LifeOsAccentTone.amber,
                            ),
                          ),
                          const Positioned(
                            bottom: 12,
                            right: 16,
                            child: _WelcomeOrbitBadge(
                              icon: Icons.shield_outlined,
                              tone: LifeOsAccentTone.purple,
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

class _WelcomeOrbitBadge extends StatelessWidget {
  final IconData icon;
  final LifeOsAccentTone tone;

  const _WelcomeOrbitBadge({required this.icon, required this.tone});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: c.primary.withValues(alpha: 0.16),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LifeOsIconSquircle(icon: icon, tone: tone, size: 36, iconSize: 18),
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
  final LifeOsOneShotEffectTracker _errorEffectTracker =
      LifeOsOneShotEffectTracker();
  bool _obscurePassword = true;
  bool _hadActiveFailure = false;
  int _failureGeneration = 0;
  int _errorShakeTrigger = 0;

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
            prev.failure != curr.failure ||
            prev.infoMessage != curr.infoMessage,
        listener: (context, state) {
          if (state.failure == null && _hadActiveFailure) {
            _hadActiveFailure = false;
            _failureGeneration++;
          }
          if (state.failure != null) {
            _hadActiveFailure = true;
            final effectKey =
                'login_err_${_failureGeneration}_${state.failure!.code}_${state.failure!.message}';
            if (_errorEffectTracker.consumeOnce(effectKey)) {
              setState(() => _errorShakeTrigger++);
            }
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
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            LifeOsSoftCard(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Email đăng nhập',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
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
                                      prefixIcon: Icon(
                                        Icons.mail_outline_rounded,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Mật khẩu',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    key: const Key('login_password_field'),
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) {
                                      if (!state.isSubmitting) {
                                        _submitEmailSignIn();
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText: '••••••••',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePassword
                                            ? 'Hiện mật khẩu'
                                            : 'Ẩn mật khẩu',
                                        onPressed: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
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
                                              extra: _emailController.text
                                                  .trim(),
                                            ),
                                      child: const Text('Quên mật khẩu?'),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  LifeOsPressable(
                                    passthroughPointerOnly: true,
                                    enabled: !state.isSubmitting,
                                    child: SizedBox(
                                      height: 50,
                                      child: FilledButton(
                                        key: const Key('login_submit_button'),
                                        style: FilledButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              25,
                                            ),
                                          ),
                                        ),
                                        onPressed: state.isSubmitting
                                            ? null
                                            : _submitEmailSignIn,
                                        child: state.isSubmitting
                                            ? SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.2,
                                                      color: c.onPrimary,
                                                    ),
                                              )
                                            : const Text('Đăng nhập'),
                                      ),
                                    ),
                                  ),
                                  const _AuthSectionDivider(
                                    text: 'Hoặc tiếp tục với',
                                  ),
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
                            ).lifeOsErrorShake(
                              context: context,
                              triggerCount: _errorShakeTrigger,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Chưa có tài khoản?',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: c.textSecondary,
                                  ),
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
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final LifeOsOneShotEffectTracker _errorEffectTracker =
      LifeOsOneShotEffectTracker();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = true;
  bool _hadActiveFailure = false;
  int _failureGeneration = 0;
  int _errorShakeTrigger = 0;

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
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
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
          if (state.failure == null && _hadActiveFailure) {
            _hadActiveFailure = false;
            _failureGeneration++;
          }
          if (state.failure != null) {
            _hadActiveFailure = true;
            final effectKey =
                'register_err_${_failureGeneration}_${state.failure!.code}_${state.failure!.message}';
            if (_errorEffectTracker.consumeOnce(effectKey)) {
              setState(() => _errorShakeTrigger++);
            }
            LifeOsTopToast.fromSnackBar(
              context,
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
                              style: TextStyle(
                                fontSize: 13.5,
                                color: c.textSecondary,
                              ),
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
                                  const _AuthSectionDivider(
                                    text: 'Hoặc đăng ký bằng Email',
                                  ),
                                  Text(
                                    'Họ và tên',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    key: const Key('register_name_field'),
                                    controller: _nameController,
                                    autofillHints: const [AutofillHints.name],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      hintText: 'Nhập họ và tên của bạn',
                                      prefixIcon: Icon(
                                        Icons.person_outline_rounded,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Email',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    key: const Key('register_email_field'),
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      hintText: 'Nhập địa chỉ email',
                                      prefixIcon: Icon(
                                        Icons.mail_outline_rounded,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Số điện thoại (tùy chọn)',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    key: const Key('register_phone_field'),
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    autofillHints: const [
                                      AutofillHints.telephoneNumber,
                                    ],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      hintText: '0901 234 567',
                                      prefixIcon: Icon(
                                        Icons.phone_iphone_rounded,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Mật khẩu',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    key: const Key('register_password_field'),
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    textInputAction: TextInputAction.next,
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      hintText: '••••••••',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePassword
                                            ? 'Hiện mật khẩu'
                                            : 'Ẩn mật khẩu',
                                        onPressed: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    key: const Key(
                                      'register_confirm_password_field',
                                    ),
                                    controller: _confirmPasswordController,
                                    obscureText: _obscureConfirmPassword,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    textInputAction: TextInputAction.done,
                                    decoration: InputDecoration(
                                      hintText: '••••••••',
                                      prefixIcon: const Icon(
                                        Icons.verified_user_outlined,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: _obscureConfirmPassword
                                            ? 'Hiện mật khẩu'
                                            : 'Ẩn mật khẩu',
                                        onPressed: () => setState(
                                          () => _obscureConfirmPassword =
                                              !_obscureConfirmPassword,
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
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: c.primary,
                                    onChanged: (v) => setState(
                                      () => _acceptedTerms = v ?? false,
                                    ),
                                    title: Text(
                                      'Tôi đồng ý với Điều khoản sử dụng và Chính sách quyền riêng tư.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  LifeOsPressable(
                                    passthroughPointerOnly: true,
                                    enabled: !state.isSubmitting,
                                    child: SizedBox(
                                      height: 50,
                                      child: FilledButton(
                                        key: const Key(
                                          'register_submit_button',
                                        ),
                                        style: FilledButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              25,
                                            ),
                                          ),
                                        ),
                                        onPressed: state.isSubmitting
                                            ? null
                                            : () {
                                                context.read<AuthBloc>().add(
                                                  AuthSignUpSubmitted(
                                                    email:
                                                        _emailController.text,
                                                    password:
                                                        _passwordController
                                                            .text,
                                                    confirmPassword:
                                                        _confirmPasswordController
                                                            .text,
                                                    fullName:
                                                        _nameController.text,
                                                    phoneNumber:
                                                        _phoneController.text,
                                                    acceptedTerms:
                                                        _acceptedTerms,
                                                  ),
                                                );
                                              },
                                        child: state.isSubmitting
                                            ? SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: c.onPrimary,
                                                    ),
                                              )
                                            : const Text('Đăng ký'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ).lifeOsErrorShake(
                              context: context,
                              triggerCount: _errorShakeTrigger,
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Đã có tài khoản?',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: c.textSecondary,
                                  ),
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
                    Text(
                      'Địa chỉ email',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
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
                      label: 'Gửi liên kết qua Email',
                      onPressed: () {
                        final email = _emailCtrl.text.trim();
                        if (email.isEmpty) {
                          LifeOsTopToast.show(
                            context,
                            'Vui lòng nhập email đã đăng ký.',
                            kind: LifeOsToastKind.warning,
                          );
                          return;
                        }
                        context.read<AuthBloc>().add(
                          AuthPasswordResetRequested(email),
                        );
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

/// Screen 05 of Auth Sheet: Honest Email Verification Link Guidance (`/verify-otp`).
class VerifyOtpPage extends StatefulWidget {
  final String? email;

  const VerifyOtpPage({super.key, this.email});

  @override
  State<VerifyOtpPage> createState() => _VerifyOtpPageState();
}

class _VerifyOtpPageState extends State<VerifyOtpPage> {
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

  void _resendResetEmail() {
    final email = (widget.email ?? '').trim();
    if (email.isEmpty) {
      LifeOsTopToast.show(
        context,
        'Vui lòng quay lại và nhập email hợp lệ.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    context.read<AuthBloc>().add(AuthPasswordResetRequested(email));
    setState(() => _secondsLeft = 58);
    LifeOsTopToast.show(
      context,
      'Đã gửi lại liên kết đặt lại mật khẩu đến $email.',
      kind: LifeOsToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final emailDisplay = (widget.email ?? '').trim().isEmpty
        ? 'email đã đăng ký của bạn'
        : widget.email!.trim();
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
                        child: Icon(
                          Icons.mark_email_read_outlined,
                          size: 34,
                          color: c.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Kiểm tra email xác minh',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Liên kết đặt lại mật khẩu từ Firebase Authentication đã được gửi đến $emailDisplay.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                    ),
                    const SizedBox(height: 18),
                    LifeOsSoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 20,
                                color: c.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Xác thực qua liên kết bảo mật',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '1. Mở hộp thư đến hoặc thư mục Spam để tìm email từ LifeOS / Firebase.\n'
                            '2. Nhấn vào liên kết để tạo mật khẩu mới trực tiếp trên trang xác thực an toàn.\n'
                            '3. Quay lại LifeOS và đăng nhập bằng mật khẩu mới.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    LifeOsPrimaryCtaButton(
                      label: 'Quay lại đăng nhập',
                      onPressed: () => context.go('/login'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _secondsLeft == 0
                              ? _resendResetEmail
                              : null,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, AppSpacing.minHitTarget),
                          ),
                          child: Text(
                            _secondsLeft > 0
                                ? 'Gửi lại sau $mm:$ss'
                                : 'Gửi lại liên kết',
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => context.pop(),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, AppSpacing.minHitTarget),
                          ),
                          child: const Text('Đổi email'),
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

/// Screen 06 of Auth Sheet: Honest Password Reset Guidance (`/reset-password`).
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController _emailCtrl = TextEditingController();

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
                        child: Icon(
                          Icons.lock_reset_rounded,
                          size: 34,
                          color: c.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Đặt lại mật khẩu qua Email',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Vì an toàn tài khoản, mật khẩu mới chỉ được cập nhật thông qua liên kết xác thực gửi tới email của bạn.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    LifeOsSoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Email tài khoản',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              hintText: 'Nhập email để gửi lại liên kết',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                AppSpacing.buttonHeightM,
                              ),
                            ),
                            onPressed: () {
                              final email = _emailCtrl.text.trim();
                              if (email.isEmpty) {
                                LifeOsTopToast.show(
                                  context,
                                  'Vui lòng nhập email của bạn trước.',
                                  kind: LifeOsToastKind.warning,
                                );
                                return;
                              }
                              context.read<AuthBloc>().add(
                                AuthPasswordResetRequested(email),
                              );
                              LifeOsTopToast.show(
                                context,
                                'Đã gửi liên kết đặt lại mật khẩu đến $email.',
                                kind: LifeOsToastKind.success,
                              );
                            },
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text('Gửi liên kết qua Email'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    LifeOsPrimaryCtaButton(
                      label: 'Quay lại đăng nhập',
                      onPressed: () => context.go('/login'),
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
            passed
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: passed ? c.primary : c.border,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              softWrap: true,
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
  static const List<(String, String, IconData)> _interestOptions = [
    ('expense', 'Quản lý chi tiêu', Icons.account_balance_wallet_outlined),
    ('calendar', 'Quản lý lịch', Icons.event_note_outlined),
    ('family', 'Quản lý gia đình', Icons.family_restroom_outlined),
    ('home', 'Quản lý nhà cửa', Icons.home_outlined),
    ('vehicle', 'Quản lý xe cộ', Icons.directions_car_outlined),
    ('all', 'Tất cả', Icons.apps_rounded),
  ];

  int _stepIndex = 0;
  final TextEditingController _inviteCodeCtrl = TextEditingController();
  final Set<String> _selectedInterests = <String>{'expense', 'calendar'};
  bool _calPersonal = true;
  bool _calWork = true;
  bool _calStudy = false;
  bool _calFamily = true;
  bool _twoWaySync = true;
  String _bankConnectMethod = 'sepay';
  bool _autoCompletingSkip = false;

  String _userScopeSuffix(BuildContext context) {
    final uid = context.read<AuthBloc>().state.user?.id.trim() ?? '';
    return uid.isEmpty ? 'guest' : uid;
  }

  String _skipVaultKey(BuildContext context) =>
      'ux_onboarding_skipped_v1__u_${_userScopeSuffix(context)}';

  String _interestsVaultKey(BuildContext context) =>
      'ux_user_interests_v1__u_${_userScopeSuffix(context)}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreOnboardingPrefs();
    });
  }

  Future<void> _restoreOnboardingPrefs() async {
    final skipKey = _skipVaultKey(context);
    final interestsKey = _interestsVaultKey(context);
    final skipped = await NativeSecureVaultBridge.instance.readSecret(skipKey);
    if (!mounted) return;
    if (skipped == '1' && !_autoCompletingSkip) {
      _autoCompletingSkip = true;
      context.read<AuthBloc>().add(const AuthOnboardingCompleted());
      return;
    }

    final savedInterestsRaw = await NativeSecureVaultBridge.instance.readSecret(
      interestsKey,
    );
    if (!mounted || savedInterestsRaw == null || savedInterestsRaw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(savedInterestsRaw);
      if (decoded is List) {
        final next = decoded.map((e) => e.toString()).toSet();
        if (next.isNotEmpty) {
          setState(() {
            _selectedInterests
              ..clear()
              ..addAll(next);
          });
        }
      }
    } catch (_) {
      // Bỏ qua dữ liệu nhu cầu cũ không hợp lệ.
    }
  }

  Future<void> _toggleInterest(String id) async {
    final domainIds = <String>{
      'expense',
      'calendar',
      'family',
      'home',
      'vehicle',
    };
    setState(() {
      if (id == 'all') {
        if (_selectedInterests.contains('all')) {
          _selectedInterests.remove('all');
        } else {
          _selectedInterests
            ..addAll(domainIds)
            ..add('all');
        }
      } else {
        if (_selectedInterests.contains(id)) {
          _selectedInterests.remove(id);
          _selectedInterests.remove('all');
        } else {
          _selectedInterests.add(id);
          if (domainIds.every(_selectedInterests.contains)) {
            _selectedInterests.add('all');
          }
        }
      }
    });
    await NativeSecureVaultBridge.instance.writeSecret(
      key: _interestsVaultKey(context),
      value: jsonEncode(_selectedInterests.toList()),
    );
  }

  Future<void> _skipOnboarding() async {
    final skipKey = _skipVaultKey(context);
    final interestsKey = _interestsVaultKey(context);
    await NativeSecureVaultBridge.instance.writeSecret(
      key: skipKey,
      value: '1',
    );
    await NativeSecureVaultBridge.instance.writeSecret(
      key: interestsKey,
      value: jsonEncode(_selectedInterests.toList()),
    );
    if (!mounted) return;
    context.read<AuthBloc>().add(const AuthOnboardingCompleted());
  }

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
                        Row(
                          children: [
                            const Expanded(child: SizedBox()),
                            const LifeOsBrandWordmark(
                              iconSize: 28,
                              fontSize: 18,
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Semantics(
                                  button: true,
                                  label: 'Bỏ qua thiết lập ban đầu',
                                  child: TextButton(
                                    key: const Key('onboarding_skip_btn'),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(
                                        64,
                                        AppSpacing.minHitTarget,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                    ),
                                    onPressed: state.isSubmitting
                                        ? null
                                        : _skipOnboarding,
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Bỏ qua'),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
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
                          'Thiết lập nhanh nhu cầu, Gia đình, Lịch trình & Ngân hàng theo quyền chọn của bạn',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        LifeOsSoftCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chọn nhu cầu quan tâm',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final opt in _interestOptions)
                                    FilterChip(
                                      key: Key('onboarding_interest_${opt.$1}'),
                                      selected: _selectedInterests.contains(
                                        opt.$1,
                                      ),
                                      avatar: Icon(opt.$3, size: 16),
                                      label: Text(opt.$2),
                                      selectedColor: c.primarySubtle,
                                      checkmarkColor: c.primary,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.padded,
                                      onSelected: (_) =>
                                          _toggleInterest(opt.$1),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 3-Step Selector Pills
                        LifeOsSegmentedPills<int>(
                          selected: _stepIndex,
                          options: const [
                            (0, 'Gia đình', Icons.home_outlined),
                            (1, 'Lịch trình', Icons.calendar_today_outlined),
                            (2, 'Ngân hàng', Icons.account_balance_outlined),
                          ],
                          onChanged: (v) => setState(() => _stepIndex = v),
                        ),
                        const SizedBox(height: 14),

                        if (_stepIndex == 0) _buildFamilyInviteStep(c),
                        if (_stepIndex == 1) _buildCalendarConnectStep(c),
                        if (_stepIndex == 2) _buildBankConnectStep(c),

                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          key: const Key(
                            'onboarding_open_permissions_popup_btn',
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(
                              AppSpacing.buttonHeightM,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          onPressed: () => showLifeOsPermissionsPopup(
                            context,
                            markDismissedOnClose: false,
                          ),
                          icon: const Icon(
                            Icons.verified_user_outlined,
                            size: 18,
                          ),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Cấp nhanh quyền Micro · Thông báo · Lịch',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
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
                                : () => context.read<AuthBloc>().add(
                                    const AuthOnboardingCompleted(),
                                  ),
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
                Text(
                  'Chỉ kết nối khi bạn nhập mã mời hợp lệ từ người thân.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
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
              hintText: 'VD: FAM-8K2P9Q',
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
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('onboarding_grant_device_calendar_btn'),
            onPressed: () async {
              final consented = await showLifeOsJustInTimePermissionRationale(
                context,
                title: 'Kết nối Lịch trên máy',
                whyNeeded:
                    'Đồng bộ các sự kiện bạn chọn và hiển thị nhắc hẹn đúng giờ ngay trong Lịch & Việc.',
                dataAccessed:
                    'Chỉ đọc tiêu đề và thời gian của các lịch bạn đánh dấu ở trên; không đọc danh bạ hay lịch riêng bị bỏ chọn.',
                whereProcessed:
                    'Đọc trực tiếp trên thiết bị và chỉ đồng bộ khi bạn bật chế độ đồng bộ hai chiều.',
                howToRevoke:
                    'Mở Cài đặt > Quyền riêng tư & Quyền ứng dụng hoặc tắt quyền Lịch trong Cài đặt hệ thống.',
              );
              if (!consented || !context.mounted) return;
              final granted = await NativeDeviceCalendarBridge.instance
                  .requestPermission();
              if (!mounted) return;
              LifeOsTopToast.show(
                context,
                granted
                    ? 'Đã kết nối Lịch trên máy thành công!'
                    : 'Bạn có thể cấp quyền Lịch bất cứ lúc nào trong Lịch & Việc.',
                kind: granted ? LifeOsToastKind.success : LifeOsToastKind.info,
              );
            },
            icon: const Icon(Icons.event_available_rounded, size: 18),
            label: const Text('Cấp quyền Lịch trên máy ngay'),
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
            icon: Icons.qr_code_2_rounded,
            title: 'Cổng QR Thu tiền & Tự gạch nợ',
            subtitle:
                'Tạo mã VietQR ngay trong ứng dụng và tự xác nhận khi tiền vào.',
            onTap: () => setState(() => _bankConnectMethod = 'sepay'),
          ),
          const SizedBox(height: 8),
          _BankMethodOptionTile(
            selected: _bankConnectMethod == 'android_notif',
            icon: Icons.notifications_active_outlined,
            title: 'Thông báo Android',
            subtitle:
                'Nhận diện chi tiêu từ thông báo ngân hàng với sự cho phép của bạn.',
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
            LifeOsIconSquircle(
              icon: icon,
              tone: LifeOsAccentTone.emerald,
              size: 38,
            ),
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
