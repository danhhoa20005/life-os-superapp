import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/drafts/local_draft_store.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/services/native_permissions_service.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/core/utils/user_behavior_prefs.dart';
import 'package:life_os/features/budgets/domain/entities/budget_entities.dart';
import 'package:life_os/features/budgets/domain/repositories/budget_repository.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/calendar/domain/repositories/calendar_repository.dart';
import 'package:life_os/features/daily_life/presentation/bloc/daily_life_bloc.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/family/domain/repositories/family_repository.dart';
import 'package:life_os/features/family/presentation/bloc/family_bloc.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/tasks/domain/entities/task_entities.dart';
import 'package:life_os/features/tasks/domain/repositories/task_repository.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_bloc.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_event.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';
import 'package:life_os/features/vehicles/domain/repositories/vehicle_repository.dart';

class _NoOpCalendarDriver implements DeviceCalendarDriver {
  const _NoOpCalendarDriver();

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

class _SilentPermsDriver implements PermissionsDriver {
  const _SilentPermsDriver();

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<AppPermissionsSnapshot> checkAll() async =>
      AppPermissionsSnapshot.allMissing;

  @override
  Future<AppPermissionsSnapshot> requestEssential() => checkAll();

  @override
  Future<AppPermissionsSnapshot> requestSingle(LifeOsPermissionKind kind) =>
      checkAll();

  @override
  Future<void> openAppSettings() async {}
}

class _SeededHarness {
  final FakeFirebaseFirestore firestore;
  final String uid;
  final String familyId;

