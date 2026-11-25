import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/behavior/behavior_domain.dart';
import 'package:life_os/core/behavior/behavior_engine.dart';
import 'package:life_os/core/behavior/local_behavior_store.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';

void main() {
  group('Behavior Engine 2.0 — Pure Dart & Architecture Guards', () {
    test(
      'behavior_domain.dart & behavior_engine.dart are 100% pure Dart with zero Flutter/Firebase imports',
      () {
        final forbiddenImport = RegExp(
          r'''import\s+['"]package:(flutter|flutter_bloc|bloc|cloud_firestore|cloud_functions|firebase_auth|firebase_core|firebase_messaging|google_sign_in|go_router)/''',
        );

        for (final path in const [
          'lib/core/behavior/behavior_domain.dart',
          'lib/core/behavior/behavior_engine.dart',
        ]) {
          final content = File(path).readAsStringSync();
          expect(
            forbiddenImport.hasMatch(content),
            isFalse,
            reason: '$path must remain 100% pure Dart!',
          );
          expect(content.contains('TextOverflow'), isFalse);
          expect(content.contains('Cubit'), isFalse);
        }
      },
    );
  });

  group('BehaviorPrivacyPolicy — Strict Allowlist & PII Scrubbing', () {
    test(
      'keeps only 7 allowlisted keys and rejects raw financial/PII/transcript content',
      () {
        final sanitized = BehaviorPrivacyPolicy.sanitizeMetadata(
          <String, Object?>{
            'targetId': 'planning_schedule',
            'featureKey': 'quick_create',
            'hourOfDay': 29, // clamped to 23
            'weekday': 9, // clamped to 7
            'screenKey': 'today',
            'durationMs': -50, // clamped to 0
            'stepCount': 3,
            // Forbidden keys:
            'note': 'Mật khẩu wifi nhà là 123456',
            'voiceTranscript': 'Ăn phở bò 55k ở quán quen',
            'amountMinor': 55000,
            'phone': '0912345678',
            'email': 'minh@lifeos.vn',
            'accountNumber': '19036888999012',
            'merchant': 'Phở Thìn',
          },
        );

        expect(
          sanitized.keys.toSet(),
          BehaviorPrivacyPolicy.allowedMetadataKeys,
        );
        expect(sanitized['targetId'], 'planning_schedule');
        expect(sanitized['hourOfDay'], 23);
        expect(sanitized['weekday'], 7);
        expect(sanitized['durationMs'], 0);
        expect(sanitized['stepCount'], 3);
        expect(sanitized.containsKey('note'), isFalse);
        expect(sanitized.containsKey('voiceTranscript'), isFalse);
        expect(sanitized.containsKey('amountMinor'), isFalse);
        expect(sanitized.containsKey('phone'), isFalse);
        expect(sanitized.containsKey('email'), isFalse);
        expect(sanitized.containsKey('accountNumber'), isFalse);
        expect(BehaviorPrivacyPolicy.externalUploadAllowed, isFalse);
      },
    );

    test(
      'rejects PII or VND monetary amounts even when passed inside allowlisted keys',
      () {
        final sanitized =
            BehaviorPrivacyPolicy.sanitizeMetadata(<String, Object?>{
              'targetId': 'hoa@lifeos.vn',
              'featureKey': '0912345678',
              'screenKey': 'Cà phê 35k',
            });
        expect(sanitized, isEmpty);

        final bankDigits = BehaviorPrivacyPolicy.sanitizeMetadata(
          <String, Object?>{'targetId': '19036888999012'},
        );
        expect(bankDigits, isEmpty);
      },
    );
  });

  group('RecencyFrequencyEngine — Circular Clock & Canonical Habit IDs', () {
    test(
      'fixes midnight wraparound bug: circular mean of 23 and 1 is 0 (not 12)',
      () {
        expect(RecencyFrequencyEngine.circularMeanHourInt([23, 1]), 0);
        expect(RecencyFrequencyEngine.circularMeanHourInt([22, 0]), 23);
        expect(RecencyFrequencyEngine.circularHourDistance(23, 1), 2);
        expect(RecencyFrequencyEngine.circularHourDistance(1, 23), 2);
        expect(RecencyFrequencyEngine.circularHourDistance(23, 0), 1);
      },
    );

    test(
      'canonicalizeHabitId merges amount variants cleanly while preserving hours',
      () {
        expect(
          RecencyFrequencyEngine.canonicalizeHabitId('Cà phê 35k'),
          'cà_phê',
        );
        expect(
          RecencyFrequencyEngine.canonicalizeHabitId('Cà phê 45k'),
          'cà_phê',
        );
        expect(
          RecencyFrequencyEngine.canonicalizeHabitId('Cà phê 45.000 ₫'),
          'cà_phê',
        );
        expect(
          RecencyFrequencyEngine.canonicalizeHabitId('Ăn trưa 1.2tr'),
          'ăn_trưa',
        );
        expect(
          RecencyFrequencyEngine.canonicalizeHabitId('Lịch họp 9h'),
          'lịch_họp_9h',
        );

        final t1 = DateTime(2026, 11, 24, 23, 15);
        final t2 = DateTime(2026, 11, 25, 1, 10);
        var habits = RecencyFrequencyEngine.upsertHabitShortcut(
          existing: const <HabitShortcut>[],
          label: 'Cà phê 35k',
          commandText: 'Cà phê 35k',
          categoryName: 'Ăn uống',
          amountMinor: 35000,
          now: t1,
        );
        habits = RecencyFrequencyEngine.upsertHabitShortcut(
          existing: habits,
          label: 'Cà phê 45k',
          commandText: 'Cà phê 45k',
          categoryName: 'Ăn uống',
          amountMinor: 45000,
          now: t2,
        );

        expect(habits.length, 1);
        expect(habits.single.id, 'cà_phê');
        expect(habits.single.frequency, 2);
        expect(habits.single.typicalHour, 0);
      },
    );
  });

  group('ContextEngine & RecommendationEngine — Formula, Safety & Cold Start', () {
    test(
      'honors user-recorded typicalHours (night-shift schedule) without rigid daytime assumptions',
      () {
        const nightCandidate = RecommendationCandidate(
          id: 'night_habit',
          featureKey: 'night_log',
          titleVi: 'Ghi ca tối',
          subtitleVi: 'Thói quen ca đêm',
          reasonVi: 'Bạn thường thao tác khoảng 23h',
          targetRoute: '/planning',
          actionLabelVi: 'Mở lịch',
          interestGroup: UserInterestGroup.schedule,
          frequencyCount: 5,
          typicalHours: [23],
        );

        final atMidnight = BehaviorContextSignal(
          now: DateTime(2026, 11, 25, 0, 15),
        );
        final atMidday = BehaviorContextSignal(
          now: DateTime(2026, 11, 25, 11, 0),
        );

        final midnightMatch = ContextEngine.scoreContextMatch(
          nightCandidate,
          atMidnight,
        );
        final middayMatch = ContextEngine.scoreContextMatch(
          nightCandidate,
          atMidday,
        );

        expect(midnightMatch, greaterThanOrEqualTo(0.9));
        expect(middayMatch, lessThanOrEqualTo(0.15));
      },
    );

    test(
      'computes exact weighted sum formula and enforces autoExecuteAllowed == false on financial mutations',
      () {
        final now = DateTime(
          2026,
          11,
          25,
          9,
          0,
        ); // Day 25 -> isEndOfMonth = true
        final candidate = RecommendationCandidate(
          id: 'rec_budget',
          featureKey: 'finance_budget',
          titleVi: 'Kiểm tra ngân sách',
          subtitleVi: 'Rà soát chi tiêu cuối tháng',
          reasonVi: 'Gần cuối tháng',
          targetRoute: '/finance',
          actionLabelVi: 'Xem ngân sách',
          interestGroup: UserInterestGroup.spending,
          frequencyCount: 3,
          lastUsedEpochMs: now
              .subtract(const Duration(days: 7))
              .millisecondsSinceEpoch,
          typicalHours: const [9],
          urgencyScore: 0.8,
          habitConsistencyScore: 0.6,
          isFinancialMutation: true,
        );

        final settings = PersonalizationSettings(
          enabled: true,
          selectedInterests: const {UserInterestGroup.spending},
          dismissedCounts: const {'rec_budget': 1},
          lastDismissedEpochMs: {
            'rec_budget': now
                .subtract(const Duration(days: 7))
                .millisecondsSinceEpoch,
          },
          totalRecordedSignals: 10,
        );
        final signal = BehaviorContextSignal(now: now);

        final breakdown = RecommendationEngine.scoreCandidate(
          candidate: candidate,
          settings: settings,
          signal: signal,
          maxFrequency: 3,
        );

        final expectedFreq = math.log(4) / math.log(4); // 1.0
        final expectedRecency = 0.5; // 7 / 14 days
        final expectedContext = 1.0; // typicalHour == 9
        final expectedUrgency = 0.8;
        final expectedPref = 1.0; // spending matches
        final expectedConsistency = 0.6;
        final expectedDismissal = 1 * 0.22 * 0.5; // 0.11
        final expectedTotal =
            0.25 * expectedFreq +
            0.20 * expectedRecency +
            0.20 * expectedContext +
            0.15 * expectedUrgency +
            0.10 * expectedPref +
            0.10 * expectedConsistency -
            expectedDismissal;

        expect(breakdown.frequencyNorm, closeTo(expectedFreq, 1e-9));
        expect(breakdown.recencyNorm, closeTo(expectedRecency, 1e-9));
        expect(breakdown.contextMatchNorm, closeTo(expectedContext, 1e-9));
        expect(breakdown.urgencyNorm, closeTo(expectedUrgency, 1e-9));
        expect(breakdown.explicitPreferenceNorm, closeTo(expectedPref, 1e-9));
        expect(
          breakdown.habitConsistencyNorm,
          closeTo(expectedConsistency, 1e-9),
        );
        expect(breakdown.dismissalPenalty, closeTo(expectedDismissal, 1e-9));
        expect(breakdown.finalScore, closeTo(expectedTotal, 1e-9));
        expect(breakdown.autoExecuteAllowed, isFalse);
      },
    );

    test(
      'returns empty list when disabled and avoids fabricating financial habits in cold start',
      () {
        final now = DateTime(2026, 11, 25, 10, 0);
        final signal = BehaviorContextSignal(now: now);

        const fakeFinancialHabit = RecommendationCandidate(
          id: 'fake_coffee',
          featureKey: 'coffee',
          titleVi: 'Uống cà phê 35k',
          subtitleVi: 'Ghi chi tiêu',
          reasonVi: 'Thói quen',
          targetRoute: '/financial-ai',
          actionLabelVi: 'Ghi nhanh',
          interestGroup: UserInterestGroup.spending,
          frequencyCount: 4,
          isFinancialMutation: true,
        );
        const calmScheduleStarter = RecommendationCandidate(
          id: 'starter_sched',
          featureKey: 'planning',
          titleVi: 'Xem lịch hôm nay',
          subtitleVi: 'Bắt đầu ngày mới gọn gàng',
          reasonVi: 'Gợi ý khởi đầu',
          targetRoute: '/planning',
          actionLabelVi: 'Mở lịch',
          interestGroup: UserInterestGroup.schedule,
          isFinancialMutation: false,
          isStarterSuggestion: true,
        );

        // Disabled -> always empty
        expect(
          RecommendationEngine.recommend(
            candidates: [fakeFinancialHabit, calmScheduleStarter],
            settings: const PersonalizationSettings(
              enabled: false,
              totalRecordedSignals: 10,
            ),
            signal: signal,
          ),
          isEmpty,
        );

        // Cold start with schedule interest -> excludes financial mutation & non-matching groups
        final coldRecs = RecommendationEngine.recommend(
          candidates: [fakeFinancialHabit, calmScheduleStarter],
          settings: const PersonalizationSettings(
            enabled: true,
            selectedInterests: {UserInterestGroup.schedule},
            totalRecordedSignals: 1,
            coldStartMinSignals: 3,
          ),
          signal: signal,
        );

        expect(coldRecs.length, 1);
        expect(coldRecs.single.candidate.id, 'starter_sched');
        expect(coldRecs.single.autoExecuteAllowed, isTrue);
      },
    );

    test('pinned shortcuts always outrank inferred high-frequency items', () {
      final now = DateTime(2026, 11, 25, 10, 0);
      final signal = BehaviorContextSignal(now: now);
      const pinned = RecommendationCandidate(
        id: 'pin_evn',
        featureKey: 'evn',
        titleVi: 'Điện nước',
        subtitleVi: 'Đã ghim',
        reasonVi: 'Tiện ích đã ghim',
        targetRoute: '/home-living',
        actionLabelVi: 'Mở',
        interestGroup: UserInterestGroup.home,
        isPinnedByUser: true,
        frequencyCount: 0,
      );
      final inferred = RecommendationCandidate(
        id: 'inferred_food',
        featureKey: 'food',
        titleVi: 'Ăn uống',
        subtitleVi: 'Thường xuyên',
        reasonVi: 'Dùng nhiều',
        targetRoute: '/finance',
        actionLabelVi: 'Mở',
        interestGroup: UserInterestGroup.spending,
        isPinnedByUser: false,
        frequencyCount: 50,
        lastUsedEpochMs: now.millisecondsSinceEpoch,
        urgencyScore: 1.0,
        habitConsistencyScore: 1.0,
      );

      final ranked = RecommendationEngine.sortPinnedShortcuts(
        candidates: [inferred, pinned],
        settings: const PersonalizationSettings(
          selectedInterests: {UserInterestGroup.spending},
          totalRecordedSignals: 20,
        ),
        signal: signal,
      );

      expect(ranked.first.candidate.id, 'pin_evn');
    });
  });

  group(
    'LocalBehaviorStore, BehaviorEventCollector, FeedbackEngine & UxMetricsTracker',
    () {
      late NativeSecureVaultBridge vault;
      late LocalBehaviorStore store;
      late BehaviorEventCollector collector;
      late FeedbackEngine feedback;
      late UxMetricsTracker metrics;

      setUp(() async {
        vault = NativeSecureVaultBridge.testable();
        store = LocalBehaviorStore(vault: vault);
        collector = BehaviorEventCollector(store: store);
        feedback = FeedbackEngine(
          store: store,
          collector: collector,
          metricsTracker: UxMetricsTracker(store: store),
        );
        metrics = UxMetricsTracker(store: store);
        await store.resetForTest();
      });

      test(
        'strictly partitions data by userId and clears cache on sign-out',
        () async {
          store.bindActiveUser('u_alice');
          await collector.recordType(
            BehaviorEventType.featureOpened,
            metadata: const {'featureKey': 'finance', 'hourOfDay': 9},
          );
          await metrics.recordTaskSuccess();
          await feedback.recordRecommendationDismissed('rec_1');

          // Switch to Bob -> zero leakage from Alice
          store.bindActiveUser('u_bob');
          expect((await store.loadEvents()), isEmpty);
          expect((await store.loadMetrics()), UxMetricsSnapshot.empty);
          expect((await store.loadSettings()).dismissedCounts, isEmpty);

          // Verify underlying vault keys carry __u_<uid> partition
          expect(
            await vault.readSecret('ux_behavior_events_v2__u_u_alice'),
            isNotNull,
          );
          expect(
            await vault.readSecret('ux_behavior_events_v2__u_u_bob'),
            isNull,
          );

          // Sign-out clears in-memory session
          store.clearSessionOnSignOut();
          expect(store.activeUserId, isNull);
        },
      );

      test(
        'enforces consent/enabled gates and 200-event bounded rolling window',
        () async {
          store.bindActiveUser('u_window');
          await store.saveSettings(
            const PersonalizationSettings(enabled: true, consentGranted: false),
          );
          final denied = await collector.recordType(
            BehaviorEventType.featureOpened,
            metadata: const {'featureKey': 'planning'},
          );
          expect(denied, isFalse);
          expect(await store.loadEvents(), isEmpty);

          await store.saveSettings(
            const PersonalizationSettings(enabled: true, consentGranted: true),
          );
          for (var i = 0; i < 215; i++) {
            await collector.recordType(
              BehaviorEventType.searchPerformed,
              metadata: <String, Object?>{'stepCount': i},
            );
          }

          final events = await store.loadEvents();
          expect(events.length, LocalBehaviorStore.maxRollingEvents);
          expect(events.first.metadata['stepCount'], 15);
          expect(events.last.metadata['stepCount'], 214);
        },
      );

      test(
        'FeedbackEngine drops dismissed candidate score immediately and UxMetricsTracker counts & resets',
        () async {
          store.bindActiveUser('u_feedback');
          final now = DateTime(2026, 11, 25, 10, 0);
          final signal = BehaviorContextSignal(now: now);
          const recA = RecommendationCandidate(
            id: 'rec_a',
            featureKey: 'a',
            titleVi: 'Việc A',
            subtitleVi: 'Chi tiết A',
            reasonVi: 'Lý do A',
            targetRoute: '/tasks-board',
            actionLabelVi: 'Mở A',
            interestGroup: UserInterestGroup.schedule,
            urgencyScore: 0.7,
          );
          const recB = RecommendationCandidate(
            id: 'rec_b',
            featureKey: 'b',
            titleVi: 'Việc B',
            subtitleVi: 'Chi tiết B',
            reasonVi: 'Lý do B',
            targetRoute: '/planning',
            actionLabelVi: 'Mở B',
            interestGroup: UserInterestGroup.schedule,
            urgencyScore: 0.65,
          );

          // Before dismissal: recA ranks #1
          await store.saveSettings(
            const PersonalizationSettings(totalRecordedSignals: 5),
          );
          var ranked = RecommendationEngine.recommend(
            candidates: [recA, recB],
            settings: await store.loadSettings(),
            signal: signal,
          );
          expect(ranked.first.candidate.id, 'rec_a');

          // Dismiss recA -> recB immediately jumps to #1
          final afterDismiss = await feedback.recordRecommendationDismissed(
            'rec_a',
            now: now,
          );
          ranked = RecommendationEngine.recommend(
            candidates: [recA, recB],
            settings: afterDismiss,
            signal: signal,
          );
          expect(ranked.first.candidate.id, 'rec_b');

          // Metrics counters & reset
          await metrics.recordTaskSuccess();
          await metrics.recordTaskFailure();
          await metrics.recordUndo();
          await metrics.recordFormAbandon();
          await metrics.recordValidationError();
          await metrics.recordSearch(zeroResults: true);
          final snap = await metrics.load();
          expect(snap.schemaVersion, UxMetricsSnapshot.currentSchemaVersion);
          expect(snap.taskSuccessCount, 1);
          expect(snap.taskFailureCount, 1);
          expect(snap.undoCount, 1);
          expect(snap.formAbandonCount, 1);
          expect(snap.validationErrorCount, 1);
          expect(snap.searchCount, 1);
          expect(snap.zeroResultSearchCount, 1);
          expect(snap.recommendationDismissedCount, 1);

          await metrics.resetAll();
          expect(await metrics.load(), UxMetricsSnapshot.empty);
        },
      );
    },
  );
}
