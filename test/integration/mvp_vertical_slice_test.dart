import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/features/authentication/domain/entities/user_entity.dart';
import 'package:life_os/features/authentication/domain/repositories/auth_repository.dart';
import 'package:life_os/features/budgets/domain/entities/budget_entities.dart';
import 'package:life_os/features/budgets/domain/repositories/budget_repository.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/calendar/domain/repositories/calendar_repository.dart';
import 'package:life_os/features/dashboard/domain/entities/dashboard_entities.dart';
import 'package:life_os/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/family/domain/repositories/family_repository.dart';
import 'package:life_os/features/notifications/domain/entities/notification_entities.dart';
import 'package:life_os/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:life_os/features/tasks/domain/entities/task_entities.dart';
import 'package:life_os/features/tasks/domain/repositories/task_repository.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:life_os/features/vehicles/domain/repositories/vehicle_repository.dart';

void main() {
  group('End-to-End Repository & Domain Vertical Slices Integration', () {
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

    test(
      'Complete Life OS lifecycle: Auth -> Ledger/Transfer/Reversal -> Dedupe & Provisional->Verified Upgrade -> Family/Fund/Tasks/Privacy',
      () async {
        final authRepo = sl<AuthRepository>();
        final txRepo = sl<TransactionRepository>();
        final budgetRepo = sl<BudgetRepository>();
        final familyRepo = sl<FamilyRepository>();
        final calRepo = sl<CalendarRepository>();
        final taskRepo = sl<TaskRepository>();
        final vehRepo = sl<VehicleRepository>();
        final notifRepo = sl<NotificationsRepository>();
        final dashRepo = sl<DashboardRepository>();

        // 1. Sign up User A (Minh)
        final signUpRes = await authRepo.signUp(
          email: 'minh@lifeos.vn',
          password: 'Password123!',
          fullName: 'Nguyễn Minh',
        );
        expect(signUpRes.isSuccess, isTrue);
        final minh = (signUpRes as Success<UserEntity>).value;

        // 2. Create Bank Wallet (10,000,000 VND) + Expense + Internal Transfer + Reversal
        final bankRes = await txRepo.createWallet(
          userId: minh.id,
          name: 'Vietcombank',
          type: WalletType.bank,
          openingBalanceMinor: 10000000,
        );
        final bankWallet = (bankRes as Success<WalletEntity>).value;

        // Record Expense (200,000 VND) with idempotency key `op_exp_1`
        await txRepo.createTransaction(
          operationId: 'op_exp_1',
          userId: minh.id,
          walletId: bankWallet.id,
          categoryName: 'Ăn uống',
          kind: TransactionKind.expense,
          amountMinor: 200000,
          merchant: 'Cơm trưa văn phòng',
          occurredAt: DateTime.now(),
        );
        // Duplicate call with same operationId MUST NOT deduct twice!
        await txRepo.createTransaction(
          operationId: 'op_exp_1',
          userId: minh.id,
          walletId: bankWallet.id,
          categoryName: 'Ăn uống',
          kind: TransactionKind.expense,
          amountMinor: 200000,
          merchant: 'Cơm trưa văn phòng',
          occurredAt: DateTime.now(),
        );

        // Internal Transfer: 1,000,000 VND from VCB -> Default Cash Wallet
        await txRepo.createTransaction(
          operationId: 'op_trf_1',
          userId: minh.id,
          walletId: bankWallet.id,
          targetWalletId: 'wallet_cash_default',
          categoryName: 'Chuyển khoản nội bộ',
          kind: TransactionKind.transfer,
          amountMinor: 1000000,
          merchant: 'Rút tiền mặt ATM',
          occurredAt: DateTime.now(),
        );

        final walletsFirst =
            (await txRepo.watchWallets(minh.id).first
                    as Success<List<WalletEntity>>)
                .value;
        expect(walletsFirst.any((w) => w.id == 'wallet_bank_default'), isTrue);
        expect(
          walletsFirst.any((w) => w.id == 'wallet_savings_default'),
          isTrue,
        );
        final vcbAfter = walletsFirst.firstWhere((w) => w.id == bankWallet.id);
        final cashAfter = walletsFirst.firstWhere(
          (w) => w.id == 'wallet_cash_default',
        );
        expect(vcbAfter.balanceMinor, 8800000); // 10M - 200k - 1M
        expect(cashAfter.balanceMinor, 1000000); // 0 + 1M

        // Verify atomic passbook audit trail & balanceAfterMinor in Firestore
        final expDoc = await fakeFirestore
            .collection('users')
            .doc(minh.id)
            .collection('transactions')
            .doc('op_exp_1')
            .get();
        expect(expDoc.data()?['balanceAfterMinor'], 9800000);
        final auditsSnap = await fakeFirestore
            .collection('users')
            .doc(minh.id)
            .collection('ledger_audits')
            .get();
        expect(
          auditsSnap.docs.length,
          greaterThanOrEqualTo(3),
        ); // 1 expense + 2 transfer legs

        // Reverse the 200,000 VND expense -> restores VCB to 9,000,000 VND!
        await txRepo.reverseTransaction(
          userId: minh.id,
          transactionId: 'op_exp_1',
          reason: 'Hoàn tiền nhà hàng',
        );
        final walletsAfterRev =
            (await txRepo.watchWallets(minh.id).first
                    as Success<List<WalletEntity>>)
                .value;
        expect(
          walletsAfterRev.firstWhere((w) => w.id == bankWallet.id).balanceMinor,
          9000000,
        );

        // 3. Bank Notification Consent -> OTP Block -> Provisional -> Verified Upgrade (T04, T07, T19)
        await notifRepo.updateAndroidNotificationConsent(
          userId: minh.id,
          enabled: true,
          allowedPackages: ['com.VCB'],
        );

        // OTP notification MUST be blocked!
        final otpRes = await notifRepo.ingestAndroidNotification(
          userId: minh.id,
          defaultWalletId: bankWallet.id,
          packageName: 'com.VCB',
          title: 'VCB',
          body: 'Ma OTP cua ban la 112233 de xac thuc giao dich 500.000VND',
        );
        expect(
          (otpRes as Success<IngestionOutcome>).value.kind,
          IngestionOutcomeKind.blockedOtpOrSecret,
        );

        // Valid Android notification arrives right before a 15-minute boundary (17:29:45) -> creates PROVISIONAL
        final nowRef = DateTime.now();
        final t0 = DateTime(nowRef.year, nowRef.month, nowRef.day, 17, 29, 45);
        final provRes = await notifRepo.ingestAndroidNotification(
          userId: minh.id,
          defaultWalletId: bankWallet.id,
          packageName: 'com.VCB',
          title: 'VCB Digibank',
          body: 'TK 102***88 GD: -180.000VND. ND: Thay nhot xe tai HEAD Honda',
          postedAt: t0,
          notificationId: 'n_honda_1',
        );
        expect(
          (provRes as Success<IngestionOutcome>).value.kind,
          IngestionOutcomeKind.createdProvisional,
        );

        // Retry 5x same notification -> ignored idempotently!
        for (var i = 0; i < 5; i++) {
          final dup = await notifRepo.ingestAndroidNotification(
            userId: minh.id,
            defaultWalletId: bankWallet.id,
            packageName: 'com.VCB',
            title: 'VCB Digibank',
            body:
                'TK 102***88 GD: -180.000VND. ND: Thay nhot xe tai HEAD Honda',
            postedAt: t0,
            notificationId: 'n_honda_1',
          );
          expect(
            (dup as Success<IngestionOutcome>).value.kind,
            IngestionOutcomeKind.duplicateIgnored,
          );
        }

        // Official Verified Bank Feed arrives 1 minute later for the SAME 180,000 VND -> upgrades PROVISIONAL to VERIFIED!
        final upgradeRes = await notifRepo.ingestVerifiedBankFeedEvent(
          userId: minh.id,
          walletId: bankWallet.id,
          externalTransactionId: 'ext_tx_honda_01',
          direction: 'debit',
          amountMinor: 180000,
          content: 'Thay nhot xe tai HEAD Honda',
          occurredAt: t0.add(const Duration(minutes: 1)),
        );
        expect(
          (upgradeRes as Success<IngestionOutcome>).value.kind,
          IngestionOutcomeKind.upgradedToVerified,
        );

        final monthKey =
            '${t0.year.toString().padLeft(4, '0')}-${t0.month.toString().padLeft(2, '0')}';
        final allTxs =
            (await txRepo
                        .watchTransactions(userId: minh.id, monthKey: monthKey)
                        .first
                    as Success<List<TransactionEntity>>)
                .value;
        final hondaTxs = allTxs.where((t) => t.amountMinor == 180000).toList();
        expect(hondaTxs.length, 1); // Upgraded in-place — ZERO duplicate!
        expect(hondaTxs.first.verification, TransactionVerification.verified);

        // 4. Family / Roommates Space, Shared Bill Splitting, Debt Simplification, Shared Fund, Private Event Isolation, Recurring Task & Vehicle Smart Suggestion
        final fam =
            (await familyRepo.createFamily(
                      userId: minh.id,
                      userName: minh.fullName,
                      familyName: 'Tổ ấm Minh & Lan',
                      spaceType: CollaborationSpaceType.family,
                    )
                    as Success<FamilyEntity>)
                .value;
        expect(fam.spaceType, CollaborationSpaceType.family);

        final invCode =
            (await familyRepo.createInviteCode(
                      userId: minh.id,
                      familyId: fam.id,
                      familyName: fam.name,
                    )
                    as Success<String>)
                .value;
        await fakeFirestore.collection('users').doc('user_lan').set({
          'id': 'user_lan',
          'email': 'lan@lifeos.vn',
          'fullName': 'Trần Lan',
        });
        final joinedFam =
            (await familyRepo.joinFamilyByInvite(
                      userId: 'user_lan',
                      userName: 'Trần Lan',
                      inviteCode: invCode,
                    )
                    as Success<FamilyEntity>)
                .value;
        expect(joinedFam.members.length, 2);

        // Split shared bill: Minh pays 400,000 VND for Ăn uống + Việc nhà (60% Minh = 240k, 40% Lan = 160k)
        await familyRepo.createSharedBillSplit(
          familyId: fam.id,
          title: 'Đi chợ nấu ăn & Nước rửa chén',
          topic: SharedExpenseTopic.housework,
          paidByUserId: minh.id,
          paidByName: minh.fullName,
          totalAmountMinor: 400000,
          splitMethod: SplitMethod.percentage,
          sharesByUserId: {minh.id: 240000, 'user_lan': 160000},
          participantNames: {minh.id: minh.fullName, 'user_lan': 'Trần Lan'},
          choreOrTaskNote: 'Trực bếp cuối tuần',
        );
        final billsNow =
            (await familyRepo.watchSharedBills(fam.id).first
                    as Success<List<SharedBillSplitEntity>>)
                .value;
        expect(billsNow.single.totalAmountMinor, 400000);

        // Multi-category Split Transaction in Minh's personal ledger -> updates 2 separate category budgets!
        await budgetRepo.upsertBudget(
          userId: minh.id,
          categoryId: 'cat_food',
          categoryName: 'Ăn uống',
          monthKey: monthKey,
          limitMinor: 3000000,
        );
        await budgetRepo.upsertBudget(
          userId: minh.id,
          categoryId: 'cat_housework',
          categoryName: 'Việc nhà & Gia dụng',
          monthKey: monthKey,
          limitMinor: 1000000,
        );
        await txRepo.createTransaction(
          operationId: 'op_split_supermarket',
          userId: minh.id,
          walletId: bankWallet.id,
          categoryName: 'Ăn uống (+1 khoản)',
          kind: TransactionKind.expense,
          amountMinor: 500000,
          merchant: 'Siêu thị Aeon',
          occurredAt: t0,
          splitLines: const [
            TransactionSplitLine(categoryName: 'Ăn uống', amountMinor: 320000),
            TransactionSplitLine(
              categoryName: 'Việc nhà & Gia dụng',
              amountMinor: 180000,
            ),
          ],
        );
        final budgetsAfterSplit =
            (await budgetRepo
                        .watchBudgets(userId: minh.id, monthKey: monthKey)
                        .first
                    as Success<List<BudgetEntity>>)
                .value;
        expect(
          budgetsAfterSplit
              .firstWhere((b) => b.categoryName == 'Ăn uống')
              .spentMinor,
          320000,
        );
        expect(
          budgetsAfterSplit
              .firstWhere((b) => b.categoryName == 'Việc nhà & Gia dụng')
              .spentMinor,
          180000,
        );

        await budgetRepo.createFund(
          userId: minh.id,
          familyId: fam.id,
          scope: FundScope.family,
          name: 'Quỹ Sắm Tết',
          targetAmountMinor: 10000000,
        );
        final funds =
            (await budgetRepo
                        .watchFunds(userId: minh.id, familyId: fam.id)
                        .first
                    as Success<List<FundEntity>>)
                .value;
        expect(funds.any((f) => f.id == 'fund_emergency_default'), isTrue);
        final tetFund = funds.firstWhere((f) => f.name == 'Quỹ Sắm Tết');

        await budgetRepo.contributeToFund(
          userId: minh.id,
          userName: minh.fullName,
          scope: FundScope.family,
          familyId: fam.id,
          fundId: tetFund.id,
          amountMinor: 2000000,
          note: 'Góp đợt 1',
        );
        final updatedFunds =
            (await budgetRepo
                        .watchFunds(userId: minh.id, familyId: fam.id)
                        .first
                    as Success<List<FundEntity>>)
                .value;
        expect(
          updatedFunds.firstWhere((f) => f.id == tetFund.id).balanceMinor,
          2000000,
        );

        // Create Private Calendar Event + Vehicle + Recurring Task
        await calRepo.createEvent(
          userId: minh.id,
          userName: minh.fullName,
          familyId: fam.id,
          visibility: CalendarEventVisibility.privateEvent,
          title: 'Lịch riêng tư của Minh',
          startsAt: DateTime.now().add(const Duration(hours: 2)),
          endsAt: DateTime.now().add(const Duration(hours: 3)),
          publishBusySlot: false,
        );

        await vehRepo.createVehicle(
          userId: minh.id,
          familyId: fam.id,
          isFamilyShared: true,
          name: 'Honda AirBlade',
          plateNumber: '59A-888.99',
          currentOdometerKm: 12000,
          serviceIntervalKm: 3000,
          serviceIntervalDays: 90,
        );

        final createdTask =
            (await taskRepo.createTask(
                      createdBy: minh.id,
                      creatorName: minh.fullName,
                      familyId: fam.id,
                      assigneeId: minh.id,
                      assigneeName: minh.fullName,
                      title: 'Đổ rác tối thứ 4',
                      dueAt: DateTime.now().add(const Duration(days: 1)),
                      priority: TaskPriorityLevel.medium,
                      recurrence: TaskRecurrence.weekly,
                    )
                    as Success<TaskEntity>)
                .value;

        await taskRepo.updateTaskStatus(
          actorUserId: minh.id,
          task: createdTask,
          nextStatus: TaskWorkflowStatus.done,
        );
        final tasksAfterDone =
            (await taskRepo.watchTasks(userId: minh.id, familyId: fam.id).first
                    as Success<List<TaskEntity>>)
                .value;
        // Original marked done + 1 new weekly recurring occurrence spawned!
        expect(tasksAfterDone.length, 2);

        // Dashboard aggregates smart suggestion from the 180k Honda oil change + 500k split supermarket = 680k
        final dash =
            (await dashRepo
                        .watchTodayDashboard(userId: minh.id, familyId: fam.id)
                        .first
                    as Success<TodayDashboardEntity>)
                .value;
        expect(dash.monthlyExpenseMinor, 680000);
        expect(dash.highlights.any((h) => h.category == 'smart_rule'), isTrue);

        // Export Personal Data JSON (PDPL 91/2025 compliance)
        final exportRes = await notifRepo.exportPersonalDataJson(minh.id);
        expect(exportRes.isSuccess, isTrue);
        expect(
          (exportRes as Success<String>).value,
          contains('minh@lifeos.vn'),
        );

        // 5. Idempotent CSV Bank Statement Import (importing same CSV twice imports ONLY ONCE!)
        const sampleCsv =
            'date,direction,amount,description\n'
            '2026-11-22,debit,95000,Bách Hóa Xanh\n'
            '2026-11-22,debit,500000,Ma OTP la 123456 khong nhap';
        final csvRun1 = await notifRepo.importCsvStatement(
          userId: minh.id,
          walletId: bankWallet.id,
          csvContent: sampleCsv,
        );
        expect(
          (csvRun1 as Success<int>).value,
          1,
        ); // OTP line dropped, valid line imported!

        final csvRun2 = await notifRepo.importCsvStatement(
          userId: minh.id,
          walletId: bankWallet.id,
          csvContent: sampleCsv,
        );
        expect(
          (csvRun2 as Success<int>).value,
          0,
        ); // Duplicate CSV import safely ignored!

        // 6. Self-Service Account & Personal Data Deletion (PDPL 91/2025 + AUD-007 Owner Guard)
        // 6a. Deleting while still owner of a multi-member family MUST be blocked safely first!
        final blockedDelete = await notifRepo.deleteAccountAndPersonalData(
          minh.id,
        );
        expect(blockedDelete, isA<Err<void>>());
        expect(
          (blockedDelete as Err<void>).failure.code,
          'FAMILY_OWNER_TRANSFER_REQUIRED',
        );

        // 6b. After removing other members so owner can safely disband, deletion succeeds cleanly!
        await familyRepo.removeMember(
          familyId: fam.id,
          actorUserId: minh.id,
          targetUserId: 'user_lan',
        );
        final deleteRes = await notifRepo.deleteAccountAndPersonalData(minh.id);
        expect(deleteRes.isSuccess, isTrue);
        final deletedUserSnap = await fakeFirestore
            .collection('users')
            .doc(minh.id)
            .get();
        expect(deletedUserSnap.exists, isFalse);
      },
    );
  });
}
