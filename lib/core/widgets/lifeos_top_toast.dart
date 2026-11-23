import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/lifeos_brand_colors.dart';

enum LifeOsToastKind { success, error, warning, info }

class _TopToastEntryData {
  final int id;
  final String message;
  final LifeOsToastKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;

  const _TopToastEntryData({
    required this.id,
    required this.message,
    required this.kind,
    this.actionLabel,
    this.onAction,
    required this.duration,
  });
}

/// Global Top Toast Notification System (Apple Dynamic Island × Google M3 Top Banner).
/// Always slides down cleanly from the TOP of the viewport below the status bar,
/// never obstructing bottom navigation bars, FABs, or soft keyboards.
class LifeOsTopToast {
  static _LifeOsTopToastHostState? _mountedHost;
  static OverlayEntry? _fallbackOverlayEntry;
  static Timer? _fallbackTimer;
  static int _nextId = 1;

  static LifeOsToastKind inferKind(String rawMessage) {
    final trimmed = rawMessage.trim();
    final lower = trimmed.toLowerCase();
    if (trimmed.startsWith('⚠') ||
        lower.contains('lỗi') ||
        lower.contains('không thể') ||
        lower.contains('thất bại') ||
        lower.contains('từ chối') ||
        lower.contains('không hợp lệ')) {
      return LifeOsToastKind.error;
    }
    if (lower.contains('vui lòng') ||
        lower.contains('cảnh báo') ||
        lower.contains('chưa ') ||
        lower.contains('cần ') ||
        lower.contains('hủy')) {
      return LifeOsToastKind.warning;
    }
    if (trimmed.startsWith('✓') ||
        lower.contains('đã lưu') ||
        lower.contains('đã thêm') ||
        lower.contains('đã cập nhật') ||
        lower.contains('đã đặt') ||
        lower.contains('đã đồng bộ') ||
        lower.contains('đã xóa') ||
        lower.contains('đã tạo') ||
        lower.contains('đã ghi') ||
        lower.contains('hoàn tất') ||
        lower.contains('thành công')) {
      return LifeOsToastKind.success;
    }
    return LifeOsToastKind.info;
  }

  static String cleanDisplayMessage(String rawMessage) {
    var s = rawMessage.trim();
    if (s.startsWith('✓')) {
      s = s.substring(1).trimLeft();
    } else if (s.startsWith('⚠')) {
      s = s.substring(1).trimLeft();
    }
    return s;
  }

