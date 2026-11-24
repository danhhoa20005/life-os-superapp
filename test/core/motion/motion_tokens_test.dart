import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/motion/lifeos_motion.dart';

void main() {
  group('LifeOsMotionTokens specification invariants', () {
    test('duration hierarchy stays monotonic and within non-blocking budgets', () {
      expect(LifeOsMotionTokens.instant, Duration.zero);
      expect(
        LifeOsMotionTokens.feedbackFast < LifeOsMotionTokens.micro,
        isTrue,
      );
      expect(LifeOsMotionTokens.micro < LifeOsMotionTokens.standard, isTrue);
      expect(LifeOsMotionTokens.standard < LifeOsMotionTokens.medium, isTrue);
      expect(LifeOsMotionTokens.medium < LifeOsMotionTokens.panel, isTrue);
      expect(LifeOsMotionTokens.panel < LifeOsMotionTokens.expressive, isTrue);
      expect(
        LifeOsMotionTokens.expressive <= LifeOsMotionTokens.longEmphasis,
        isTrue,
      );
      expect(
        LifeOsMotionTokens.longEmphasis.inMilliseconds,
        lessThanOrEqualTo(520),
      );
      // Exit transitions are faster than enter so user actions are never delayed
      expect(
        LifeOsMotionTokens.exitStandard < LifeOsMotionTokens.medium,
        isTrue,
      );
    });

    test('geometry and stagger guardrails enforce Section 3.3 limits', () {
      expect(
        LifeOsMotionTokens.pressedScaleStandard,
        inInclusiveRange(0.97, 0.985),
      );
      expect(
        LifeOsMotionTokens.pressedScaleCompact,
        inInclusiveRange(0.97, 0.985),
      );
      expect(
        LifeOsMotionTokens.localEntranceOffsetPx,
        inInclusiveRange(4.0, 12.0),
      );
      expect(
        LifeOsMotionTokens.staggerStep.inMilliseconds,
        inInclusiveRange(25, 45),
      );
      expect(LifeOsMotionTokens.maxStaggeredItems, inInclusiveRange(4, 6));
    });

    test('LifeOsStableListRegistry caps initial & burst stagger (TX-05)', () {
      final registry = LifeOsStableListRegistry(animateInitialItems: true);
      final initialAnimated = registry.registerSnapshot(
        List<String>.generate(20, (i) => 'tx_$i'),
      );
      expect(initialAnimated.length, LifeOsMotionTokens.maxStaggeredItems);

      // Re-emitting exact same snapshot must NOT replay entrance animations
      expect(
        registry.registerSnapshot(List<String>.generate(20, (i) => 'tx_$i')),
        isEmpty,
      );

      // Single new item animates once
      expect(
        registry.registerSnapshot([
          'tx_new_single',
          ...List<String>.generate(20, (i) => 'tx_$i'),
        ]),
        equals({'tx_new_single'}),
      );

      // Bulk sync of 30 new items skips mass stagger so scroll never jumps
      final bulkIds = [
        ...List<String>.generate(30, (i) => 'tx_bulk_$i'),
        'tx_new_single',
        ...List<String>.generate(20, (i) => 'tx_i_$i'),
      ];
      expect(registry.registerSnapshot(bulkIds), isEmpty);
    });
  });
}
