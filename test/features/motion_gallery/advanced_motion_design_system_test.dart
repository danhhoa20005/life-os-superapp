import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/motion/lifeos_motion.dart';
import 'package:life_os/core/utils/vietnamese_search_matcher.dart';
import 'package:life_os/core/widgets/lifeos_top_toast.dart';
import 'package:life_os/features/motion_gallery/presentation/bloc/motion_gallery_bloc.dart';
import 'package:life_os/features/motion_gallery/presentation/models/motion_sample_ui_spec.dart';
import 'package:life_os/features/motion_gallery/presentation/pages/motion_gallery_page.dart';

class _SpringHarness extends StatefulWidget {
  final ValueChanged<LifeOsSpringController> onReady1D;
  final ValueChanged<LifeOsSpring2DController> onReady2D;

  const _SpringHarness({
    required this.onReady1D,
    required this.onReady2D,
  });

  @override
  State<_SpringHarness> createState() => _SpringHarnessState();
}

class _SpringHarnessState extends State<_SpringHarness>
    with TickerProviderStateMixin {
  late final LifeOsSpringController _ctrl1D;
  late final LifeOsSpring2DController _ctrl2D;

  @override
  void initState() {
    super.initState();
    _ctrl1D = LifeOsSpringController(
      vsync: this,
      initialValue: 0.0,
      spring: LifeOsMotionTokens.snappySpring,
    );
    _ctrl2D = LifeOsSpring2DController(
      vsync: this,
      initialOffset: Offset.zero,
      spring: LifeOsMotionTokens.gestureThrowSpring,
    );
    widget.onReady1D(_ctrl1D);
    widget.onReady2D(_ctrl2D);
  }

  @override
  void dispose() {
    _ctrl1D.dispose();
    _ctrl2D.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl1D, _ctrl2D]),
      builder: (_, _) => SizedBox(
        width: 100 + _ctrl1D.value * 20,
        height: 100 + _ctrl2D.value.dy.abs() * 0.1,
      ),
    );
  }
}

