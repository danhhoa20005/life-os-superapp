import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/motion/lifeos_motion.dart';

void main() {
  group('LifeOsMotionPreferences & Accessibility Precedence (A11Y-01, A11Y-02)', () {
    test('Android disableAnimations overrides decorative standard preference', () {
      const prefs = LifeOsMotionPreferences(
        userMode: LifeOsMotionMode.standard,
        platformDisableAnimations: true,
        platformReduceMotion: false,
      );
      expect(prefs.isReducedMotion, isTrue);
      expect(prefs.isMotionOff, isTrue);
      expect(prefs.resolveDuration(LifeOsMotionTokens.panel), Duration.zero);
      expect(prefs.resolveOffset(const Offset(0.05, 0)), Offset.zero);
      expect(prefs.resolveScale(0.97), 1.0);
    });

    test('iOS reduceMotion overrides decorative standard preference with short fade', () {
      const prefs = LifeOsMotionPreferences(
        userMode: LifeOsMotionMode.standard,
        platformDisableAnimations: false,
        platformReduceMotion: true,
      );
      expect(prefs.isReducedMotion, isTrue);
      expect(prefs.isMotionOff, isFalse);
      expect(
        prefs.resolveDuration(LifeOsMotionTokens.panel),
        LifeOsMotionTokens.feedbackFast,
      );
      expect(prefs.resolveOffset(const Offset(0, 8)), Offset.zero);
      expect(prefs.resolveScale(0.97), 1.0);
    });

    testWidgets('LifeOsMotionHost reflects MediaQuery.disableAnimations and ThemeBloc mode', (
      tester,
    ) async {
      late LifeOsMotionPreferences captured;
      final themeBloc = ThemeBloc(persistToDisk: false);
      addTearDown(themeBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: LifeOsMotionHost(
              userMode: LifeOsMotionMode.standard,
              child: Builder(
                builder: (context) {
                  captured = LifeOsMotionScope.of(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      expect(captured.isReducedMotion, isTrue);
      expect(captured.isMotionOff, isTrue);

      themeBloc.add(const MotionModeChanged(LifeOsMotionMode.reduced));
      await tester.pump();
      expect(themeBloc.state.prefersReducedMotion, isTrue);
    });
  });
}
