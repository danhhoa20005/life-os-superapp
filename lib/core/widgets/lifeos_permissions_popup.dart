import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../services/native_permissions_service.dart';
import '../utils/user_behavior_prefs.dart';
import 'lifeos_design_system.dart';

bool _isPermissionsPopupOpen = false;
BuildContext? _activePermissionsPopupContext;

/// Opens the unified Motion-v2 Device Permissions Request Popup (`Popup Xin Quyền Hạn`).
///
/// - Uses Material Motion `FadeScaleTransition` (degrading cleanly under Reduce Motion).
/// - Supports 1-tap batch request of Essential Permissions (Notifications, Microphone, Calendar)
///   plus granular 1-tap setup for Exact Alarms, Unrestricted Background & Bank Notification Listener.
/// - Auto-refreshes live status when returning from Android System Settings (`AppLifecycleState.resumed`).
Future<AppPermissionsSnapshot?> showLifeOsPermissionsPopup(
  BuildContext context, {
  AppPermissionsSnapshot? initialSnapshot,
  bool markDismissedOnClose = true,
}) async {
  if (_isPermissionsPopupOpen &&
      (_activePermissionsPopupContext?.mounted ?? false)) {
    return null;
  }
  _isPermissionsPopupOpen = true;

  try {
    final motion = LifeOsMotionScope.read(context);
    final enterDuration = motion.resolveDuration(LifeOsMotionTokens.standard);

    return await showGeneralDialog<AppPermissionsSnapshot>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Đóng bảng cấp quyền',
      barrierColor: Colors.black.withValues(alpha: 0.48),
      transitionDuration: enterDuration,
      pageBuilder: (dialogCtx, _, _) {
        return _LifeOsPermissionsDialog(
          initialSnapshot: initialSnapshot,
          markDismissedOnClose: markDismissedOnClose,
        );
      },
      transitionBuilder: (ctx, animation, _, child) {
        final m = LifeOsMotionScope.of(ctx);
        if (m.isMotionOff) return child;
        if (m.isReducedMotion) {
          return FadeTransition(opacity: animation, child: child);
        }
        return FadeScaleTransition(animation: animation, child: child);
      },
    );
  } finally {
    _isPermissionsPopupOpen = false;
    _activePermissionsPopupContext = null;
  }
}

class _LifeOsPermissionsDialog extends StatefulWidget {
  final AppPermissionsSnapshot? initialSnapshot;
  final bool markDismissedOnClose;

  const _LifeOsPermissionsDialog({
    this.initialSnapshot,
    required this.markDismissedOnClose,
  });

  @override
  State<_LifeOsPermissionsDialog> createState() =>
      _LifeOsPermissionsDialogState();
}

