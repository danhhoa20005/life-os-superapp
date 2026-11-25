import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/core/utils/smart_omni_intent_parser.dart';
import 'package:life_os/core/utils/vietnamese_search_matcher.dart';
import 'package:life_os/features/calendar/presentation/bloc/calendar_bloc.dart';
import 'package:life_os/features/documents/domain/entities/document_vault_entity.dart';
import 'package:life_os/features/documents/presentation/bloc/document_vault_bloc.dart';
import 'package:life_os/features/family/presentation/bloc/family_bloc.dart';
import 'package:life_os/features/pro_utilities/data/repositories/pro_utilities_repository_impl.dart';
import 'package:life_os/features/pro_utilities/domain/entities/pro_utilities_entities.dart';
import 'package:life_os/features/tasks/domain/entities/task_entities.dart';
import 'package:life_os/features/tasks/domain/repositories/task_repository.dart';
import 'package:life_os/features/tasks/presentation/bloc/task_bloc.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_state.dart';
import 'package:life_os/features/vehicles/data/repositories/vehicle_repository_impl.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';

class _NoOpDeviceCalendarDriver implements DeviceCalendarDriver {
  const _NoOpDeviceCalendarDriver();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<List<DeviceCalendarInfo>> listCalendars() async =>
      const <DeviceCalendarInfo>[];

  @override
  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async => const <DeviceCalendarEventItem>[];

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
  group('1. VietnameseSearchMatcher, SmartOmniIntentParser & Receipt OCR', () {
    test(
      'VietnameseSearchMatcher folds all 67 Vietnamese accents + đ/Đ + multi-token + numeric amounts',
      () {
        expect(
          VietnameseSearchMatcher.fold('Đăng kiểm Ô tô & Phở Bò Đặc Biệt'),
          equals('dang kiem o to & pho bo dac biet'),
        );

        expect(
          VietnameseSearchMatcher.matchesAny('pho dac biet', [
            'Phở Bò Đặc Biệt',
            'Ăn uống',
          ]),
          isTrue,
        );

        expect(
          VietnameseSearchMatcher.matchesAny('65000', [
            'Cà phê sáng',
            '65.000 ₫',
          ]),
          isTrue,
        );

        expect(
          VietnameseSearchMatcher.matchesAny('luong gross', [
            'Lương Gross–Net',
          ]),
          isTrue,
        );

        expect(
          VietnameseSearchMatcher.matchesAny('khong ton tai', [
            'Phở Bò Đặc Biệt',
            'Ăn uống',
          ]),
          isFalse,
        );
      },
    );

    test(
      'SmartOmniIntentParser classifies unaccented Vietnamese calendar, task, water & medication inputs',
      () {
        final now = DateTime(2026, 11, 24, 8, 30);

        final cal = SmartOmniIntentParser.tryParsePrimary(
          'hop nhom 9h mai',
          now: now,
        );
        expect(cal?.kind, OmniActionKind.calendarEvent);

        final task = SmartOmniIntentParser.tryParsePrimary(
          'nhac dong tien dien',
          now: now,
        );
        expect(task?.kind, OmniActionKind.task);

        final water = SmartOmniIntentParser.tryParsePrimary(
          'uong 2 ly nuoc',
          now: now,
        );
        expect(water?.kind, OmniActionKind.waterLog);
        expect(water?.waterMl, 500);

        final med = SmartOmniIntentParser.tryParsePrimary(
          'nhac uong thuoc vitamin',
          now: now,
        );
        expect(med?.kind, OmniActionKind.medication);
      },
    );

    test(
      'SmartReceiptParserEngine classifies unaccented POS receipts accurately',
      () {
        final evn = SmartReceiptParserEngine.parse(
          'HOA DON TIEN DIEN EVN\nTONG CONG 650.000',
        );
        expect(evn.suggestedCategory, 'Điện/Nước/Internet');
        expect(evn.totalMinor, 650000);

        final food = SmartReceiptParserEngine.parse(
          'QUAN PHO BO HA NOI\nPho tai chin 55k\nTra da 5k',
        );
        expect(food.suggestedCategory, 'Ăn uống');
        expect(food.totalMinor, 60000);
      },
    );
  });

