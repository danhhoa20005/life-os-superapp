import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/behavior/local_behavior_store.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';

class _NoOpDeviceCalendarDriver implements DeviceCalendarDriver {
  const _NoOpDeviceCalendarDriver();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<List<DeviceCalendarInfo>> listCalendars() async => const [];

  @override
  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async => const [];

  @override
  Future<int?> upsertEvent({
    int? deviceEventId,
    int? deviceCalendarId,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String timeZone = 'Asia/Ho_Chi_Minh',
    String? rrule,
    int reminderMinutesBefore = 15,
  }) async => null;

  @override
  Future<bool> deleteEvent(int deviceEventId) async => false;
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await UserBehaviorPrefs.resetForTest();
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await UserBehaviorPrefs.resetForTest();
    await sl.reset();
  });

  group('UserBehaviorPrefs — Vietnamese UX & Habit Persistence', () {
    test(
      'vndZeroPadSuggestions generates instant .000 / .0000 / .000.000 VND chips',
      () {
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
      },
    );

    test(
      'remembers last used wallet and falls back safely when wallet removed',
      () async {
        final available = ['wallet_cash', 'wallet_vcb', 'wallet_momo'];
        expect(
          UserBehaviorPrefs.resolvePreferredWalletId(available),
          'wallet_cash',
        );

        await UserBehaviorPrefs.rememberWallet('wallet_vcb');
        expect(await UserBehaviorPrefs.loadLastWalletId(), 'wallet_vcb');
        expect(
          UserBehaviorPrefs.resolvePreferredWalletId(available),
          'wallet_vcb',
        );

        // If previously used wallet was deleted, fall back to first available wallet
        expect(
          UserBehaviorPrefs.resolvePreferredWalletId([
            'wallet_cash',
            'wallet_momo',
          ]),
          'wallet_cash',
        );
      },
    );

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
        UserBehaviorPrefs.contextualTimeSubtitle(
          DateTime(2026, 11, 23, 12, 15),
        ),
        'Giờ nghỉ trưa',
      );
      expect(
        UserBehaviorPrefs.contextualTimeSubtitle(
          DateTime(2026, 11, 23, 15, 45),
        ),
        'Chào buổi chiều',
      );
      expect(
        UserBehaviorPrefs.contextualTimeSubtitle(DateTime(2026, 11, 23, 21, 0)),
        'Buổi tối thư thái',
      );
    });
  });

  group('UserBehaviorPrefs v2.0 — Account Isolation, Hydration & Reset', () {
    test(
      'isolates voice engine mode, permissions popup, interests, onboarding skip, personalization, FTUE tip & searches per account',
      () async {
        UserBehaviorPrefs.bindActiveUser('u_alice');
        await UserBehaviorPrefs.savePreferredVoiceEngineMode('system_dialog');
        await UserBehaviorPrefs.markPermissionsPopupDismissed(true);
        await UserBehaviorPrefs.saveUserInterests({'spending', 'schedule'});
        await UserBehaviorPrefs.saveOnboardingSkipped(true);
        await UserBehaviorPrefs.savePersonalizationEnabled(false);
        await UserBehaviorPrefs.saveFirstActionTipDismissed(true);
        await UserBehaviorPrefs.saveRecentSearches(['điện nước', 'tiền nhà']);
        await UserBehaviorPrefs.saveAppPinCode('1234');
        await UserBehaviorPrefs.saveHideBalances(true);

        // Switch to Bob -> zero leakage from Alice!
        UserBehaviorPrefs.bindActiveUser('u_bob');
        expect(
          await UserBehaviorPrefs.loadPreferredVoiceEngineMode(),
          'google_service',
        );
        expect(await UserBehaviorPrefs.hasDismissedPermissionsPopup(), isFalse);
        expect(await UserBehaviorPrefs.loadUserInterests(), isEmpty);
        expect(await UserBehaviorPrefs.loadOnboardingSkipped(), isFalse);
        expect(await UserBehaviorPrefs.loadPersonalizationEnabled(), isTrue);
        expect(await UserBehaviorPrefs.loadFirstActionTipDismissed(), isFalse);
        expect(await UserBehaviorPrefs.loadRecentSearches(), isEmpty);

        // Bob sets his own data
        await UserBehaviorPrefs.saveUserInterests({'vehicle'});
        await UserBehaviorPrefs.saveRecentSearches(['thay nhớt']);

        // Reset Alice's behavior data ONLY -> Bob's data & Alice's PIN/hideBalances remain intact!
        UserBehaviorPrefs.bindActiveUser('u_alice');
        await UserBehaviorPrefs.resetAllBehaviorDataForActiveUser();
        expect(await UserBehaviorPrefs.loadUserInterests(), isEmpty);
        expect(await UserBehaviorPrefs.loadPersonalizationEnabled(), isTrue);
        expect(await UserBehaviorPrefs.loadFirstActionTipDismissed(), isFalse);
        expect(await UserBehaviorPrefs.loadRecentSearches(), isEmpty);
        expect(await UserBehaviorPrefs.loadHabitShortcuts(), isEmpty);
        expect(await LocalBehaviorStore.instance.loadEvents(), isEmpty);
        expect(await UserBehaviorPrefs.verifyAppPinCode('1234'), isTrue);
        expect(await UserBehaviorPrefs.loadHideBalances(), isTrue);

        // Switch back to Bob -> Bob is completely untouched
        UserBehaviorPrefs.bindActiveUser('u_bob');
        expect(await UserBehaviorPrefs.loadUserInterests(), {'vehicle'});
        expect(await UserBehaviorPrefs.loadRecentSearches(), ['thay nhớt']);
      },
    );

    test(
      'recordHabitExecution hydrates prior habits on re-bind, merges amount-free IDs, and uses circular-mean hour',
      () async {
        UserBehaviorPrefs.bindActiveUser('u_habit_user');
        await UserBehaviorPrefs.recordHabitExecution(
          label: 'Cà phê 35k',
          commandText: 'Cà phê 35k',
          categoryName: 'Ăn uống',
          amountMinor: 35000,
          now: DateTime(2026, 11, 24, 23, 30),
        );

        // Simulate app restart / session switch back without calling loadHabitShortcuts() first
        UserBehaviorPrefs.clearSessionOnSignOut();
        UserBehaviorPrefs.bindActiveUser('u_habit_user');

        await UserBehaviorPrefs.recordHabitExecution(
          label: 'Cà phê 45k',
          commandText: 'Cà phê 45k',
          categoryName: 'Ăn uống',
          amountMinor: 45000,
          now: DateTime(2026, 11, 25, 1, 10),
        );
        await UserBehaviorPrefs.recordHabitExecution(
          label: 'Gửi xe 10k',
          commandText: 'Gửi xe 10k',
          categoryName: 'Di chuyển',
          amountMinor: 10000,
          now: DateTime(2026, 11, 25, 8, 0),
        );

        final habits = await UserBehaviorPrefs.loadHabitShortcuts();
        expect(habits.length, 2);
        final coffee = habits.firstWhere((h) => h.id == 'cà_phê');
        expect(coffee.frequency, 2);
        expect(coffee.typicalHour, 0);
        expect(habits.any((h) => h.id == 'gửi_xe'), isTrue);
      },
    );
  });

  group('Adaptive TodayPage Dashboard UX (360x800 @ 112%)', () {
    testWidgets(
      'renders circadian subtitle, honest local-save sync, scope pill, FTUE tip, contextual recommendations & personalization sheet with zero overflow',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        NativeDeviceCalendarBridge.setDriverOverride(
          const _NoOpDeviceCalendarDriver(),
        );

        final firestore = FakeFirebaseFirestore();
        const uid = 'u_adaptive_today_2026';
        await firestore.collection('users').doc(uid).set({
          'id': uid,
          'email': 'adaptive@lifeos.vn',
          'fullName': 'Nguyễn Thảo',
          'onboardingCompleted': true,
          'availabilityOptIn': false,
          'createdAt': DateTime(2026, 11, 20).toIso8601String(),
        });
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'adaptive@lifeos.vn',
            displayName: 'Nguyễn Thảo',
            isEmailVerified: true,
          ),
        );

        await configureDependencies(
          authOverride: auth,
          firestoreOverride: firestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
          financialClassifierOverride: FastTextClassifier(
            useWorkerIsolate: false,
          ),
        );

        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.12),
            ),
            child: LifeOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Circadian subtitle below greeting
        expect(find.textContaining('Xin chào, Thảo'), findsOneWidget);
        expect(
          find.text(UserBehaviorPrefs.contextualTimeSubtitle(DateTime.now())),
          findsOneWidget,
        );

        // 2. Hero card shows explicit solo personal scope pill and comfortable >=44dp privacy button
        expect(find.byKey(const Key('today_hero_scope_pill')), findsOneWidget);
        expect(find.text('Ví cá nhân · Riêng tư'), findsOneWidget);
        final privacyBtnRect = tester.getRect(
          find.byKey(const Key('toggle_balance_privacy_btn')),
        );
        expect(privacyBtnRect.width, greaterThanOrEqualTo(44.0));
        expect(privacyBtnRect.height, greaterThanOrEqualTo(44.0));

        // 3. Honest sync status inside hero details ('Lưu cục bộ an toàn', NEVER 'Đang đồng bộ')
        await tester.tap(find.byKey(const Key('today_hero_details_toggle')));
        await tester.pumpAndSettle();
        expect(find.text('Lưu cục bộ an toàn'), findsOneWidget);
        expect(find.text('Đang đồng bộ'), findsNothing);
        await tester.tap(find.byKey(const Key('today_hero_details_toggle')));
        await tester.pumpAndSettle();

        // 4. Scroll to FTUE First-Action Tip & Adaptive Contextual Recommendations
        final ftueTip = find.byKey(const Key('today_ftue_first_action_tip'));
        await tester.scrollUntilVisible(
          ftueTip,
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(ftueTip, findsOneWidget);
        expect(find.text('Bắt đầu trong 10 giây'), findsOneWidget);
        expect(
          find.byKey(const Key('today_contextual_recommendation_card')),
          findsOneWidget,
        );

        // Verify zero truncated paragraphs & zero exceptions at 360x800 @ 112%
        for (final element in find.byType(RichText).evaluate()) {
          final ro = element.renderObject;
          if (ro is RenderParagraph && ro.attached && ro.hasSize) {
            expect(
              ro.didExceedMaxLines,
              isFalse,
              reason: 'Truncated text: "${ro.text.toPlainText()}"',
            );
          }
        }
        expect(tester.takeException(), isNull);

        // 5. Dismiss FTUE tip -> hides immediately and persists
        final dismissFtueBtn = find.byKey(
          const Key('today_ftue_dismiss_tip_btn'),
        );
        await tester.ensureVisible(dismissFtueBtn);
        await tester.tap(dismissFtueBtn);
        await tester.pumpAndSettle();
        expect(ftueTip, findsNothing);
        expect(await UserBehaviorPrefs.loadFirstActionTipDismissed(), isTrue);

        // 5b. Dismiss first contextual recommendation card -> records dismissal count immediately
        final recCardFinder = find.byKey(
          const Key('today_contextual_recommendation_card'),
        );
        await tester.ensureVisible(recCardFinder);
        final recDismissBtn = find.descendant(
          of: recCardFinder,
          matching: find.text('Ẩn'),
        );
        expect(recDismissBtn, findsWidgets);
        await tester.ensureVisible(recDismissBtn.first);
        await tester.tap(recDismissBtn.first);
        await tester.pumpAndSettle();
        final afterDismissSettings = await LocalBehaviorStore.instance
            .loadSettings();
        expect(afterDismissSettings.dismissedCounts, isNotEmpty);

        // 6. Open Personalization Settings Sheet -> toggle switch off, pick interest, reset with confirmation & TopToast
        final settingsBtn = find.byKey(
          const Key('today_personalization_settings_btn'),
        );
        await tester.ensureVisible(settingsBtn);
        await tester.pumpAndSettle();
        await tester.tap(settingsBtn);
        await tester.pumpAndSettle();

        final enableSwitch = find.byKey(
          const Key('personalization_enable_switch'),
        );
        expect(enableSwitch, findsOneWidget);
        await tester.tap(enableSwitch);
        await tester.pumpAndSettle();
        expect(await UserBehaviorPrefs.loadPersonalizationEnabled(), isFalse);

        await tester.tap(
          find.byKey(const Key('personalization_interest_vehicle')),
        );
        await tester.pumpAndSettle();
        expect(await UserBehaviorPrefs.loadUserInterests(), {'vehicle'});

        final resetBtn = find.byKey(const Key('personalization_reset_btn'));
        await tester.ensureVisible(resetBtn);
        await tester.tap(resetBtn);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('personalization_reset_confirm_btn')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('personalization_reset_confirm_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Đặt lại dữ liệu hành vi?'), findsNothing);
        expect(
          find.byKey(const Key('personalization_reset_btn')),
          findsNothing,
        );
        expect(await UserBehaviorPrefs.loadUserInterests(), isEmpty);
        expect(await UserBehaviorPrefs.loadPersonalizationEnabled(), isTrue);
        expect(
          find.text('Đã đặt lại dữ liệu hành vi cho tài khoản này.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('lifeos_top_toast_banner')),
          findsOneWidget,
        );

        // Advance past Top Toast auto-dismiss timer so no pending timers remain
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