  const _SeededHarness({
    required this.firestore,
    required this.uid,
    required this.familyId,
  });
}

Future<_SeededHarness> _bootRichLifeOs(
  WidgetTester tester, {
  required String uid,
  required String fullName,
  Size viewport = const Size(412, 915),
  double textScale = 1.0,
  ThemeMode themeMode = ThemeMode.light,
  bool highContrast = false,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  NativeDeviceCalendarBridge.setDriverOverride(const _NoOpCalendarDriver());
  NativePermissionsService.setDriverOverride(const _SilentPermsDriver());
  await UserBehaviorPrefs.resetForTest();
  LocalDraftStore.clearAllInMemoryCaches();

  final firestore = FakeFirebaseFirestore();
  final now = DateTime.now();
  final mk = '${now.year}-${now.month.toString().padLeft(2, '0')}';

  await firestore.collection('users').doc(uid).set({
    'id': uid,
    'email': '$uid@lifeos.vn',
    'fullName': fullName,
    'phoneNumber': '0912345678',
    'onboardingCompleted': true,
    'availabilityOptIn': true,
  });
  await firestore.collection('users').doc('${uid}_m2').set({
    'id': '${uid}_m2',
    'email': 'lan.tran@lifeos.vn',
    'fullName': 'Trần Ngọc Lan',
    'onboardingCompleted': true,
    'availabilityOptIn': false,
  });

  // Wallets
  final walletCol = firestore
      .collection('users')
      .doc(uid)
      .collection('wallets');
  await walletCol.doc('w_vcb').set({
    'id': 'w_vcb',
    'ownerId': uid,
    'name': 'Vietcombank Lương',
    'type': 'bank',
    'balanceMinor': 24500000,
    'currencyCode': 'VND',
    'isEstimatedBalance': false,
  });
  await walletCol.doc('w_cash').set({
    'id': 'w_cash',
    'ownerId': uid,
    'name': 'Tiền mặt ví chính',
    'type': 'cash',
    'balanceMinor': 2150000,
    'currencyCode': 'VND',
    'isEstimatedBalance': false,
  });

  // Realistic multi-day + provisional transactions
  final txCol = firestore
      .collection('users')
      .doc(uid)
      .collection('transactions');
  await txCol.doc('tx_salary').set({
    'id': 'tx_salary',
    'ownerId': uid,
    'walletId': 'w_vcb',
    'walletName': 'Vietcombank Lương',
    'categoryName': 'Lương',
    'merchant': 'Công ty Công nghệ Việt',
    'kind': 'income',
    'direction': 'credit',
    'amountMinor': 28000000,
    'verification': 'userConfirmed',
    'sourceKind': 'manual',
    'occurredAt': Timestamp.fromDate(DateTime(now.year, now.month, 1, 9, 0)),
    'monthKey': mk,
  });
  final expenseMerchants = <(String, String, int, int)>[
    ('Ăn uống', 'Phở Bò Hà Nội', 65000, 0),
    ('Cà phê & Đồ uống', 'Highlands Coffee Quận 1', 59000, 0),
    ('Di chuyển & Xăng xe', 'Petrolimex Số 12', 110000, 1),
    ('Siêu thị & Chợ', 'Bách Hóa Xanh', 385000, 1),
    ('Hóa đơn điện nước', 'EVN Điện lực TP.HCM', 840000, 2),
    ('Sức khỏe & Thuốc', 'Nhà thuốc Pharmacity', 215000, 3),
    ('Mua sắm gia dụng', 'Lock&Lock Mall', 690000, 4),
    ('Ăn uống', 'Bún chả Hàng Mành', 120000, 5),
    ('Giải trí', 'CGV Cinema Vincom', 260000, 6),
  ];
  for (var i = 0; i < expenseMerchants.length; i++) {
    final item = expenseMerchants[i];
    final occurred = now.subtract(Duration(days: item.$4, hours: i % 5));
    final occurredMk =
        '${occurred.year}-${occurred.month.toString().padLeft(2, '0')}';
    await txCol.doc('tx_exp_$i').set({
      'id': 'tx_exp_$i',
      'ownerId': uid,
      'walletId': i.isEven ? 'w_vcb' : 'w_cash',
      'walletName': i.isEven ? 'Vietcombank Lương' : 'Tiền mặt ví chính',
      'categoryName': item.$1,
      'merchant': item.$2,
      'kind': 'expense',
      'direction': 'debit',
      'amountMinor': item.$3,
      'verification': 'userConfirmed',
      'sourceKind': 'manual',
      'occurredAt': Timestamp.fromDate(occurred),
      'monthKey': occurredMk,
    });
  }
  await txCol.doc('tx_prov_1').set({
    'id': 'tx_prov_1',
    'ownerId': uid,
    'walletId': 'w_vcb',
    'walletName': 'Vietcombank Lương',
    'categoryName': 'Ăn uống',
    'merchant': 'GrabFood Đơn tối',
    'kind': 'expense',
    'direction': 'debit',
    'amountMinor': 98000,
    'verification': 'provisional',
    'sourceKind': 'androidNotification',
    'occurredAt': Timestamp.fromDate(now),
    'monthKey': mk,
  });

  // Recurring bill
  await firestore
      .collection('users')
      .doc(uid)
      .collection('bills')
      .doc('bill_fpt')
      .set({
        'id': 'bill_fpt',
        'ownerId': uid,
        'title': 'Cước Internet FPT Fiber',
        'providerName': 'FPT Telecom',
        'estimatedAmountMinor': 280000,
        'nextDueDate': Timestamp.fromDate(now.add(const Duration(days: 2))),
      });

  final mockAuth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: uid,
      email: '$uid@lifeos.vn',
      displayName: fullName,
    ),
  );

  await sl.reset();
  await configureDependencies(
    authOverride: mockAuth,
    firestoreOverride: firestore,
    httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
    googleCalendarTokenOverride: ({required interactive}) async => null,
    financialClassifierOverride: FastTextClassifier(useWorkerIsolate: false),
  );

  // Seed Family, members, split bills, invites, shopping & funds
  final familyRepo = sl<FamilyRepository>();
  final famRes = await familyRepo.createFamily(
    userId: uid,
    userName: fullName,
    familyName: 'Gia đình Minh Thảo',
  );
  final familyId = (famRes as Success<FamilyEntity>).value.id;
  await firestore.collection('users').doc(uid).update({
    'activeFamilyId': familyId,
  });

  final inviteRes = await familyRepo.createInviteCode(
    userId: uid,
    familyId: familyId,
    familyName: 'Gia đình Minh Thảo',
    invitedByName: fullName,
    inviteeName: 'Trần Ngọc Lan',
  );
  if (inviteRes is Success<String>) {
    await familyRepo.joinFamilyByInvite(
      userId: '${uid}_m2',
      userName: 'Trần Ngọc Lan',
      inviteCode: inviteRes.value,
    );
  }
  await familyRepo.createInviteCode(
    userId: uid,
    familyId: familyId,
    familyName: 'Gia đình Minh Thảo',
    invitedByName: fullName,
    inviteeName: 'Phạm Minh Khôi',
    inviteeContact: '0909 888 999',
  );

