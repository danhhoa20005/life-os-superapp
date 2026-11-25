import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'lifeos_design_system.dart';

/// Standardized 8-state financial & ledger trust model (Section 14).
enum FinancialTrustStatus {
  saved,
  pendingConfirmation,
  syncing,
  syncFailed,
  reconciled,
  needsReview,
  reversed,
  disputed,
}

extension FinancialTrustStatusX on FinancialTrustStatus {
  String get labelVi => switch (this) {
    FinancialTrustStatus.saved => 'Đã lưu',
    FinancialTrustStatus.pendingConfirmation => 'Chờ xác nhận',
    FinancialTrustStatus.syncing => 'Đang đồng bộ',
    FinancialTrustStatus.syncFailed => 'Đồng bộ thất bại',
    FinancialTrustStatus.reconciled => 'Đã đối soát',
    FinancialTrustStatus.needsReview => 'Cần kiểm tra lại',
    FinancialTrustStatus.reversed => 'Đã đảo bút toán',
    FinancialTrustStatus.disputed => 'Đang tranh chấp',
  };

  IconData get icon => switch (this) {
    FinancialTrustStatus.saved => Icons.check_circle_outline_rounded,
    FinancialTrustStatus.pendingConfirmation => Icons.hourglass_top_rounded,
    FinancialTrustStatus.syncing => Icons.sync_rounded,
    FinancialTrustStatus.syncFailed => Icons.sync_problem_rounded,
    FinancialTrustStatus.reconciled => Icons.verified_rounded,
    FinancialTrustStatus.needsReview => Icons.fact_check_outlined,
    FinancialTrustStatus.reversed => Icons.undo_rounded,
    FinancialTrustStatus.disputed => Icons.gavel_rounded,
  };

  (Color bg, Color fg, double radius, double borderWidth) resolveVisual(
    TammySemanticColors c,
  ) {
    return switch (this) {
      FinancialTrustStatus.saved => (
        c.successSubtle,
        c.success,
        AppSpacing.radiusPill,
        0.9,
      ),
      FinancialTrustStatus.reconciled => (
        c.successSubtle,
        c.success,
        AppSpacing.radiusPill,
        1.1,
      ),
      FinancialTrustStatus.pendingConfirmation => (
        c.warningSubtle,
        c.warning,
        AppSpacing.radiusMd,
        1.0,
      ),
      FinancialTrustStatus.syncing => (
        c.primarySubtle,
        c.primary,
        AppSpacing.radiusMd,
        1.0,
      ),
      FinancialTrustStatus.needsReview => (
        c.warningSubtle,
        c.warning,
        AppSpacing.radiusSm,
        1.15,
      ),
      FinancialTrustStatus.syncFailed => (
        c.errorSubtle,
        c.error,
        AppSpacing.radiusSm,
        1.3,
      ),
      FinancialTrustStatus.reversed => (
        c.warningSubtle,
        c.warning,
        AppSpacing.radiusSm,
        1.2,
      ),
      FinancialTrustStatus.disputed => (
        c.errorSubtle,
        c.error,
        AppSpacing.radiusSm,
        1.35,
      ),
    };
  }
}

/// Accessible financial trust badge pairing icon + label + distinct border geometry (never color-only).
class FinancialTrustStatusBadge extends StatelessWidget {
  final FinancialTrustStatus status;
  final String? customLabel;
  final bool compact;

  const FinancialTrustStatusBadge({
    super.key,
    required this.status,
    this.customLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final label = (customLabel != null && customLabel!.trim().isNotEmpty)
        ? customLabel!.trim()
        : status.labelVi;
    final (bg, fg, radius, borderWidth) = status.resolveVisual(c);

    final textWidget = Text(
      label,
      softWrap: label.length > 12,
      style: TextStyle(
        fontSize: compact ? 11.2 : 12.0,
        height: 1.22,
        fontWeight: FontWeight.w700,
        color: fg,
      ),
    );

    return Semantics(
      container: true,
      label: 'Trạng thái tài chính: $label',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 3.5 : 4.5,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: fg.withValues(alpha: 0.36),
            width: borderWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: compact ? 13 : 14, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: label.length <= 12
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: textWidget,
                    )
                  : textWidget,
            ),
          ],
        ),
      ),
    );
  }
}

/// Clear privacy boundary badge separating Personal-only vs Family-shared records.
class DataVisibilityBadge extends StatelessWidget {
  final bool isFamilyShared;
  final String? customLabel;

