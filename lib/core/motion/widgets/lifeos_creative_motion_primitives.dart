import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/lifeos_brand_colors.dart';
import '../lifeos_motion_scope.dart';
import '../lifeos_motion_tokens.dart';
import '../physics/lifeos_spring_controllers.dart';

/// Accessibility-gated `flutter_animate` helper extensions (`gskinner/flutter_animate`).
/// Ensures declarative effects never violate OS Reduce Motion.
extension LifeOsAnimateWidgetExt on Widget {
  Widget lifeOsShimmer({
    required BuildContext context,
    bool active = true,
    Duration duration = const Duration(milliseconds: 900),
    Color? highlightColor,
  }) {
    final motion = LifeOsMotionScope.of(context);
    if (!active || motion.isReducedMotion || !TickerMode.valuesOf(context).enabled) {
      return this;
    }
    return animate().shimmer(
      duration: duration,
      color: highlightColor ?? Colors.white.withValues(alpha: 0.36),
    );
  }

  Widget lifeOsErrorShake({
    required BuildContext context,
    required int triggerCount,
  }) {
    final motion = LifeOsMotionScope.of(context);
    if (triggerCount <= 0 || motion.isReducedMotion) {
      return this;
    }
    return Animate(
      key: ValueKey<int>(triggerCount),
      effects: const [
        ShakeEffect(
          duration: Duration(milliseconds: 340),
          hz: 5,
          offset: Offset(6, 0),
        ),
      ],
      child: this,
    );
  }
}

/// 1. Genuine Bodymovin Vector Lottie Player (`xvrh/lottie-flutter ^3.8.2`)
/// - Supports finite cycle count (`maxCycles`) so widget tests calling `pumpAndSettle()` never hang!
/// - Supports `ValueDelegate.color` theme overrides for Light & Dark modes.
/// - Freezes cleanly on settled frame (`0.85`) when Reduce Motion is enabled.
class LifeOsLottieAnimation extends StatefulWidget {
  final String assetPath;
  final double size;
  final int maxCycles;
  final double playbackSpeed;
  final Color? primaryColorOverride;
  final Color? accentColorOverride;
  final String? semanticsLabel;

  const LifeOsLottieAnimation({
    super.key,
    required this.assetPath,
    this.size = 96,
    this.maxCycles = 1,
    this.playbackSpeed = 1.0,
    this.primaryColorOverride,
    this.accentColorOverride,
    this.semanticsLabel,
  });

  @override
  State<LifeOsLottieAnimation> createState() => _LifeOsLottieAnimationState();
}

class _LifeOsLottieAnimationState extends State<LifeOsLottieAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _completedCycles = 0;
  Duration _baseDuration = const Duration(milliseconds: 1000);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _baseDuration)
      ..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _completedCycles++;
      if (mounted && _completedCycles < widget.maxCycles) {
        final motion = LifeOsMotionScope.read(context);
        if (!motion.isReducedMotion && TickerMode.valuesOf(context).enabled) {
          _controller.forward(from: 0.0);
        }
      }
    }
  }

  void _syncPlayback() {
    if (!_loaded || !mounted) return;
    final motion = LifeOsMotionScope.read(context);
    final tickers = TickerMode.valuesOf(context).enabled;
    if (motion.isReducedMotion || !tickers) {
      _controller.stop();
      _controller.value = 0.85;
      return;
    }
    final scaledMs =
        (_baseDuration.inMilliseconds / widget.playbackSpeed.clamp(0.15, 3.0))
            .round();
    _controller.duration = Duration(milliseconds: math.max(80, scaledMs));
    if (!_controller.isAnimating && _completedCycles == 0) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(covariant LifeOsLottieAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.playbackSpeed != widget.playbackSpeed) {
      _completedCycles = 0;
      _syncPlayback();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final delegates = LottieDelegates(
      values: [
        if (widget.primaryColorOverride != null) ...[
          ValueDelegate.color(
            const ['**', 'PrimaryFill'],
            value: widget.primaryColorOverride,
          ),
          ValueDelegate.color(
            const ['**', 'PrimaryStroke'],
            value: widget.primaryColorOverride,
          ),
        ],
        if (widget.accentColorOverride != null) ...[
          ValueDelegate.color(
            const ['**', 'AccentFill'],
            value: widget.accentColorOverride,
          ),
          ValueDelegate.color(
            const ['**', 'AccentStroke'],
            value: widget.accentColorOverride,
          ),
        ],
      ],
    );

    final player = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Lottie.asset(
        widget.assetPath,
        controller: _controller,
        delegates: delegates,
        fit: BoxFit.contain,
        onLoaded: (composition) {
          _baseDuration = composition.duration;
          _loaded = true;
          _syncPlayback();
        },
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.verified_rounded,
            size: widget.size * 0.56,
            color: c.primary,
          ),
        ),
      ),
    );

    if (widget.semanticsLabel != null) {
      return Semantics(label: widget.semanticsLabel, image: true, child: player);
    }
    return ExcludeSemantics(child: player);
  }
}

