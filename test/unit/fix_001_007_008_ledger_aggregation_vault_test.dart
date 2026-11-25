import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/core/services/file_storage_service.dart';
import 'package:life_os/core/services/native_secure_vault_bridge.dart';
import 'package:life_os/features/budgets/data/repositories/budget_repository_impl.dart';
import 'package:life_os/features/calendar/domain/entities/calendar_entities.dart';
import 'package:life_os/features/calendar/domain/repositories/calendar_repository.dart';
import 'package:life_os/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:life_os/features/dashboard/domain/entities/dashboard_entities.dart';
import 'package:life_os/features/documents/data/repositories/document_vault_repository_impl.dart';
import 'package:life_os/features/documents/domain/entities/document_vault_entity.dart';
import 'package:life_os/features/documents/domain/repositories/document_vault_repository.dart';
import 'package:life_os/features/tasks/domain/entities/task_entities.dart';
import 'package:life_os/features/tasks/domain/repositories/task_repository.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';
import 'package:life_os/features/transactions/data/models/transaction_models.dart';
import 'package:life_os/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:life_os/features/transactions/domain/entities/financial_aggregation_engine.dart';
import 'package:life_os/features/transactions/domain/entities/ledger_integrity_engine.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';
import 'package:life_os/features/vehicles/domain/repositories/vehicle_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockTransactionRepository extends Mock
    implements TransactionRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockCalendarRepository extends Mock implements CalendarRepository {}

class _MockVehicleRepository extends Mock implements VehicleRepository {}