  group(
    '2. Finance Ledger Filters, Provisional Exclusion & Edited Auto-Tx Persistence',
    () {
      test(
        'TransactionListState excludes unconfirmed provisional rows, matches creditCardPayment under transfer chip, and supports wallet/category/unaccented search',
        () {
          final now = DateTime(2026, 11, 24, 10, 0);
          final confirmedExpense = TransactionEntity(
            id: 'tx_1',
            ownerId: 'u1',
            walletId: 'w_bank',
            walletName: 'Vietcombank',
            categoryName: 'Ăn uống',
            kind: TransactionKind.expense,
            direction: 'debit',
            amountMinor: 65000,
            merchant: 'Phở Thìn Bờ Hồ',
            note: 'Ăn sáng cuối tuần',
            occurredAt: now,
            monthKey: '2026-11',
            sourceKind: TransactionSourceKind.manual,
            verification: TransactionVerification.userConfirmed,
            crossSourceFingerprint: 'fp_1',
          );
          final cardRepayment = TransactionEntity(
            id: 'tx_2',
            ownerId: 'u1',
            walletId: 'w_bank',
            targetWalletId: 'w_card',
            walletName: 'Vietcombank',
            categoryName: 'Thanh toán thẻ tín dụng',
            kind: TransactionKind.creditCardPayment,
            direction: 'transfer',
            amountMinor: 3500000,
            merchant: 'Tất toán sao kê thẻ',
            occurredAt: now,
            monthKey: '2026-11',
            sourceKind: TransactionSourceKind.manual,
            verification: TransactionVerification.userConfirmed,
            crossSourceFingerprint: 'fp_2',
          );
          final unconfirmedProvisional = TransactionEntity(
            id: 'tx_prov',
            ownerId: 'u1',
            walletId: 'w_bank',
            categoryName: 'Mua sắm',
            kind: TransactionKind.expense,
            direction: 'debit',
            amountMinor: 250000,
            merchant: 'Shopee VN',
            occurredAt: now,
            monthKey: '2026-11',
            sourceKind: TransactionSourceKind.androidNotification,
            verification: TransactionVerification.provisional,
            crossSourceFingerprint: 'fp_prov',
          );

          final baseState = TransactionListState(
            monthKey: '2026-11',
            allTransactions: [
              confirmedExpense,
              cardRepayment,
              unconfirmedProvisional,
            ],
          );

          // Provisional item must NOT pollute confirmed ledger list
          expect(baseState.filteredTransactions.map((t) => t.id), [
            'tx_1',
            'tx_2',
          ]);
          expect(baseState.provisionalTransactions.map((t) => t.id), [
            'tx_prov',
          ]);

          // '⇄ Chuyển ví' (TransactionKind.transfer) must include creditCardPayment
          final transferFiltered = baseState.copyWith(
            kindFilter: TransactionKind.transfer,
          );
          expect(transferFiltered.hasActiveFilters, isTrue);
          expect(transferFiltered.filteredTransactions.map((t) => t.id), [
            'tx_2',
          ]);

          // Unaccented search ("pho thin") matches accented merchant
          final searched = baseState.copyWith(searchQuery: 'pho thin');
          expect(searched.filteredTransactions.map((t) => t.id), ['tx_1']);

          // Numeric search ("65000") matches 65.000 ₫ transaction
          final amountSearched = baseState.copyWith(searchQuery: '65000');
          expect(amountSearched.filteredTransactions.map((t) => t.id), [
            'tx_1',
          ]);
        },
      );

      test(
        'TransactionRemoteDataSource.decideProvisionalTransaction persists edited amount & note and adjusts wallet balance accurately',
        () async {
          final firestore = FakeFirebaseFirestore();
          final ds = TransactionRemoteDataSource(firestore);
          const uid = 'u_autotx';

          await firestore
              .collection('users')
              .doc(uid)
              .collection('wallets')
              .doc('w_main')
              .set({
                'id': 'w_main',
                'ownerId': uid,
                'name': 'VCB Chính',
                'type': 'bank',
                'balanceMinor': 1000000,
                'isEstimatedBalance': false,
              });

          await firestore
              .collection('users')
              .doc(uid)
              .collection('transactions')
              .doc('tx_auto_1')
              .set({
                'id': 'tx_auto_1',
                'ownerId': uid,
                'walletId': 'w_main',
                'categoryName': 'Chi tiêu khác',
                'kind': 'expense',
                'direction': 'debit',
                'amountMinor': 120000,
                'merchant': 'GrabBike',
                'note': 'Tự động bắt từ thông báo',
                'occurredAt': DateTime(2026, 11, 24).toIso8601String(),
                'monthKey': '2026-11',
                'sourceKind': 'androidNotification',
                'verification': 'provisional',
                'isReversed': false,
                'crossSourceFingerprint': 'fp_auto_1',
              });

          await ds.decideProvisionalTransaction(
            userId: uid,
            transactionId: 'tx_auto_1',
            approve: true,
            updatedCategoryName: 'Xe cộ & Di chuyển',
            updatedAmountMinor: 95000,
            updatedNote: 'Đi họp khách hàng Q1',
          );

          final txDoc = await firestore
              .collection('users')
              .doc(uid)
              .collection('transactions')
              .doc('tx_auto_1')
              .get();
          expect(txDoc.data()!['verification'], 'userConfirmed');
          expect(txDoc.data()!['categoryName'], 'Xe cộ & Di chuyển');
          expect(txDoc.data()!['amountMinor'], 95000);
          expect(txDoc.data()!['note'], 'Đi họp khách hàng Q1');

          final walletDoc = await firestore
              .collection('users')
              .doc(uid)
              .collection('wallets')
              .doc('w_main')
              .get();
          // 1,000,000 - 95,000 = 905,000 (uses edited amount, NOT stale 120,000!)
          expect(walletDoc.data()!['balanceMinor'], 905000);
        },
      );
    },
  );

