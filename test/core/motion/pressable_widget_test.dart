import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/motion/lifeos_motion.dart';

void main() {
  group('LifeOsPressable & LifeOsSkeletonBox safety contracts', () {
    testWidgets(
      'LifeOsPressable preserves outer hit target while pressed, handles cancel/repeat/dispose cleanly',
      (tester) async {
        var tapCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: LifeOsMotionScope.overrideForTest(
                  preferences: const LifeOsMotionPreferences(
                    userMode: LifeOsMotionMode.standard,
                    hapticsEnabled: false,
                  ),
                  child: LifeOsPressable(
                    key: const Key('pressable_target'),
                    semanticsLabel: 'Lưu giao dịch',
                    onPressed: () => tapCount++,
                    child: const SizedBox(width: 160, height: 50),
                  ),
                ),
              ),
            ),
          ),
        );

        final initialRect = tester.getRect(find.byKey(const Key('pressable_target')));
        expect(initialRect.width, 160);
        expect(initialRect.height, 50);

        // Press down and pump 40ms into SpringSimulation
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('pressable_target'))),
        );
        await tester.pump(const Duration(milliseconds: 40));

        // Outer interactive hit box MUST remain 160x50!
        final pressedRect = tester.getRect(find.byKey(const Key('pressable_target')));
        expect(pressedRect.size, initialRect.size);

        // Cancel gesture (drag away / cancel) -> recovers cleanly without firing tap
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(tapCount, 0);

        // Rapid repeated taps settle cleanly and increment exact count
        await tester.tap(find.byKey(const Key('pressable_target')));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tap(find.byKey(const Key('pressable_target')));
        await tester.pumpAndSettle();
        expect(tapCount, 2);

        // Mid-animation disposal does not throw ticker leaks
        final g2 = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('pressable_target'))),
        );
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await g2.up();
      },
    );

    testWidgets(
      'LifeOsSkeletonBox stops ticker under TickerMode(false) and Reduce Motion (PERF-02, PERF-03)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: LifeOsMotionScope.overrideForTest(
              preferences: const LifeOsMotionPreferences(
                userMode: LifeOsMotionMode.reduced,
              ),
              child: const Scaffold(
                body: LifeOsSkeletonBox(
                  width: 120,
                  height: 20,
                  semanticsLabel: 'Đang tải số dư',
                ),
              ),
            ),
          ),
        );

        // Because Reduce Motion disables looping shimmer, pumpAndSettle MUST NOT time out!
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Đang tải số dư'), findsOneWidget);

        // Under standard motion + TickerMode(enabled: false) (offstage tab), ticker also stops!
        await tester.pumpWidget(
          MaterialApp(
            home: LifeOsMotionScope.overrideForTest(
              preferences: const LifeOsMotionPreferences(
                userMode: LifeOsMotionMode.standard,
              ),
              child: const TickerMode(
                enabled: false,
                child: Scaffold(
                  body: LifeOsSkeletonBox(width: 120, height: 20),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      },
    );
  });
}
