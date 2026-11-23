import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/features/daily_life/data/repositories/daily_life_repository_impl.dart';
import 'package:life_os/features/daily_life/domain/entities/daily_life_entities.dart';
import 'package:life_os/features/daily_life/presentation/bloc/daily_life_bloc.dart';

void main() {
  group(
    '360° Daily Life Engines (EVN 5-Tier QĐ 2892/2026, PIT 5-Bracket Luật 109/2025, Asian BMI/TDEE)',
    () {
      test(
        'VietnamEvnUtilityEngine calculates 2026 5-tier EVN (QĐ 2892/QĐ-BCT) & legacy 6-tier accurately',
        () {
          // 1. Default 2026 5-tier (0-100@1901, 101-200@2289, 201-400@2894) for 250 kWh:
          // 100*1901 (190100) + 100*2289 (228900) + 50*2894 (144700) = 563700; 8% VAT = 45096 => 608796
          final bill2026 = VietnamEvnUtilityEngine.calculate(
            prevElectricKwh: 1000,
            currElectricKwh: 1250,
            prevWaterM3: 40,
            currWaterM3: 50,
            useEvnTieredTariff: true,
            waterVndPerM3: 15000,
            internetAndManagementMinor: 200000,
            splitMemberCount: 2,
          );
          expect(bill2026.kwhConsumed, 250);
          expect(bill2026.evnTiers.length, 3);
          expect(bill2026.electricityPreVatMinor, 563700);
          expect(bill2026.electricityVatMinor, 45096);
          expect(bill2026.electricityTotalMinor, 608796);
          expect(bill2026.grandTotalMinor, 958796);
          expect(bill2026.perPersonShareMinor, 479398);

          // 2. Legacy 6-tier comparison mode
          final billLegacy = VietnamEvnUtilityEngine.calculate(
            prevElectricKwh: 1000,
            currElectricKwh: 1250,
            prevWaterM3: 40,
            currWaterM3: 50,
            useEvnTieredTariff: true,
            policy: EvnTariffPolicy.legacy6TierPreNov2026,
            waterVndPerM3: 15000,
            internetAndManagementMinor: 200000,
            splitMemberCount: 2,
          );
          expect(billLegacy.evnTiers.length, 4);
          expect(billLegacy.electricityPreVatMinor, 562550);
        },
      );

      test(
        'VietnamGrossNetTaxEngine computes 2026 5-bracket PIT (15.5M/6.2M) & round-trip Net->Gross',
        () {
          final gross35M = VietnamGrossNetTaxEngine.fromGross(
            grossMinor: 35000000,
            dependentsCount: 1,
          );
          // Insurance: 8% (2.8M) + 1.5% (525k) + 1% (350k) = 3.675.000
          expect(gross35M.totalEmployeeInsuranceMinor, 3675000);
          // Taxable (2026): 35M - 3.675M - 15.5M - 6.2M = 9.625.000 (Bracket 1 <=10M @ 5% => 481.250)
          expect(gross35M.taxableIncomeMinor, 9625000);
          expect(gross35M.personalIncomeTaxMinor, 481250);
          expect(gross35M.netSalaryMinor, 30843750);

          // Reverse Net -> Gross (2026 policy)
          final reversed = VietnamGrossNetTaxEngine.fromNet(
            targetNetMinor: 30843750,
            dependentsCount: 1,
          );
          expect((reversed.grossSalaryMinor - 35000000).abs() <= 5, isTrue);
        },
      );

      test(
        'AsianHealthBmiTdeeEngine applies Asian-Pacific WHO cutoffs (18.5–22.9)',
        () {
          final normal = AsianHealthBmiTdeeEngine.evaluate(
            weightKg: 62,
            heightCm: 170,
            systolicMmHg: 116,
            diastolicMmHg: 74,
          );
          expect(normal.bmi, 21.5);
          expect(normal.bmiCategory, contains('Chuẩn Châu Á'));
          expect(normal.bloodPressureStatus, contains('tối ưu'));
          expect(normal.tdeeKcal, greaterThan(1800));
        },
      );
    },
  );

  test(
    'DailyLifeBloc persists Medications, Meal Combo Groceries, EVN Readings & Notes in Firestore',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repo = DailyLifeRepositoryImpl(firestore);
      final bloc = DailyLifeBloc(repo);
      const uid = 'uid_daily_life_spec';

      bloc.add(const DailyLifeWatchStarted(uid));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      bloc.add(
        MedicationCabinetAdded(
          userId: uid,
          name: 'Vitamin D3 K2',
          dosage: '1 viên sáng',
          slot: MedicationScheduleSlot.morning,
          remainingPills: 30,
          expiryDate: DateTime(2027, 6, 1),
        ),
      );
      bloc.add(
        MealComboAppliedToGroceries(
          userId: uid,
          combo: VietnameseMealSuggestionCatalog.presets.first,
        ),
      );
      bloc.add(
        const UtilityReadingSaved(
          userId: uid,
          monthKey: '2026-11',
          prevElectricKwh: 1200,
          currElectricKwh: 1420,
          prevWaterM3: 50,
          currWaterM3: 60,
          useEvnTieredTariff: true,
          fixedServicesMinor: 220000,
          totalAmountMinor: 880000,
        ),
      );
      bloc.add(
        const SmartNoteSaved(
          userId: uid,
          title: 'Mật khẩu Wi-Fi phòng khách',
          content: 'LifeOS_5G / 88889999',
          categoryTag: 'Mã số & Wi-Fi',
          isPinned: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      final snap = bloc.state.snapshot;
      expect(snap.medications.length, 1);
      expect(snap.medications.first.name, 'Vitamin D3 K2');
      expect(
        snap.groceryItems.length,
        VietnameseMealSuggestionCatalog.presets.first.ingredients.length,
      );
      expect(snap.mealPlans.length, 1);
      expect(snap.utilityReadings.length, 1);
      expect(snap.notes.length, 1);
      expect(snap.notes.first.isPinned, isTrue);

      await bloc.close();
    },
  );

  testWidgets('All 5 Daily Life 360° Super App Pages render and navigate cleanly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final mockUser = MockUser(
      isAnonymous: false,
      uid: 'uid_superapp_360',
      email: 'minh@lifeos.vn',
      displayName: 'Trần Minh',
      isEmailVerified: true,
    );
    final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();
    await fakeFirestore.collection('users').doc('uid_superapp_360').set({
      'id': 'uid_superapp_360',
      'email': 'minh@lifeos.vn',
      'fullName': 'Trần Minh',
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

    // 0. Open Live Appearance & Font Size Studio Sheet right from Top Brand Header!
    await tester.tap(find.byKey(const Key('open_appearance_studio_button')));
    await tester.pumpAndSettle();
    expect(find.text('Giao diện Sáng/Tối & Cỡ chữ'), findsOneWidget);
    expect(find.text('Nhỏ gọn (85%)'), findsOneWidget);
    await tester.tap(find.text('Nhỏ gọn (85%)'));
    await tester.pumpAndSettle();
    expect(find.text('85%'), findsOneWidget);
    // Dismiss appearance sheet
    Navigator.of(
      tester.element(find.text('Giao diện Sáng/Tối & Cỡ chữ')),
    ).pop();
    await tester.pumpAndSettle();

    // Scroll slightly on compact TodayPage to view 4x2 Dock & Ecosystem Strip
    await tester.drag(find.byType(ListView).first, const Offset(0, -280));
    await tester.pumpAndSettle();

    expect(find.text('Tiện ích của bạn'), findsOneWidget);

    // 1. Open Health & Medication Hub from 4x2 Dock
    await tester.tap(find.byKey(const Key('home_tile_health')));
    await tester.pumpAndSettle();
    expect(find.text('Sức khỏe & Tủ thuốc'), findsOneWidget);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();

    // 2. Open Kitchen & Smart Groceries from 4x2 Dock
    await tester.tap(find.byKey(const Key('home_tile_kitchen')));
    await tester.pumpAndSettle();
    expect(find.text('Bếp & Đi chợ Thông minh'), findsOneWidget);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();

    // 3. Open Home Living & EVN 6-Tier Utilities from 4x2 Dock
    await tester.tap(find.byKey(const Key('home_tile_evn')));
    await tester.pumpAndSettle();
    expect(find.text('Điện nước EVN & Nhà cửa'), findsOneWidget);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();

    // 4. Open 4-Column Super App 360° Directory -> launch Smart Notes & Gross-Net Salary
    await tester.tap(find.byKey(const Key('home_tile_all_services')));
    await tester.pumpAndSettle();
    expect(find.text('Tất cả Dịch vụ 360°'), findsOneWidget);
    await tester.tap(find.text('Lương Gross–Net'));
    await tester.pumpAndSettle();
    expect(find.text('Ghi chú & Lương Gross–Net'), findsOneWidget);
  });
}