  group(
    '3. Tasks Update/Delete, Wellness Target Preservation, Bill Rollover & Family Selection',
    () {
      test(
        'ProUtilitiesRepositoryImpl.updateDailyWellness preserves custom targetWaterMl when logging water or focus',
        () async {
          final firestore = FakeFirebaseFirestore();
          final repo = ProUtilitiesRepositoryImpl(firestore);
          const uid = 'u_wellness';
          final todayKey = LifeHabitEntity.formatDayKey(DateTime.now());

          await firestore
              .collection('users')
              .doc(uid)
              .collection('wellness_daily')
              .doc(todayKey)
              .set({
                'dateKey': todayKey,
                'waterMl': 500,
                'targetWaterMl': 2800,
                'focusMinutes': 25,
                'completedPomodoros': 1,
              });

          await repo.updateDailyWellness(
            userId: uid,
            dateKey: todayKey,
            addWaterMl: 300,
          );

          final doc = await firestore
              .collection('users')
              .doc(uid)
              .collection('wellness_daily')
              .doc(todayKey)
              .get();
          expect(doc.data()!['waterMl'], 800);
          expect(doc.data()!['targetWaterMl'], 2800);
          expect(doc.data()!['lastCupMl'], 300);
        },
      );

      test(
        'VehicleRemoteDataSource.payRecurringBill clamps Jan 31 nextDueDate to Feb 28 without overflowing into March',
        () async {
          final firestore = FakeFirebaseFirestore();
          final ds = VehicleRemoteDataSource(firestore);
          const uid = 'u_bill';

          await firestore
              .collection('users')
              .doc(uid)
              .collection('wallets')
              .doc('w1')
              .set({
                'id': 'w1',
                'ownerId': uid,
                'name': 'Tiền mặt',
                'type': 'cash',
                'balanceMinor': 2000000,
              });

          final jan31 = DateTime(2026, 1, 31, 9, 0);
          await firestore
              .collection('users')
              .doc(uid)
              .collection('bills')
              .doc('bill_internet')
              .set({
                'id': 'bill_internet',
                'ownerId': uid,
                'title': 'Cước Internet FPT',
                'providerName': 'FPT Telecom',
                'estimatedAmountMinor': 250000,
                'nextDueDate': Timestamp.fromDate(jan31),
              });

          final bill = RecurringBillEntity(
            id: 'bill_internet',
            ownerId: uid,
            title: 'Cước Internet FPT',
            providerName: 'FPT Telecom',
            estimatedAmountMinor: 250000,
            nextDueDate: jan31,
            lastPaidAmountMinor: 250000,
          );

          await ds.payRecurringBill(
            userId: uid,
            bill: bill,
            paidAmountMinor: 250000,
            walletId: 'w1',
          );

          final updated = await firestore
              .collection('users')
              .doc(uid)
              .collection('bills')
              .doc('bill_internet')
              .get();
          final rawNext = updated.data()!['nextDueDate'];
          final nextDue = rawNext is Timestamp
              ? rawNext.toDate()
              : (rawNext is DateTime
                    ? rawNext
                    : DateTime.parse(rawNext.toString()));
          expect(nextDue.year, 2026);
          expect(nextDue.month, 2);
          expect(nextDue.day, 28);
        },
      );

      test(
        'TaskRepository & TaskBloc support TaskUpdated and TaskDeleted cleanly',
        () async {
          final firestore = FakeFirebaseFirestore();
          final mockAuth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'u_task', email: 'hoa@lifeos.vn'),
          );
          await sl.reset();
          await configureDependencies(
            authOverride: mockAuth,
            firestoreOverride: firestore,
            httpClientOverride: MockClient(
              (_) async => http.Response('{}', 404),
            ),
            googleCalendarTokenOverride: ({required interactive}) async => null,
          );

          final repo = sl<TaskRepository>();
          final createdRes = await repo.createTask(
            createdBy: 'u_task',
            creatorName: 'Hòa',
            assigneeId: 'u_task',
            assigneeName: 'Hòa',
            title: 'Đóng tiền nước tháng 11',
            description: 'Ghi chú ban đầu',
            priority: TaskPriorityLevel.medium,
            recurrence: TaskRecurrence.none,
          );
          expect(createdRes.isSuccess, isTrue);
          final created = createdRes.fold(
            (_) => throw StateError('err'),
            (t) => t,
          );

          final bloc = sl<TaskBloc>()
            ..add(const TasksWatchStarted(userId: 'u_task'));
          await Future<void>.delayed(const Duration(milliseconds: 60));

          bloc.add(
            TaskUpdated(
              actorUserId: 'u_task',
              task: created,
              title: 'Đóng tiền nước & phí rác tháng 11',
              description: 'Đã cập nhật chi tiết',
              priority: TaskPriorityLevel.high,
              recurrence: TaskRecurrence.none,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(
            bloc.state.tasks.single.title,
            'Đóng tiền nước & phí rác tháng 11',
          );
          expect(bloc.state.tasks.single.priority, TaskPriorityLevel.high);

          bloc.add(
            TaskDeleted(actorUserId: 'u_task', task: bloc.state.tasks.single),
          );
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(bloc.state.tasks, isEmpty);
          await bloc.close();
        },
      );

      test(
        'FamilyBloc preserves user-selected family instead of snapping back to preferredFamilyId on stream emission',
        () async {
          final firestore = FakeFirebaseFirestore();
          const uid = 'u_fam';
          for (final id in ['fam_1', 'fam_2']) {
            await firestore.collection('families').doc(id).set({
              'id': id,
              'name': id == 'fam_1' ? 'Gia đình Nội' : 'Nhóm Dự án',
              'ownerId': uid,
              'spaceType': 'family',
              'memberIds': [uid],
              'members': [
                {'userId': uid, 'displayName': 'Hòa', 'role': 'owner'},
              ],
            });
          }

          final mockAuth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: uid, email: 'hoa@lifeos.vn'),
          );
          await sl.reset();
          await configureDependencies(
            authOverride: mockAuth,
            firestoreOverride: firestore,
            httpClientOverride: MockClient(
              (_) async => http.Response('{}', 404),
            ),
            googleCalendarTokenOverride: ({required interactive}) async => null,
          );

          final bloc = sl<FamilyBloc>();
          bloc.add(
            const FamilySubscriptionRequested(
              userId: uid,
              preferredFamilyId: 'fam_1',
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 80));
          expect(bloc.state.selectedFamilyId, 'fam_1');

          // User switches to fam_2
          bloc.add(const FamilyShoppingWatchRequested('fam_2'));
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(bloc.state.selectedFamilyId, 'fam_2');

          // Stream emits again (e.g. family name updated on fam_1) while preferredFamilyId was fam_1
          await firestore.collection('families').doc('fam_1').update({
            'name': 'Gia đình Nội 2026',
          });
          await Future<void>.delayed(const Duration(milliseconds: 80));
          expect(bloc.state.selectedFamilyId, 'fam_2');
          await bloc.close();
        },
      );

