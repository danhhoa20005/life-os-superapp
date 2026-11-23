import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/features/pro_utilities/data/repositories/pro_utilities_repository_impl.dart';
import 'package:life_os/features/pro_utilities/domain/entities/pro_utilities_entities.dart';
import 'package:life_os/features/pro_utilities/presentation/bloc/pro_utilities_bloc.dart';

void main() {
  group('Paid-Market Pro Engines (Pure Dart)', () {
    test(
      'SmartReceiptParserEngine extracts multi-line items, merchant, category & total VND',
      () {
        const raw =
            'GrabFood - Phở Thìn Bờ Hồ\n'
            '2x Phở tái lăn 130k\n'
            '2x Quẩy giòn 20.000\n'
            'Tổng thanh toán: 150.000đ';
        final res = SmartReceiptParserEngine.parse(raw);

        expect(res.merchant, 'GrabFood - Phở Thìn Bờ Hồ');
        expect(res.suggestedCategory, 'Ăn uống');
        expect(res.items.length, 2);
        expect(res.totalMinor, 150000);
      },
    );

    test(
      'LoanAmortizationEngine computes Declining Balance and Annuity EMI accurately',
      () {
        final declining = LoanAmortizationEngine.calculate(
          principalMinor: 120000000, // 120M VND
          annualRatePct: 12.0, // 1%/month
          termMonths: 12,
          decliningBalance: true,
        );
        // Month 1: 10M principal + 1.2M interest = 11.2M; Month 12: 10M + 0.1M = 10.1M
        expect(declining.firstMonthPaymentMinor, 11200000);
        expect(declining.lastMonthPaymentMinor, 10100000);
        expect(declining.totalInterestMinor, 7800000);

        final emi = LoanAmortizationEngine.calculate(
          principalMinor: 120000000,
          annualRatePct: 12.0,
          termMonths: 12,
          decliningBalance: false,
        );
        expect(emi.firstMonthPaymentMinor, emi.lastMonthPaymentMinor);
        expect(emi.totalPayableMinor, greaterThan(120000000));
      },
    );

    test(
      'FireWealthSimulatorEngine computes 25x FIRE target and exact 6-Jars VND sum',
      () {
        final sim = FireWealthSimulatorEngine.simulate(
          currentNetWorthMinor: 500000000,
          monthlyIncomeMinor: 30000000,
          monthlyExpenseMinor: 10000000,
          expectedAnnualReturnPct: 10.0,
        );

        // 10M/mo * 12 * 25 = 3,000,000,000 VND (3 Billion VND)
        expect(sim.fireNumberMinor, 3000000000);
        expect(sim.yearsToFire, greaterThan(0));

        final jarsSum = sim.sixJarsMonthlyAllocation.values.fold<int>(
          0,
          (s, v) => s + v,
        );
        expect(jarsSum, 30000000);
      },
    );
  });

  test(
    'ProUtilitiesBloc persists Subscriptions, Habits, Hydration & Gift Reciprocity in Firestore',
    () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final repo = ProUtilitiesRepositoryImpl(fakeFirestore);
      final bloc = ProUtilitiesBloc(repository: repo)
        ..add(const ProUtilitiesWatchStarted('u_pro'));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      bloc.add(
        SubscriptionOrWarrantyAdded(
          userId: 'u_pro',
          title: 'YouTube Premium',
          providerOrStore: 'Google',
          cycle: SubscriptionCycle.monthly,
          amountMinor: 79000,
          nextBillingOrExpiryDate: DateTime.now().add(const Duration(days: 2)),
        ),
      );
      bloc.add(
        const WellnessMetricsIncremented(
          userId: 'u_pro',
          addWaterMl: 500,
          addFocusMinutes: 25,
          addPomodoros: 1,
        ),
      );
      bloc.add(
        const GiftLedgerEntrySubmitted(
          userId: 'u_pro',
          contactName: 'Trần Minh Tuấn',
          relationshipGroup: 'Đồng nghiệp',
          direction: GiftDirection.received,
          occasion: GiftOccasion.wedding,
          amountMinor: 1000000,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(bloc.state.totalMonthlySubBurnMinor, 79000);
      expect(bloc.state.totalAnnualSubBurnMinor, 79000 * 12);
      expect(bloc.state.todayWellness.waterMl, 500);
      expect(bloc.state.todayWellness.completedPomodoros, 1);
      expect(bloc.state.totalGiftReceivedMinor, 1000000);

      await bloc.close();
    },
  );

  testWidgets(
    'ProUtilitiesHubPage & 4 Paid-Market Suites render cleanly in LifeOsApp',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUser = MockUser(
        isAnonymous: false,
        uid: 'uid_pro_ui',
        email: 'pro@lifeos.vn',
        displayName: 'Minh Pro',
        isEmailVerified: true,
      );
      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
      final fakeFirestore = FakeFirebaseFirestore();
      await fakeFirestore.collection('users').doc('uid_pro_ui').set({
        'id': 'uid_pro_ui',
        'email': 'pro@lifeos.vn',
        'fullName': 'Minh Pro',
        'onboardingCompleted': true,
        'availabilityOptIn': false,
        'createdAt': DateTime.now().toIso8601String(),
      });

      await configureDependencies(
        authOverride: mockAuth,
        firestoreOverride: fakeFirestore,
        httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
      );

      await tester.pumpWidget(const LifeOsApp());
      await tester.pumpAndSettle();

      // Scroll Home down & tap "Tiện ích Pro 0₫" card
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_pro_utilities_hub_card')));
      await tester.pumpAndSettle();

      expect(find.text('Tiện ích Pro Tích hợp'), findsOneWidget);
      expect(find.text('Radar Gói Đăng ký & Phiếu Bảo hành'), findsOneWidget);

      // Open Receipt AI & Wealth Tools Page
      await tester.tap(find.text('Quét Bill AI, Tính Lãi Vay & Tự do FIRE'));
      await tester.pumpAndSettle();
      expect(find.text('Công cụ Tài chính Pro'), findsOneWidget);
      expect(find.textContaining('280.000 ₫'), findsWidgets);
    },
  );
}
