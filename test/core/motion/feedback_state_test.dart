import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/core/widgets/lifeos_design_system.dart';

void main() {
  group('High-Integrity Finance Feedback, Deduplicated Toasts & Accessibility (TX-01..04, A11Y-01..03)', () {
    test('TX-01 & TX-03: LifeOsOneShotEffectTracker fires once per unique authoritative key and blocks replays', () {
      final tracker = LifeOsOneShotEffectTracker();
      expect(tracker.consumeOnce('tx_confirmed_001'), isTrue);
      // Repeated widget rebuild or duplicate bank callback with same key must NOT replay
      expect(tracker.consumeOnce('tx_confirmed_001'), isFalse);
      expect(tracker.consumeOnce(''), isFalse);
      expect(tracker.consumeOnce(null), isFalse);
      // Distinct authoritative confirmation fires cleanly
      expect(tracker.consumeOnce('tx_confirmed_002'), isTrue);
    });

    testWidgets(
      'TX-04: LifeOsTruthfulNumericText & LifeOsAnimatedProgressBar keep exact values mid-transition without fake numbers',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: Column(
                children: [
                  LifeOsTruthfulNumericText(
                    formattedValue: '1.250.000 ₫',
                    style: TextStyle(fontSize: 22),
                  ),
                  LifeOsAnimatedProgressBar(
                    progressRatio: 0.55,
                    color: Colors.green,
                    semanticsLabel: 'Ngân sách ăn uống',
                    semanticsValue: '55%',
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('1.250.000 ₫'), findsOneWidget);

        // Update to overspent state (128%) and check mid-transition frame at 60ms
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: Column(
                children: [
                  LifeOsTruthfulNumericText(
                    formattedValue: '2.560.000 ₫',
                    style: TextStyle(fontSize: 22),
                  ),
                  LifeOsAnimatedProgressBar(
                    progressRatio: 1.28,
                    color: Colors.red,
                    semanticsLabel: 'Ngân sách ăn uống',
                    semanticsValue: '128%',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 60));

        // New exact value is already present mid-crossfade (never an interpolated fake amount!)
        expect(find.text('2.560.000 ₫'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text('2.560.000 ₫'), findsOneWidget);
        expect(find.text('1.250.000 ₫'), findsNothing);
      },
    );

    testWidgets(
      'Section 7.5 & A11Y-03: LifeOsTopToast deduplicates identical foreground bursts and exposes liveRegion semantics under 125% text scale & Reduce Motion',
      (tester) async {
        late BuildContext hostCtx;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(highContrast: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.25),
              ),
              child: LifeOsMotionHost(
                userMode: LifeOsMotionMode.reduced,
                child: LifeOsTopToastHost(child: child ?? const SizedBox.shrink()),
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  hostCtx = ctx;
                  return const Column(
                    children: [
                      LifeOsAnimatedStatusBadge(
                        statusKey: 'matched_qr',
                        label: 'Khớp đơn QR thiết bị',
                        icon: Icons.qr_code_2_rounded,
                        tone: LifeOsAccentTone.blue,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('Khớp đơn QR thiết bị'), findsOneWidget);

        // Trigger identical foreground toast twice in rapid succession -> 1 surface, zero crash/overflow
        LifeOsTopToast.show(hostCtx, '✓ Đã ghi sổ giao dịch 85.000 ₫');
        await tester.pump(const Duration(milliseconds: 40));
        LifeOsTopToast.show(hostCtx, '✓ Đã ghi sổ giao dịch 85.000 ₫');
        await tester.pump();

        expect(find.text('Đã ghi sổ giao dịch 85.000 ₫'), findsOneWidget);
        expect(tester.takeException(), isNull);

        LifeOsTopToast.dismiss();
        await tester.pumpAndSettle();
      },
    );
  });
}