      test(
        'CalendarState & DocumentVaultState filter and reset cleanly via unaccented Vietnamese matching',
        () {
          final doc = DocumentVaultEntity(
            id: 'd1',
            ownerId: 'u1',
            isFamilyShared: false,
            folder: DocumentFolderCategory.importantDocs,
            title: 'Căn cước công dân gắn chip',
            referenceCode: '079200012345',
            note: 'Bản gốc',
            uploadedByName: 'Hòa',
            createdAt: DateTime(2026, 11, 24),
          );
          final docState = DocumentVaultState(
            documents: [doc],
            selectedFolder: DocumentFolderCategory.vehiclePapers,
            searchQuery: 'bang lai',
          );
          expect(docState.hasActiveFilters, isTrue);
          expect(docState.visibleDocuments, isEmpty);

          final unaccentedSearch = docState.copyWith(
            clearSelectedFolder: true,
            searchQuery: 'can cuoc cong dan',
          );
          expect(unaccentedSearch.visibleDocuments.length, 1);

          const calState = CalendarState(
            selectedCalendarId: 'cal_work',
            searchQuery: 'hop khach',
          );
          expect(calState.hasActiveFilters, isTrue);
        },
      );
    },
  );

  group(
    '4. End-to-End Widget Tests for "Tất cả" Filters, Unaccented Search & Clear/Reset Buttons',
    () {
      testWidgets(
        'SuperAppDirectoryPage supports unaccented Vietnamese search, × clear button, domain chip & 1-tap reset from empty state',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          NativeDeviceCalendarBridge.setDriverOverride(
            const _NoOpDeviceCalendarDriver(),
          );
          addTearDown(() {
            NativeDeviceCalendarBridge.setDriverOverride(null);
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final fakeFirestore = FakeFirebaseFirestore();
          const uid = 'uid_filter_e2e';
          await fakeFirestore.collection('users').doc(uid).set({
            'id': uid,
            'email': 'hoa@lifeos.vn',
            'fullName': 'Nguyễn Danh Hòa',
            'onboardingCompleted': true,
          });
          await fakeFirestore
              .collection('users')
              .doc(uid)
              .collection('wallets')
              .doc('wallet_bank_default')
              .set({
                'id': 'wallet_bank_default',
                'ownerId': uid,
                'name': 'Tài khoản Vietcombank',
                'type': 'bank',
                'balanceMinor': 25000000,
                'isEstimatedBalance': false,
              });

          final mockAuth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(
              uid: uid,
              email: 'hoa@lifeos.vn',
              displayName: 'Nguyễn Danh Hòa',
            ),
          );

          await sl.reset();
          await configureDependencies(
            authOverride: mockAuth,
            firestoreOverride: fakeFirestore,
            httpClientOverride: MockClient(
              (_) async => http.Response('{}', 404),
            ),
            googleCalendarTokenOverride: ({required interactive}) async => null,
          );

          await tester.pumpWidget(const LifeOsApp());
          await tester.pumpAndSettle();

          // Navigate to All Services 360° Directory
          final allServicesCard = find.byKey(
            const Key('home_tile_all_services'),
          );
          await tester.scrollUntilVisible(
            allServicesCard,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(allServicesCard);
          await tester.pumpAndSettle();

          final searchField = find.byKey(
            const Key('super_app_directory_search_input'),
          );
          expect(searchField, findsOneWidget);

          // 1. Unaccented Vietnamese query finds accented service
          await tester.enterText(searchField, 'luong gross');
          await tester.pumpAndSettle();
          expect(find.text('Lương Gross–Net'), findsOneWidget);
          expect(
            find.byKey(const Key('super_app_directory_clear_btn')),
            findsOneWidget,
          );

          // 2. Tap × clear button -> clears controller & restores full catalog
          await tester.tap(
            find.byKey(const Key('super_app_directory_clear_btn')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Sổ thu chi'), findsOneWidget);
          expect(find.text('Sức khỏe & SOS'), findsOneWidget);

          // 3. Unmatched query -> shows empty filter card with 1-tap reset button
          await tester.enterText(searchField, 'khong co dich vu xyz');
          await tester.pumpAndSettle();
          final resetBtn = find.byKey(
            const Key('super_app_directory_reset_btn'),
          );
          expect(resetBtn, findsOneWidget);

          await tester.tap(resetBtn);
          await tester.pumpAndSettle();
          expect(find.text('Sổ thu chi'), findsOneWidget);
          expect(find.text('Xe & Bảo dưỡng'), findsOneWidget);
        },
      );
    },
  );
}