  await familyRepo.createSharedBillSplit(
    familyId: familyId,
    title: 'Tiền điện nước tháng này',
    topic: SharedExpenseTopic.utilities,
    paidByUserId: uid,
    paidByName: fullName,
    totalAmountMinor: 1200000,
    splitMethod: SplitMethod.equal,
    sharesByUserId: {uid: 600000, '${uid}_m2': 600000},
    participantNames: {uid: fullName, '${uid}_m2': 'Trần Ngọc Lan'},
  );
  await familyRepo.createSharedBillSplit(
    familyId: familyId,
    title: 'Đi chợ cuối tuần Lotte',
    topic: SharedExpenseTopic.shopping,
    paidByUserId: '${uid}_m2',
    paidByName: 'Trần Ngọc Lan',
    totalAmountMinor: 420000,
    splitMethod: SplitMethod.equal,
    sharesByUserId: {uid: 210000, '${uid}_m2': 210000},
    participantNames: {uid: fullName, '${uid}_m2': 'Trần Ngọc Lan'},
  );
  await familyRepo.addShoppingItem(
    familyId: familyId,
    userName: fullName,
    title: 'Sữa tươi Vinamilk ít đường',
    quantityLabel: '2 lốc',
    estimatedPriceMinor: 78000,
  );
  await familyRepo.addShoppingItem(
    familyId: familyId,
    userName: 'Trần Ngọc Lan',
    title: 'Gạo ST25 túi 5kg',
    quantityLabel: '1 túi',
    estimatedPriceMinor: 195000,
  );

  final budgetRepo = sl<BudgetRepository>();
  await budgetRepo.upsertBudget(
    userId: uid,
    categoryId: 'cat_food',
    categoryName: 'Ăn uống',
    monthKey: mk,
    limitMinor: 4500000,
  );
  await budgetRepo.upsertBudget(
    userId: uid,
    categoryId: 'cat_move',
    categoryName: 'Di chuyển & Xăng xe',
    monthKey: mk,
    limitMinor: 1500000,
  );
  await budgetRepo.createFund(
    userId: uid,
    familyId: familyId,
    scope: FundScope.family,
    name: 'Quỹ sinh hoạt Gia đình',
    targetAmountMinor: 15000000,
  );
  await budgetRepo.createFund(
    userId: uid,
    scope: FundScope.personal,
    name: 'Quỹ dự phòng cá nhân',
    targetAmountMinor: 50000000,
  );

  await sl<CalendarRepository>().createEvent(
    userId: uid,
    userName: fullName,
    familyId: familyId,
    visibility: CalendarEventVisibility.sharedEvent,
    title: 'Họp tổng kết ngân sách tuần',
    startsAt: now.add(const Duration(hours: 2)),
    endsAt: now.add(const Duration(hours: 3)),
    publishBusySlot: true,
  );
  await sl<TaskRepository>().createTask(
    createdBy: uid,
    creatorName: fullName,
    familyId: familyId,
    assigneeId: '${uid}_m2',
    assigneeName: 'Trần Ngọc Lan',
    title: 'Kiểm tra đồng hồ nước tầng 1',
    dueAt: now.add(const Duration(days: 1)),
    priority: TaskPriorityLevel.high,
    recurrence: TaskRecurrence.none,
  );
  await sl<VehicleRepository>().createVehicle(
    userId: uid,
    familyId: familyId,
    isFamilyShared: true,
    name: 'Honda Air Blade 160',
    plateNumber: '59X3-686.86',
    currentOdometerKm: 8450,
    serviceIntervalKm: 2000,
    serviceIntervalDays: 120,
    category: VehicleCategory.scooter,
  );

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: viewport,
        textScaler: TextScaler.linear(textScale),
      ),
      child: const LifeOsApp(),
    ),
  );
  await tester.pumpAndSettle();

  final rootCtx = tester.element(find.byType(Scaffold).first);
  rootCtx.read<ThemeBloc>().add(ThemeModeChanged(themeMode));
  rootCtx.read<ThemeBloc>().add(HighContrastToggled(highContrast));
  await tester.pumpAndSettle();

  return _SeededHarness(firestore: firestore, uid: uid, familyId: familyId);
}

