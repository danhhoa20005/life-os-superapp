import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/core/security/bank_notification_parser.dart';
import 'package:life_os/core/services/file_storage_service.dart';
import 'package:life_os/core/utils/smart_quick_entry_parser.dart';
import 'package:life_os/core/utils/vnd_amount.dart';
import 'package:life_os/features/app_update/domain/entities/app_update_entities.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/tasks/domain/entities/task_entities.dart';
import 'package:life_os/features/tasks/domain/repositories/task_repository.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';
import 'package:mocktail/mocktail.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

void main() {
  group('Domain Money, Personal Finance Analytics, Income Allocator & Group/Family Bill Splitting', () {
    test('VndAmount parses Vietnamese currency formats into exact integer minor units', () {
      expect(VndAmount.tryParseInput('-85.000đ'), 85000);
      expect(VndAmount.tryParseInput('+1,500,000.00 VND'), 1500000);
      expect(VndAmount.tryParseInput('540.000 VNĐ'), 540000);
      expect(VndAmount.format(1250000), '1.250.000 ₫');
      expect(() => VndAmount.positiveFromMinor(0), throwsA(isA<ValidationFailure>()));
      expect(() => VndAmount.positiveFromMinor(-100), throwsA(isA<ValidationFailure>()));
    });

    test('FinanceOverviewSummary handles multi-category Split Transactions (Ăn uống + Việc nhà), savings rate & excludes transfers/reversals', () {
      final wallets = [
        const WalletEntity(
          id: 'w_bank',
          ownerId: 'u1',
          name: 'VCB',
          type: WalletType.bank,
          balanceMinor: 8500000,
        ),
        const WalletEntity(
          id: 'w_cash',
          ownerId: 'u1',
          name: 'Tiền mặt',
          type: WalletType.cash,
          balanceMinor: 1000000,
        ),
      ];

      final now = DateTime.utc(2026, 11, 22);
      final txs = [
        TransactionEntity(
          id: 't_inc',
          ownerId: 'u1',
          walletId: 'w_bank',
          categoryName: 'Lương & Thu nhập',
          kind: TransactionKind.income,
          direction: 'credit',
          amountMinor: 10000000,
          merchant: 'Lương tháng 11',
          occurredAt: now,
          monthKey: '2026-11',
          sourceKind: TransactionSourceKind.bankApi,
          verification: TransactionVerification.verified,
          crossSourceFingerprint: 'fp1',
        ),
        // Split supermarket receipt: 500,000 VND = 320,000 Ăn uống + 180,000 Việc nhà & Gia dụng
        TransactionEntity(
          id: 't_exp_split',
          ownerId: 'u1',
          walletId: 'w_bank',
          categoryName: 'Ăn uống (+1 khoản)',
          kind: TransactionKind.expense,
          direction: 'debit',
          amountMinor: 500000,
          merchant: 'Siêu thị Co.opmart',
          occurredAt: now,
          monthKey: '2026-11',
          sourceKind: TransactionSourceKind.manual,
          verification: TransactionVerification.userConfirmed,
          crossSourceFingerprint: 'fp2',
          splitLines: const [
            TransactionSplitLine(categoryName: 'Ăn uống', amountMinor: 320000),
            TransactionSplitLine(categoryName: 'Việc nhà & Gia dụng', amountMinor: 180000),
          ],
        ),
        // Internal transfer (1,000,000 VND Bank -> Cash) MUST NOT count as expense!
        TransactionEntity(
          id: 't_trf',
          ownerId: 'u1',
          walletId: 'w_bank',
          targetWalletId: 'w_cash',
          categoryName: 'Chuyển khoản nội bộ',
          kind: TransactionKind.transfer,
          direction: 'debit',
          amountMinor: 1000000,
          merchant: 'Rút tiền ATM',
          occurredAt: now,
          monthKey: '2026-11',
          sourceKind: TransactionSourceKind.manual,
          verification: TransactionVerification.userConfirmed,
          crossSourceFingerprint: 'fp3',
        ),
        // Provisional bank notification MUST NOT count until confirmed!
        TransactionEntity(
          id: 't_prov',
          ownerId: 'u1',
          walletId: 'w_bank',
          categoryName: 'Ăn uống',
          kind: TransactionKind.expense,
          direction: 'debit',
          amountMinor: 85000,
          merchant: 'Phở',
          occurredAt: now,
          monthKey: '2026-11',
          sourceKind: TransactionSourceKind.androidNotification,
          verification: TransactionVerification.provisional,
          crossSourceFingerprint: 'fp4',
        ),
        // Reversed expense MUST NOT count!
        TransactionEntity(
          id: 't_rev_orig',
          ownerId: 'u1',
          walletId: 'w_bank',
          categoryName: 'Mua sắm',
          kind: TransactionKind.expense,
          direction: 'debit',
          amountMinor: 300000,
          merchant: 'Đơn hoàn tiền',
          occurredAt: now,
          monthKey: '2026-11',
          sourceKind: TransactionSourceKind.manual,
          verification: TransactionVerification.userConfirmed,
          crossSourceFingerprint: 'fp5',
          reversedById: 'rev_t_rev_orig',
        ),
      ];

      final summary = FinanceOverviewSummary.compute(wallets: wallets, transactions: txs);
      expect(summary.netWorthMinor, 9500000);
      expect(summary.monthlyIncomeMinor, 10000000);
      expect(summary.monthlyExpenseMinor, 500000);
      expect(summary.monthlyInternalTransferMinor, 1000000);
      expect(summary.provisionalCount, 1);
      expect(summary.verifiedCount, 1);
      expect(summary.userConfirmedCount, 2); // split expense + internal transfer
      expect(summary.netCashFlowMinor, 9500000);
      expect(summary.savingsRatePct, closeTo(95.0, 0.001));
      expect(summary.expenseByCategory['Ăn uống'], 320000);
      expect(summary.expenseByCategory['Việc nhà & Gia dụng'], 180000);
      expect(summary.sortedCategoryShares.first.categoryName, 'Ăn uống');
      expect(summary.sortedCategoryShares.first.sharePct, closeTo(64.0, 0.001));
    });

    test('IncomeAllocationEngine distributes odd VND income across Personal, Family & Roommates presets with ZERO rounding loss', () {
      const oddIncome = 20000003; // Prime/odd VND amount
      for (final preset in AllocationPreset.values) {
        final plan = IncomeAllocationEngine.allocate(
          totalIncomeMinor: oddIncome,
          preset: preset,
        );
        expect(plan.allocatedTotalMinor, oddIncome);
        expect(plan.buckets.any((b) => b.categoryName.contains('Ăn uống')), isTrue);
        expect(plan.buckets.any((b) => b.categoryName.contains('Việc nhà')), isTrue);
      }
    });

    test('SplitBillCalculator & DebtSimplifier solve 3-person Roommate/Family cycle with exact 1-VND remainder & SEVQR transfer codes', () {
      // 1. Equal split with odd VND remainder: 100,000 / 3 = 33,334 (payer) + 33,333 + 33,333
      final equalOdd = SplitBillCalculator.computeEqualSplit(
        totalAmountMinor: 100000,
        participantIds: const ['chi', 'an', 'binh'],
        payerUserId: 'binh',
      );
      expect(equalOdd['binh'], 33334);
      expect(equalOdd['an'], 33333);
      expect(equalOdd['chi'], 33333);
      expect(equalOdd.values.fold<int>(0, (s, v) => s + v), 100000);

      // 2. Weighted / Shares split (3 : 2 : 1 on 100,000 VND)
      final shareSplit = SplitBillCalculator.computeWeightedSplit(
        totalAmountMinor: 100000,
        weightsByUserId: const {'an': 3, 'binh': 2, 'chi': 1},
      );
      expect(shareSplit.values.fold<int>(0, (s, v) => s + v), 100000);
      expect(shareSplit['an'], 50000);
      expect(shareSplit['binh'], 33333);
      expect(shareSplit['chi'], 16667);

      // 3. Multi-party DebtSimplifier cycle:
      // An pays 300k Housework, Bình pays 600k Utilities, Chi pays 150k Dining (each split equally = 350k/person)
      final members = const [
        FamilyMemberInfo(userId: 'an', fullName: 'An', role: HouseholdRole.owner),
        FamilyMemberInfo(userId: 'binh', fullName: 'Bình', role: HouseholdRole.member),
        FamilyMemberInfo(userId: 'chi', fullName: 'Chi', role: HouseholdRole.member),
      ];
      final names = const {'an': 'An', 'binh': 'Bình', 'chi': 'Chi'};
      final now = DateTime.utc(2026, 11, 22);

      final bills = [
        SharedBillSplitEntity(
          id: 'b1',
          familyId: 'fam_room',
          title: 'Dọn dẹp & Nước giặt',
          topic: SharedExpenseTopic.housework,
          paidByUserId: 'an',
          paidByName: 'An',
          totalAmountMinor: 300000,
          splitMethod: SplitMethod.equal,
          sharesByUserId: const {'an': 100000, 'binh': 100000, 'chi': 100000},
          participantNames: names,
          createdAt: now,
        ),
        SharedBillSplitEntity(
          id: 'b2',
          familyId: 'fam_room',
          title: 'Điện nước Internet tháng 11',
          topic: SharedExpenseTopic.utilities,
          paidByUserId: 'binh',
          paidByName: 'Bình',
          totalAmountMinor: 600000,
          splitMethod: SplitMethod.equal,
          sharesByUserId: const {'an': 200000, 'binh': 200000, 'chi': 200000},
          participantNames: names,
          createdAt: now,
        ),
        SharedBillSplitEntity(
          id: 'b3',
          familyId: 'fam_room',
          title: 'Ăn bún chả chung',
          topic: SharedExpenseTopic.dining,
          paidByUserId: 'chi',
          paidByName: 'Chi',
          totalAmountMinor: 150000,
          splitMethod: SplitMethod.equal,
          sharesByUserId: const {'an': 50000, 'binh': 50000, 'chi': 50000},
          participantNames: names,
          createdAt: now,
        ),
      ];

      final summaryBefore = DebtSimplifier.summarize(
        familyId: 'fam_room',
        members: members,
        bills: bills,
        settlements: const [],
      );
      // Mathematical zero-sum invariant across all members
      expect(
        summaryBefore.memberBalances.fold<int>(0, (s, m) => s + m.netBalanceMinor),
        0,
      );
      expect(summaryBefore.totalSharedSpendMinor, 1050000);
      // Reduced to minimum 2 transfers: Chi -> Bình (200k) and An -> Bình (50k)
      expect(summaryBefore.suggestedTransfers.length, 2);
      expect(summaryBefore.suggestedTransfers.first.fromUserId, 'chi');
      expect(summaryBefore.suggestedTransfers.first.toUserId, 'binh');
      expect(summaryBefore.suggestedTransfers.first.amountMinor, 200000);
      expect(
        summaryBefore.suggestedTransfers.first.sePayTransferCode,
        startsWith('SEVQR LIFEOS SPLIT'),
      );

      // Chi settles 200,000 VND to Bình -> Only An -> Bình (50,000 VND) remains!
      final summaryAfter = DebtSimplifier.summarize(
        familyId: 'fam_room',
        members: members,
        bills: bills,
        settlements: [
          DebtSettlementEntity(
            id: 'st_1',
            familyId: 'fam_room',
            fromUserId: 'chi',
            fromUserName: 'Chi',
            toUserId: 'binh',
            toUserName: 'Bình',
            amountMinor: 200000,
            paymentCode: summaryBefore.suggestedTransfers.first.sePayTransferCode,
            createdAt: now,
          ),
        ],
      );
      expect(summaryAfter.suggestedTransfers.length, 1);
      expect(summaryAfter.suggestedTransfers.single.fromUserId, 'an');
      expect(summaryAfter.suggestedTransfers.single.toUserId, 'binh');
      expect(summaryAfter.suggestedTransfers.single.amountMinor, 50000);
    });

    test('OTP Redactor & BankNotificationParser block OTPs, detect housework, respect T15 accumulated=0, and keep distinct refs (T06)', () {
      final otpOutcome = BankNotificationParser.parseAndroidNotification(
        ownerId: 'u1',
        packageName: 'com.VCB',
        title: 'Vietcombank SmartOTP',
        body: 'Ma OTP xac thuc giao dich cua Quy khach la 839201. Khong chia se ma nay.',
      );
      expect(otpOutcome.dropReason, BankSignalDropReason.otpOrSecret);
      expect(otpOutcome.signal, isNull);

      expect(
        BankNotificationParser.safeObservedBalanceFromIpn(
          accumulated: 0,
          bankSupportsBalance: false,
        ),
        isNull,
      );
      expect(
        BankNotificationParser.safeObservedBalanceFromIpn(
          accumulated: 0,
          bankSupportsBalance: true,
        ),
        isNull,
      );

      final t1 = DateTime.utc(2026, 11, 22, 10, 1, 0);
      final fpA = BankNotificationParser.computeCrossSourceFingerprint(
        ownerId: 'u1',
        direction: 'debit',
        amountMinor: 120000,
        occurredAt: t1,
        referenceCode: 'FT_REF_001',
      );
      final fpB = BankNotificationParser.computeCrossSourceFingerprint(
        ownerId: 'u1',
        direction: 'debit',
        amountMinor: 120000,
        occurredAt: t1.add(const Duration(seconds: 25)),
        referenceCode: 'FT_REF_002',
      );
      expect(fpA, isNot(equals(fpB)));

      final houseworkNotif = BankNotificationParser.parseAndroidNotification(
        ownerId: 'u1',
        packageName: 'com.VCB',
        title: 'VCB Digibank',
        body: 'TK 102***88 GD: -160.000VND. ND: Thanh toan bTaskee don dep nha',
        postedAt: t1,
      );
      expect(houseworkNotif.signal?.categorySuggestion, 'Việc nhà & Gia dụng');

      final validVeh = BankNotificationParser.parseAndroidNotification(
        ownerId: 'u1',
        packageName: 'com.mbmobile',
        title: 'Biến động số dư MBBank',
        body: 'TK 098***11 GD: -180.000VND. ND: Thay nhot xe tai HEAD Honda',
        postedAt: t1,
      );
      expect(validVeh.signal, isNotNull);
      expect(validVeh.signal!.amountMinor, 180000);
      expect(validVeh.signal!.isVehicleMaintenanceHint, isTrue);
    });

    test('Vehicle due calculation min(km, days), plate masking & task recipient-only acceptance', () async {
      final serviceDate = DateTime.utc(2026, 11, 1);
      final veh = VehicleEntity(
        id: 'v1',
        ownerId: 'owner_1',
        familyId: 'fam_1',
        isFamilyShared: true,
        name: 'Honda AirBlade',
        plateNumber: '59A-123.45',
        currentOdometerKm: 12850,
        lastServiceOdometerKm: 10000,
        lastServiceDate: serviceDate,
        serviceIntervalKm: 3000,
        serviceIntervalDays: 90,
      );

      expect(veh.displayPlateForViewer('owner_1'), '59A-123.45');
      expect(veh.displayPlateForViewer('member_2'), '59A-***45');
      expect(veh.dueStateAt(DateTime.utc(2026, 11, 22)), VehicleDueState.dueSoon);

      final bill = RecurringBillEntity(
        id: 'b1',
        ownerId: 'owner_1',
        title: 'Tiền điện EVN',
        providerName: 'EVN',
        estimatedAmountMinor: 500000,
        nextDueDate: DateTime.utc(2026, 12, 5),
        averagePaidMinor: 500000,
        lastPaidAmountMinor: 680000,
        paymentCount: 3,
      );
      expect(bill.hasAbnormalSpike, isTrue);

      final mockTaskRepo = _MockTaskRepository();
      final respondUseCase = RespondToTaskUseCase(mockTaskRepo);
      const task = TaskEntity(
        id: 'task_1',
        familyId: 'fam_1',
        createdBy: 'dad_id',
        creatorName: 'Bố',
        assigneeId: 'child_id',
        assigneeName: 'Con',
        title: 'Mua nước uống trước 18h',
        status: TaskWorkflowStatus.proposed,
      );

      final unauthorized = await respondUseCase(
        const RespondToTaskParams(
          actorUserId: 'dad_id',
          task: task,
          accept: true,
        ),
      );
      expect(unauthorized, isA<Err<void>>());
      expect((unauthorized as Err<void>).failure, isA<PermissionDeniedFailure>());

      // PHẦN 11: SparkSafeFileStorageService keeps Cloud Storage disabled (Spark 0 VND) while storing locally
      const storage = SparkSafeFileStorageService();
      expect(storage.isCloudObjectStorageEnabled, isFalse);
      expect(storage.isLocalDeviceVaultEnabled, isTrue);
      final uploadAttempt = await storage.uploadUserAttachment(
        userId: 'owner_1',
        folder: 'receipts',
        fileName: 'bill.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );
      expect(uploadAttempt, isA<Success<StoredFileReference>>());
      await storage.deleteUserAttachment(
        userId: 'owner_1',
        storageKey: (uploadAttempt as Success<StoredFileReference>).value.storageKey,
      );
    });

    test('SemanticAppVersion, SmartQuickEntryParser & EmergencyRunwaySnapshot work deterministically', () {
      final v100 = SemanticAppVersion.parse('1.0.0+1');
      final v110 = SemanticAppVersion.parse('v1.1.0+2');
      final v200 = SemanticAppVersion.parse('2.0.0+1');

      expect(v110.isNewerThan(v100), isTrue);
      expect(v100.isNewerThan(v110), isFalse);
      expect(v100.isOlderThanCore(v200), isTrue);

      final pho = SmartQuickEntryParser.tryParse('ăn phở bò 65k')!;
      expect(pho.amountMinor, 65000);
      expect(pho.kind, TransactionKind.expense);
      expect(pho.categoryName, 'Ăn uống');

      final salary = SmartQuickEntryParser.tryParse('nhận lương tháng 11 18tr5')!;
      expect(salary.amountMinor, 18500000);
      expect(salary.kind, TransactionKind.income);
      expect(salary.categoryName, 'Lương & Thu nhập');

      final electric = SmartQuickEntryParser.tryParse('tiền điện 850k')!;
      expect(electric.amountMinor, 850000);
      expect(electric.categoryName, 'Điện/Nước/Internet');

      final runway = EmergencyRunwaySnapshot.compute(
        netLiquidMinor: 48000000,
        monthlyExpenseMinor: 8000000,
      );
      expect(runway.monthsOfRunway, closeTo(6.0, 0.001));
      expect(runway.shortfallMinor, 0);
    });
  });
}