class _LifeOsPermissionsDialogState extends State<_LifeOsPermissionsDialog>
    with WidgetsBindingObserver {
  AppPermissionsSnapshot _snapshot = AppPermissionsSnapshot.allMissing;
  bool _isLoading = true;
  bool _isRequestingBatch = false;
  LifeOsPermissionKind? _activeRequestKind;

  @override
  void initState() {
    super.initState();
    _activePermissionsPopupContext = context;
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialSnapshot != null) {
      _snapshot = widget.initialSnapshot!;
      _isLoading = false;
    } else {
      _refreshSnapshot();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSnapshot();
    }
  }

  Future<void> _refreshSnapshot() async {
    final latest = await NativePermissionsService.instance.checkAll();
    if (!mounted) return;
    setState(() {
      _snapshot = latest;
      _isLoading = false;
    });
  }

  Future<void> _handleGrantEssential() async {
    if (_isRequestingBatch) return;
    if (_snapshot.isAllEssentialGranted) {
      if (widget.markDismissedOnClose) {
        await UserBehaviorPrefs.markPermissionsPopupDismissed(true);
      }
      if (mounted) Navigator.of(context).pop(_snapshot);
      return;
    }

    setState(() => _isRequestingBatch = true);
    final updated = await NativePermissionsService.instance.requestEssential();
    if (!mounted) return;
    setState(() {
      _snapshot = updated;
      _isRequestingBatch = false;
    });
    if (updated.isAllEssentialGranted) {
      await UserBehaviorPrefs.markPermissionsPopupDismissed(true);
      if (mounted) {
        LifeOsTopToast.show(
          context,
          'Đã cấp đủ quyền cơ bản cho LifeOS!',
          kind: LifeOsToastKind.success,
        );
      }
    }
  }

  Future<void> _handleGrantSingle(LifeOsPermissionKind kind) async {
    if (_activeRequestKind != null || _isRequestingBatch) return;
    setState(() => _activeRequestKind = kind);
    final updated = await NativePermissionsService.instance.requestSingle(kind);
    if (!mounted) return;
    setState(() {
      _snapshot = updated;
      _activeRequestKind = null;
    });
  }

  Future<void> _handleDismiss() async {
    if (widget.markDismissedOnClose) {
      await UserBehaviorPrefs.markPermissionsPopupDismissed(true);
    }
    if (mounted) {
      Navigator.of(context).pop(_snapshot);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_activePermissionsPopupContext == context) {
      _activePermissionsPopupContext = null;
    }
    _isPermissionsPopupOpen = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final snap = _snapshot;

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
            child: Material(
              key: const Key('lifeos_permissions_popup_dialog'),
              color: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: c.border, width: 0.9),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Header + Status Pill + Close
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const LifeOsIconSquircle(
                              icon: Icons.verified_user_outlined,
                              tone: LifeOsAccentTone.emerald,
                              size: 42,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cấp quyền thiết bị',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Bật quyền cần thiết để nhắc lịch, thu âm và đồng bộ ổn định.',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12.2,
                                      height: 1.3,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              key: const Key(
                                'permissions_popup_close_icon_btn',
                              ),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Đóng',
                              onPressed: _handleDismiss,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 2. Progress Bar + Tabular Summary Badge
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Text(
                              'Quyền cơ bản (${snap.essentialGrantedCount}/3)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            LifeOsAnimatedStatusBadge(
                              statusKey: 'perm_count_${snap.totalGrantedCount}',
                              label: 'Đã bật ${snap.totalGrantedCount}/6',
                              icon: snap.isAllEssentialGranted
                                  ? Icons.check_circle_rounded
                                  : Icons.tune_rounded,
                              tone: snap.isAllEssentialGranted
                                  ? LifeOsAccentTone.emerald
                                  : LifeOsAccentTone.amber,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LifeOsAnimatedProgressBar(
                          progressRatio: _isLoading
                              ? 0.0
                              : snap.totalGrantedCount / 6.0,
                          color: c.primary,
                          height: 6.5,
                          semanticsLabel: 'Tiến độ cấp quyền thiết bị',
                          semanticsValue:
                              '${snap.totalGrantedCount} trên 6 quyền',
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.separator),

                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 3. Essential 3 Runtime Permissions
                          _PermissionItemRow(
                            rowKey: const Key('perm_item_notifications'),
                            actionKey: const Key('perm_action_notifications'),
                            icon: Icons.notifications_active_outlined,
                            tone: LifeOsAccentTone.emerald,
                            title: 'Thông báo nhắc nhở',
                            subtitle:
                                'Nhắc lịch hẹn, uống nước & uống thuốc đúng giờ',
                            whyNeeded:
                                'Gửi thông báo nhắc lịch hẹn, thuốc men và biến động đã đăng ký.',
                            dataAccessed:
                                'Chỉ gửi thông báo từ LifeOS, không đọc tin nhắn ứng dụng khác.',
                            whereProcessed:
                                'Hiển thị trực tiếp trên thiết bị (có tùy chọn ẩn số tiền ở màn hình khóa).',
                            howToRevoke:
                                'Tắt bất kỳ lúc nào tại Cài đặt > Thông báo trên điện thoại.',
                            granted: snap.notifications,
                            busy:
                                _activeRequestKind ==
                                LifeOsPermissionKind.notifications,
                            onRequest: () => _handleGrantSingle(
                              LifeOsPermissionKind.notifications,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PermissionItemRow(
                            rowKey: const Key('perm_item_microphone'),
                            actionKey: const Key('perm_action_microphone'),
                            icon: Icons.mic_none_rounded,
                            tone: LifeOsAccentTone.blue,
                            title: 'Micro giọng nói',
                            subtitle:
                                'Ghi nhanh thu chi & việc làm bằng giọng nói',
                            whyNeeded:
                                'Chuyển lời nói tiếng Việt thành giao dịch hoặc nhắc việc nhanh.',
                            dataAccessed:
                                'Âm thanh chỉ được thu khi bạn chủ động bấm nút Micro.',
                            whereProcessed:
                                'Nhận diện ngay trên máy hoặc dịch vụ giọng nói khi bạn xác nhận.',
                            howToRevoke:
                                'Thu hồi bất kỳ lúc nào trong Cài đặt > Quyền ứng dụng > Micro.',
                            granted: snap.microphone,
                            busy:
                                _activeRequestKind ==
                                LifeOsPermissionKind.microphone,
                            onRequest: () => _handleGrantSingle(
                              LifeOsPermissionKind.microphone,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PermissionItemRow(
                            rowKey: const Key('perm_item_calendar'),
                            actionKey: const Key('perm_action_calendar'),
                            icon: Icons.calendar_month_outlined,
                            tone: LifeOsAccentTone.purple,
                            title: 'Lịch trên điện thoại',
                            subtitle:
                                'Đồng bộ sự kiện hai chiều với lịch hệ thống',
                            whyNeeded:
                                'Đồng bộ lịch hẹn gia đình và công việc với Lịch trên điện thoại.',
                            dataAccessed:
                                'Chỉ đọc và ghi các sự kiện trong bộ lịch bạn chọn đồng bộ.',
                            whereProcessed:
                                'Đồng bộ trực tiếp với ứng dụng Lịch cục bộ trên thiết bị.',
                            howToRevoke:
                                'Tắt bất kỳ lúc nào trong Cài đặt > Quyền ứng dụng > Lịch.',
                            granted: snap.calendar,
                            busy:
                                _activeRequestKind ==
                                LifeOsPermissionKind.calendar,
                            onRequest: () => _handleGrantSingle(
                              LifeOsPermissionKind.calendar,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 4. Progressive Disclosure for Advanced Background & Banking Permissions
                          LifeOsDetailsDiscloseSection(
                            toggleKey: const Key('perm_popup_advanced_toggle'),
                            label:
                                'Quyền chạy ngầm & tự động (${snap.advancedGrantedCount}/3)',
                            expandedLabel: 'Thu gọn quyền nâng cao',
                            child: Column(
                              children: [
                                _PermissionItemRow(
                                  rowKey: const Key('perm_item_exactAlarm'),
                                  actionKey: const Key(
                                    'perm_action_exactAlarm',
                                  ),
                                  icon: Icons.alarm_on_rounded,
                                  tone: LifeOsAccentTone.amber,
                                  title: 'Báo thức chuẩn giờ',
                                  subtitle:
                                      'Đổ chuông lịch hẹn chính xác từng phút',
                                  whyNeeded:
                                      'Đảm bảo chuông nhắc thuốc và lịch quan trọng reo đúng giờ.',
                                  dataAccessed:
                                      'Chỉ đặt lịch đánh thức báo thức nội bộ, không thu thập dữ liệu cá nhân.',
                                  whereProcessed:
                                      'Xử lý hoàn toàn cục bộ qua bộ hẹn giờ hệ thống Android.',
                                  howToRevoke:
                                      'Tắt trong Cài đặt > Ứng dụng > Báo thức & nhắc nhở.',
                                  granted: snap.exactAlarm,
                                  busy:
                                      _activeRequestKind ==
                                      LifeOsPermissionKind.exactAlarm,
                                  actionLabel: 'Mở cài đặt',
                                  onRequest: () => _handleGrantSingle(
                                    LifeOsPermissionKind.exactAlarm,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _PermissionItemRow(
                                  rowKey: const Key(
                                    'perm_item_batteryUnrestricted',
                                  ),
                                  actionKey: const Key(
                                    'perm_action_batteryUnrestricted',
                                  ),
                                  icon: Icons.battery_charging_full_rounded,
                                  tone: LifeOsAccentTone.emerald,
                                  title: 'Chạy ngầm ổn định',
                                  subtitle:
                                      'Giữ chuông nhắc hoạt động khi khóa màn hình',
                                  whyNeeded:
                                      'Tránh hệ điều hành tắt dịch vụ nhắc nhở và đồng bộ nền.',
                                  dataAccessed:
                                      'Không truy cập dữ liệu cá nhân; chỉ giữ tiến trình đồng bộ nền ổn định.',
                                  whereProcessed:
                                      'Áp dụng tại chế độ quản lý pin của thiết bị.',
                                  howToRevoke:
                                      'Đổi lại mức tối ưu pin trong Cài đặt > Pin của ứng dụng.',
                                  granted: snap.batteryUnrestricted,
                                  busy:
                                      _activeRequestKind ==
                                      LifeOsPermissionKind.batteryUnrestricted,
                                  actionLabel: 'Cho phép',
                                  onRequest: () => _handleGrantSingle(
                                    LifeOsPermissionKind.batteryUnrestricted,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _PermissionItemRow(
                                  rowKey: const Key(
                                    'perm_item_bankNotificationListener',
                                  ),
                                  actionKey: const Key(
                                    'perm_action_bankNotificationListener',
                                  ),
                                  icon: Icons.account_balance_outlined,
                                  tone: LifeOsAccentTone.emerald,
                                  title: 'Biến động Ngân hàng (Tùy chọn)',
                                  subtitle:
                                      'Tự động ghi sổ thu chi · Không đọc mã OTP',
                                  whyNeeded:
                                      'Tự động tạo bản ghi chờ duyệt khi có biến động số dư ngân hàng.',
                                  dataAccessed:
                                      'Chỉ lọc thông báo từ các ngân hàng bạn chọn; bỏ qua hoàn toàn tin nhắn OTP.',
                                  whereProcessed:
                                      'Phân tích ngay trên máy, chỉ lưu khoản chi sau khi bạn đồng ý.',
                                  howToRevoke:
                                      'Tắt ngay trong Cài đặt > Quyền truy cập thông báo hoặc màn Ngân hàng.',
                                  granted: snap.bankNotificationListener,
                                  busy:
                                      _activeRequestKind ==
                                      LifeOsPermissionKind
                                          .bankNotificationListener,
                                  actionLabel: 'Mở cài đặt',
                                  onRequest: () => _handleGrantSingle(
                                    LifeOsPermissionKind
                                        .bankNotificationListener,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Divider(height: 1, color: c.separator),
                  // 5. Pinned Primary Batch Grant CTA + Dismiss Button (always visible)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LifeOsPressable(
                          passthroughPointerOnly: true,
                          enabled: !_isRequestingBatch,
                          child: SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              key: const Key(
                                'permissions_popup_grant_essential_btn',
                              ),
                              onPressed: _isRequestingBatch
                                  ? null
                                  : _handleGrantEssential,
                              icon: _isRequestingBatch
                                  ? SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.0,
                                        color: c.onPrimary,
                                      ),
                                    )
                                  : Icon(
                                      snap.isAllEssentialGranted
                                          ? Icons.check_rounded
                                          : Icons.verified_rounded,
                                      size: 18,
                                    ),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  snap.isAllEssentialGranted
                                      ? 'Hoàn tất thiết lập'
                                      : 'Cấp nhanh quyền cơ bản',
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (!snap.isAllEssentialGranted) ...[
                          const SizedBox(height: 4),
                          Center(
                            child: TextButton(
                              key: const Key('permissions_popup_later_btn'),
                              onPressed: _handleDismiss,
                              child: Text(
                                'Để sau',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionItemRow extends StatelessWidget {
  final Key rowKey;
  final Key actionKey;
  final IconData icon;
  final LifeOsAccentTone tone;
  final String title;
  final String subtitle;
  final String whyNeeded;
  final String dataAccessed;
  final String whereProcessed;
  final String howToRevoke;
  final bool granted;
  final bool busy;
  final String actionLabel;
  final VoidCallback onRequest;

  const _PermissionItemRow({
    required this.rowKey,
    required this.actionKey,
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.whyNeeded,
    required this.dataAccessed,
    required this.whereProcessed,
    required this.howToRevoke,
    required this.granted,
    required this.busy,
    this.actionLabel = 'Bật',
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return Container(
      key: rowKey,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: granted
            ? c.primarySubtle.withValues(alpha: 0.45)
            : c.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted
              ? c.primary.withValues(alpha: 0.35)
              : c.border.withValues(alpha: 0.7),
          width: 0.85,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LifeOsIconSquircle(
                icon: icon,
                tone: tone,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 13.3,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      subtitle,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (granted)
                const LifeOsStatusPill(
                  icon: Icons.check_circle_rounded,
                  label: 'Đã cấp',
                  tone: LifeOsAccentTone.emerald,
                )
              else
                SizedBox(
                  height: AppSpacing.buttonHeightM,
                  child: FilledButton.tonal(
                    key: actionKey,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(
                        AppSpacing.minHitTarget,
                        AppSpacing.buttonHeightM,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: busy ? null : onRequest,
                    child: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              actionLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: c.separator.withValues(alpha: 0.8),
                width: 0.7,
              ),
            ),
            child: Text(
              '• Vì sao cần: $whyNeeded\n'
              '• Dữ liệu truy cập: $dataAccessed\n'
              '• Xử lý tại máy: $whereProcessed\n'
              '• Cách tắt trong Cài đặt: $howToRevoke',
              softWrap: true,
              style: TextStyle(
                fontSize: 11.0,
                height: 1.32,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