  static void show(
    BuildContext context,
    String message, {
    LifeOsToastKind? kind,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 2800),
  }) {
    if (message.trim().isEmpty) return;
    final resolvedKind = kind ?? inferKind(message);
    final entry = _TopToastEntryData(
      id: _nextId++,
      message: cleanDisplayMessage(message),
      kind: resolvedKind,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );

    final host = _mountedHost;
    if (host != null && host.mounted) {
      host._present(entry);
      return;
    }

    // Fallback for isolated widget tests mounting a bare MaterialApp without LifeOsTopToastHost
    _dismissFallbackOverlay();
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    if (overlay == null) return;

    late final OverlayEntry overlayEntry;
    final hasAction = entry.actionLabel != null && entry.onAction != null;
    overlayEntry = OverlayEntry(
      builder: (ctx) {
        final topPad = MediaQuery.maybePaddingOf(ctx)?.top ?? 0;
        return Positioned(
          top: topPad + 10,
          left: 14,
          right: 14,
          child: IgnorePointer(
            ignoring: !hasAction,
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _TopToastBannerCard(
                    data: entry,
                    rawOriginalMessage: message,
                    onDismiss: _dismissFallbackOverlay,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _fallbackOverlayEntry = overlayEntry;
    overlay.insert(overlayEntry);
    _fallbackTimer = Timer(duration, _dismissFallbackOverlay);
  }

  /// Seamless drop-in adapter converting any `SnackBar` (including `SnackBarAction`) into a Top Toast.
  static void fromSnackBar(BuildContext context, SnackBar snackBar) {
    final content = snackBar.content;
    String msg = '';
    if (content is Text) {
      msg = content.data ?? content.textSpan?.toPlainText() ?? '';
    } else {
      msg = content.toString();
    }
    final act = snackBar.action;
    show(context, msg, actionLabel: act?.label, onAction: act?.onPressed);
  }

  static void dismiss() {
    _mountedHost?._dismissCurrent();
    _dismissFallbackOverlay();
  }

  static void _dismissFallbackOverlay() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _fallbackOverlayEntry?.remove();
    _fallbackOverlayEntry = null;
  }
}

/// Host wrapper placed inside `MaterialApp.builder` so top toasts float cleanly above
/// all pages, bottom sheets, and dialogs — and auto-clean timers on disposal.
class LifeOsTopToastHost extends StatefulWidget {
  final Widget child;

  const LifeOsTopToastHost({super.key, required this.child});

  @override
  State<LifeOsTopToastHost> createState() => _LifeOsTopToastHostState();
}

class _LifeOsTopToastHostState extends State<LifeOsTopToastHost>
    with SingleTickerProviderStateMixin {
  _TopToastEntryData? _current;
  Timer? _autoDismissTimer;
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    LifeOsTopToast._mountedHost = this;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
  }

  void _present(_TopToastEntryData data) {
    _autoDismissTimer?.cancel();
    setState(() {
      _current = data;
    });
    _animController.forward(from: 0);
    _autoDismissTimer = Timer(data.duration, () {
      if (mounted) {
        _dismissCurrent();
      }
    });
  }

  Future<void> _dismissCurrent() async {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    if (!mounted || _current == null) return;
    try {
      await _animController.reverse();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _current = null;
      });
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    LifeOsTopToast._dismissFallbackOverlay();
    if (identical(LifeOsTopToast._mountedHost, this)) {
      LifeOsTopToast._mountedHost = null;
    }
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.maybePaddingOf(context)?.top ?? 0;
    final active = _current;
    final isInteractive =
        active != null && active.actionLabel != null && active.onAction != null;

    return Stack(
      children: [
        widget.child,
        if (active != null)
          Positioned(
            top: topInset + 10,
            left: 14,
            right: 14,
            child: IgnorePointer(
              ignoring: !isInteractive,
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Dismissible(
                        key: ValueKey('top_toast_${active.id}'),
                        direction: DismissDirection.up,
                        onDismissed: (_) {
                          _autoDismissTimer?.cancel();
                          setState(() => _current = null);
                        },
                        child: Material(
                          type: MaterialType.transparency,
                          child: _TopToastBannerCard(
                            data: active,
                            rawOriginalMessage: active.message,
                            onDismiss: _dismissCurrent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TopToastBannerCard extends StatelessWidget {
  final _TopToastEntryData data;
  final String rawOriginalMessage;
  final VoidCallback onDismiss;

  const _TopToastBannerCard({
    required this.data,
    required this.rawOriginalMessage,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = TammySemanticColors.of(context);

    final (
      IconData icon,
      Color accent,
      Color subtleBg,
      String badgeTitle,
    ) = switch (data.kind) {
      LifeOsToastKind.success => (
        Icons.check_circle_rounded,
        isDark ? const Color(0xFF34D399) : LifeOSBrandColors.primary,
        isDark ? const Color(0xFF113522) : const Color(0xFFE6F8EC),
        'Thành công',
      ),
      LifeOsToastKind.error => (
        Icons.error_outline_rounded,
        isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
        isDark ? const Color(0xFF3B1619) : const Color(0xFFFEE2E2),
        'Cần kiểm tra',
      ),
      LifeOsToastKind.warning => (
        Icons.warning_amber_rounded,
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
        isDark ? const Color(0xFF3A2A0D) : const Color(0xFFFEF3C7),
        'Lưu ý',
      ),
      LifeOsToastKind.info => (
        Icons.notifications_active_outlined,
        isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
        isDark ? const Color(0xFF13294B) : const Color(0xFFEFF6FF),
        'Thông báo',
      ),
    };

    final hasAction = data.actionLabel != null && data.onAction != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          key: const Key('lifeos_top_toast_banner'),
          padding: EdgeInsets.fromLTRB(12, 10, hasAction ? 8 : 14, 10),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF151F19).withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.42 : 0.28),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF0A140E,
                ).withValues(alpha: isDark ? 0.42 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: subtleBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badgeTitle,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 10.8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      data.message,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasAction) ...[
                const SizedBox(width: 6),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    backgroundColor: subtleBg,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    final cb = data.onAction;
                    onDismiss();
                    cb?.call();
                  },
                  child: Text(
                    data.actionLabel!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Đóng thông báo',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onDismiss,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
