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
  group('360° Daily Life Engines (EVN 6-Tier, Gross-Net 7-Bracket PIT, Asian BMI/TDEE)', () {
    test('VietnamEvnUtilityEngine calculates 6-tier EVN residential bill + 8% VAT & split accurately', () {
      final bill = VietnamEvnUtilityEngine.calculate(
        prevElectricKwh: 1000,
        currElectricKwh: 1250, // 250 kWh: 50@T1 + 50@T2 + 100@T3 + 50@T4
        prevWaterM3: 40,
        currWaterM3: 50, // 10 m3 * 15.000 = 150.000
        useEvnTieredTariff: true,
        waterVndPerM3: 15000,
        internetAndManagementMinor: 200000,
        splitMemberCount: 2,
      );

      expect(bill.kwhConsumed, 250);
      expect(bill.evnTiers.length, 4);
      // 50*1893 (94650) + 50*1956 (97800) + 100*2271 (227100) + 50*2860 (143000) = 562550
      expect(bill.electricityPreVatMinor, 562550);
      expect(bill.electricityVatMinor, 45004); // 8% VAT
      expect(bill.electricityTotalMinor, 607554);
      expect(bill.waterTotalMinor, 150000);
      expect(bill.grandTotalMinor, 957554);
      expect(bill.perPersonShareMinor, 478777);
    });

    test('VietnamGrossNetTaxEngine computes BHXH/BHYT/BHTN, 7 PIT brackets & round-trip Net->Gross', () {
      final gross30M = VietnamGrossNetTaxEngine.fromGross(
        grossMinor: 30000000,
        dependentsCount: 1,
      );
      // Insurance: 8% (2.4M) + 1.5% (450k) + 1% (300k) = 3.150.000
      expect(gross30M.totalEmployeeInsuranceMinor, 3150000);
      // Taxable: 30M - 3.15M - 11M - 4.4M = 11.450.000 (Bracket 1: 5M@5%=250k, Bracket 2: 5M@10%=500k, Bracket 3: 1.45M@15%=217.5k => 967.500)
      expect(gross30M.taxableIncomeMinor, 11450000);
      expect(gross30M.personalIncomeTaxMinor, 967500);
      expect(gross30M.netSalaryMinor, 25882500);

      // Reverse Net -> Gross
      final reversed = VietnamGrossNetTaxEngine.fromNet(
        targetNetMinor: 25882500,
        dependentsCount: 1,
      );
      expect((reversed.grossSalaryMinor - 30000000).abs() <= 5, isTrue);
    });

    test('AsianHealthBmiTdeeEngine applies Asian-Pacific WHO cutoffs (18.5–22.9)', () {
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
    });
  });

  test('DailyLifeBloc persists Medications, Meal Combo Groceries, EVN Readings & Notes in Firestore', () async {
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
    expect(snap.groceryItems.length,
        VietnameseMealSuggestionCatalog.presets.first.ingredients.length);
    expect(snap.mealPlans.length, 1);
    expect(snap.utilityReadings.length, 1);
    expect(snap.notes.length, 1);
    expect(snap.notes.first.isPinned, isTrue);

    await bloc.close();
  });

  testWidgets('All 5 Daily Life 360° Super App Pages render and navigate cleanly', (tester) async {
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
    Navigator.of(tester.element(find.text('Giao diện Sáng/Tối & Cỡ chữ'))).pop();
    await tester.pumpAndSettle();

    // Scroll slightly on compact TodayPage to view 4x2 Dock & Ecosystem Strip
    await tester.drag(find.byType(ListView).first, const Offset(0, -280));
    await tester.pumpAndSettle();

    expect(find.text('Tiện ích thường dùng'), findsOneWidget);

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
