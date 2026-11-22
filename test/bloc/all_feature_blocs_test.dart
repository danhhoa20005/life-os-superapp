import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_bloc.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_event.dart';
import 'package:life_os/features/authentication/presentation/bloc/auth_state.dart';
import 'package:life_os/features/budgets/domain/entities/budget_entities.dart';
import 'package:life_os/features/budgets/domain/usecases/budget_usecases.dart';
import 'package:life_os/features/budgets/presentation/bloc/budget_bloc.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/calendar/domain/repositories/calendar_repository.dart';
import 'package:life_os/features/calendar/presentation/bloc/calendar_bloc.dart';
import 'package:life_os/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/family/domain/usecases/family_usecases.dart';
import 'package:life_os/features/family/presentation/bloc/family_bloc.dart';
import 'package:life_os/features/notifications/domain/entities/notification_entities.dart';
import 'package:life_os/features/notifications/presentation/bloc/notification_ingestion_bloc.dart';
import 'package:life_os/features/tasks/domain/repositories/task_repository.dart';
import 'package:life_os/features/tasks/presentation/bloc/task_bloc.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_bloc.dart';
import 'package:life_os/features/transactions/presentation/bloc/transaction_event.dart';
import 'package:life_os/features/vehicles/presentation/bloc/vehicle_bloc.dart';

