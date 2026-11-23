import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../bloc/app_update_bloc.dart';

/// Sleek OTA In-App Update notification card displayed on TodayPage whenever a newer release exists.
class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppUpdateBloc, AppUpdateState>(
      builder: (context, state) {
        if (!state.hasUpdate || state.manifest == null) {
          return const SizedBox.shrink();
        }
        if (state.isBannerDismissed && !state.isForceUpdate) {
          return const SizedBox.shrink();
        }

        final manifest = state.manifest!;
        final c = TammySemanticColors.of(context);
        final isDownloading = state.status == AppUpdateStatus.downloading;
        final pct = state.downloadProgress?.percent ?? 0;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Container(
            key: const Key('ota_app_update_banner'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0B3B2E),
                  Color(0xFF0E6248),
                  Color(0xFF0A4D68),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: c.primary.withValues(alpha: 0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BananaGlassIcon(
                      assetPath: AppAssets.icSysOtaUpdate,
                      fallbackIcon: Icons.system_update_rounded,
                      fallbackColor: Color(0xFF86EFAC),
                      size: 42,
                      borderRadius: 12,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.isForceUpdate
                                ? 'Cập nhật Bắt buộc · ${manifest.releaseTitle}'
                                : 'Đã có bản cập nhật mới · v${manifest.latestVersion}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'Hiện tại: v${state.installedVersion} → Mới: v${manifest.latestVersion}'
                            '${manifest.formattedSizeMb != null ? " (${manifest.formattedSizeMb})" : ""}'
                            ' · Nguồn: ${manifest.sourceName}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 12,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!state.isForceUpdate && !isDownloading)
                      IconButton(
                        tooltip: 'Tạm ẩn thông báo cập nhật',
                        onPressed: () => context.read<AppUpdateBloc>().add(
                          const AppUpdateBannerDismissed(),
                        ),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.78),
                          size: 20,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ...manifest.changelog
                    .take(3)
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '• ',
                              style: TextStyle(
                                color: Color(0xFF86EFAC),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                line,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (isDownloading) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (state.downloadProgress?.totalBytes ?? 0) > 0
                          ? state.downloadProgress!.fraction
                          : null,
                      minHeight: 7,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF86EFAC),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đang tải gói cài đặt trực tiếp... $pct%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const Key('ota_install_now_button'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF86EFAC),
                          foregroundColor: const Color(0xFF052E16),
                        ),
                        onPressed: () => context.read<AppUpdateBloc>().add(
                          const AppUpdateDownloadRequested(),
                        ),
                        icon: const Icon(
                          Icons.download_for_offline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          state.status == AppUpdateStatus.permissionRequired ||
                                  state.status == AppUpdateStatus.readyToInstall
                              ? 'Cài đặt bản cập nhật ngay'
                              : 'Tải & Cập nhật ngay',
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        onPressed: () => context.read<AppUpdateBloc>().add(
                          AppUpdateOpenReleasePageRequested(
                            manifest.htmlReleaseUrl,
                          ),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Xem trên GitHub'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Full Version & OTA Update control card embedded inside AccountProfilePage.
class AppUpdateSettingsCard extends StatelessWidget {
  const AppUpdateSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return BlocConsumer<AppUpdateBloc, AppUpdateState>(
      listenWhen: (p, n) =>
          p.infoMessage != n.infoMessage || p.failure != n.failure,
      listener: (context, state) {
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
        final isChecking = state.status == AppUpdateStatus.checking;
        final isDownloading = state.status == AppUpdateStatus.downloading;
        final manifest = state.manifest;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    BananaGlassIcon(
                      assetPath: AppAssets.icSysOtaUpdate,
                      fallbackIcon: Icons.rocket_launch_rounded,
                      fallbackColor: c.primary,
                      size: 42,
                      borderRadius: 12,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Phiên bản ứng dụng',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Đang dùng: v${state.installedDisplay}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                SemanticStatusBadge(
                  kind: state.hasUpdate
                      ? SemanticStatusKind.warning
                      : SemanticStatusKind.success,
                  label: state.hasUpdate
                      ? 'Có bản cập nhật mới: v${manifest?.latestVersion} (${manifest?.sourceName})'
                      : 'Hệ thống đang ở phiên bản mới nhất',
                ),
                if (state.hasUpdate && manifest != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.surfaceRaised,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manifest.releaseTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        ...manifest.changelog.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '• $item',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isDownloading) ...[
                  const SizedBox(height: AppSpacing.sm),
                  LinearProgressIndicator(
                    value: (state.downloadProgress?.totalBytes ?? 0) > 0
                        ? state.downloadProgress!.fraction
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đang tải bản cập nhật... ${state.downloadProgress?.percent ?? 0}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (state.hasUpdate)
                      FilledButton.icon(
                        key: const Key('profile_download_update_button'),
                        onPressed: isDownloading
                            ? null
                            : () => context.read<AppUpdateBloc>().add(
                                const AppUpdateDownloadRequested(),
                              ),
                        icon: const Icon(
                          Icons.system_update_alt_rounded,
                          size: 18,
                        ),
                        label: const Text('Tải & Cài đặt bản mới'),
                      ),
                    OutlinedButton.icon(
                      key: const Key('check_app_update_button'),
                      onPressed: isChecking || isDownloading
                          ? null
                          : () => context.read<AppUpdateBloc>().add(
                              const AppUpdateCheckRequested(silent: false),
                            ),
                      icon: isChecking
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Kiểm tra bản mới'),
                    ),
                    TextButton.icon(
                      onPressed: () => context.read<AppUpdateBloc>().add(
                        const AppUpdateOpenReleasePageRequested(
                          'https://github.com/danhhoa20005/life-os-superapp/releases',
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 17),
                      label: const Text('GitHub Releases'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
