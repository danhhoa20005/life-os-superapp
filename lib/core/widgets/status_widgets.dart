import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'liquid_glass.dart';

/// WCAG 2.2 AA compliant semantic badge: NEVER conveys meaning by color alone (always Icon + Label).
enum SemanticStatusKind { success, warning, error, info, provisional }

class SemanticStatusBadge extends StatelessWidget {
  final SemanticStatusKind kind;
  final String label;

  const SemanticStatusBadge({
    super.key,
    required this.kind,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final (bg, fg, icon) = switch (kind) {
      SemanticStatusKind.success => (
        c.successSubtle,
        c.success,
        Icons.check_circle_rounded,
      ),
      SemanticStatusKind.warning => (
        c.warningSubtle,
        c.warning,
        Icons.warning_amber_rounded,
      ),
      SemanticStatusKind.error => (
        c.errorSubtle,
        c.error,
        Icons.error_outline_rounded,
      ),
      SemanticStatusKind.provisional => (
        c.warningSubtle,
        c.warning,
        Icons.hourglass_top_rounded,
      ),
      SemanticStatusKind.info => (
        c.primarySubtle,
        c.primary,
        Icons.verified_user_outlined,
      ),
    };

    return Semantics(
      label: 'Trạng thái: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: fg.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sync state indicator distinguishing local offline cache (`hasPendingWrites`) from Cloud-confirmed data.
class CloudSyncIndicator extends StatelessWidget {
  final bool hasPendingWrites;

  const CloudSyncIndicator({super.key, required this.hasPendingWrites});

  @override
  Widget build(BuildContext context) {
    return SemanticStatusBadge(
      kind: hasPendingWrites
          ? SemanticStatusKind.warning
          : SemanticStatusKind.success,
      label: hasPendingWrites ? 'Đang đồng bộ' : 'Đã đồng bộ',
    );
  }
}

/// Apple Liquid Glass header container — strictly reserved for navigation bars/toolbars (`a.docx`).
class LiquidGlassBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;

  const LiquidGlassBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LiquidGlassTokens.surfaceGradient(
              isDark: isDark,
              material: LiquidGlassMaterial.navigationChrome,
            ),
          ),
          child: AppBar(
            leading: leading,
            title: title,
            actions: actions,
            backgroundColor: Colors.transparent,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(
                height: 1.0,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            Colors.white.withValues(alpha: 0.22),
                            c.separator.withValues(alpha: 0.65),
                            Colors.white.withValues(alpha: 0.14),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.95),
                            c.separator.withValues(alpha: 0.72),
                            Colors.white.withValues(alpha: 0.85),
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

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String? imageAsset;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateView({
    super.key,
    required this.icon,
    this.imageAsset,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageAsset != null)
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: c.primarySubtle.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  border: Border.all(color: c.separator),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  imageAsset!,
                  width: 128,
                  height: 128,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(icon, size: 40, color: c.primary),
                ),
              )
            else
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: c.primarySubtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: c.primary),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorRetryView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorRetryView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 42, color: c.error),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showDestructiveConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final c = TammySemanticColors.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