void main() {
  group('1. Kiểm toán Danh mục 66 Mẫu & Kiến trúc Clean Architecture', () {
    test(
      'buildAllMotionGallerySamples() returns exactly 66 unique samples (#01..#66) covering all 8 MotionSampleCategory groups',
      () {
        final samples = buildAllMotionGallerySamples();
        expect(samples.length, 66);

        // Verify strict sequential numbering #01..#66 and unique IDs
        final seenNumbers = <int>{};
        final seenIds = <String>{};
        final categoryCounts = <MotionSampleCategory, int>{};

        for (var i = 0; i < samples.length; i++) {
          final s = samples[i];
          expect(s.number, i + 1);
          expect(
            s.formattedCode,
            '#${(i + 1).toString().padLeft(2, '0')}',
          );
          expect(seenNumbers.add(s.number), isTrue);
          expect(
            seenIds.add(s.id),
            isTrue,
            reason: 'Duplicate sample id: ${s.id}',
          );
          expect(s.titleVi.trim(), isNotEmpty);
          expect(s.uxPurposeVi.trim(), isNotEmpty);
          expect(s.tokenSummary.trim(), isNotEmpty);
          expect(s.upstreamRef.trim(), isNotEmpty);
          categoryCounts[s.category] = (categoryCounts[s.category] ?? 0) + 1;
        }

        expect(seenNumbers.length, 66);
        expect(seenIds.length, 66);
        expect(MotionSampleCategory.values.length, 8);
        expect(categoryCounts.keys.toSet(), MotionSampleCategory.values.toSet());
        for (final cat in MotionSampleCategory.values) {
          expect(
            categoryCounts[cat] ?? 0,
            greaterThanOrEqualTo(8),
            reason: 'Category $cat should contain at least 8 samples',
          );
        }
      },
    );

    test(
      'ZERO Cubit classes in lib/ and ZERO AnimationController/Ticker/Flutter leaks in any domain/ directory',
      () {
        final dartFiles = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();

        final cubitViolations = <String>[];
        final domainMotionLeaks = <String>[];

        final cubitPattern = RegExp(
          r'\b(extends\s+Cubit|Cubit<|CubitProvider)\b',
        );
        final forbiddenDomainPattern = RegExp(
          r'(\bAnimationController\b|\bTicker\b|\bTickerProvider\b|\bSingleTickerProviderStateMixin\b|\bTickerProviderStateMixin\b|package:flutter/)',
        );

        for (final file in dartFiles) {
          final normalized = file.path.replaceAll('\\', '/');
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trim();
            if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
              continue;
            }
            if (cubitPattern.hasMatch(trimmed)) {
              cubitViolations.add('$normalized:${i + 1} -> $trimmed');
            }
            if (normalized.contains('/domain/') &&
                forbiddenDomainPattern.hasMatch(trimmed)) {
              domainMotionLeaks.add('$normalized:${i + 1} -> $trimmed');
            }
          }
        }

        expect(
          cubitViolations,
          isEmpty,
          reason: 'Found forbidden Cubit usage: $cubitViolations',
        );
        expect(
          domainMotionLeaks,
          isEmpty,
          reason:
              'Found AnimationController/Ticker/Flutter leak in domain/: $domainMotionLeaks',
        );
      },
    );
  });

  group('2. MotionGalleryBloc State Machine & Diacritic-Free Search', () {
    blocTest<MotionGalleryBloc, MotionGalleryState>(
      'handles category filter, Vietnamese unaccented query, speed 0.25x/0.5x/1.0x, replaySeed increment, and activeSampleId',
      build: MotionGalleryBloc.new,
      act: (bloc) async {
        Future<void> dispatch(MotionGalleryEvent event) async {
          bloc.add(event);
          await Future<void>.delayed(Duration.zero);
        }

        await dispatch(
          const MotionGalleryCategorySelected(
            MotionSampleCategory.springPhysicsGestures,
          ),
        );
        await dispatch(const MotionGalleryQueryChanged('mam ngoc'));
        await dispatch(const MotionGallerySpeedChanged(0.25));
        await dispatch(const MotionGallerySpeedChanged(0.5));
        await dispatch(const MotionGallerySpeedChanged(1.0));
        await dispatch(const MotionGalleryReplayTriggered());
        await dispatch(
          const MotionGalleryActiveSampleSelected(
            'creative_interactive_mascot',
          ),
        );
        await dispatch(const MotionGalleryCategorySelected(null));
        await dispatch(const MotionGalleryActiveSampleSelected(null));
      },
      expect: () => const <MotionGalleryState>[
        MotionGalleryState(
          selectedCategory: MotionSampleCategory.springPhysicsGestures,
        ),
        MotionGalleryState(
          selectedCategory: MotionSampleCategory.springPhysicsGestures,
          searchQuery: 'mam ngoc',
        ),
        MotionGalleryState(
          selectedCategory: MotionSampleCategory.springPhysicsGestures,
          searchQuery: 'mam ngoc',
          speedFactor: 0.25,
        ),
        MotionGalleryState(
          selectedCategory: MotionSampleCategory.springPhysicsGestures,
          searchQuery: 'mam ngoc',
          speedFactor: 0.5,
        ),
        MotionGalleryState(
          selectedCategory: MotionSampleCategory.springPhysicsGestures,
          searchQuery: 'mam ngoc',
          speedFactor: 1.0,
        ),
        MotionGalleryState(
          selectedCategory: MotionSampleCategory.springPhysicsGestures,
          searchQuery: 'mam ngoc',
          speedFactor: 1.0,
          replaySeed: 2,
        ),
        MotionGalleryState(
          selectedCategory: MotionSampleCategory.springPhysicsGestures,
          searchQuery: 'mam ngoc',
          speedFactor: 1.0,
          replaySeed: 2,
          activeSampleId: 'creative_interactive_mascot',
        ),
        MotionGalleryState(
          selectedCategory: null,
          searchQuery: 'mam ngoc',
          speedFactor: 1.0,
          replaySeed: 2,
          activeSampleId: 'creative_interactive_mascot',
        ),
        MotionGalleryState(
          selectedCategory: null,
          searchQuery: 'mam ngoc',
          speedFactor: 1.0,
          replaySeed: 2,
          activeSampleId: null,
        ),
      ],
    );

    test(
      'VietnameseSearchMatcher matches unaccented Vietnamese queries against 66-sample catalog',
      () {
        final all = buildAllMotionGallerySamples();
        final mascotMatches = all
            .where(
              (s) => VietnameseSearchMatcher.matchesAny('mam ngoc', [
                s.titleVi,
                s.uxPurposeVi,
              ]),
            )
            .toList();
        expect(
          mascotMatches.any((s) => s.id == 'creative_interactive_mascot'),
          isTrue,
        );

        final springMatches = all
            .where(
              (s) => VietnameseSearchMatcher.matchesAny('lo xo', [
                s.titleVi,
                s.uxPurposeVi,
                s.category.shortLabelVi,
              ]),
            )
            .toList();
        expect(springMatches.length, greaterThanOrEqualTo(9));
      },
    );
  });

  group('3. Spring Physics Math, C0/C1 Interruption, TickerMode & Leak Hygiene', () {
    test(
      'LifeOsMotionTokens: sheetSnapSpring & chartMorphSpring achieve zeta >= 1.0 (0% overshoot), rubberBandClamp resists over-drag, and projectNearestDetent predicts fling detents',
      () {
        // 1. Damping ratios
        final sheetZeta = LifeOsMotionTokens.dampingRatioOf(
          LifeOsMotionTokens.sheetSnapSpring,
        );
        final chartZeta = LifeOsMotionTokens.dampingRatioOf(
          LifeOsMotionTokens.chartMorphSpring,
        );
        final bouncyZeta = LifeOsMotionTokens.dampingRatioOf(
          LifeOsMotionTokens.bouncySpring,
        );

        expect(sheetZeta, greaterThanOrEqualTo(1.0));
        expect(chartZeta, greaterThanOrEqualTo(1.0));
        expect(bouncyZeta, lessThan(0.75));

        // Analytical 0% overshoot verification across t = 0..1.5s
        final sheetSim = SpringSimulation(
          LifeOsMotionTokens.sheetSnapSpring,
          0.0,
          1.0,
          0.0,
        );
        final chartSim = SpringSimulation(
          LifeOsMotionTokens.chartMorphSpring,
          0.0,
          1.0,
          0.0,
        );
        for (var ms = 0; ms <= 1500; ms += 8) {
          final t = ms / 1000.0;
          expect(sheetSim.x(t), lessThanOrEqualTo(1.0001));
          expect(chartSim.x(t), lessThanOrEqualTo(1.0001));
        }

        // 2. Hyperbolic rubberBandClamp diminishes over-drag amplitude
        expect(
          LifeOsMotionTokens.rubberBandClamp(
            0.65,
            min: 0.42,
            max: 0.92,
            viewportExtent: 1.0,
          ),
          closeTo(0.65, 1e-6),
        );
        final overMax = LifeOsMotionTokens.rubberBandClamp(
          1.22, // +0.30 past max 0.92
          min: 0.42,
          max: 0.92,
          viewportExtent: 1.0,
          resistance: 0.55,
        );
        expect(overMax, greaterThan(0.92));
        expect(overMax, lessThan(1.22));

        final belowMin = LifeOsMotionTokens.rubberBandClamp(
          0.12, // -0.30 below min 0.42
          min: 0.42,
          max: 0.92,
          viewportExtent: 1.0,
          resistance: 0.55,
        );
        expect(belowMin, lessThan(0.42));
        expect(belowMin, greaterThan(0.12));

        // 3. projectNearestDetent velocity lookahead (0.18s)
        const detents = <double>[0.42, 0.72, 0.92];
        expect(
          LifeOsMotionTokens.projectNearestDetent(
            current: 0.46,
            velocityPerSec: 0.0,
            detents: detents,
          ),
          0.42,
        );
        expect(
          LifeOsMotionTokens.projectNearestDetent(
            current: 0.46,
            velocityPerSec: 1.6, // projected = 0.46 + 0.288 = 0.748 -> 0.72
            detents: detents,
          ),
          0.72,
        );
        expect(
          LifeOsMotionTokens.projectNearestDetent(
            current: 0.52,
            velocityPerSec: 2.5, // projected = 0.52 + 0.45 = 0.97 -> 0.92
            detents: detents,
          ),
          0.92,
        );
        expect(
          LifeOsMotionTokens.projectNearestDetent(
            current: 0.70,
            velocityPerSec: -1.8, // projected = 0.70 - 0.324 = 0.376 -> 0.42
            detents: detents,
          ),
          0.42,
        );
      },
    );

    testWidgets(
      'LifeOsSpringController & LifeOsSpring2DController preserve C0 position & C1 velocity on 40ms mid-flight reversal, halt under TickerMode(false), and dispose with zero leaked tickers',
      (tester) async {
        late LifeOsSpringController ctrl1D;
        late LifeOsSpring2DController ctrl2D;

        await tester.pumpWidget(
          MaterialApp(
            home: _SpringHarness(
              onReady1D: (c) => ctrl1D = c,
              onReady2D: (c) => ctrl2D = c,
            ),
          ),
        );

        // Start 0.0 -> 1.0 (1D) and (0,0) -> (120, -80) (2D)
        ctrl1D.animateTo(1.0);
        ctrl2D.animateTo(const Offset(120, -80));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));

        expect(ctrl1D.isAnimating, isTrue);
        expect(ctrl2D.isAnimating, isTrue);

        final pos1DBefore = ctrl1D.value;
        final vel1DBefore = ctrl1D.velocity;
        final pos2DBefore = ctrl2D.value;
        final vel2DBefore = ctrl2D.velocity;

        expect(pos1DBefore, greaterThan(0.02));
        expect(pos1DBefore, lessThan(0.98));
        expect(vel1DBefore, greaterThan(0.5));
        expect(pos2DBefore.dx, greaterThan(2.0));
        expect(vel2DBefore.dx, greaterThan(10.0));

        // Reverse mid-flight at 40ms back to 0.0 / Offset.zero!
        ctrl1D.animateTo(0.0);
        ctrl2D.animateTo(Offset.zero);

        // C0 Position & C1 Velocity continuity at exact instant of retargeting (dt = 0):
        expect(ctrl1D.value, closeTo(pos1DBefore, 1e-5));
        expect(ctrl1D.velocity, closeTo(vel1DBefore, 1e-2));
        expect(ctrl2D.value.dx, closeTo(pos2DBefore.dx, 1e-4));
        expect(ctrl2D.value.dy, closeTo(pos2DBefore.dy, 1e-4));
        expect(ctrl2D.velocity.dx, closeTo(vel2DBefore.dx, 1e-1));
        expect(ctrl2D.velocity.dy, closeTo(vel2DBefore.dy, 1e-1));

        // Because initial forward momentum is preserved (C1 > 0), 8ms later position coasts slightly before smoothly reversing toward 0.0
        await tester.pump(const Duration(milliseconds: 8));
        expect(ctrl1D.value, greaterThan(0.0));

        // Settle cleanly back to 0.0
        await tester.pumpAndSettle();
        expect(ctrl1D.value, closeTo(0.0, 0.002));
        expect(ctrl2D.value.dx, closeTo(0.0, 1.0));
        expect(ctrl2D.value.dy, closeTo(0.0, 1.0));

        // Offstage TickerMode(enabled: false) -> tickersEnabled: false halts immediately (!isAnimating)
        ctrl1D.animateTo(0.85, tickersEnabled: false);
        ctrl2D.animateTo(const Offset(60, 40), tickersEnabled: false);
        expect(ctrl1D.isAnimating, isFalse);
        expect(ctrl2D.isAnimating, isFalse);
        expect(ctrl1D.value, 0.85);
        expect(ctrl2D.value, const Offset(60, 40));

        // Re-trigger active spring flight, then dispose mid-flight to verify zero ticker leaks
        ctrl1D.animateTo(0.0);
        ctrl2D.animateTo(Offset.zero);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 24));
        expect(ctrl1D.isAnimating, isTrue);

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        expect(tester.takeException(), isNull);
        tester.verifyTickersWereDisposed();
      },
    );
  });

  group('4. Light Mode, Dark Mode & Reduced Motion / Disable Animations (A11Y)', () {
    testWidgets(
      'MotionGalleryPage renders cleanly across ThemeMode.light, ThemeMode.dark, platformReduceMotion, and platformDisableAnimations',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Light Mode + Standard Motion
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.light,
            builder: (_, child) => LifeOsTopToastHost(child: child!),
            home: const MotionGalleryPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('66 mẫu chuẩn hoá'), findsOneWidget);
        expect(find.text('Giao diện: Sáng'), findsOneWidget);
        expect(find.text('Reduce Motion: Tắt (Chuẩn)'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 2. Dark Mode
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.dark,
            builder: (_, child) => LifeOsTopToastHost(child: child!),
            home: const MotionGalleryPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Giao diện: Tối'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 3. iOS OS Reduce Motion (platformReduceMotion: true)
        await tester.pumpWidget(
          LifeOsMotionScope.overrideForTest(
            preferences: const LifeOsMotionPreferences(
              platformReduceMotion: true,
              hapticsEnabled: false,
            ),
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (_, child) => LifeOsTopToastHost(child: child!),
              home: const MotionGalleryPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Reduce Motion: Đang bật'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 4. Android Remove Animations (platformDisableAnimations: true -> 0ms instant)
        await tester.pumpWidget(
          LifeOsMotionScope.overrideForTest(
            preferences: const LifeOsMotionPreferences(
              platformDisableAnimations: true,
              hapticsEnabled: false,
            ),
            child: MaterialApp(
              theme: AppTheme.dark(),
              builder: (_, child) => LifeOsTopToastHost(child: child!),
              home: const MotionGalleryPage(),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Reduce Motion: Đang bật'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('5. Full 66-Sample Narrow 360x800 @ 112% Audit & End-to-End App Navigation', () {
    testWidgets(
      'Traverses all 8 MotionSampleCategory filters on 360x800 @ 112% text scale: mounts, paints, and settles ALL 66 samples with 0 exceptions & 0 RenderFlex overflows',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final allSamples = buildAllMotionGallerySamples();
        expect(allSamples.length, 66);

        // Phase A: Audit every individual sample #01..#66 inside MotionGalleryPage at 360x800 @ 112%
        final sampleDiagnostics = <String>[];
        for (final sample in allSamples) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                return MediaQuery(
                  data: mq.copyWith(textScaler: const TextScaler.linear(1.12)),
                  child: LifeOsTopToastHost(child: child!),
                );
              },
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      child: Builder(
                        builder: (innerCtx) =>
                            sample.previewBuilder(innerCtx, 1.0, 1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Object? err;
          while ((err = tester.takeException()) != null) {
            sampleDiagnostics.add(
              '${sample.formattedCode} (${sample.id}): $err',
            );
          }
        }
        expect(
          sampleDiagnostics,
          isEmpty,
          reason:
              'Samples with layout/overflow issues at 360x800 @ 112%:\n${sampleDiagnostics.join('\n')}',
        );

        // Phase B: Full MotionGalleryPage across all 8 category filters at 360x800 @ 112%
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: const TextScaler.linear(1.12)),
                child: LifeOsTopToastHost(child: child!),
              );
            },
            home: const MotionGalleryPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final mountedSampleIds = <String>{};
        final scrollViewFinder = find.byKey(
          const Key('motion_gallery_scroll_view'),
        );

        for (final category in MotionSampleCategory.values) {
          final expectedInCat = allSamples
              .where((s) => s.category == category)
              .map((s) => s.id)
              .toSet();

          // Jump CustomScrollView back to top so the toolbar category strip is visible
          final scrollableState = tester.state<ScrollableState>(
            find.descendant(
              of: scrollViewFinder,
              matching: find.byType(Scrollable),
            ).first,
          );
          scrollableState.position.jumpTo(0.0);
          await tester.pumpAndSettle();

          final chipKey = ValueKey<String>('motion_cat_${category.name}');
          await tester.ensureVisible(find.byKey(chipKey));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(chipKey));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          void collectVisibleCards() {
            for (final id in expectedInCat) {
              if (find
                  .byKey(ValueKey<String>('motion_card_$id'))
                  .evaluate()
                  .isNotEmpty) {
                mountedSampleIds.add(id);
              }
            }
          }

          collectVisibleCards();

          // Scroll smoothly down through the filtered SliverList until all cards in this category mount & settle
          var step = 0;
          while (!mountedSampleIds.containsAll(expectedInCat) && step < 30) {
            step++;
            final pos = scrollableState.position;
            if (pos.pixels >= pos.maxScrollExtent) {
              break;
            }
            final nextOffset = (pos.pixels + 340.0).clamp(
              0.0,
              pos.maxScrollExtent,
            );
            pos.jumpTo(nextOffset);
            await tester.pump();
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'Exception while rendering category ${category.name} at step $step',
            );
            collectVisibleCards();
          }

          expect(
            mountedSampleIds.containsAll(expectedInCat),
            isTrue,
            reason:
                'Missing unmounted samples in ${category.name}: ${expectedInCat.difference(mountedSampleIds)}',
          );
        }

        expect(mountedSampleIds.length, 66);
      },
    );

    testWidgets(
      'End-to-End Integration Flow: LifeOsApp -> Cài đặt -> settings_motion_studio_row -> /motion-gallery -> search "Mầm Ngọc", expand "Chi tiết Token & 6 Lò xo", tap "Phát lại"',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeFirestore = FakeFirebaseFirestore();
        const uid = 'uid_motion_qa_e2e';
        await fakeFirestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'qa.motion@lifeos.vn',
          'fullName': 'Kỹ sư QA Motion',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
        });
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('wallet_bank_default')
            .set({
              'id': 'wallet_bank_default',
              'ownerId': uid,
              'name': 'Vietcombank Chính',
              'type': 'bank',
              'balanceMinor': 24500000,
              'isEstimatedBalance': false,
            });

        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'qa.motion@lifeos.vn',
            displayName: 'Kỹ sư QA Motion',
          ),
        );

        await sl.reset();
        await configureDependencies(
          authOverride: mockAuth,
          firestoreOverride: fakeFirestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 1. Navigate to Cài đặt from TodayPage shortcut grid
        final settingsShortcut = find.text('Cài đặt').first;
        await tester.scrollUntilVisible(
          settingsShortcut,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(settingsShortcut);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 2. Tap Key('settings_motion_studio_row') -> opens /motion-gallery
        final motionStudioRow = find.byKey(
          const Key('settings_motion_studio_row'),
        );
        await tester.scrollUntilVisible(
          motionStudioRow,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(motionStudioRow);
        await tester.pumpAndSettle();

        expect(find.text('Motion Studio'), findsOneWidget);
        expect(find.text('66 mẫu chuẩn hoá'), findsOneWidget);

        // 3. Expand 'Chi tiết Token & 6 Lò xo'
        final tokenToggle = find.byKey(
          const Key('motion_gallery_tokens_toggle'),
        );
        await tester.ensureVisible(tokenToggle);
        await tester.pumpAndSettle();
        await tester.tap(tokenToggle);
        await tester.pumpAndSettle();
        expect(find.text('Bảng Duration Tokens chuẩn hoá'), findsOneWidget);
        expect(
          find.text('6 Lò xo Vật lý hiệu chuẩn (SpringDescription)'),
          findsOneWidget,
        );

        // 4. Search 'Mầm Ngọc' in Key('motion_gallery_search_input')
        final searchField = find.byKey(
          const Key('motion_gallery_search_input'),
        );
        await tester.ensureVisible(searchField);
        await tester.pumpAndSettle();
        await tester.enterText(searchField, 'Mầm Ngọc');
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Linh vật tương tác 5 trạng thái "Mầm Ngọc"'),
          findsOneWidget,
        );
        expect(find.textContaining('Đang hiển thị 1 / 66 mẫu'), findsOneWidget);

        // 5. Tap 'Phát lại' (Key('motion_gallery_replay_btn'))
        final replayBtn = find.byKey(const Key('motion_gallery_replay_btn'));
        await tester.ensureVisible(replayBtn);
        await tester.pumpAndSettle();
        await tester.tap(replayBtn);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