/// 2. Genuine Frame-Stepping RGBA Sprite Sheet Player (`drawImageRect`)
/// Plays multi-frame horizontal sprite strips (e.g. `assets/motion/coin_spin_spritesheet.png`)
/// with bounded cycles or manual scrub progress.
class LifeOsSpriteSheetPlayer extends StatefulWidget {
  final String assetPath;
  final int frameCount;
  final double displaySize;
  final int fps;
  final int maxCycles;
  final double? manualProgress;

  const LifeOsSpriteSheetPlayer({
    super.key,
    required this.assetPath,
    this.frameCount = 8,
    this.displaySize = 84,
    this.fps = 12,
    this.maxCycles = 3,
    this.manualProgress,
  });

  @override
  State<LifeOsSpriteSheetPlayer> createState() =>
      _LifeOsSpriteSheetPlayerState();
}

class _LifeOsSpriteSheetPlayerState extends State<LifeOsSpriteSheetPlayer>
    with SingleTickerProviderStateMixin {
  ui.Image? _spriteImage;
  late final AnimationController _ctrl;
  int _cycles = 0;

  @override
  void initState() {
    super.initState();
    final cycleMs = ((widget.frameCount / math.max(1, widget.fps)) * 1000)
        .round();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: math.max(120, cycleMs)),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _cycles++;
          if (mounted &&
              widget.manualProgress == null &&
              _cycles < widget.maxCycles) {
            final motion = LifeOsMotionScope.read(context);
            if (!motion.isReducedMotion &&
                TickerMode.valuesOf(context).enabled) {
              _ctrl.forward(from: 0.0);
            }
          }
        }
      });
    _loadSprite();
  }

  Future<void> _loadSprite() async {
    try {
      final data = await rootBundle.load(widget.assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _spriteImage = frame.image);
        final motion = LifeOsMotionScope.read(context);
        if (widget.manualProgress == null &&
            !motion.isReducedMotion &&
            TickerMode.valuesOf(context).enabled) {
          _ctrl.forward(from: 0.0);
        }
      }
    } catch (_) {
      // Graceful fallback painted if asset bundle is mocked in unit tests
    }
  }

  void replay() {
    _cycles = 0;
    final motion = LifeOsMotionScope.read(context);
    if (!motion.isReducedMotion && TickerMode.valuesOf(context).enabled) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final progress = widget.manualProgress ??
        (motion.isReducedMotion ? 0.0 : _ctrl.value);

    return GestureDetector(
      onTap: replay,
      child: SizedBox(
        width: widget.displaySize,
        height: widget.displaySize,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final p = widget.manualProgress ??
                (motion.isReducedMotion ? 0.0 : _ctrl.value);
            final frameIdx =
                (p * widget.frameCount).floor() % widget.frameCount;
            return CustomPaint(
              painter: _SpriteFramePainter(
                image: _spriteImage,
                frameIndex: frameIdx,
                frameCount: widget.frameCount,
                fallbackProgress: progress,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SpriteFramePainter extends CustomPainter {
  final ui.Image? image;
  final int frameIndex;
  final int frameCount;
  final double fallbackProgress;

  const _SpriteFramePainter({
    required this.image,
    required this.frameIndex,
    required this.frameCount,
    required this.fallbackProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img != null && frameCount > 0) {
      final fw = img.width / frameCount;
      final fh = img.height.toDouble();
      final src = Rect.fromLTWH(frameIndex * fw, 0, fw, fh);
      final dst = Offset.zero & size;
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }

    // Vector fallback while decoding or in mocked bundle tests
    final angle = (frameIndex / math.max(1, frameCount)) * math.pi;
    final rx = math.max(4.0, (size.width * 0.38) * math.cos(angle).abs());
    final ry = size.height * 0.38;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      Paint()..color = LifeOSBrandColors.primary,
    );
  }

  @override
  bool shouldRepaint(covariant _SpriteFramePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.frameIndex != frameIndex ||
      oldDelegate.fallbackProgress != fallbackProgress;
}

/// 3. Genuine GLSL Runtime Fragment Shader Surface (`shaders/*.frag`)
/// Loads compiled Impeller/Skia GLSL shaders with graceful painted fallback
/// in headless tests or Reduce Motion.
enum LifeOsShaderPreset { liquidCaustics, holographicFoil }

class LifeOsShaderSurface extends StatefulWidget {
  final LifeOsShaderPreset preset;
  final double height;
  final double borderRadius;
  final Duration activeDuration;
  final Widget? child;

  const LifeOsShaderSurface({
    super.key,
    this.preset = LifeOsShaderPreset.liquidCaustics,
    this.height = 132,
    this.borderRadius = 18,
    this.activeDuration = const Duration(milliseconds: 2400),
    this.child,
  });

  @override
  State<LifeOsShaderSurface> createState() => _LifeOsShaderSurfaceState();
}

class _LifeOsShaderSurfaceState extends State<LifeOsShaderSurface>
    with SingleTickerProviderStateMixin {
  static final Map<String, ui.FragmentProgram> _programCache =
      <String, ui.FragmentProgram>{};

  ui.FragmentProgram? _program;
  late final AnimationController _timeCtrl;
  Offset _pointerUv = const Offset(0.5, 0.5);
  bool _tickersEnabled = true;

  String get _assetKey => switch (widget.preset) {
    LifeOsShaderPreset.liquidCaustics => 'shaders/liquid_caustics.frag',
    LifeOsShaderPreset.holographicFoil => 'shaders/holographic_foil.frag',
  };

  @override
  void initState() {
    super.initState();
    _timeCtrl = AnimationController(
      vsync: this,
      duration: widget.activeDuration,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadProgram();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    if (!_tickersEnabled && _timeCtrl.isAnimating) {
      _timeCtrl.stop();
    }
  }

  Future<void> _loadProgram() async {
    final cached = _programCache[_assetKey];
    if (cached != null) {
      if (!mounted) return;
      setState(() => _program = cached);
      _startBoundedPulse();
      return;
    }
    try {
      final prog = await ui.FragmentProgram.fromAsset(_assetKey);
      _programCache[_assetKey] = prog;
      if (mounted) {
        setState(() => _program = prog);
        _startBoundedPulse();
      }
    } catch (_) {
      // Headless VM test environment without shader backend falls back cleanly
      if (mounted) _startBoundedPulse();
    }
  }

  void _startBoundedPulse() {
    if (!mounted) return;
    final motion = LifeOsMotionScope.read(context);
    if (!motion.isReducedMotion && _tickersEnabled) {
      _timeCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final motion = LifeOsMotionScope.of(context);

    return GestureDetector(
      onTap: _startBoundedPulse,
      onPanUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          setState(() {
            _pointerUv = Offset(
              (details.localPosition.dx / box.size.width).clamp(0.0, 1.0),
              (details.localPosition.dy / box.size.height).clamp(0.0, 1.0),
            );
          });
          if (!_timeCtrl.isAnimating && !motion.isReducedMotion) {
            _timeCtrl.forward(from: 0.0);
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _timeCtrl,
            child: widget.child,
            builder: (context, child) {
              final elapsedSec = motion.isReducedMotion
                  ? 0.0
                  : _timeCtrl.value * 4.0;
              return CustomPaint(
                painter: _GlslSurfacePainter(
                  program: _program,
                  preset: widget.preset,
                  timeSec: elapsedSec,
                  pointerUv: _pointerUv,
                  isDark: isDark,
                ),
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GlslSurfacePainter extends CustomPainter {
  final ui.FragmentProgram? program;
  final LifeOsShaderPreset preset;
  final double timeSec;
  final Offset pointerUv;
  final bool isDark;

  const _GlslSurfacePainter({
    required this.program,
    required this.preset,
    required this.timeSec,
    required this.pointerUv,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final prog = program;
    if (prog != null) {
      try {
        final shader = prog.fragmentShader();
        if (preset == LifeOsShaderPreset.liquidCaustics) {
          final c1 = isDark
              ? const Color(0xFF0E4D26)
              : const Color(0xFF0B7A2A);
          final c2 = isDark
              ? const Color(0xFF1E8E48)
              : const Color(0xFF55D52F);
          shader
            ..setFloat(0, size.width)
            ..setFloat(1, size.height)
            ..setFloat(2, timeSec)
            ..setFloat(3, c1.r)
            ..setFloat(4, c1.g)
            ..setFloat(5, c1.b)
            ..setFloat(6, 1.0)
            ..setFloat(7, c2.r)
            ..setFloat(8, c2.g)
            ..setFloat(9, c2.b)
            ..setFloat(10, 1.0);
        } else {
          final base = isDark
              ? const Color(0xFF1B2721)
              : const Color(0xFF113824);
          const sheen = Color(0xFFA7F3D0);
          shader
            ..setFloat(0, size.width)
            ..setFloat(1, size.height)
            ..setFloat(2, timeSec)
            ..setFloat(3, pointerUv.dx)
            ..setFloat(4, pointerUv.dy)
            ..setFloat(5, base.r)
            ..setFloat(6, base.g)
            ..setFloat(7, base.b)
            ..setFloat(8, 1.0)
            ..setFloat(9, sheen.r)
            ..setFloat(10, sheen.g)
            ..setFloat(11, sheen.b)
            ..setFloat(12, 1.0);
        }
        canvas.drawRect(rect, Paint()..shader = shader);
        return;
      } catch (_) {
        // Fallback below
      }
    }

    // Analytical fallback gradient (identical aesthetic in headless test runner)
    final phase = math.sin(timeSec * 1.5) * 0.25;
    final gradient = LinearGradient(
      begin: Alignment(-0.8 + phase, -0.9),
      end: Alignment(0.8 + (pointerUv.dx - 0.5), 0.9),
      colors: preset == LifeOsShaderPreset.liquidCaustics
          ? const [Color(0xFF0B7A2A), Color(0xFF159943), Color(0xFF55D52F)]
          : const [Color(0xFF113824), Color(0xFF0B7A2A), Color(0xFF6EE7B7)],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _GlslSurfacePainter oldDelegate) =>
      oldDelegate.timeSec != timeSec ||
      oldDelegate.pointerUv != pointerUv ||
      oldDelegate.isDark != isDark ||
      oldDelegate.program != program;
}

/// 4. Zero-Allocation Struct-of-Arrays Particle Burst & Ambient Field (`wonderous` port)
class LifeOsParticleBurst extends StatefulWidget {
  final int particleCount;
  final double height;
  final Widget? child;

  const LifeOsParticleBurst({
    super.key,
    this.particleCount = 28,
    this.height = 128,
    this.child,
  });

  @override
  State<LifeOsParticleBurst> createState() => _LifeOsParticleBurstState();
}

class _LifeOsParticleBurstState extends State<LifeOsParticleBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<double> _angles;
  late final List<double> _speeds;
  late final List<double> _radii;
  late final List<Color> _colors;
  Offset _originFraction = const Offset(0.5, 0.55);

  @override
  void initState() {
    super.initState();
    final rng = math.Random(42);
    const palette = <Color>[
      Color(0xFF0B7A2A),
      Color(0xFF55D52F),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFF38BDF8),
    ];
    _angles = List<double>.generate(
      widget.particleCount,
      (i) => (i / widget.particleCount) * math.pi * 2 + rng.nextDouble() * 0.25,
    );
    _speeds = List<double>.generate(
      widget.particleCount,
      (_) => 36.0 + rng.nextDouble() * 68.0,
    );
    _radii = List<double>.generate(
      widget.particleCount,
      (_) => 2.8 + rng.nextDouble() * 3.8,
    );
    _colors = List<Color>.generate(
      widget.particleCount,
      (i) => palette[i % palette.length],
    );
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    SchedulerBinding.instance.addPostFrameCallback((_) => triggerBurst());
  }

  void triggerBurst([Offset? localFraction]) {
    if (!mounted) return;
    if (localFraction != null) {
      _originFraction = localFraction;
    }
    final motion = LifeOsMotionScope.read(context);
    final tickers = TickerMode.getValuesNotifier(context).value.enabled;
    if (motion.isReducedMotion || !tickers) {
      _ctrl.value = 0.0;
      return;
    }
    _ctrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          triggerBurst(
            Offset(
              (d.localPosition.dx / box.size.width).clamp(0.1, 0.9),
              (d.localPosition.dy / box.size.height).clamp(0.1, 0.9),
            ),
          );
        } else {
          triggerBurst();
        }
      },
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _ctrl,
          child: widget.child,
          builder: (context, child) {
            return CustomPaint(
              foregroundPainter: _ParticleBurstPainter(
                t: _ctrl.value,
                originFraction: _originFraction,
                angles: _angles,
                speeds: _speeds,
                radii: _radii,
                colors: _colors,
              ),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

class _ParticleBurstPainter extends CustomPainter {
  final double t;
  final Offset originFraction;
  final List<double> angles;
  final List<double> speeds;
  final List<double> radii;
  final List<Color> colors;

  const _ParticleBurstPainter({
    required this.t,
    required this.originFraction,
    required this.angles,
    required this.speeds,
    required this.radii,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.0 || t >= 1.0) return;
    final origin = Offset(
      size.width * originFraction.dx,
      size.height * originFraction.dy,
    );
    final decel = Curves.easeOutQuart.transform(t);
    final alpha = (1.0 - t).clamp(0.0, 1.0);
    final gravityY = 34.0 * t * t;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < angles.length; i++) {
      final dist = speeds[i] * decel;
      final px = origin.dx + math.cos(angles[i]) * dist;
      final py = origin.dy + math.sin(angles[i]) * dist + gravityY;
      paint.color = colors[i].withValues(alpha: alpha);
      canvas.drawCircle(Offset(px, py), radii[i] * (1.0 - t * 0.45), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleBurstPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.originFraction != originFraction;
}

/// 5. Pure-Dart Interactive State-Machine Mascot Rig ("Mầm Ngọc LifeOS")
/// Replaces C++ FFI `rive_native` with a 100% deterministic, pointer-tracking,
/// spring-physics character state machine (`idle`, `listening`, `thinking`, `celebrate`, `sleep`).
enum LifeOsMascotState { idle, listening, thinking, celebrate, sleep }

extension LifeOsMascotStateLabel on LifeOsMascotState {
  String get labelVi => switch (this) {
    LifeOsMascotState.idle => 'Sẵn sàng',
    LifeOsMascotState.listening => 'Lắng nghe',
    LifeOsMascotState.thinking => 'Phân tích',
    LifeOsMascotState.celebrate => 'Hoàn thành',
    LifeOsMascotState.sleep => 'Nghỉ tĩnh',
  };
}

class LifeOsInteractiveMascotRig extends StatefulWidget {
  final LifeOsMascotState state;
  final double size;
  final ValueChanged<LifeOsMascotState>? onStateTapped;

  const LifeOsInteractiveMascotRig({
    super.key,
    this.state = LifeOsMascotState.idle,
    this.size = 128,
    this.onStateTapped,
  });

  @override
  State<LifeOsInteractiveMascotRig> createState() =>
      _LifeOsInteractiveMascotRigState();
}

class _LifeOsInteractiveMascotRigState extends State<LifeOsInteractiveMascotRig>
    with TickerProviderStateMixin {
  late final LifeOsSpringController _hopCtrl;
  late final LifeOsSpringController _leafSpreadCtrl;
  Offset _eyeLook = Offset.zero;

  @override
  void initState() {
    super.initState();
    _hopCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: LifeOsMotionTokens.bouncySpring,
    );
    _leafSpreadCtrl = LifeOsSpringController(
      vsync: this,
      initialValue: _targetLeafSpread(widget.state),
      spring: LifeOsMotionTokens.bouncySpring,
    );
  }

  double _targetLeafSpread(LifeOsMascotState s) => switch (s) {
    LifeOsMascotState.idle => 0.35,
    LifeOsMascotState.listening => 0.75,
    LifeOsMascotState.thinking => 0.52,
    LifeOsMascotState.celebrate => 1.0,
    LifeOsMascotState.sleep => 0.08,
  };

  @override
  void didUpdateWidget(covariant LifeOsInteractiveMascotRig oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      final motion = LifeOsMotionScope.read(context);
      final tickers = TickerMode.valuesOf(context).enabled;
      _leafSpreadCtrl.animateTo(
        _targetLeafSpread(widget.state),
        motion: motion,
        tickersEnabled: tickers,
      );
      if (widget.state == LifeOsMascotState.celebrate &&
          !motion.isReducedMotion) {
        _hopCtrl.jumpTo(-14.0);
        _hopCtrl.animateTo(
          0.0,
          velocity: -180.0,
          motion: motion,
          tickersEnabled: tickers,
        );
      }
    }
  }

  void _triggerTapHop() {
    final motion = LifeOsMotionScope.read(context);
    motion.selectionHaptic();
    if (!motion.isReducedMotion && TickerMode.valuesOf(context).enabled) {
      _hopCtrl.jumpTo(-10.0);
      _hopCtrl.animateTo(0.0, velocity: -140.0, motion: motion);
    }
    final nextIdx =
        (LifeOsMascotState.values.indexOf(widget.state) + 1) %
        LifeOsMascotState.values.length;
    widget.onStateTapped?.call(LifeOsMascotState.values[nextIdx]);
  }

  @override
  void dispose() {
    _hopCtrl.dispose();
    _leafSpreadCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = LifeOsMotionScope.of(context);
    final effectiveState = motion.isReducedMotion &&
            widget.state == LifeOsMascotState.celebrate
        ? LifeOsMascotState.idle
        : widget.state;

    return GestureDetector(
      onTap: _triggerTapHop,
      onPanUpdate: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && !motion.isReducedMotion) {
          final nx = ((d.localPosition.dx / box.size.width) - 0.5) * 2.0;
          final ny = ((d.localPosition.dy / box.size.height) - 0.5) * 2.0;
          setState(() {
            _eyeLook = Offset(nx.clamp(-1.0, 1.0), ny.clamp(-1.0, 1.0));
          });
        }
      },
      onPanEnd: (_) {
        if (mounted) setState(() => _eyeLook = Offset.zero);
      },
      child: Semantics(
        button: true,
        label: 'Linh vật Mầm Ngọc LifeOS: ${widget.state.labelVi}',
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_hopCtrl, _leafSpreadCtrl]),
            builder: (context, _) {
              return CustomPaint(
                painter: _MascotStatePainter(
                  state: effectiveState,
                  hopOffsetPx: motion.isReducedMotion ? 0.0 : _hopCtrl.value,
                  leafSpread: _leafSpreadCtrl.value,
                  eyeLook: _eyeLook,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MascotStatePainter extends CustomPainter {
  final LifeOsMascotState state;
  final double hopOffsetPx;
  final double leafSpread;
  final Offset eyeLook;

  const _MascotStatePainter({
    required this.state,
    required this.hopOffsetPx,
    required this.leafSpread,
    required this.eyeLook,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.56 + hopOffsetPx;
    final r = size.width * 0.29;

    // 1. Soft ground shadow scaling inversely with hop height
    final shadowScale = (1.0 + hopOffsetPx / 45.0).clamp(0.65, 1.1);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.89),
        width: r * 1.5 * shadowScale,
        height: r * 0.28 * shadowScale,
      ),
      Paint()..color = const Color(0xFF0B7A2A).withValues(alpha: 0.16),
    );

    // 2. Two spring-articulated sprout leaves on crown
    final crownY = cy - r * 0.96;
    final spreadAngle = 0.25 + leafSpread * 0.45;
    for (final dir in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(cx, crownY);
      canvas.rotate(dir * spreadAngle);
      final leafPath = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(dir * r * 0.45, -r * 0.55, dir * r * 0.08, -r * 0.78)
        ..quadraticBezierTo(-dir * r * 0.22, -r * 0.42, 0, 0)
        ..close();
      canvas.drawPath(
        leafPath,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xFF12B847), Color(0xFF86EFAC)],
          ).createShader(Rect.fromLTWH(-r, -r, r * 2, r)),
      );
      canvas.restore();
    }

    // 3. Translucent Emerald-Jade Droplet Body
    final bodyRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: r * 2.0,
      height: r * 2.08,
    );
    canvas.drawOval(
      bodyRect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.3),
          radius: 0.95,
          colors: [Color(0xFF34D399), Color(0xFF0B7A2A), Color(0xFF113824)],
          stops: [0.0, 0.65, 1.0],
        ).createShader(bodyRect),
    );

    // Specular glass highlight arc
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - r * 0.34, cy - r * 0.38),
        width: r * 0.52,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    // 4. Expressive Eyes & Mouth by State
    final lookDx = eyeLook.dx * r * 0.16;
    final lookDy = eyeLook.dy * r * 0.14;
    final eyeY = cy - r * 0.06 + lookDy;
    final eyePaint = Paint()..color = const Color(0xFFFEFCE8);

    if (state == LifeOsMascotState.sleep) {
      final sleepStroke = Paint()
        ..color = const Color(0xFFFEFCE8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      for (final sgn in const [-1.0, 1.0]) {
        final ex = cx + sgn * r * 0.36;
        canvas.drawArc(
          Rect.fromCenter(center: Offset(ex, eyeY), width: r * 0.30, height: r * 0.18),
          0,
          math.pi,
          false,
          sleepStroke,
        );
      }
    } else {
      final eyeRadius = state == LifeOsMascotState.listening
          ? r * 0.16
          : r * 0.135;
      canvas.drawCircle(Offset(cx - r * 0.36 + lookDx, eyeY), eyeRadius, eyePaint);
      canvas.drawCircle(Offset(cx + r * 0.36 + lookDx, eyeY), eyeRadius, eyePaint);
    }

    // Mouth / Status Expression
    final mouthPaint = Paint()
      ..color = const Color(0xFFFEFCE8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    if (state == LifeOsMascotState.celebrate) {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(cx + lookDx * 0.5, cy + r * 0.20),
          width: r * 0.44,
          height: r * 0.32,
        ),
        0,
        math.pi,
        false,
        mouthPaint,
      );
    } else if (state == LifeOsMascotState.thinking) {
      canvas.drawCircle(
        Offset(cx + r * 0.08 + lookDx * 0.5, cy + r * 0.24),
        r * 0.08,
        Paint()..color = const Color(0xFFFEFCE8),
      );
    } else {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(cx + lookDx * 0.5, cy + r * 0.18),
          width: r * 0.28,
          height: r * 0.16,
        ),
        0.1,
        math.pi - 0.2,
        false,
        mouthPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MascotStatePainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.hopOffsetPx != hopOffsetPx ||
      oldDelegate.leafSpread != leafSpread ||
      oldDelegate.eyeLook != eyeLook;
}