TransactionEntity _makeTx({
  required String id,
  required int amountMinor,
  required TransactionKind kind,
  required DateTime occurredAt,
  TransactionVerification verification = TransactionVerification.userConfirmed,
  String categoryName = 'Ăn uống',
  String walletId = 'w_main',
  String? targetWalletId,
  String? note,
  String? reversedById,
  String? reversalOfId,
  String? verificationStatus,
  bool isRefund = false,
  List<TransactionSplitLine> splitLines = const [],
}) {
  final monthKey =
      '${occurredAt.year.toString().padLeft(4, '0')}-${occurredAt.month.toString().padLeft(2, '0')}';
  final direction = (kind == TransactionKind.income) ? 'credit' : 'debit';
  return TransactionEntity(
    id: id,
    ownerId: 'u_test',
    walletId: walletId,
    targetWalletId: targetWalletId,
    categoryName: categoryName,
    kind: kind,
    direction: direction,
    amountMinor: amountMinor,
    merchant: 'Merchant $id',
    note: note,
    occurredAt: occurredAt,
    monthKey: monthKey,
    sourceKind: TransactionSourceKind.manual,
    verification: verification,
    verificationStatus: verificationStatus,
    crossSourceFingerprint: 'fp_$id',
    reversedById: reversedById,
    reversalOfId: reversalOfId,
    isRefund: isRefund,
    splitLines: splitLines,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const FinanceOverviewSummary(
        netWorthMinor: 0,
        monthlyIncomeMinor: 0,
        monthlyExpenseMinor: 0,
        monthlyInternalTransferMinor: 0,
        provisionalCount: 0,
        expenseByCategory: {},
      ),
    );
    registerFallbackValue(
      const FinancialAggregationResult(
        incomeMinor: 0,
        grossExpenseMinor: 0,
        internalTransferMinor: 0,
        expenseByCategory: {},
      ),
    );
  });

  group('FIX-001: FinancialAggregationEngine, Unbounded Streams & Dashboard', () {
    test(
      'Scale invariance across 100, 101, 500, 1,000 and 10,000 transactions matches exact 1-VND ledger ground truth',
      () {
        final anchor = DateTime(2026, 11, 15, 10, 0);
        for (final count in [100, 101, 500, 1000, 10000]) {
          final txs = <TransactionEntity>[];
          var expectedIncome = 0;
          var expectedGrossExpense = 0;
          var expectedRefund = 0;
          var expectedTransfer = 0;
          var expectedUnconfirmedCount = 0;
          var expectedProvisionalAmount = 0;
          final expectedByCategory = <String, int>{};

          for (var i = 0; i < count; i++) {
            final amt = 1000 + (i * 137) % 97531;
            final dayOffset = i % 25;
            final occurredAt = DateTime(2026, 11, 1 + dayOffset, 9, i % 60);
            final mod = i % 10;

            if (mod == 0 || mod == 1 || mod == 2) {
              // Confirmed expenses across 3 verifications + splitLines
              final ver = mod == 0
                  ? TransactionVerification.userConfirmed
                  : mod == 1
                  ? TransactionVerification.verified
                  : TransactionVerification.matchedPaymentOrder;
              if (i % 20 == 0 && amt >= 1000) {
                final partA = amt ~/ 3;
                final partB = amt - partA;
                txs.add(
                  _makeTx(
                    id: 'tx_$i',
                    amountMinor: amt,
                    kind: TransactionKind.expense,
                    occurredAt: occurredAt,
                    verification: ver,
                    categoryName: 'Ăn uống (+1 khoản)',
                    splitLines: [
                      TransactionSplitLine(
                        categoryName: 'Ăn uống',
                        amountMinor: partA,
                      ),
                      TransactionSplitLine(
                        categoryName: 'Di chuyển',
                        amountMinor: partB,
                      ),
                    ],
                  ),
                );
                expectedByCategory['Ăn uống'] =
                    (expectedByCategory['Ăn uống'] ?? 0) + partA;
                expectedByCategory['Di chuyển'] =
                    (expectedByCategory['Di chuyển'] ?? 0) + partB;
              } else {
                txs.add(
                  _makeTx(
                    id: 'tx_$i',
                    amountMinor: amt,
                    kind: TransactionKind.expense,
                    occurredAt: occurredAt,
                    verification: ver,
                    categoryName: 'Mua sắm',
                  ),
                );
                expectedByCategory['Mua sắm'] =
                    (expectedByCategory['Mua sắm'] ?? 0) + amt;
              }
              expectedGrossExpense += amt;
            } else if (mod == 3) {
              // Confirmed salary/regular income
              txs.add(
                _makeTx(
                  id: 'tx_$i',
                  amountMinor: amt,
                  kind: TransactionKind.income,
                  occurredAt: occurredAt,
                  verification: TransactionVerification.verified,
                  categoryName: 'Lương & Thu nhập',
                ),
              );
              expectedIncome += amt;
            } else if (mod == 4) {
              // Refund (isRefund / note)
              txs.add(
                _makeTx(
                  id: 'tx_$i',
                  amountMinor: amt,
                  kind: TransactionKind.income,
                  occurredAt: occurredAt,
                  verification: TransactionVerification.userConfirmed,
                  categoryName: 'Hoàn tiền mua sắm',
                  note: i.isEven ? 'Hoàn tiền đơn hàng' : null,
                  isRefund: i.isOdd,
                ),
              );
              expectedRefund += amt;
            } else if (mod == 5) {
              // Internal transfer or creditCardPayment — NEVER income/expense
              final kind = i.isEven
                  ? TransactionKind.transfer
                  : TransactionKind.creditCardPayment;
              txs.add(
                _makeTx(
                  id: 'tx_$i',
                  amountMinor: amt,
                  kind: kind,
                  occurredAt: occurredAt,
                  targetWalletId: 'w_savings',
                  categoryName: 'Chuyển nội bộ',
                ),
              );
              expectedTransfer += amt;
            } else if (mod == 6) {
              // Reversed original + reversal entry — must cancel to 0!
              final revId = 'rev_tx_$i';
              txs.add(
                _makeTx(
                  id: 'tx_$i',
                  amountMinor: amt,
                  kind: TransactionKind.expense,
                  occurredAt: occurredAt,
                  reversedById: revId,
                  verificationStatus: 'REVERSED',
                ),
              );
              if (i + 1 < count) {
                txs.add(
                  _makeTx(
                    id: revId,
                    amountMinor: amt,
                    kind: TransactionKind.reversal,
                    occurredAt: occurredAt,
                    reversalOfId: 'tx_$i',
                  ),
                );
              }
            } else if (mod == 7) {
              // Provisional or needsReview — unconfirmed only!
              final ver = i.isEven
                  ? TransactionVerification.provisional
                  : TransactionVerification.needsReview;
              txs.add(
                _makeTx(
                  id: 'tx_$i',
                  amountMinor: amt,
                  kind: TransactionKind.expense,
                  occurredAt: occurredAt,
                  verification: ver,
                ),
              );
              expectedUnconfirmedCount += 1;
              expectedProvisionalAmount += amt;
            } else if (mod == 8) {
              // Rejected — completely ignored
              txs.add(
                _makeTx(
                  id: 'tx_$i',
                  amountMinor: amt,
                  kind: TransactionKind.income,
                  occurredAt: occurredAt,
                  verification: TransactionVerification.rejected,
                ),
              );
            } else {
              // Matched payment order expense
              txs.add(
                _makeTx(
                  id: 'tx_$i',
                  amountMinor: amt,
                  kind: TransactionKind.expense,
                  occurredAt: occurredAt,
                  verification: TransactionVerification.matchedPaymentOrder,
                  categoryName: 'Hóa đơn',
                ),
              );
              expectedGrossExpense += amt;
              expectedByCategory['Hóa đơn'] =
                  (expectedByCategory['Hóa đơn'] ?? 0) + amt;
            }
          }

          final result = FinancialAggregationEngine.forMonth(
            txs,
            anchor.year,
            anchor.month,
          );
          expect(
            result.incomeMinor,
            expectedIncome,
            reason: 'Income mismatch at N=$count',
          );
          expect(
            result.grossExpenseMinor,
            expectedGrossExpense,
            reason: 'Gross expense mismatch at N=$count',
          );
          expect(
            result.refundMinor,
            expectedRefund,
            reason: 'Refund mismatch at N=$count',
          );
          expect(
            result.netExpenseMinor,
            expectedGrossExpense - expectedRefund,
            reason: 'Net expense mismatch at N=$count',
          );
          expect(
            result.internalTransferMinor,
            expectedTransfer,
            reason: 'Internal transfer mismatch at N=$count',
          );
          expect(
            result.unconfirmedCount,
            expectedUnconfirmedCount,
            reason: 'Unconfirmed count mismatch at N=$count',
          );
          expect(
            result.provisionalAmountMinor,
            expectedProvisionalAmount,
            reason: 'Provisional amount mismatch at N=$count',
          );
          expect(
            result.expenseByCategory,
            expectedByCategory,
            reason: 'Category split mismatch at N=$count',
          );
        }
      },
    );

    test(
      'forDay, forWeek, forMonth, forQuarter, forYear & forRange slice boundaries accurately',
      () {
        final txs = [
          // Q1 Jan
          _makeTx(
            id: 'jan_1',
            amountMinor: 100000,
            kind: TransactionKind.expense,
            occurredAt: DateTime(2026, 1, 10, 9),
          ),
          // Q4 Nov Week (Mon 2026-11-16 .. Sun 2026-11-22)
          _makeTx(
            id: 'nov_16',
            amountMinor: 250000,
            kind: TransactionKind.expense,
            occurredAt: DateTime(2026, 11, 16, 8),
          ),
          _makeTx(
            id: 'nov_18',
            amountMinor: 5000000,
            kind: TransactionKind.income,
            occurredAt: DateTime(2026, 11, 18, 12),
          ),
          _makeTx(
            id: 'nov_23',
            amountMinor: 90000,
            kind: TransactionKind.expense,
            occurredAt: DateTime(2026, 11, 23, 0, 0),
          ),
          // Next year boundary
          _makeTx(
            id: 'next_yr',
            amountMinor: 999999,
            kind: TransactionKind.expense,
            occurredAt: DateTime(2027, 1, 1, 0, 0),
          ),
        ];

        final dayRes = FinancialAggregationEngine.forDay(
          txs,
          DateTime(2026, 11, 16),
        );
        expect(dayRes.grossExpenseMinor, 250000);
        expect(dayRes.incomeMinor, 0);

        final weekRes = FinancialAggregationEngine.forWeek(
          txs,
          DateTime(2026, 11, 18),
        );
        expect(weekRes.grossExpenseMinor, 250000);
        expect(weekRes.incomeMinor, 5000000);

        final monthRes = FinancialAggregationEngine.forMonth(txs, 2026, 11);
        expect(monthRes.grossExpenseMinor, 340000);
        expect(monthRes.incomeMinor, 5000000);

        final q4Res = FinancialAggregationEngine.forQuarter(txs, 2026, 4);
        expect(q4Res.grossExpenseMinor, 340000);
        expect(q4Res.incomeMinor, 5000000);

        final q1Res = FinancialAggregationEngine.forQuarter(txs, 2026, 1);
        expect(q1Res.grossExpenseMinor, 100000);

        final yearRes = FinancialAggregationEngine.forYear(txs, 2026);
        expect(yearRes.grossExpenseMinor, 440000);
        expect(yearRes.incomeMinor, 5000000);

        final customRes = FinancialAggregationEngine.forRange(
          txs,
          startInclusive: DateTime(2026, 11, 16),
          endExclusive: DateTime(2026, 11, 23),
        );
        expect(customRes.grossExpenseMinor, 250000);
        expect(customRes.incomeMinor, 5000000);
      },
    );

    test(
      'DashboardRepositoryImpl & TransactionRepositoryImpl aggregate 500 transactions beyond 100-limit & sync Budget matchedPaymentOrder',
      () async {
        final db = FakeFirebaseFirestore();
        const uid = 'u_agg_500';
        final now = DateTime.now();
        final monthKey =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

        await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_main')
            .set({
              'id': 'w_main',
              'ownerId': uid,
              'name': 'Ví Chính',
              'type': 'bank',
              'balanceMinor': 50000000,
            });

        // Seed 150+500 transactions (> 100 cap!):
        // First 350 are expenses of 10,000 VND each = 3,500,000 VND
        // Next 100 are matchedPaymentOrder expenses of 20,000 VND each = 2,000,000 VND
        // Next 30 are incomes of 1,000,000 VND each = 30,000,000 VND
        // Next 20 are internal transfers of 500,000 VND each = 10,000,000 VND (NOT income/expense!)
        var expectedExpense = 0;
        var expectedIncome = 0;
        var expectedFoodBudget = 0;

        for (var i = 0; i < 500; i++) {
          final docId = 'tx_${i.toString().padLeft(4, '0')}';
          final occurredAt = DateTime(now.year, now.month, 1).add(
            Duration(minutes: i * 10),
          );
          String kind = 'expense';
          String ver = 'userConfirmed';
          String cat = 'Ăn uống';
          int amt = 10000;
          String? targetWallet;

          if (i < 350) {
            amt = 10000 + (i % 5) * 1000;
            expectedExpense += amt;
            expectedFoodBudget += amt;
          } else if (i < 450) {
            ver = 'matchedPaymentOrder';
            amt = 20000;
            expectedExpense += amt;
            expectedFoodBudget += amt;
          } else if (i < 480) {
            kind = 'income';
            ver = 'verified';
            cat = 'Lương & Thu nhập';
            amt = 1000000;
            expectedIncome += amt;
          } else {
            kind = 'transfer';
            cat = 'Chuyển khoản nội bộ';
            amt = 500000;
            targetWallet = 'w_savings';
          }

          await db
              .collection('users')
              .doc(uid)
              .collection('transactions')
              .doc(docId)
              .set({
                'id': docId,
                'ownerId': uid,
                'walletId': 'w_main',
                if (targetWallet != null) 'targetWalletId': targetWallet,
                'categoryName': cat,
                'kind': kind,
                'direction': kind == 'income' ? 'credit' : 'debit',
                'amountMinor': amt,
                'currencyCode': 'VND',
                'merchant': 'M_$i',
                'occurredAt': Timestamp.fromDate(occurredAt),
                'monthKey': monthKey,
                'sourceKind': 'manual',
                'verification': ver,
                'crossSourceFingerprint': 'fp_$i',
              });
        }

        await db
            .collection('users')
            .doc(uid)
            .collection('budgets')
            .doc('${monthKey}_cat_food')
            .set({
              'id': '${monthKey}_cat_food',
              'ownerId': uid,
              'categoryId': 'cat_food',
              'categoryName': 'Ăn uống',
              'monthKey': monthKey,
              'limitMinor': 10000000,
              'alertThresholdPct': 80,
            });

        final txDs = TransactionRemoteDataSource(db);
        final txRepo = TransactionRepositoryImpl(txDs);

        // 1. UI list remains capped at 100, while aggregation stream returns all 500
        final limitedList = await txRepo
            .watchTransactions(userId: uid, monthKey: monthKey)
            .first;
        expect((limitedList as Success<List<TransactionEntity>>).value.length, 100);

        final unboundedList = await txRepo
            .watchAllTransactionsForAggregation(userId: uid, monthKey: monthKey)
            .first;
        expect(
          (unboundedList as Success<List<TransactionEntity>>).value.length,
          500,
        );

        final periodList = await txRepo
            .watchTransactionsInPeriod(
              userId: uid,
              startInclusive: DateTime(now.year, now.month, 1),
              endExclusive: DateTime(now.year, now.month + 1, 1),
            )
            .first;
        expect(
          (periodList as Success<List<TransactionEntity>>).value.length,
          500,
        );

        // 2. DashboardRepositoryImpl computes exact 500-tx totals + persists monthly_summaries
        final mockTasks = _MockTaskRepository();
        final mockCal = _MockCalendarRepository();
        final mockVeh = _MockVehicleRepository();
        when(
          () => mockTasks.watchTasks(
            userId: any(named: 'userId'),
            familyId: any(named: 'familyId'),
          ),
        ).thenAnswer((_) => Stream.value(const Success(<TaskEntity>[])));
        when(
          () => mockCal.watchEvents(
            userId: any(named: 'userId'),
            familyId: any(named: 'familyId'),
          ),
        ).thenAnswer(
          (_) => Stream.value(const Success(<CalendarEventEntity>[])),
        );
        when(
          () => mockVeh.watchVehicles(
            userId: any(named: 'userId'),
            familyId: any(named: 'familyId'),
          ),
        ).thenAnswer((_) => Stream.value(const Success(<VehicleEntity>[])));

        final dashRepo = DashboardRepositoryImpl(
          transactionRepo: txRepo,
          taskRepo: mockTasks,
          calendarRepo: mockCal,
          vehicleRepo: mockVeh,
        );

        final dashRes = await dashRepo.watchTodayDashboard(userId: uid).first;
        expect(dashRes, isA<Success<TodayDashboardEntity>>());
        final dash = (dashRes as Success<TodayDashboardEntity>).value;
        expect(dash.monthlyExpenseMinor, expectedExpense);
        expect(dash.monthlyIncomeMinor, expectedIncome);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        final summaryDoc = await db
            .collection('users')
            .doc(uid)
            .collection('monthly_summaries')
            .doc(monthKey)
            .get();
        expect(summaryDoc.exists, isTrue);
        expect(summaryDoc.data()!['grossExpenseMinor'], expectedExpense);
        expect(summaryDoc.data()!['incomeMinor'], expectedIncome);

        // 3. BudgetRepositoryImpl matches FinancialAggregationEngine including matchedPaymentOrder
        final budgetRepo = BudgetRepositoryImpl(BudgetRemoteDataSource(db));
        final budgetsRes = await budgetRepo
            .watchBudgets(userId: uid, monthKey: monthKey)
            .first;
        final budgets = (budgetsRes as Success).value;
        expect(budgets.single.spentMinor, expectedFoodBudget);
      },
    );

    test(
      'DashboardRepositoryImpl propagates Err honestly (never 0 VND) and auto-refreshes across midnight & month rollover',
      () async {
        final mockTxRepo = _MockTransactionRepository();
        final mockTasks = _MockTaskRepository();
        final mockCal = _MockCalendarRepository();
        final mockVeh = _MockVehicleRepository();

        var simulatedNow = DateTime(2026, 11, 30, 23, 59, 50);
        final tickCtrl = StreamController<void>.broadcast();
        final walletsCtrl =
            StreamController<Result<List<WalletEntity>>>.broadcast();

        when(() => mockTxRepo.watchWallets('u_roll')).thenAnswer(
          (_) => walletsCtrl.stream,
        );
        when(
          () => mockTxRepo.watchAllTransactionsForAggregation(
            userId: 'u_roll',
            monthKey: '2026-11',
          ),
        ).thenAnswer(
          (_) => Stream.value(
            Success<List<TransactionEntity>>([
              _makeTx(
                id: 'nov_exp',
                amountMinor: 120000,
                kind: TransactionKind.expense,
                occurredAt: DateTime(2026, 11, 30, 18, 0),
              ),
            ]),
          ),
        );
        when(
          () => mockTxRepo.watchAllTransactionsForAggregation(
            userId: 'u_roll',
            monthKey: '2026-12',
          ),
        ).thenAnswer(
          (_) => Stream.value(
            Success<List<TransactionEntity>>([
              _makeTx(
                id: 'dec_exp',
                amountMinor: 45000,
                kind: TransactionKind.expense,
                occurredAt: DateTime(2026, 12, 1, 7, 30),
              ),
            ]),
          ),
        );
        when(
          () => mockTxRepo.saveNetWorthSnapshot(
            userId: any(named: 'userId'),
            monthKey: any(named: 'monthKey'),
            summary: any(named: 'summary'),
          ),
        ).thenAnswer((_) async => const Success(null));
        when(
          () => mockTxRepo.saveMonthlySummary(
            userId: any(named: 'userId'),
            monthKey: any(named: 'monthKey'),
            summary: any(named: 'summary'),
          ),
        ).thenAnswer((_) async => const Success(null));

        when(
          () => mockTasks.watchTasks(
            userId: any(named: 'userId'),
            familyId: any(named: 'familyId'),
          ),
        ).thenAnswer((_) => Stream.value(const Success(<TaskEntity>[])));
        when(
          () => mockCal.watchEvents(
            userId: any(named: 'userId'),
            familyId: any(named: 'familyId'),
          ),
        ).thenAnswer(
          (_) => Stream.value(const Success(<CalendarEventEntity>[])),
        );
        when(
          () => mockVeh.watchVehicles(
            userId: any(named: 'userId'),
            familyId: any(named: 'familyId'),
          ),
        ).thenAnswer((_) => Stream.value(const Success(<VehicleEntity>[])));

        final dashRepo = DashboardRepositoryImpl(
          transactionRepo: mockTxRepo,
          taskRepo: mockTasks,
          calendarRepo: mockCal,
          vehicleRepo: mockVeh,
          clock: () => simulatedNow,
          boundaryTickStream: tickCtrl.stream,
        );

        final emitted = <Result<TodayDashboardEntity>>[];
        final sub = dashRepo
            .watchTodayDashboard(userId: 'u_roll')
            .listen(emitted.add);

        // 1. Wallet stream fails -> must emit Err, NEVER 0 VND Success!
        walletsCtrl.add(const Err(NetworkFailure()));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(emitted.last, isA<Err<TodayDashboardEntity>>());

        // 2. Wallet recovers on 2026-11-30 -> Nov expense = 120,000
        walletsCtrl.add(
          const Success([
            WalletEntity(
              id: 'w_1',
              ownerId: 'u_roll',
              name: 'Ví',
              type: WalletType.cash,
              balanceMinor: 1000000,
            ),
          ]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          (emitted.last as Success<TodayDashboardEntity>)
              .value
              .monthlyExpenseMinor,
          120000,
        );
        expect(
          (emitted.last as Success<TodayDashboardEntity>)
              .value
              .todayExpenseMinor,
          120000,
        );

        // 3. Cross midnight into 2026-12-01 -> auto-rotates monthKey & computes Dec 45,000!
        simulatedNow = DateTime(2026, 12, 1, 8, 0);
        tickCtrl.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          (emitted.last as Success<TodayDashboardEntity>)
              .value
              .monthlyExpenseMinor,
          45000,
        );
        expect(
          (emitted.last as Success<TodayDashboardEntity>)
              .value
              .todayExpenseMinor,
          45000,
        );

        await sub.cancel();
        await walletsCtrl.close();
        await tickCtrl.close();
      },
    );
  });

  group('FIX-007: LedgerIntegrityEngine & Immutable Sổ Cái', () {
    test(
      'LedgerIntegrityEngine enforces balance invariant, duplicate operationId guard & VERIFIED immutability',
      () {
        final now = DateTime.utc(2026, 11, 24);
        final badAudit = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: 'aud_bad',
          operationId: 'op_1',
          transactionId: 'op_1',
          walletId: 'w_1',
          previousBalanceMinor: 1000,
          deltaAmountMinor: -200,
          newBalanceMinor: 900, // Invalid!
          createdAt: now,
          actorId: 'u_1',
          source: 'manual',
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
        );
        expect(badAudit, isA<Err<LedgerAuditRecord>>());

        final goodAudit = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: 'aud_good',
          operationId: 'op_1',
          transactionId: 'op_1',
          walletId: 'w_1',
          previousBalanceMinor: 1000,
          deltaAmountMinor: -200,
          newBalanceMinor: 800,
          createdAt: now,
          actorId: 'u_1',
          source: 'manual',
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
        );
        expect(goodAudit, isA<Success<LedgerAuditRecord>>());
        expect(
          LedgerIntegrityEngine.isBalanceEquationValid(
            (goodAudit as Success<LedgerAuditRecord>).value,
          ),
          isTrue,
        );

        expect(
          LedgerIntegrityEngine.validateUniqueOperationId(
            operationId: 'op_1',
            existingOperationIds: const ['op_1', 'op_2'],
          ),
          isA<Err<void>>(),
        );

        final verifiedTx = _makeTx(
          id: 'tx_ver_1',
          amountMinor: 500000,
          kind: TransactionKind.expense,
          occurredAt: now,
          verification: TransactionVerification.verified,
          verificationStatus: 'VERIFIED',
        );
        expect(
          LedgerIntegrityEngine.validateClientMutation(
            existing: verifiedTx,
            newAmountMinor: 400000,
          ),
          isA<Err<void>>(),
        );
        expect(
          LedgerIntegrityEngine.validateClientMutation(
            existing: verifiedTx,
            newWalletId: 'w_other',
          ),
          isA<Err<void>>(),
        );
        expect(
          LedgerIntegrityEngine.validateClientMutation(
            existing: verifiedTx,
            newKind: TransactionKind.income,
          ),
          isA<Err<void>>(),
        );
        expect(
          LedgerIntegrityEngine.validateClientMutation(
            existing: verifiedTx,
            newVerification: TransactionVerification.userConfirmed,
          ),
          isA<Err<void>>(),
        );
      },
    );

    test(
      'Property test: Idempotent operationId (3x calls = 1x delta), transfer conservation, idempotent reverseTransaction & ledger_audits',
      () async {
        final db = FakeFirebaseFirestore();
        final ds = TransactionRemoteDataSource(db);
        const uid = 'u_ledger_prop';
        final rng = Random(42);

        await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_bank')
            .set({
              'id': 'w_bank',
              'ownerId': uid,
              'name': 'VCB',
              'type': 'bank',
              'balanceMinor': 10000000,
            });
        await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_cash')
            .set({
              'id': 'w_cash',
              'ownerId': uid,
              'name': 'Tiền mặt',
              'type': 'cash',
              'balanceMinor': 2000000,
            });

        // Property 1: Same operationId called 3 times updates balance ONLY ONCE
        for (var i = 0; i < 3; i++) {
          await ds.createTransaction(
            operationId: 'op_idem_triple',
            userId: uid,
            walletId: 'w_bank',
            categoryName: 'Ăn uống',
            kind: TransactionKind.expense,
            amountMinor: 250000,
            merchant: 'Phở',
            occurredAt: DateTime(2026, 11, 20),
          );
        }
        final wBankAfterIdem = await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_bank')
            .get();
        expect(wBankAfterIdem.data()!['balanceMinor'], 9750000);
        expect(wBankAfterIdem.data()!['lastAuditId'], 'aud_op_idem_triple');

        final auditTriple = await db
            .collection('users')
            .doc(uid)
            .collection('ledger_audits')
            .doc('aud_op_idem_triple')
            .get();
        expect(auditTriple.exists, isTrue);
        expect(auditTriple.data()!['operationId'], 'op_idem_triple');
        expect(auditTriple.data()!['transactionId'], 'op_idem_triple');
        expect(auditTriple.data()!['deltaAmountMinor'], -250000);
        expect(auditTriple.data()!['previousBalanceMinor'], 10000000);
        expect(auditTriple.data()!['newBalanceMinor'], 9750000);
        expect(auditTriple.data()!['actorId'], uid);
        expect(auditTriple.data()!['source'], 'manual');
        expect(auditTriple.data()!['verificationStatus'], 'USER_CONFIRMED');

        // Property 2: Randomized transfers conserve sum_before == sum_after and update lastAuditId on BOTH wallets
        for (var step = 0; step < 5; step++) {
          final amt = 10000 + rng.nextInt(50000);
          final beforeBank =
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('wallets')
                      .doc('w_bank')
                      .get())
                  .data()!['balanceMinor'] as int;
          final beforeCash =
              (await db
                      .collection('users')
                      .doc(uid)
                      .collection('wallets')
                      .doc('w_cash')
                      .get())
                  .data()!['balanceMinor'] as int;
          final sumBefore = beforeBank + beforeCash;

          final opId = 'op_trf_$step';
          await ds.createTransaction(
            operationId: opId,
            userId: uid,
            walletId: 'w_bank',
            targetWalletId: 'w_cash',
            categoryName: 'Chuyển nội bộ',
            kind: TransactionKind.transfer,
            amountMinor: amt,
            merchant: 'Rút tiền',
            occurredAt: DateTime(2026, 11, 21),
          );

          final bankSnap = await db
              .collection('users')
              .doc(uid)
              .collection('wallets')
              .doc('w_bank')
              .get();
          final cashSnap = await db
              .collection('users')
              .doc(uid)
              .collection('wallets')
              .doc('w_cash')
              .get();
          final sumAfter =
              (bankSnap.data()!['balanceMinor'] as int) +
              (cashSnap.data()!['balanceMinor'] as int);
          expect(sumAfter, sumBefore);
          expect(bankSnap.data()!['lastAuditId'], 'aud_${opId}_src');
          expect(cashSnap.data()!['lastAuditId'], 'aud_${opId}_dst');
        }

        // Property 3: create + reverse restores exact balance, sets REVERSED, writes aud_rev_*, and 2nd reverse is idempotent!
        final balBeforeCreate =
            (await db
                    .collection('users')
                    .doc(uid)
                    .collection('wallets')
                    .doc('w_cash')
                    .get())
                .data()!['balanceMinor'] as int;

        await ds.createTransaction(
          operationId: 'op_to_rev',
          userId: uid,
          walletId: 'w_cash',
          categoryName: 'Mua sắm',
          kind: TransactionKind.expense,
          amountMinor: 333000,
          merchant: 'Áo khoác',
          occurredAt: DateTime(2026, 11, 22),
        );

        final rev1 = await ds.reverseTransaction(
          userId: uid,
          transactionId: 'op_to_rev',
          reason: 'Hoàn trả hàng',
        );
        // Calling reverseTransaction a second time MUST be idempotent (no error, same reversal)!
        final rev2 = await ds.reverseTransaction(
          userId: uid,
          transactionId: 'op_to_rev',
          reason: 'Hoàn trả hàng lần 2',
        );
        expect(rev1.entity.id, 'rev_op_to_rev');
        expect(rev2.entity.id, 'rev_op_to_rev');
        expect(rev1.entity.balanceAfterMinor, balBeforeCreate);

        final cashAfterRev = await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_cash')
            .get();
        expect(cashAfterRev.data()!['balanceMinor'], balBeforeCreate);
        expect(cashAfterRev.data()!['lastAuditId'], 'aud_rev_op_to_rev');

        final origDoc = await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc('op_to_rev')
            .get();
        expect(origDoc.data()!['verificationStatus'], 'REVERSED');
        expect(origDoc.data()!['reversedById'], 'rev_op_to_rev');

        final revAudit = await db
            .collection('users')
            .doc(uid)
            .collection('ledger_audits')
            .doc('aud_rev_op_to_rev')
            .get();
        expect(revAudit.exists, isTrue);
        expect(revAudit.data()!['verificationStatus'], 'REVERSED');
        expect(revAudit.data()!['deltaAmountMinor'], 333000);
        expect(revAudit.data()!['newBalanceMinor'], balBeforeCreate);

        // Property 4: decideProvisionalTransaction blocks VERIFIED edits & writes audits on reject/approve
        await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc('tx_verified_locked')
            .set({
              'id': 'tx_verified_locked',
              'operationId': 'op_ver_lock',
              'ownerId': uid,
              'walletId': 'w_bank',
              'categoryName': 'Thu nhập',
              'kind': 'income',
              'direction': 'credit',
              'amountMinor': 1500000,
              'currencyCode': 'VND',
              'merchant': 'Bank Feed',
              'occurredAt': Timestamp.fromDate(DateTime(2026, 11, 22)),
              'monthKey': '2026-11',
              'sourceKind': 'bankApi',
              'verification': 'verified',
              'verificationStatus': 'VERIFIED',
              'observedBalanceMinor': 11500000,
              'crossSourceFingerprint': 'fp_locked',
            });

        final lockedModel = TransactionModel.fromFirestore(
          await db
              .collection('users')
              .doc(uid)
              .collection('transactions')
              .doc('tx_verified_locked')
              .get(),
        );
        expect(lockedModel.entity.operationId, 'op_ver_lock');
        expect(lockedModel.entity.verificationStatus, 'VERIFIED');
        expect(lockedModel.entity.observedBalanceMinor, 11500000);

        await expectLater(
          () => ds.decideProvisionalTransaction(
            userId: uid,
            transactionId: 'tx_verified_locked',
            approve: true,
            updatedAmountMinor: 9999999,
          ),
          throwsA(isA<AppException>()),
        );

        // Rejecting a needsReview tx that had ledgerApplied=true reverses balance & writes audit
        await db
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .doc('tx_review_applied')
            .set({
              'id': 'tx_review_applied',
              'ownerId': uid,
              'walletId': 'w_cash',
              'categoryName': 'Ăn uống',
              'kind': 'expense',
              'direction': 'debit',
              'amountMinor': 50000,
              'currencyCode': 'VND',
              'merchant': 'Test',
              'occurredAt': Timestamp.fromDate(DateTime(2026, 11, 22)),
              'monthKey': '2026-11',
              'sourceKind': 'androidNotification',
              'verification': 'needsReview',
              'ledgerApplied': true,
              'crossSourceFingerprint': 'fp_rev_app',
            });

        await ds.decideProvisionalTransaction(
          userId: uid,
          transactionId: 'tx_review_applied',
          approve: false,
        );
        final cashAfterReject = await db
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc('w_cash')
            .get();
        expect(cashAfterReject.data()!['balanceMinor'], balBeforeCreate + 50000);
        expect(
          cashAfterReject.data()!['lastAuditId'],
          'aud_reject_tx_review_applied',
        );
        final rejectAudit = await db
            .collection('users')
            .doc(uid)
            .collection('ledger_audits')
            .doc('aud_reject_tx_review_applied')
            .get();
        expect(rejectAudit.exists, isTrue);
        expect(rejectAudit.data()!['verificationStatus'], 'REJECTED');
      },
    );
  });

  group('FIX-008: AES-256-GCM / AEAD Encrypted Vault & Security Hardening', () {
    test(
      'SparkSafeFileStorageService writes LOSV ciphertext, detects 1-bit tamper fail-closed & verifies physical deletion',
      () async {
        final tempRoot = Directory.systemTemp.createTempSync('losv_vault_sec_');
        addTearDown(() {
          if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
        });

        final bridge = NativeSecureVaultBridge.testable();
        final storage = SparkSafeFileStorageService(
          customVaultRootPath: tempRoot.path,
          vaultBridge: bridge,
        );
        final plaintext = Uint8List.fromList(
          utf8.encode('CCCD_MAT_TRUOC_079200099988_BI_MAT_TUYET_DOI'),
        );

        final uploadRes = await storage.uploadUserAttachment(
          userId: 'u_vault_1',
          folder: 'important_docs',
          fileName: 'cccd.png',
          mimeType: 'image/png',
          bytes: plaintext,
        );
        expect(uploadRes, isA<Success<StoredFileReference>>());
        final ref = (uploadRes as Success<StoredFileReference>).value;
        expect(ref.localFilePath, endsWith('.enc'));
        expect(ref.plaintextSha256, isNotEmpty);
        expect(ref.encryptedSizeBytes, greaterThan(plaintext.length));

        final encFile = File(ref.localFilePath!);
        expect(encFile.existsSync(), isTrue);
        final diskBytes = encFile.readAsBytesSync();

        // Disk bytes MUST start with "LOSV" magic and NOT contain plaintext
        expect(diskBytes.sublist(0, 4), [0x4C, 0x4F, 0x53, 0x56]); // "LOSV"
        expect(utf8.decode(diskBytes, allowMalformed: true), isNot(contains('CCCD_MAT_TRUOC')));
        expect(diskBytes, isNot(equals(plaintext)));

        // Valid read succeeds and returns exact plaintext
        final readOk = await storage.readLocalAttachmentBytes(
          userId: 'u_vault_1',
          storageKey: ref.storageKey,
          expectedPlaintextSha256: ref.plaintextSha256,
        );
        expect((readOk as Success<Uint8List?>).value, equals(plaintext));

        // Flip 1 bit in the .enc ciphertext -> fail-closed FormatException / VaultSecurityException!
        final tampered = Uint8List.fromList(diskBytes);
        final targetOffset = tampered.length ~/ 2;
        tampered[targetOffset] = tampered[targetOffset] ^ 0x01;
        encFile.writeAsBytesSync(tampered, flush: true);

        await expectLater(
          () => storage.readLocalAttachmentBytes(
            userId: 'u_vault_1',
            storageKey: ref.storageKey,
          ),
          throwsA(isA<FormatException>()),
        );

        // Restore valid encrypted bytes, then test DocumentVaultRepositoryImpl.deleteDocument removes physical file!
        encFile.writeAsBytesSync(diskBytes, flush: true);
        final db = FakeFirebaseFirestore();
        final docRepo = DocumentVaultRepositoryImpl(db, fileStorage: storage);
        final createdDocRes = await docRepo.createDocument(
          const CreateDocumentVaultParams(
            userId: 'u_vault_1',
            userName: 'An',
            shareWithFamily: false,
            folder: DocumentFolderCategory.importantDocs,
            title: 'CCCD gắn chip',
            referenceCode: '079200099988',
          ),
        );
        final createdDoc = (createdDocRes as Success<DocumentVaultEntity>).value;

        final attachedRes = await docRepo.attachEncryptedLocalFile(
          userId: 'u_vault_1',
          document: createdDoc,
          fileName: 'cccd_front.png',
          mimeType: 'image/png',
          bytes: plaintext,
        );
        expect(attachedRes, isA<Success<DocumentVaultEntity>>());
        final attachedDoc = (attachedRes as Success<DocumentVaultEntity>).value;
        expect(
          attachedDoc.storageScope,
          DocumentStorageScope.localEncryptedVault,
        );
        expect(attachedDoc.attachmentSha256, isNotEmpty);
        final attachedEncFile = File(attachedDoc.localAttachmentPath!);
        expect(attachedEncFile.existsSync(), isTrue);

        // Read back through repository
        final repoRead = await docRepo.readEncryptedLocalFile(
          userId: 'u_vault_1',
          document: attachedDoc,
        );
        expect((repoRead as Success<Uint8List?>).value, equals(plaintext));

        // Delete document -> physical .enc file and .meta MUST be gone!
        final delRes = await docRepo.deleteDocument(
          userId: 'u_vault_1',
          document: attachedDoc,
        );
        expect(delRes, isA<Success<void>>());
        expect(attachedEncFile.existsSync(), isFalse);
        expect(File('${attachedEncFile.path}.meta').existsSync(), isFalse);
      },
    );

    test(
      'Native Android XML & Kotlin security hardening rules are intact',
      () {
        final filePathsXml = File(
          'android/app/src/main/res/xml/file_paths.xml',
        ).readAsStringSync();
        expect(filePathsXml.contains('<files-path'), isFalse);
        expect(filePathsXml, contains('ota_updates'));

        final backupRulesXml = File(
          'android/app/src/main/res/xml/backup_rules.xml',
        ).readAsStringSync();
        expect(backupRulesXml, contains('secure_doc_vault'));
        expect(backupRulesXml, contains('lifeos_hardware_vault_prefs_v1'));

        final extractionRulesXml = File(
          'android/app/src/main/res/xml/data_extraction_rules.xml',
        ).readAsStringSync();
        expect(extractionRulesXml, contains('secure_doc_vault'));
        expect(extractionRulesXml, contains('lifeos_hardware_vault_prefs_v1'));

        final kotlinVault = File(
          'android/app/src/main/kotlin/vn/lifeos/app/life_os/LifeOsSecureVault.kt',
        ).readAsStringSync();
        expect(kotlinVault, contains('fun encryptBytes('));
        expect(kotlinVault, contains('fun decryptBytes('));
        expect(kotlinVault, contains('AES/GCM/NoPadding'));
        expect(kotlinVault, contains('noBackupFilesDir'));

        final storageDart = File(
          'lib/core/services/file_storage_service.dart',
        ).readAsStringSync();
        expect(storageDart.contains('systemTemp'), isFalse);
      },
    );
  });
}