Future<void> _scrollToBottomAndScan(
  WidgetTester tester,
  Finder containerFinder,
  String label,
  List<String> issues,
) async {
  void scan(String phase) {
    for (var i = 0; i < 25; i++) {
      final ex = tester.takeException();
      if (ex == null) break;
      issues.add('[$label | $phase] Exception: $ex');
    }
    for (final element in find.byType(RichText).evaluate()) {
      final ro = element.renderObject;
      if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
      final plain = ro.text.toPlainText().trim();
      if (plain.isEmpty) continue;
      if (ro.didExceedMaxLines) {
        issues.add('[$label | $phase] Truncated: "$plain"');
      }
    }
  }

  scan('top');

  Finder scrollableCandidates;
  if (containerFinder.evaluate().isNotEmpty) {
    final desc = find.descendant(
      of: containerFinder.first,
      matching: find.byType(Scrollable),
    );
    scrollableCandidates = desc.evaluate().isNotEmpty ? desc : containerFinder;
  } else {
    scrollableCandidates = find.byType(Scrollable);
  }

  ScrollableState? verticalScrollable;
  for (final element in scrollableCandidates.evaluate()) {
    if (element is StatefulElement && element.state is ScrollableState) {
      final st = element.state as ScrollableState;
      if (st.axisDirection == AxisDirection.down) {
        verticalScrollable = st;
        break;
      }
    }
  }
  if (verticalScrollable == null) return;

  for (var step = 1; step <= 14; step++) {
    final pos = verticalScrollable.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) break;
    if (pos.pixels >= pos.maxScrollExtent - 2.0) break;
    final nextOffset = (pos.pixels + 420.0).clamp(0.0, pos.maxScrollExtent);
    pos.jumpTo(nextOffset);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    scan('scroll_$step');
    if (nextOffset >= pos.maxScrollExtent - 1.0 &&
        verticalScrollable.position.maxScrollExtent <= nextOffset + 1.0) {
      break;
    }
  }
  await tester.pumpAndSettle();
  scan('bottom_settled');
}

