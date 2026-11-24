import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/widgets/lifeos_design_system.dart';
import 'package:life_os/features/motion_gallery/presentation/models/motion_sample_ui_spec.dart';
import 'package:life_os/features/motion_gallery/presentation/pages/motion_gallery_page.dart';

/// Baseline BEFORE optimization for Architecture 1:
/// Eagerly mounts ALL 66 interactive sample cards inside a non-virtualized `Column`.
class _LegacyEagerMotionCatalog extends StatelessWidget {
  final List<MotionSampleSpec> samples;

  const _LegacyEagerMotionCatalog({required this.samples});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            for (final s in samples)
              Padding(
                key: ValueKey<String>('eager_card_${s.id}'),
                padding: const EdgeInsets.all(12),
                child: LifeOsSoftCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${s.formattedCode} · ${s.titleVi}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      s.previewBuilder(context, 1.0, 1),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shared realistic Voice Capture Form content (header + wallet chips + input + draft summary + actions)
/// to measure full-form `setState` vs isolated `ValueNotifier<double>` + `RepaintBoundary`.
class _VoiceCaptureFormContent extends StatelessWidget {
  final VoidCallback onFormBuilt;
  final Widget waveformSlot;

  const _VoiceCaptureFormContent({
    required this.onFormBuilt,
    required this.waveformSlot,
  });

  @override
  Widget build(BuildContext context) {
    onFormBuilt();
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LifeOsTopBrandHeader(title: 'Ghi chép Giọng nói AI'),
            const SizedBox(height: 12),
            LifeOsSoftCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Đang tự động thu âm...',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  waveformSlot,
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: TextEditingController(
                text: 'Ăn trưa phở bò 65 nghìn bằng ví Vietcombank',
              ),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Nội dung nhận diện giọng nói',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in const [
                  'Vietcombank Chính',
                  'Tiền mặt Gia đình',
                  'Techcombank Chi tiêu',
                  'Thẻ Tín dụng Quốc tế',
                  'Quỹ Dự phòng',
                ])
                  Chip(label: Text(w)),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LifeOsSoftCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Khoản dự thảo #${i + 1}: Phân loại tự động 100% trên máy',
                        ),
                      ),
                      const Text(
                        '65.000 ₫',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Nói lại'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Xác nhận & Lưu'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BenchWaveformPainter extends CustomPainter {
  final double rmsDb;

  const _BenchWaveformPainter({required this.rmsDb});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 24;
    final spacing = size.width / barCount;
    final normRms = ((rmsDb + 2.0) / 12.0).clamp(0.18, 1.0);
    final paint = Paint()
      ..color = const Color(0xFF0B7A2A)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;

    for (var i = 0; i < barCount; i++) {
      final x = i * spacing + spacing / 2;
      final wave = math.sin((i / barCount) * math.pi * 2.5).abs();
      final h = (size.height * (0.25 + 0.75 * wave * normRms)).clamp(
        4.0,
        size.height,
      );
      final y0 = (size.height - h) / 2;
      canvas.drawLine(Offset(x, y0), Offset(x, y0 + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BenchWaveformPainter oldDelegate) =>
      (oldDelegate.rmsDb - rmsDb).abs() > 0.01;
}

/// BEFORE optimization: calls `setState` on the parent form for every RMS dB signal.
class _LegacySetStateVoiceSheet extends StatefulWidget {
  final VoidCallback onFormBuilt;

  const _LegacySetStateVoiceSheet({super.key, required this.onFormBuilt});

  @override
  State<_LegacySetStateVoiceSheet> createState() =>
      _LegacySetStateVoiceSheetState();
}

class _LegacySetStateVoiceSheetState extends State<_LegacySetStateVoiceSheet> {
  double _rmsDb = 0.0;

  void pushRms(double nextRms) {
    setState(() => _rmsDb = nextRms);
  }

  @override
  Widget build(BuildContext context) {
    return _VoiceCaptureFormContent(
      onFormBuilt: widget.onFormBuilt,
      waveformSlot: SizedBox(
        height: 28,
        width: double.infinity,
        child: CustomPaint(painter: _BenchWaveformPainter(rmsDb: _rmsDb)),
      ),
    );
  }
}

/// AFTER optimization: updates `ValueNotifier<double>` inside an isolated `RepaintBoundary`.
class _OptimizedNotifierVoiceSheet extends StatefulWidget {
  final VoidCallback onFormBuilt;

  const _OptimizedNotifierVoiceSheet({super.key, required this.onFormBuilt});

  @override
  State<_OptimizedNotifierVoiceSheet> createState() =>
      _OptimizedNotifierVoiceSheetState();
}

class _OptimizedNotifierVoiceSheetState
    extends State<_OptimizedNotifierVoiceSheet> {
  final ValueNotifier<double> rmsNotifier = ValueNotifier<double>(0.0);

  @override
  void dispose() {
    rmsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _VoiceCaptureFormContent(
      onFormBuilt: widget.onFormBuilt,
      waveformSlot: RepaintBoundary(
        child: SizedBox(
          height: 28,
          width: double.infinity,
          child: ValueListenableBuilder<double>(
            valueListenable: rmsNotifier,
            builder: (_, rmsDb, _) => CustomPaint(
              painter: _BenchWaveformPainter(rmsDb: rmsDb),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpringTickBenchHost extends StatefulWidget {
  final ValueChanged<LifeOsSpringController> onReady1D;
  final ValueChanged<LifeOsSpring2DController> onReady2D;

  const _SpringTickBenchHost({
    required this.onReady1D,
    required this.onReady2D,
  });

  @override
  State<_SpringTickBenchHost> createState() => _SpringTickBenchHostState();
}

class _SpringTickBenchHostState extends State<_SpringTickBenchHost>
    with TickerProviderStateMixin {
  late final LifeOsSpringController _c1;
  late final LifeOsSpring2DController _c2;

  @override
  void initState() {
    super.initState();
    _c1 = LifeOsSpringController(
      vsync: this,
      spring: LifeOsMotionTokens.snappySpring,
    );
    _c2 = LifeOsSpring2DController(
      vsync: this,
      spring: LifeOsMotionTokens.gestureThrowSpring,
    );
    widget.onReady1D(_c1);
    widget.onReady2D(_c2);
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_c1, _c2]),
        builder: (_, _) => Transform.translate(
          offset: Offset(_c2.value.dx, _c1.value * 24.0),
          child: const SizedBox(width: 48, height: 48),
        ),
      ),
    );
  }
}

double _median(List<int> values) {
  final sorted = List<int>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid].toDouble();
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

double _p95(List<int> values) {
  final sorted = List<int>.from(values)..sort();
  final idx = ((sorted.length - 1) * 0.95).round().clamp(0, sorted.length - 1);
  return sorted[idx].toDouble();
}

void main() {
  group('LifeOS Motion v2.0 — Empirical Performance Benchmarks', () {
    testWidgets(
      'Measures Before vs After (66-sample Virtualization & 30-event Voice RMS) and per-tick cost (Spring Retargeting & 28-Particle Burst)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final allSamples = buildAllMotionGallerySamples();
        expect(allSamples.length, 66);

        // Warm-up Flutter typography, theme, and rendering caches
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: Text('Warmup')),
          ),
        );
        await tester.pumpAndSettle();

        // ─────────────────────────────────────────────────────────────────────
        // BENCHMARK 1: 66-Sample Catalog First-Frame Mount (Column vs SliverList.builder)
        // ─────────────────────────────────────────────────────────────────────
        final eagerMountUs = <int>[];
        var eagerMountedCards = 0;
        for (var run = 0; run < 3; run++) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          final sw = Stopwatch()..start();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              builder: (_, child) => LifeOsTopToastHost(child: child!),
              home: _LegacyEagerMotionCatalog(samples: allSamples),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
          sw.stop();
          eagerMountUs.add(sw.elapsedMicroseconds);

          if (run == 0) {
            eagerMountedCards = allSamples
                .where(
                  (s) => find
                      .byKey(ValueKey<String>('eager_card_${s.id}'))
                      .evaluate()
                      .isNotEmpty,
                )
                .length;
          }
        }
        // Clean up eager tree cleanly
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        final lazyMountUs = <int>[];
        var lazyMountedCards = 0;
        for (var run = 0; run < 3; run++) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          final sw = Stopwatch()..start();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              builder: (_, child) => LifeOsTopToastHost(child: child!),
              home: const MotionGalleryPage(),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
          sw.stop();
          lazyMountUs.add(sw.elapsedMicroseconds);

          if (run == 0) {
            lazyMountedCards = allSamples
                .where(
                  (s) => find
                      .byKey(ValueKey<String>('motion_card_${s.id}'))
                      .evaluate()
                      .isNotEmpty,
                )
                .length;
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(eagerMountedCards, 66);
        expect(lazyMountedCards, lessThan(8));
        expect(_median(lazyMountUs), lessThan(_median(eagerMountUs)));

        // ─────────────────────────────────────────────────────────────────────
        // BENCHMARK 2: Voice AI Waveform — 30 Consecutive RMS Events (setState vs ValueNotifier)
        // ─────────────────────────────────────────────────────────────────────
        final rmsSequence = List<double>.generate(
          30,
          (i) => -1.5 + math.sin(i * 0.45).abs() * 10.5,
        );

        var legacyFormBuilds = 0;
        final legacyKey = GlobalKey<_LegacySetStateVoiceSheetState>();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: _LegacySetStateVoiceSheet(
              key: legacyKey,
              onFormBuilt: () => legacyFormBuilds++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        legacyFormBuilds = 0; // Count strictly across the 30 RMS events

        final legacyRmsFrameUs = <int>[];
        final swLegacyTotal = Stopwatch()..start();
        for (final rms in rmsSequence) {
          final swFrame = Stopwatch()..start();
          legacyKey.currentState!.pushRms(rms);
          await tester.pump(const Duration(milliseconds: 16));
          swFrame.stop();
          legacyRmsFrameUs.add(swFrame.elapsedMicroseconds);
        }
        swLegacyTotal.stop();

        var optimizedFormBuilds = 0;
        final optKey = GlobalKey<_OptimizedNotifierVoiceSheetState>();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: _OptimizedNotifierVoiceSheet(
              key: optKey,
              onFormBuilt: () => optimizedFormBuilds++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        optimizedFormBuilds = 0; // Count strictly across the 30 RMS events

        final optRmsFrameUs = <int>[];
        final swOptTotal = Stopwatch()..start();
        for (final rms in rmsSequence) {
          final swFrame = Stopwatch()..start();
          optKey.currentState!.rmsNotifier.value = rms;
          await tester.pump(const Duration(milliseconds: 16));
          swFrame.stop();
          optRmsFrameUs.add(swFrame.elapsedMicroseconds);
        }
        swOptTotal.stop();

        expect(legacyFormBuilds, 30);
        expect(optimizedFormBuilds, 0);
        expect(
          swOptTotal.elapsedMicroseconds,
          lessThan(swLegacyTotal.elapsedMicroseconds),
        );

        // ─────────────────────────────────────────────────────────────────────
        // BENCHMARK 3A: Per-Frame Tick Cost (us/tick) — LifeOsSpringController Retargeting
        // ─────────────────────────────────────────────────────────────────────
        late LifeOsSpringController spring1D;
        late LifeOsSpring2DController spring2D;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: _SpringTickBenchHost(
                  onReady1D: (c) => spring1D = c,
                  onReady2D: (c) => spring2D = c,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Pure SpringSimulation math + controller retargeting microbenchmark (1,000 steps)
        final rawSimSw = Stopwatch()..start();
        var simAcc = 0.0;
        final sim = SpringSimulation(
          LifeOsMotionTokens.snappySpring,
          0.0,
          1.0,
          2.4,
        );
        for (var i = 0; i < 1000; i++) {
          simAcc += sim.x((i % 60) * 0.016667) + sim.dx((i % 60) * 0.016667);
        }
        rawSimSw.stop();
        expect(simAcc.isFinite, isTrue);

        // Full Flutter widget tick + mid-flight retargeting across 180 frames (16ms/tick)
        final springWidgetTickUs = <int>[];
        for (var frame = 0; frame < 180; frame++) {
          if (frame % 6 == 0) {
            final target1D = (frame ~/ 6).isEven ? 1.0 : 0.0;
            final target2D = (frame ~/ 6).isEven
                ? const Offset(84, -48)
                : const Offset(-52, 36);
            spring1D.animateTo(target1D);
            spring2D.animateTo(target2D);
          }
          final swTick = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          swTick.stop();
          springWidgetTickUs.add(swTick.elapsedMicroseconds);
        }

        // ─────────────────────────────────────────────────────────────────────
        // BENCHMARK 3B: Per-Frame Tick Cost (us/tick) — LifeOsParticleBurst (28 particles SoA)
        // ─────────────────────────────────────────────────────────────────────
        final particleKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  child: LifeOsParticleBurst(
                    key: particleKey,
                    particleCount: 28,
                    height: 140,
                    child: const Center(child: Text('Cột mốc hoàn thành')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final particleTickUs = <int>[];
        for (var burst = 0; burst < 4; burst++) {
          await tester.tap(find.byKey(particleKey));
          for (var tick = 0; tick < 50; tick++) {
            final swTick = Stopwatch()..start();
            await tester.pump(const Duration(milliseconds: 16));
            swTick.stop();
            particleTickUs.add(swTick.elapsedMicroseconds);
          }
        }

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final metrics = <String, Object>{
          'arch1_eager_mounted_cards': eagerMountedCards,
          'arch1_lazy_mounted_cards': lazyMountedCards,
          'arch1_eager_mount_median_ms':
              (_median(eagerMountUs) / 1000.0).toStringAsFixed(2),
          'arch1_lazy_mount_median_ms':
              (_median(lazyMountUs) / 1000.0).toStringAsFixed(2),
          'arch1_speedup_factor':
              (_median(eagerMountUs) / math.max(1.0, _median(lazyMountUs)))
                  .toStringAsFixed(2),
          'arch2_legacy_total_ms':
              (swLegacyTotal.elapsedMicroseconds / 1000.0).toStringAsFixed(2),
          'arch2_optimized_total_ms':
              (swOptTotal.elapsedMicroseconds / 1000.0).toStringAsFixed(2),
          'arch2_legacy_median_us_per_event':
              _median(legacyRmsFrameUs).toStringAsFixed(1),
          'arch2_optimized_median_us_per_event':
              _median(optRmsFrameUs).toStringAsFixed(1),
          'arch2_legacy_form_rebuilds': legacyFormBuilds,
          'arch2_optimized_form_rebuilds': optimizedFormBuilds,
          'arch2_speedup_factor': (swLegacyTotal.elapsedMicroseconds /
                  math.max(1, swOptTotal.elapsedMicroseconds))
              .toStringAsFixed(2),
          'spring_pure_math_ns_per_eval':
              ((rawSimSw.elapsedMicroseconds * 1000.0) / 1000.0)
                  .toStringAsFixed(1),
          'spring_retarget_widget_median_us_per_tick':
              _median(springWidgetTickUs).toStringAsFixed(1),
          'spring_retarget_widget_p95_us_per_tick':
              _p95(springWidgetTickUs).toStringAsFixed(1),
          'particle_28_soa_median_us_per_tick':
              _median(particleTickUs).toStringAsFixed(1),
          'particle_28_soa_p95_us_per_tick':
              _p95(particleTickUs).toStringAsFixed(1),
        };

        // ignore: avoid_print
        print('[MOTION_BENCHMARK_JSON] ${jsonEncode(metrics)}');
      },
    );
  });
}