void main() {
  group('All Feature BLoCs & Restart Persistence Verification', () {
    late MockFirebaseAuth mockAuth;
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() async {
      mockAuth = MockFirebaseAuth();
      fakeFirestore = FakeFirebaseFirestore();
      await configureDependencies(
        authOverride: mockAuth,
        firestoreOverride: fakeFirestore,
      );
    });

    test('AuthBloc, FamilyBloc, BudgetBloc, CalendarBloc, TaskBloc, VehicleBloc, NotificationIngestionBloc & DashboardBloc operate cleanly and persist across app restart', () async {
      // 1. AuthBloc sign-up + onboarding
      final authBloc = sl<AuthBloc>()..add(const AuthSubscriptionRequested());
      authBloc.add(
        const AuthSignUpSubmitted(
          email: 'hoa@lifeos.vn',
          password: 'StrongPassword123',
          fullName: 'Danh Hòa',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(authBloc.state.status, AuthStatus.authenticated);
      final uid = authBloc.state.user!.id;

      authBloc.add(const AuthOnboardingCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(authBloc.state.user!.onboardingCompleted, isTrue);

      // 2. FamilyBloc creates household & shopping item
      final familyBloc = sl<FamilyBloc>()..add(FamilySubscriptionRequested(userId: uid));
      familyBloc.add(
        FamilyCreateSubmitted(
          userId: uid,
          userName: 'Danh Hòa',
          familyName: 'Gia đình Hòa',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(familyBloc.state.families.length, 1);
      final famId = familyBloc.state.families.first.id;

      familyBloc.add(
        ShoppingItemAdded(
          familyId: famId,
          userName: 'Danh Hòa',
          title: 'Gạo ST25',
          quantityLabel: '1 túi 5kg',
          estimatedPriceMinor: 195000,
        ),
      );
      familyBloc.add(
        SharedBillSplitCreated(
          CreateSharedBillSplitParams(
            familyId: famId,
            title: 'Lẩu gia đình & Nước giặt đồ',
            topic: SharedExpenseTopic.housework,
            paidByUserId: uid,
            paidByName: 'Danh Hòa',
            totalAmountMinor: 350000,
            splitMethod: SplitMethod.equal,
            participantIds: [uid, 'partner_2'],
            participantNames: {uid: 'Danh Hòa', 'partner_2': 'Minh Anh'},
            choreOrTaskNote: 'Dọn dẹp cuối tuần',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(familyBloc.state.shoppingItems.any((i) => i.title == 'Gạo ST25'), isTrue);
      expect(familyBloc.state.sharedBills.length, 1);
      expect(familyBloc.state.sharedLedger.suggestedTransfers.length, 1);
      expect(familyBloc.state.sharedLedger.suggestedTransfers.single.amountMinor, 175000);

      final transfer = familyBloc.state.sharedLedger.suggestedTransfers.single;
      familyBloc.add(
        DebtSettlementRecorded(
          RecordDebtSettlementParams(
            familyId: famId,
            fromUserId: transfer.fromUserId,
            fromUserName: transfer.fromUserName,
            toUserId: transfer.toUserId,
            toUserName: transfer.toUserName,
            amountMinor: transfer.amountMinor,
            paymentCode: transfer.sePayTransferCode,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(familyBloc.state.settlements.length, 1);
      expect(familyBloc.state.sharedLedger.suggestedTransfers, isEmpty);

      // 3. BudgetBloc creates monthly budget & family fund
      const monthKey = '2026-11';
      final budgetBloc = sl<BudgetBloc>()
        ..add(BudgetsSubscriptionRequested(userId: uid, monthKey: monthKey, familyId: famId));
      budgetBloc.add(
        const BudgetUpsertSubmitted(
          UpsertBudgetParams(
            userId: 'placeholder_overridden_below',
            categoryId: 'cat_food',
            categoryName: 'Ăn uống',
            monthKey: monthKey,
            limitMinor: 4000000,
          ),
        ),
      );
      budgetBloc.add(
        BudgetUpsertSubmitted(
          UpsertBudgetParams(
            userId: uid,
            categoryId: 'cat_food',
            categoryName: 'Ăn uống',
            monthKey: monthKey,
            limitMinor: 4000000,
          ),
        ),
      );
      budgetBloc.add(
        FundCreateSubmitted(
          CreateFundParams(
            userId: uid,
            familyId: famId,
            scope: FundScope.family,
            name: 'Quỹ Du lịch Đà Lạt',
            targetAmountMinor: 8000000,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(budgetBloc.state.budgets.any((b) => b.limitMinor == 4000000), isTrue);
      expect(budgetBloc.state.funds.any((f) => f.name == 'Quỹ Du lịch Đà Lạt'), isTrue);

      // 4. CalendarBloc & TaskBloc
      final calendarBloc = sl<CalendarBloc>()
        ..add(CalendarWatchStarted(userId: uid, familyId: famId));
      calendarBloc.add(
        CalendarEventCreated(
          CreateCalendarEventParams(
            userId: uid,
            userName: 'Danh Hòa',
            familyId: famId,
            visibility: CalendarEventVisibility.privateEvent,
            title: 'Tập gym buổi chiều',
            startsAt: DateTime.now().add(const Duration(hours: 1)),
            endsAt: DateTime.now().add(const Duration(hours: 2)),
          ),
        ),
      );

      final taskBloc = sl<TaskBloc>()..add(TasksWatchStarted(userId: uid, familyId: famId));
      taskBloc.add(
        TaskCreateSubmitted(
          CreateTaskParams(
            createdBy: uid,
            creatorName: 'Danh Hòa',
            familyId: famId,
            assigneeId: uid,
            assigneeName: 'Danh Hòa',
            title: 'Thanh toán tiền nước',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(calendarBloc.state.events.any((e) => e.title == 'Tập gym buổi chiều'), isTrue);
      expect(taskBloc.state.tasks.any((t) => t.title == 'Thanh toán tiền nước'), isTrue);

      // 5. VehicleBloc & NotificationIngestionBloc
      final vehicleBloc = sl<VehicleBloc>()
        ..add(VehiclesWatchStarted(userId: uid, familyId: famId));
      vehicleBloc.add(
        VehicleCreated(
          userId: uid,
          familyId: famId,
          isFamilyShared: false,
          name: 'Yamaha Grande',
          plateNumber: '59K1-567.89',
          currentOdometerKm: 5200,
        ),
      );

      final notifBloc = sl<NotificationIngestionBloc>()
        ..add(NotificationsCenterStarted(uid));
      notifBloc.add(
        ConsentConfigUpdated(
          userId: uid,
          enabled: true,
          allowedPackages: const ['com.VCB'],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      notifBloc.add(
        BankNotificationSignalReceived(
          userId: uid,
          defaultWalletId: 'wallet_cash_default',
          packageName: 'com.VCB',
          title: 'VCB',
          body: 'GD: -65.000VND tai Highlands Coffee',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(vehicleBloc.state.vehicles.any((v) => v.name == 'Yamaha Grande'), isTrue);
      expect(notifBloc.state.lastOutcome?.kind, IngestionOutcomeKind.createdProvisional);

      // 6. Close all BLoCs and simulate App Restart against the same Firestore & Auth session!
      await dashboardDisposeCheck(uid, famId);
      await familyBloc.close();
      await budgetBloc.close();
      await calendarBloc.close();
      await taskBloc.close();
      await vehicleBloc.close();
      await notifBloc.close();
      await authBloc.close();

      // Re-configure DI as a fresh app cold boot while preserving Firebase instances
      await configureDependencies(
        authOverride: mockAuth,
        firestoreOverride: fakeFirestore,
      );

      final restartedAuthBloc = sl<AuthBloc>()..add(const AuthSubscriptionRequested());
      final restartedTxListBloc = sl<TransactionListBloc>()
        ..add(TransactionsSubscriptionRequested(userId: uid));

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(restartedAuthBloc.state.status, AuthStatus.authenticated);
      expect(restartedAuthBloc.state.user?.email, 'hoa@lifeos.vn');
      expect(
        restartedTxListBloc.state.allTransactions
            .any((t) => t.verification == TransactionVerification.provisional && t.amountMinor == 65000),
        isTrue,
      );

      await restartedTxListBloc.close();
      await restartedAuthBloc.close();
    });
  });
}

Future<void> dashboardDisposeCheck(String uid, String famId) async {
  final dashBloc = sl<DashboardBloc>()
    ..add(DashboardWatchStarted(userId: uid, familyId: famId));
  await Future<void>.delayed(const Duration(milliseconds: 60));
  expect(dashBloc.state.data.provisionalPendingCount, greaterThanOrEqualTo(1));
  await dashBloc.close();
}
