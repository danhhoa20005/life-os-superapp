import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/status_widgets.dart';

/// Flagship Tammy × Apple Splash Screen displayed while initializing Firebase session
/// or previewing Life OS brand identity.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: const Key('life_os_splash_page'),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF05180B), Color(0xFF000000), Color(0xFF071F10)]
                : const [Color(0xFFEAF6EE), Color(0xFFF7F9F8), Color(0xFFE8F1FB)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.94, end: 1.0),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, child) => Transform.scale(
                    scale: scale,
                    child: child,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 210,
                        height: 210,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(42),
                          border: Border.all(color: c.separator),
                          boxShadow: [
                            BoxShadow(
                              color: c.primary.withValues(alpha: 0.16),
                              blurRadius: 36,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              AppAssets.splashHero,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(
                                  Icons.shield_rounded,
                                  size: 72,
                                  color: c.primary,
                                ),
                              ),
                            ),
                            const Positioned(
                              right: 12,
                              bottom: 12,
                              child: BrandLogoMark(size: 44, borderRadius: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Life OS',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Tài chính Cá nhân · Hội nhóm · Gia đình',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: c.textSecondary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const SemanticStatusBadge(
                        kind: SemanticStatusKind.info,
                        label: 'Privacy-by-Default · Chuẩn Sổ cái VND',
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: c.primary,
                        ),
                      ),
                    ],
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