  const DataVisibilityBadge({
    super.key,
    required this.isFamilyShared,
    this.customLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final label =
        customLabel ??
        (isFamilyShared ? 'Gia đình · Chia sẻ' : 'Cá nhân · Riêng tư');
    final icon = isFamilyShared
        ? Icons.groups_outlined
        : Icons.lock_outline_rounded;
    final bg = isFamilyShared ? c.primarySubtle : c.surfaceRaised;
    final fg = isFamilyShared ? c.primary : c.textSecondary;

    return Semantics(
      container: true,
      label: isFamilyShared
          ? 'Phạm vi dữ liệu: Gia đình, đang chia sẻ với thành viên nhóm'
          : 'Phạm vi dữ liệu: Cá nhân, chỉ riêng bạn xem được',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: fg.withValues(alpha: 0.28), width: 0.9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.5, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                softWrap: true,
                style: TextStyle(
                  fontSize: 11.8,
                  height: 1.2,
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

/// Honest offline / sync-pending / sync-failed recovery banner with explicit retry action.
class LifeOsOfflineSyncBanner extends StatelessWidget {
  final bool isOffline;
  final bool hasPendingWrites;
  final bool syncFailed;
  final int pendingCount;
  final VoidCallback? onRetry;

  const LifeOsOfflineSyncBanner({
    super.key,
    this.isOffline = false,
    this.hasPendingWrites = false,
    this.syncFailed = false,
    this.pendingCount = 0,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOffline && !hasPendingWrites && !syncFailed) {
      return const SizedBox.shrink();
    }
    final c = TammySemanticColors.of(context);
    final Color bg;
    final Color fg;
    final IconData icon;
    final String title;
    final String subtitle;

    if (syncFailed) {
      bg = c.errorSubtle;
      fg = c.error;
      icon = Icons.sync_problem_rounded;
      title = 'Đồng bộ dữ liệu chưa thành công';
      subtitle =
          'Thay đổi của bạn vẫn được giữ an toàn trên máy. Kiểm tra mạng và thử lại.';
    } else if (isOffline) {
      bg = c.warningSubtle;
      fg = c.warning;
      icon = Icons.cloud_off_rounded;
      title = 'Đang ngoại tuyến — Dữ liệu lưu tạm trên máy';
      subtitle =
          'Ứng dụng sẽ tự đồng bộ lên đám mây ngay khi thiết bị có kết nối mạng.';
    } else {
      bg = c.primarySubtle;
      fg = c.primary;
      icon = Icons.sync_rounded;
      title = pendingCount > 0
          ? 'Đang đồng bộ thay đổi ($pendingCount mục chờ)...'
          : 'Đang đồng bộ thay đổi...';
      subtitle = 'Dữ liệu đã được lưu cục bộ và đang xác nhận với máy chủ.';
    }

    return Semantics(
      liveRegion: true,
      container: true,
      label: '$title. $subtitle',
      child: Container(
        key: const Key('lifeos_offline_sync_banner'),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: fg.withValues(alpha: 0.35), width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 13.2,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.0,
                          height: 1.32,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  key: const Key('offline_sync_retry_btn'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: fg,
                    side: BorderSide(color: fg.withValues(alpha: 0.45)),
                    minimumSize: const Size(
                      AppSpacing.minHitTarget,
                      AppSpacing.minHitTarget,
                    ),
                  ),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Thử đồng bộ lại'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable Just-in-Time Privacy Rationale dialog answering all 4 Section 13 questions
/// before requesting any sensitive device permission. Declining never blocks unrelated features.
Future<bool> showLifeOsJustInTimePermissionRationale(
  BuildContext context, {
  required String title,
  required String whyNeeded,
  required String dataAccessed,
  required String whereProcessed,
  required String howToRevoke,
  IconData icon = Icons.verified_user_outlined,
  LifeOsAccentTone tone = LifeOsAccentTone.emerald,
  String grantLabel = 'Đồng ý cấp quyền',
  String laterLabel = 'Để sau',
}) async {
  final c = TammySemanticColors.of(context);
  final approved = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      key: const Key('lifeos_jit_permission_rationale_dialog'),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LifeOsIconSquircle(icon: icon, tone: tone, size: 40, iconSize: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              softWrap: true,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RationaleRow(
              icon: Icons.help_outline_rounded,
              question: 'Vì sao cần quyền?',
              answer: whyNeeded,
            ),
            const SizedBox(height: AppSpacing.sm),
            _RationaleRow(
              icon: Icons.folder_shared_outlined,
              question: 'Dữ liệu nào được truy cập?',
              answer: dataAccessed,
            ),
            const SizedBox(height: AppSpacing.sm),
            _RationaleRow(
              icon: Icons.phonelink_lock_rounded,
              question: 'Dữ liệu được xử lý ở đâu?',
              answer: whereProcessed,
            ),
            const SizedBox(height: AppSpacing.sm),
            _RationaleRow(
              icon: Icons.tune_rounded,
              question: 'Làm thế nào để tắt quyền?',
              answer: howToRevoke,
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          key: const Key('jit_rationale_later_btn'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(laterLabel),
        ),
        FilledButton(
          key: const Key('jit_rationale_grant_btn'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(grantLabel)),
        ),
      ],
    ),
  );
  return approved ?? false;
}

class _RationaleRow extends StatelessWidget {
  final IconData icon;
  final String question;
  final String answer;

  const _RationaleRow({
    required this.icon,
    required this.question,
    required this.answer,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: c.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: c.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  answer,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 12.0,
                    height: 1.32,
                    color: c.textSecondary,
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