void main() {
  tearDown(() async {
    debugOnRebuildDirtyWidget = null;
    NativeDeviceCalendarBridge.setDriverOverride(null);
    NativePermissionsService.setDriverOverride(null);
    await UserBehaviorPrefs.resetForTest();
    LocalDraftStore.clearAllInMemoryCaches();
    await NativeSecureVaultBridge.instance.clearAllSecrets();
    await sl.reset();
  });

  group('UI Optimization Performance Benchmark', () {
    testWidgets(
      'Measure rebuild counts on unrelated BLoC state, first settle times, and BackdropFilter/CustomPaint counts',
      (tester) async {
        addTearDown(() {
          debugOnRebuildDirtyWidget = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final harness = await _bootRichLifeOs(
          tester,
          uid: 'u_bench',
          fullName: 'Nguyễn Minh Hoàng',
          viewport: const Size(412, 915),
          textScale: 1.0,
        );

        Future<(int ms, int frames)> measureSettle(
          Future<void> Function() trigger,
        ) async {
          final sw = Stopwatch()..start();
          await trigger();
          var frames = 0;
          await tester.pump();
          frames++;
          while (tester.binding.hasScheduledFrame && frames < 120) {
            await tester.pump(const Duration(milliseconds: 16));
            frames++;
          }
          sw.stop();
          return (sw.elapsedMilliseconds, frames);
        }

        Future<Map<String, int>> measureRebuilds(
          String tag,
          Future<void> Function() action, {
          Object? Function()? readState,
        }) async {
          final beforeState = readState?.call();
          final counts = <String, int>{};
          debugOnRebuildDirtyWidget = (element, builtOnce) {
            final name = element.widget.runtimeType.toString();
            counts[name] = (counts[name] ?? 0) + 1;
          };
          try {
            await action();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));
            await tester.pumpAndSettle();
          } finally {
            debugOnRebuildDirtyWidget = null;
          }
          if (readState != null) {
            final afterState = readState();
            expect(
              afterState,
              isNot(equals(beforeState)),
              reason: 'Benchmark probe "$tag" must mutate BLoC state.',
            );
          }
          return counts;
        }

        int visibleBlurCount() =>
            find.byType(BackdropFilter, skipOffstage: true).evaluate().length;
        int mountedBlurCount() =>
            find.byType(BackdropFilter, skipOffstage: false).evaluate().length;
        int visiblePaintCount() =>
            find.byType(CustomPaint, skipOffstage: true).evaluate().length;

        // 1. TodayPage measurements
        final todayBlurVis = visibleBlurCount();
        final todayBlurAll = mountedBlurCount();
        final todayPaintVis = visiblePaintCount();

        final todayCtx = tester.element(find.byType(Scaffold).first);
        final todayRebuildsWater = await measureRebuilds(
          'today_water',
          () async {
            todayCtx.read<DailyLifeBloc>().add(
              WaterIntakeLogged(userId: harness.uid, deltaMl: 250),
            );
          },
          readState: () => todayCtx.read<DailyLifeBloc>().state,
        );
        final todayRebuildsSearch = await measureRebuilds(
          'today_search',
          () async {
            todayCtx.read<TransactionListBloc>().add(
              const TransactionsSearchChanged('zzz_unrelated_probe'),
            );
          },
          readState: () => todayCtx.read<TransactionListBloc>().state,
        );
        todayCtx.read<TransactionListBloc>().add(
          const TransactionsSearchChanged(''),
        );
        await tester.pumpAndSettle();

        // 2. FinancePage measurements
        final financeSettle = await measureSettle(() async {
          GoRouter.of(
            tester.element(find.byType(Scaffold).first),
          ).go('/finance');
        });
        await tester.pumpAndSettle();
        final financeBlurVis = visibleBlurCount();
        final financeBlurAll = mountedBlurCount();
        final financePaintVis = visiblePaintCount();

        final finCtx = tester.element(find.byType(Scaffold).first);
        final financeRebuildsWater = await measureRebuilds(
          'finance_water',
          () async {
            finCtx.read<DailyLifeBloc>().add(
              WaterIntakeLogged(userId: harness.uid, deltaMl: 250),
            );
          },
          readState: () => finCtx.read<DailyLifeBloc>().state,
        );
        final financeRebuildsSearch = await measureRebuilds(
          'finance_search',
          () async {
            finCtx.read<TransactionListBloc>().add(
              const TransactionsSearchChanged('phở'),
            );
          },
          readState: () => finCtx.read<TransactionListBloc>().state,
        );
        finCtx.read<TransactionListBloc>().add(
          const TransactionsSearchChanged(''),
        );
        await tester.pumpAndSettle();

        // 3. FinanceReportPage measurements
        final reportSettle = await measureSettle(() async {
          GoRouter.of(
            tester.element(find.byType(Scaffold).first),
          ).push('/finance-report');
        });
        await tester.pumpAndSettle();
        final reportBlurVis = visibleBlurCount();
        final reportPaintVis = visiblePaintCount();
        final repCtx = tester.element(find.byType(Scaffold).first);
        final reportRebuildsWater = await measureRebuilds(
          'report_water',
          () async {
            repCtx.read<DailyLifeBloc>().add(
              WaterIntakeLogged(userId: harness.uid, deltaMl: 250),
            );
          },
          readState: () => repCtx.read<DailyLifeBloc>().state,
        );
        GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
        await tester.pumpAndSettle();

        // 4. FamilyPage measurements
        final familySettle = await measureSettle(() async {
          GoRouter.of(
            tester.element(find.byType(Scaffold).first),
          ).go('/family');
        });
        await tester.pumpAndSettle();
        final familyBlurVis = visibleBlurCount();
        final familyBlurAll = mountedBlurCount();
        final familyPaintVis = visiblePaintCount();

        final famCtx = tester.element(find.byType(Scaffold).first);
        final familyRebuildsWater = await measureRebuilds(
          'family_water',
          () async {
            famCtx.read<DailyLifeBloc>().add(
              WaterIntakeLogged(userId: harness.uid, deltaMl: 250),
            );
          },
          readState: () => famCtx.read<DailyLifeBloc>().state,
        );
        final familyRebuildsShoppingOnSplitTab = await measureRebuilds(
          'family_shopping',
          () async {
            famCtx.read<FamilyBloc>().add(
              ShoppingItemAdded(
                familyId: harness.familyId,
                userName: 'Nguyễn Minh Hoàng',
                title: 'Nước mắm Nam Ngư',
                quantityLabel: '1 chai',
                estimatedPriceMinor: 48000,
              ),
            );
          },
          readState: () => famCtx.read<FamilyBloc>().state,
        );

        // 5. Return Today settle
        final todaySettle = await measureSettle(() async {
          GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/today');
        });
        await tester.pumpAndSettle();

        int countFor(Map<String, int> m, String key) => m[key] ?? 0;

        debugPrint(
          '[UI-BENCH] SETTLE today=${todaySettle.$1}ms/${todaySettle.$2}f '
          'finance=${financeSettle.$1}ms/${financeSettle.$2}f '
          'report=${reportSettle.$1}ms/${reportSettle.$2}f '
          'family=${familySettle.$1}ms/${familySettle.$2}f',
        );
        debugPrint(
          '[UI-BENCH] BLUR(visible/mounted) '
          'today=$todayBlurVis/$todayBlurAll '
          'finance=$financeBlurVis/$financeBlurAll '
          'report=$reportBlurVis '
          'family=$familyBlurVis/$familyBlurAll | '
          'CustomPaint(visible): today=$todayPaintVis finance=$financePaintVis '
          'report=$reportPaintVis family=$familyPaintVis',
        );
        debugPrint(
          '[UI-BENCH] REBUILD Today(water): '
          'TodayPage=${countFor(todayRebuildsWater, 'TodayPage')} '
          'Header=${countFor(todayRebuildsWater, 'LifeOsTopBrandHeader')} '
          'Hero=${countFor(todayRebuildsWater, 'ProHeroGradientCard')} '
          'Schedule=${countFor(todayRebuildsWater, 'UpcomingScheduleCycleCard')} '
          'Grid=${countFor(todayRebuildsWater, 'LifeOsResponsiveIconGrid')} | '
          'totalEntries=${todayRebuildsWater.values.fold<int>(0, (a, b) => a + b)}',
        );
        debugPrint(
          '[UI-BENCH] REBUILD Today(txSearch): '
          'TodayPage=${countFor(todayRebuildsSearch, 'TodayPage')} '
          'Header=${countFor(todayRebuildsSearch, 'LifeOsTopBrandHeader')} '
          'Hero=${countFor(todayRebuildsSearch, 'ProHeroGradientCard')} '
          'Schedule=${countFor(todayRebuildsSearch, 'UpcomingScheduleCycleCard')} '
          'total=${todayRebuildsSearch.values.fold<int>(0, (a, b) => a + b)}',
        );
        debugPrint(
          '[UI-BENCH] REBUILD Finance(water): '
          'FinancePage=${countFor(financeRebuildsWater, 'FinancePage')} '
          'Header=${countFor(financeRebuildsWater, 'LifeOsTopBrandHeader')} '
          'TxTab=${countFor(financeRebuildsWater, '_TransactionsTabView')} '
          'total=${financeRebuildsWater.values.fold<int>(0, (a, b) => a + b)}',
        );
        debugPrint(
          '[UI-BENCH] REBUILD Finance(txSearch): '
          'FinancePage=${countFor(financeRebuildsSearch, 'FinancePage')} '
          'Header=${countFor(financeRebuildsSearch, 'LifeOsTopBrandHeader')} '
          'OverviewDeck=${countFor(financeRebuildsSearch, '_LifeOsSpendingOverviewDeck')} '
          'DailyChart=${countFor(financeRebuildsSearch, 'DailySpendingChartCard')} '
          'Donut=${countFor(financeRebuildsSearch, 'ProDonutChart')} '
          'total=${financeRebuildsSearch.values.fold<int>(0, (a, b) => a + b)}',
        );
        debugPrint(
          '[UI-BENCH] REBUILD Report(water): '
          'FinanceReportPage=${countFor(reportRebuildsWater, 'FinanceReportPage')} '
          'Insights=${countFor(reportRebuildsWater, 'LifeInsightsCrossDomainCard')} '
          'total=${reportRebuildsWater.values.fold<int>(0, (a, b) => a + b)}',
        );
        debugPrint(
          '[UI-BENCH] REBUILD Family(water): '
          'FamilyPage=${countFor(familyRebuildsWater, 'FamilyPage')} '
          'Header=${countFor(familyRebuildsWater, 'LifeOsTopBrandHeader')} '
          'SplitTab=${countFor(familyRebuildsWater, '_SplitBillsAndSettlementTabView')} '
          'total=${familyRebuildsWater.values.fold<int>(0, (a, b) => a + b)}',
        );
        debugPrint(
          '[UI-BENCH] REBUILD Family(shoppingAdded while on SplitTab): '
          'FamilyPage=${countFor(familyRebuildsShoppingOnSplitTab, 'FamilyPage')} '
          'Header=${countFor(familyRebuildsShoppingOnSplitTab, 'LifeOsTopBrandHeader')} '
          'SplitTab=${countFor(familyRebuildsShoppingOnSplitTab, '_SplitBillsAndSettlementTabView')} '
          'MintHero=${countFor(familyRebuildsShoppingOnSplitTab, 'LifeOsMintHeroCard')} '
          'total=${familyRebuildsShoppingOnSplitTab.values.fold<int>(0, (a, b) => a + b)}',
        );

        expect(todayBlurAll, lessThanOrEqualTo(1));
        expect(financeBlurAll, lessThanOrEqualTo(1));
        expect(reportBlurVis, 0);
        expect(familyBlurAll, lessThanOrEqualTo(1));

        expect(countFor(todayRebuildsWater, 'TodayPage'), 0);
        expect(countFor(todayRebuildsWater, 'LifeOsTopBrandHeader'), 0);
        expect(countFor(todayRebuildsWater, 'ProHeroGradientCard'), 0);
        expect(countFor(todayRebuildsWater, 'UpcomingScheduleCycleCard'), 0);
        expect(countFor(todayRebuildsWater, 'LifeOsResponsiveIconGrid'), 0);

        expect(countFor(todayRebuildsSearch, 'TodayPage'), 0);
        expect(countFor(todayRebuildsSearch, 'ProHeroGradientCard'), 0);

        expect(countFor(financeRebuildsWater, 'FinancePage'), 0);
        expect(countFor(financeRebuildsWater, '_TransactionsTabView'), 0);
        expect(
          financeRebuildsWater.values.fold<int>(0, (a, b) => a + b),
          lessThanOrEqualTo(4),
        );

        expect(countFor(financeRebuildsSearch, 'FinancePage'), 0);
        expect(
          countFor(financeRebuildsSearch, '_LifeOsSpendingOverviewDeck'),
          0,
        );
        expect(countFor(financeRebuildsSearch, 'DailySpendingChartCard'), 0);
        expect(countFor(financeRebuildsSearch, 'ProDonutChart'), 0);

        expect(countFor(reportRebuildsWater, 'FinanceReportPage'), 0);
        expect(countFor(reportRebuildsWater, 'LifeInsightsCrossDomainCard'), 0);
        expect(
          reportRebuildsWater.values.fold<int>(0, (a, b) => a + b),
          lessThanOrEqualTo(4),
        );

        expect(countFor(familyRebuildsWater, 'FamilyPage'), 0);
        expect(
          countFor(familyRebuildsWater, '_SplitBillsAndSettlementTabView'),
          0,
        );
        expect(
          familyRebuildsWater.values.fold<int>(0, (a, b) => a + b),
          lessThanOrEqualTo(4),
        );

        expect(countFor(familyRebuildsShoppingOnSplitTab, 'FamilyPage'), 0);
        expect(
          countFor(
            familyRebuildsShoppingOnSplitTab,
            '_SplitBillsAndSettlementTabView',
          ),
          0,
        );
        expect(
          countFor(familyRebuildsShoppingOnSplitTab, 'LifeOsMintHeroCard'),
          0,
        );
        expect(
          familyRebuildsShoppingOnSplitTab.values.fold<int>(0, (a, b) => a + b),
          lessThanOrEqualTo(60),
        );

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('UI Optimization Layout Robustness Matrix', () {
    const viewports = <(String, Size, double)>[
      ('320x640 @ 1.3', Size(320, 640), 1.3),
      ('360x800 @ 1.25', Size(360, 800), 1.25),
      ('412x915 @ 1.0', Size(412, 915), 1.0),
    ];
    const themes = <(String, ThemeMode, bool)>[
      ('Light', ThemeMode.light, false),
      ('Dark', ThemeMode.dark, false),
      ('HighContrast', ThemeMode.light, true),
    ];

    for (final vp in viewports) {
      for (final th in themes) {
        testWidgets(
          'Zero overflow & zero exception across all target screens on ${vp.$1} [${th.$1}]',
          (tester) async {
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

            await _bootRichLifeOs(
              tester,
              uid: 'u_m_${vp.$2.width.toInt()}_${th.$1}',
              fullName: 'Nguyễn Minh Hoàng',
              viewport: vp.$2,
              textScale: vp.$3,
              themeMode: th.$2,
              highContrast: th.$3,
            );

            final issues = <String>[];
            final ctxLabel = '${vp.$1} [${th.$1}]';

            // 1. TodayPage (scroll top -> bottom)
            await _scrollToBottomAndScan(
              tester,
              find.byType(Scrollable),
              '$ctxLabel | TodayPage',
              issues,
            );

            // 2. FinancePage + 4 sub-tabs (scroll to bottom each)
            GoRouter.of(
              tester.element(find.byType(Scaffold).first),
            ).go('/finance');
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byKey(const Key('transactions_list_view')),
              '$ctxLabel | Finance: Sổ thu chi',
              issues,
            );

            await tester.tap(find.text('Ngân sách').first);
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byKey(const Key('budgets_list_view')),
              '$ctxLabel | Finance: Ngân sách',
              issues,
            );

            await tester.tap(find.byKey(const Key('finance_analytics_tab')));
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byKey(const Key('analytics_list_view')),
              '$ctxLabel | Finance: Phân tích',
              issues,
            );

            await tester.tap(find.byKey(const Key('finance_tools_tab')));
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byKey(const Key('finance_tools_hub_list_view')),
              '$ctxLabel | Finance: Công cụ',
              issues,
            );

            // 3. FinanceReportPage (scroll to bottom)
            GoRouter.of(
              tester.element(find.byType(Scaffold).first),
            ).push('/finance-report');
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byKey(const Key('finance_report_list_view')),
              '$ctxLabel | FinanceReportPage',
              issues,
            );
            GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
            await tester.pumpAndSettle();

            // 4. FamilyPage + 4 sub-tabs (scroll to bottom each)
            GoRouter.of(
              tester.element(find.byType(Scaffold).first),
            ).go('/family');
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byKey(const Key('split_bills_list_view')),
              '$ctxLabel | Family: Chia tiền',
              issues,
            );

            await tester.tap(find.byKey(const Key('family_members_tab')));
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byKey(const Key('members_list_view')),
              '$ctxLabel | Family: Thành viên',
              issues,
            );

            await tester.tap(find.byKey(const Key('family_shopping_tab')));
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byKey(const Key('shopping_list_view')),
              '$ctxLabel | Family: Mua sắm',
              issues,
            );

            await tester.tap(find.byKey(const Key('family_assets_life_tab')));
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byKey(const Key('family_household_assets_list_view')),
              '$ctxLabel | Family: Tổ ấm',
              issues,
            );

            // 5. FamilyFundsPage (scroll to bottom)
            GoRouter.of(
              tester.element(find.byType(Scaffold).first),
            ).push('/family-funds');
            await tester.pumpAndSettle();
            await _scrollToBottomAndScan(
              tester,
              find.byType(Scrollable),
              '$ctxLabel | FamilyFundsPage',
              issues,
            );
            GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
            await tester.pumpAndSettle();

            expect(
              issues,
              isEmpty,
              reason:
                  'Layout/overflow/truncation issues on $ctxLabel:\n${issues.join('\n')}',
            );
          },
        );
      }
    }
  });
}
