import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await UserBehaviorPrefs.resetForTest();
  });

  group('UserBehaviorPrefs — Vietnamese UX & Habit Persistence', () {
    test('vndZeroPadSuggestions generates instant .000 / .0000 / .000.000 VND chips', () {
      final for45 = UserBehaviorPrefs.vndZeroPadSuggestions('45');
      expect(for45.length, 3);
      expect(for45[0].$1, 45000);
      expect(for45[0].$2, '45.000 ₫');
      expect(for45[1].$1, 450000);
      expect(for45[1].$2, '450.000 ₫');
      expect(for45[2].$1, 4500000);
      expect(for45[2].$2, '4.500.000 ₫');

      // Already full VND numbers (>= 10000) or empty/zero should not clutter UI
      expect(UserBehaviorPrefs.vndZeroPadSuggestions(''), isEmpty);
      expect(UserBehaviorPrefs.vndZeroPadSuggestions('0'), isEmpty);
      expect(UserBehaviorPrefs.vndZeroPadSuggestions('50000'), isEmpty);
    });

    test('remembers last used wallet and falls back safely when wallet removed', () async {
      final available = ['wallet_cash', 'wallet_vcb', 'wallet_momo'];
      expect(UserBehaviorPrefs.resolvePreferredWalletId(available), 'wallet_cash');

      await UserBehaviorPrefs.rememberWallet('wallet_vcb');
      expect(await UserBehaviorPrefs.loadLastWalletId(), 'wallet_vcb');
      expect(UserBehaviorPrefs.resolvePreferredWalletId(available), 'wallet_vcb');

      // If previously used wallet was deleted, fall back to first available wallet
      expect(
        UserBehaviorPrefs.resolvePreferredWalletId(['wallet_cash', 'wallet_momo']),
        'wallet_cash',
      );
    });

    test('persists privacy balance mask and pinned home shortcuts', () async {
      expect(await UserBehaviorPrefs.loadHideBalances(), isFalse);
      await UserBehaviorPrefs.saveHideBalances(true);
      expect(await UserBehaviorPrefs.loadHideBalances(), isTrue);

      await UserBehaviorPrefs.savePinnedShortcuts({
        'finance',
        'planning',
        'kitchen',
        'utilities',
      });
      final pinned = await UserBehaviorPrefs.loadPinnedShortcuts();
      expect(pinned, ['finance', 'planning', 'kitchen', 'utilities']);
    });

    test('contextualTimeSubtitle adapts to Vietnamese daily rhythm', () {
      expect(
        UserBehaviorPrefs.contextualTimeSubtitle(DateTime(2026, 11, 23, 7, 30)),
        'Chào buổi sáng',
      );
      expect(
        UserBehaviorPrefs.contextualTimeSubtitle(DateTime(2026, 11, 23, 12, 15)),
        'Giờ nghỉ trưa',
      );
      expect(
        UserBehaviorPrefs.contextualTimeSubtitle(DateTime(2026, 11, 23, 15, 45)),
        'Chào buổi chiều',
      );
      expect(
        UserBehaviorPrefs.contextualTimeSubtitle(DateTime(2026, 11, 23, 21, 0)),
        'Buổi tối thư thái',
      );
    });
  });
}
