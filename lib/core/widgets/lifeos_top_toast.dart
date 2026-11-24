import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'liquid_glass.dart';

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

/// Global Top Toast Notification System crafted to tactile 3D Apple HIG Platter standards:
/// - Squarer `13px` continuous-squircle geometry
/// - Bright, airy porcelain-glass surface (never muddy or overly dark in Dark Mode)
/// - Physical 3D top specular crown + bottom chamfered slab lip + 3D glossy cushion icon badge
class LifeOsTopToast {
  static const double applePlatterRadius = 13.0;

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
        lower.contains('đã chia') ||
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
          top: topPad + 8,
          left: 12,
          right: 12,
          child: IgnorePointer(
            ignoring: !hasAction,
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
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
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    LifeOsTopToast._mountedHost = this;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 185),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1.08), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutQuart),
        );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
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
            top: topInset + 8,
            left: 12,
            right: 12,
            child: IgnorePointer(
              ignoring: !isInteractive,
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
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

    // Bright, sculpted Apple 3D semantic cushion tones
    final (
      IconData icon,
      Color cushionTop,
      Color cushionBottom,
      String badgeTitle,
    ) = switch (data.kind) {
      LifeOsToastKind.success => (
        Icons.check_rounded,
        const Color(0xFF52E06E),
        const Color(0xFF24B347),
        'Thành công',
      ),
      LifeOsToastKind.error => (
        Icons.priority_high_rounded,
        const Color(0xFFFF6B63),
        const Color(0xFFE5352B),
        'Cần kiểm tra',
      ),
      LifeOsToastKind.warning => (
        Icons.warning_amber_rounded,
        const Color(0xFFFFBA49),
        const Color(0xFFEB8205),
        'Lưu ý',
      ),
      LifeOsToastKind.info => (
        Icons.notifications_rounded,
        const Color(0xFF52A8FF),
        const Color(0xFF0071E3),
        'Thông báo',
      ),
    };

    final hasAction = data.actionLabel != null && data.onAction != null;

    // Airy, luminous Apple porcelain-glass typography & keycaps (never muddy or overly dark!)
    final Color primaryLabel = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF1D1D1F);
    final Color secondaryLabel = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF6E6E73);
    final Color actionFill = isDark
        ? const Color(0xFF424E48)
        : const Color(0xFFF2F4F7);
    final Color actionText = isDark
        ? const Color(0xFF7CC0FF)
        : const Color(0xFF0066CC);

    final squircleShape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(LifeOsTopToast.applePlatterRadius * 2),
      side: BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.20)
            : const Color(0xFFD6DFDA),
        width: 0.85,
      ),
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: squircleShape,
        shadows: [
          // 1. Soft airy 3D ambient lift (warm slate-sage, never pitch black)
          BoxShadow(
            color: (isDark ? const Color(0xFF060E0A) : const Color(0xFF1E352A))
                .withValues(alpha: isDark ? 0.28 : 0.095),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
          // 2. Physical 3D slab thickness shadow right beneath the card
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF1E2E26))
                .withValues(alpha: isDark ? 0.20 : 0.065),
            blurRadius: 5,
            spreadRadius: 0,
            offset: const Offset(0, 2.5),
          ),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: squircleShape),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: CustomPaint(
            foregroundPainter: _Apple3DToastBevelPainter(
              radius: LifeOsTopToast.applePlatterRadius,
              isDark: isDark,
            ),
            child: LiquidGlassSurface(
              key: const Key('lifeos_top_toast_banner'),
              material: LiquidGlassMaterial.floatingToast,
              borderRadius: LifeOsTopToast.applePlatterRadius,
              enableBlur: false,
              // Bright porcelain white in light mode; lifted frosted slate-pearl in dark mode!
              tintColor: isDark
                  ? const Color(0xFF323C37)
                  : const Color(0xFFFFFFFF),
              rimIntensity: 0.55,
              shadows: const [],
              padding: EdgeInsets.fromLTRB(12, 10.5, hasAction ? 8 : 13, 11.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Apple3DCushionBadge(
                    icon: icon,
                    topColor: cushionTop,
                    bottomColor: cushionBottom,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                badgeTitle,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 11.2,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.08,
                                  height: 1.15,
                                  color: secondaryLabel,
                                ),
                              ),
                            ),
                            if (!hasAction) ...[
                              const SizedBox(width: 6),
                              Text(
                                'bây giờ',
                                style: TextStyle(
                                  fontSize: 10.8,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.05,
                                  color: secondaryLabel.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          data.message,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 13.0,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.15,
                            height: 1.26,
                            color: primaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasAction) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 0.8,
                      height: 26,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.black.withValues(alpha: 0.07),
                    ),
                    const SizedBox(width: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.16 : 0.04,
                            ),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: actionText,
                          backgroundColor: actionFill,
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.5),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : Colors.white.withValues(alpha: 0.90),
                              width: 0.8,
                            ),
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
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Semantics(
                      button: true,
                      label: 'Đóng thông báo',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onDismiss,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: secondaryLabel,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sculpted 3D glossy Apple App-Icon squircle (`36x36`) with top glass dome highlight
/// and bottom cushion depth.
class _Apple3DCushionBadge extends StatelessWidget {
  final IconData icon;
  final Color topColor;
  final Color bottomColor;
  final bool isDark;

  const _Apple3DCushionBadge({
    required this.icon,
    required this.topColor,
    required this.bottomColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final squircle = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: Colors.white.withValues(alpha: isDark ? 0.28 : 0.48),
        width: 0.85,
      ),
    );

    return Container(
      width: 36,
      height: 36,
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ),
        shape: squircle,
        shadows: [
          BoxShadow(
            color: bottomColor.withValues(alpha: isDark ? 0.34 : 0.26),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: squircle),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Top glossy 3D dome reflection
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 17,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.42),
                      Colors.white.withValues(alpha: 0.04),
                    ],
                  ),
                ),
              ),
            ),
            Icon(
              icon,
              size: 19.5,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the physical 3D top crown light catch + bottom 1.6px slab thickness bevel
/// so the squarer Apple toast platter looks tangibly 3D without dark muddy shadows.
class _Apple3DToastBevelPainter extends CustomPainter {
  final double radius;
  final bool isDark;

  const _Apple3DToastBevelPainter({
    required this.radius,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // 1. Bright top crown highlight (simulates overhead studio light hitting 3D bevel)
    final topCrownPaint = Paint()
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.22 : 0.85),
          Colors.white.withValues(alpha: isDark ? 0.38 : 1.0),
          Colors.white.withValues(alpha: isDark ? 0.22 : 0.85),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 4));
    canvas.drawLine(
      Offset(radius * 0.6, 0.8),
      Offset(size.width - radius * 0.6, 0.8),
      topCrownPaint,
    );

    // 2. Subtle bottom 3D thickness chamfer lip (gives tactile 2mm extruded card feel)
    final bottomLipPaint = Paint()
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..color = isDark
          ? Colors.black.withValues(alpha: 0.30)
          : const Color(0xFFD0DCD5).withValues(alpha: 0.72);
    canvas.drawLine(
      Offset(radius * 0.5, size.height - 0.9),
      Offset(size.width - radius * 0.5, size.height - 0.9),
      bottomLipPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _Apple3DToastBevelPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.isDark != isDark;
  }
}
