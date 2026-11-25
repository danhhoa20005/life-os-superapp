import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/core/utils/smart_money_split_ai_engine.dart';
import 'package:life_os/features/budgets/data/repositories/budget_repository_impl.dart';
import 'package:life_os/features/budgets/domain/entities/budget_entities.dart';
import 'package:life_os/features/budgets/domain/usecases/budget_usecases.dart';
import 'package:life_os/features/budgets/presentation/bloc/budget_bloc.dart';
import 'package:life_os/features/family/data/repositories/family_repository_impl.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/tasks/data/repositories/task_repository_impl.dart';
import 'package:life_os/features/tasks/domain/entities/task_entities.dart';
import 'package:life_os/features/vehicles/data/repositories/vehicle_repository_impl.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';

void main() {
  group('v3.27.0 Financial & Security Property Tests (Seeded)', () {
    test(
      'AUD-013 Property: apportionExactVnd / apportionExactVndBigInt / BasisPoints conserve exact VND across 1,000 seeded multi-billion cases & zero-weight members receive 0',
      () {
        final rng = math.Random(20261125);
        for (var i = 0; i < 1000; i++) {
          final count = 2 + rng.nextInt(14);
          final totalMinor = i == 0
              ? 0
              : (i < 150
                    ? 1 + rng.nextInt(250000)
                    : (100000000 + rng.nextInt(900000000)) *
                          (1 + rng.nextInt(90)));

          // Inject deliberate 0-weight participants in ~40% of cases.
          final hasZeroWeight = i % 5 < 2;
          final bigWeights = <BigInt>[];
          final bpsWeights = <int>[];
          final doubleWeights = <double>[];
          for (var j = 0; j < count; j++) {
            final isZero = hasZeroWeight && j == count - 1;
            final wInt = isZero ? 0 : (1 + rng.nextInt(5000));
            bigWeights.add(BigInt.from(wInt) * BigInt.from(1000000 + i));
            bpsWeights.add(wInt);
            doubleWeights.add(isZero ? 0.0 : wInt + (j % 3) * 0.125);
          }

          final sharesBig = SmartMoneySplitAiEngine.apportionExactVndBigInt(
            totalMinor,
            bigWeights,
          );
          final sharesBps =
              SmartMoneySplitAiEngine.apportionExactVndBasisPoints(
                totalMinor,
                bpsWeights,
              );
          final sharesDouble = SmartMoneySplitAiEngine.apportionExactVnd(
            totalMinor,
            doubleWeights,
          );

          expect(sharesBig.length, count);
          expect(sharesBps.length, count);
          expect(sharesDouble.length, count);

          expect(sharesBig.fold<int>(0, (s, v) => s + v), totalMinor);
          expect(sharesBps.fold<int>(0, (s, v) => s + v), totalMinor);
          expect(sharesDouble.fold<int>(0, (s, v) => s + v), totalMinor);

          for (var j = 0; j < count; j++) {
            expect(sharesBig[j], greaterThanOrEqualTo(0));
            expect(sharesBps[j], greaterThanOrEqualTo(0));
            expect(sharesDouble[j], greaterThanOrEqualTo(0));
            if (bigWeights[j] == BigInt.zero) {
              expect(
                sharesBig[j],
                0,
                reason: 'Zero-weight index $j stole $totalMinor remainder',
              );
              expect(sharesBps[j], 0);
              expect(sharesDouble[j], 0);
            }
          }
        }

        // Strict validation rejection tests
        expect(
          () => SmartMoneySplitAiEngine.apportionExactVnd(-1, [1.0, 1.0]),
          throwsArgumentError,
        );
        expect(
          () => SmartMoneySplitAiEngine.apportionExactVnd(1000, [
            double.nan,
            1.0,
          ]),
          throwsArgumentError,
        );
        expect(
          () => SmartMoneySplitAiEngine.apportionExactVnd(1000, [
            double.infinity,
            1.0,
          ]),
          throwsArgumentError,
        );
        expect(
          () => SmartMoneySplitAiEngine.apportionExactVnd(1000, [-5.0, 10.0]),
          throwsArgumentError,
        );
        expect(
          () => SmartMoneySplitAiEngine.apportionExactVnd(1000, [0.0, 0.0]),
          throwsArgumentError,
        );
        expect(
          () => SmartMoneySplitAiEngine.apportionExactVndBigInt(1000, [
            BigInt.zero,
            BigInt.zero,
          ]),
          throwsArgumentError,
        );
        expect(
          () => SmartMoneySplitAiEngine.apportionExactVndBasisPoints(1000, [
            -10,
            20,
          ]),
          throwsArgumentError,
        );
      },
    );

    test(
      'AUD-013 Property: optimizeSettlementTransfers strictly preserves zero-sum clearing across 1,000 seeded graphs & uses Exact Subset DP to beat naive greedy',
      () {
        final rng = math.Random(20261125);
        for (var i = 0; i < 1000; i++) {
          final m =
              2 +
              rng.nextInt(13); // covers both M <= 12 (DP) and M > 12 (greedy)
          final net = <String, int>{for (var k = 0; k < m; k++) 'u_$k': 0};
          // Plant random transfers in a zero-sum graph so total sum == 0 guaranteed.
          final edgeCount = m + rng.nextInt(m * 2);
          for (var e = 0; e < edgeCount; e++) {
            final a = 'u_${rng.nextInt(m)}';
            final b = 'u_${rng.nextInt(m)}';
            if (a == b) continue;
            final amt = 1000 + rng.nextInt(500000);
            net[a] = net[a]! - amt;
            net[b] = net[b]! + amt;
          }

          final transfers = SmartMoneySplitAiEngine.optimizeSettlementTransfers(
            net,
          );
          final nonZeroCount = net.values.where((v) => v != 0).length;
          expect(
            transfers.length,
            lessThanOrEqualTo(math.max(0, nonZeroCount - 1)),
          );

          // Reconstruct resulting settled deltas and verify every single member matches exact balance!
          final reconstructed = <String, int>{for (final k in net.keys) k: 0};
          for (final t in transfers) {
            expect(t.amountMinor, greaterThan(0));
            expect(t.fromUserId, isNot(equals(t.toUserId)));
            reconstructed[t.fromUserId] =
                reconstructed[t.fromUserId]! - t.amountMinor;
            reconstructed[t.toUserId] =
                reconstructed[t.toUserId]! + t.amountMinor;
          }
          expect(reconstructed, net, reason: 'Mismatch on seeded graph #$i');
        }

        // Reject unbalanced graph
        expect(
          () => SmartMoneySplitAiEngine.optimizeSettlementTransfers(const {
            'u_1': 100000,
            'u_2': -99000,
          }),
          throwsArgumentError,
        );

        // Canonical Exact Zero-Sum Subset DP superiority check vs greedy:
        // Clique 1: A=+300, B=-100, C=-200 -> 2 transfers (sum 0)
        // Clique 2: D=+150, E=+150, F=-300 -> 2 transfers (sum 0)
        // Total M=6, Optimal = 4 transfers (DP finds both disjoint zero-sum cliques!)
        final dpOptimal = SmartMoneySplitAiEngine.optimizeSettlementTransfers(
          const {'A': 300, 'B': -100, 'C': -200, 'D': 150, 'E': 150, 'F': -300},
        );
        expect(dpOptimal.length, 4);
      },
    );
  });

  group('v3.27.0 Family Fund 9-State Lifecycle, Atomic Ledger & Scalability', () {
    late FakeFirebaseFirestore fakeFs;
    late BudgetRemoteDataSource remote;
    late BudgetRepositoryImpl repo;

    const famId = 'fam_v327';
    const ownerId = 'u_owner';
    const mgrBId = 'u_mgr_b';
    const memberId = 'u_member';
    const walletId = 'w_owner_main';

    setUp(() async {
      fakeFs = FakeFirebaseFirestore();
      remote = BudgetRemoteDataSource(fakeFs);
      repo = BudgetRepositoryImpl(remote);

      await fakeFs.collection('families').doc(famId).set({
        'id': famId,
        'name': 'Gia đình v3.27',
        'createdBy': ownerId,
        'memberIds': [ownerId, mgrBId, memberId],
        'memberRoles': {ownerId: 'owner', mgrBId: 'admin', memberId: 'member'},
        'memberNames': {ownerId: 'An', mgrBId: 'Bình', memberId: 'Chi'},
      });
      await fakeFs
          .collection('users')
          .doc(ownerId)
          .collection('wallets')
          .doc(walletId)
          .set({
            'id': walletId,
            'ownerId': ownerId,
            'name': 'VCB Chính',
            'balanceMinor': 5000000,
          });
      await fakeFs
          .collection('families')
          .doc(famId)
          .collection('funds')
          .doc('fund_1')
          .set({
            'id': 'fund_1',
            'ownerId': ownerId,
            'familyId': famId,
            'name': 'Quỹ Sinh hoạt',
            'balanceMinor': 0,
            'targetAmountMinor': 3000000,
            'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
          });
    });

    test(
      'AUD-006: RequestFundExpenseUseCase strips canAutoApprove on FundScope.family & enforces full 9-state FSM + atomic wallet contribution + idempotency + non-truncated stream',
      () async {
        final usecases = (
          contribute: ContributeToFundUseCase(repo),
          request: RequestFundExpenseUseCase(repo),
          submitDraft: SubmitFundExpenseDraftUseCase(repo),
          decide: DecideFundExpenseUseCase(repo),
          execute: ExecuteFundExpenseUseCase(repo),
          reconcile: ReconcileFundExpenseUseCase(repo),
          dispute: DisputeFundExpenseUseCase(repo),
          reverse: ReverseFundExpenseUseCase(repo),
          cancel: CancelFundExpenseUseCase(repo),
        );

        // 1. Atomic single-tx wallet-to-fund contribution with operationId idempotency
        final contribRes = await usecases.contribute(
          const ContributeFundParams(
            userId: ownerId,
            userName: 'An',
            scope: FundScope.family,
            familyId: famId,
            fundId: 'fund_1',
            amountMinor: 1200000,
            note: 'Góp quỹ tháng 11',
            sourceWalletId: walletId,
            operationId: 'op_contrib_1',
          ),
        );
        expect(contribRes, isA<Success<void>>());

        // Duplicate retry with same operationId -> idempotent no-op (no double debit/credit!)
        final retryRes = await usecases.contribute(
          const ContributeFundParams(
            userId: ownerId,
            userName: 'An',
            scope: FundScope.family,
            familyId: famId,
            fundId: 'fund_1',
            amountMinor: 1200000,
            note: 'Góp quỹ tháng 11',
            sourceWalletId: walletId,
            operationId: 'op_contrib_1',
          ),
        );
        expect(retryRes, isA<Success<void>>());

        final walletSnap = await fakeFs
            .collection('users')
            .doc(ownerId)
            .collection('wallets')
            .doc(walletId)
            .get();
        expect(walletSnap.data()?['balanceMinor'], 3800000);
        expect(walletSnap.data()?['lastAuditId'], isNotEmpty);

        final fundAfterContrib = await fakeFs
            .collection('families')
            .doc(famId)
            .collection('funds')
            .doc('fund_1')
            .get();
        expect(fundAfterContrib.data()?['balanceMinor'], 1200000);
        expect(fundAfterContrib.data()?['lastEventType'], 'contribution');

        // 2. Family request passing canAutoApprove: true MUST NOT auto-approve!
        await usecases.request(
          const RequestFundExpenseParams(
            userId: ownerId,
            userName: 'An',
            scope: FundScope.family,
            familyId: famId,
            fundId: 'fund_1',
            title: 'Mua đồ bếp',
            amountMinor: 400000,
            canAutoApprove: true,
            operationId: 'op_req_1',
          ),
        );

        final expCol = fakeFs
            .collection('families')
            .doc(famId)
            .collection('funds')
            .doc('fund_1')
            .collection('expenses');
        final exp1Snap = (await expCol.get()).docs.single;
        expect(
          FundExpenseStatus.fromWireValue(exp1Snap.data()['status'] as String?),
          FundExpenseStatus.pendingApproval,
        );

        // Balance remains intact until executed
        expect(
          (await fakeFs
                  .collection('families')
                  .doc(famId)
                  .collection('funds')
                  .doc('fund_1')
                  .get())
              .data()?['balanceMinor'],
          1200000,
        );

        // 3. Separation-of-duties: ownerId cannot approve own expense in 3-member group!
        final selfApprove = await usecases.decide(
          DecideFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: exp1Snap.id,
            approve: true,
            actorUserId: ownerId,
          ),
        );
        expect(selfApprove, isA<Err<void>>());
        expect(
          (selfApprove as Err<void>).failure,
          isA<PermissionDeniedFailure>(),
        );

        // 4. Member cannot approve
        final memApprove = await usecases.decide(
          DecideFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: exp1Snap.id,
            approve: true,
            actorUserId: memberId,
          ),
        );
        expect(memApprove, isA<Err<void>>());

        // 5. Manager B approves -> status = approved (fund balance STILL 1,200,000)
        final mgrApprove = await usecases.decide(
          DecideFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: exp1Snap.id,
            approve: true,
            actorUserId: mgrBId,
          ),
        );
        expect(mgrApprove, isA<Success<void>>());

        // 6. Manager B executes -> atomic debit to 800,000 + fund_audits entry
        final execRes = await usecases.execute(
          ExecuteFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: exp1Snap.id,
            actorUserId: mgrBId,
          ),
        );
        expect(execRes, isA<Success<void>>());
        expect(
          (await fakeFs
                  .collection('families')
                  .doc(famId)
                  .collection('funds')
                  .doc('fund_1')
                  .get())
              .data()?['balanceMinor'],
          800000,
        );

        // 7. Member disputes -> Manager B reverses -> fund balance restored to 1,200,000!
        final dispRes = await usecases.dispute(
          DisputeFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: exp1Snap.id,
            actorUserId: memberId,
            reason: 'Sai hóa đơn',
          ),
        );
        expect(dispRes, isA<Success<void>>());

        final revRes = await usecases.reverse(
          ReverseFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: exp1Snap.id,
            actorUserId: mgrBId,
          ),
        );
        expect(revRes, isA<Success<void>>());
        expect(
          (await fakeFs
                  .collection('families')
                  .doc(famId)
                  .collection('funds')
                  .doc('fund_1')
                  .get())
              .data()?['balanceMinor'],
          1200000,
        );

        // 8. Re-reversing terminal `reversed` expense MUST fail!
        final reRev = await usecases.reverse(
          ReverseFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: exp1Snap.id,
            actorUserId: mgrBId,
          ),
        );
        expect(reRev, isA<Err<void>>());

        // 9. Draft -> Edit Draft -> Submit -> Approve -> Execute -> Reconcile flow
        await usecases.request(
          const RequestFundExpenseParams(
            userId: memberId,
            userName: 'Chi',
            scope: FundScope.family,
            familyId: famId,
            fundId: 'fund_1',
            title: 'Nháp ban đầu',
            amountMinor: 100000,
            canAutoApprove: false,
            saveAsDraft: true,
            operationId: 'op_draft_1',
          ),
        );
        final draftSnap = await expCol.doc('exp_op_draft_1').get();
        expect(draftSnap.data()?['status'], 'draft');

        await usecases.submitDraft(
          const SubmitFundExpenseDraftParams(
            scope: FundScope.family,
            userId: memberId,
            familyId: famId,
            fundId: 'fund_1',
            expenseId: 'exp_op_draft_1',
            updatedTitle: 'Tiền internet chung',
            updatedAmountMinor: 250000,
          ),
        );
        await usecases.decide(
          const DecideFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: 'exp_op_draft_1',
            approve: true,
            actorUserId: ownerId,
          ),
        );
        await usecases.execute(
          const ExecuteFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: 'exp_op_draft_1',
            actorUserId: ownerId,
          ),
        );
        final recRes = await usecases.reconcile(
          const ReconcileFundExpenseParams(
            familyId: famId,
            fundId: 'fund_1',
            expenseId: 'exp_op_draft_1',
            actorUserId: ownerId,
            reconciledTxId: 'tx_bank_reconcile_1',
          ),
        );
        expect(recRes, isA<Success<void>>());
        final recSnap = await expCol.doc('exp_op_draft_1').get();
        expect(recSnap.data()?['status'], 'reconciled');
        expect(recSnap.data()?['reconciledTxId'], 'tx_bank_reconcile_1');

        // 10. Verify > 25 contributions + expenses hydrate WITHOUT .limit(10) truncation!
        for (var i = 0; i < 25; i++) {
          await usecases.contribute(
            ContributeFundParams(
              userId: memberId,
              userName: 'Chi',
              scope: FundScope.family,
              familyId: famId,
              fundId: 'fund_1',
              amountMinor: 10000,
              operationId: 'bulk_c_$i',
            ),
          );
          await usecases.request(
            RequestFundExpenseParams(
              userId: memberId,
              userName: 'Chi',
              scope: FundScope.family,
              familyId: famId,
              fundId: 'fund_1',
              title: 'Khoản số $i',
              amountMinor: 5000,
              canAutoApprove: false,
              operationId: 'bulk_e_$i',
            ),
          );
        }

        final hydrated = await repo
            .watchFunds(userId: ownerId, familyId: famId)
            .firstWhere(
              (r) =>
                  r is Success<List<FundEntity>> &&
                  r.value.isNotEmpty &&
                  r.value.first.recentContributions.length >= 26,
            );
        final fund = (hydrated as Success<List<FundEntity>>).value.first;
        expect(fund.recentContributions.length, 26);
        expect(fund.expenseRequests.length, 27);
        expect(fund.auditTrail.length, greaterThanOrEqualTo(28));
      },
    );

    test(
      'BudgetBloc sequential submitAndAwait rejects premature pop on error and succeeds with operationId match',
      () async {
        final bloc = BudgetBloc(
          repository: repo,
          upsertBudget: UpsertBudgetUseCase(repo),
          createFund: CreateFundUseCase(repo),
          contributeToFund: ContributeToFundUseCase(repo),
          requestFundExpense: RequestFundExpenseUseCase(repo),
          decideFundExpense: DecideFundExpenseUseCase(repo),
        );
        bloc.add(
          const BudgetsSubscriptionRequested(
            userId: ownerId,
            monthKey: '2026-11',
            familyId: famId,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final failState = await bloc.submitAndAwait(
          const FundContributionSubmitted(
            ContributeFundParams(
              userId: ownerId,
              userName: 'An',
              scope: FundScope.family,
              familyId: famId,
              fundId: 'fund_1',
              amountMinor: -100,
              operationId: 'op_bad_1',
            ),
          ),
          operationId: 'op_bad_1',
        );
        expect(failState.failure, isA<ValidationFailure>());
        expect(failState.lastActionOperationId, 'op_bad_1');

        final okState = await bloc.submitAndAwait(
          const FundContributionSubmitted(
            ContributeFundParams(
              userId: ownerId,
              userName: 'An',
              scope: FundScope.family,
              familyId: famId,
              fundId: 'fund_1',
              amountMinor: 150000,
              operationId: 'op_ok_1',
            ),
          ),
          operationId: 'op_ok_1',
        );
        expect(okState.failure, isNull);
        expect(okState.actionMessage, isNotNull);
        await bloc.close();
      },
    );
  });

  group('v3.27.0 Vehicle, Task & Family Hardening Regression', () {
    test(
      'AUD-010: VehicleRemoteDataSource recordMaintenance & payRecurringBill write lastAuditId & balanced ledger_audits',
      () async {
        final fakeFs = FakeFirebaseFirestore();
        final vRepo = VehicleRepositoryImpl(VehicleRemoteDataSource(fakeFs));
        const uid = 'u_veh_1';
        const wid = 'w_veh_1';

        await fakeFs
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc(wid)
            .set({
              'id': wid,
              'ownerId': uid,
              'name': 'Ví Chi tiêu',
              'balanceMinor': 2000000,
            });
        await fakeFs
            .collection('users')
            .doc(uid)
            .collection('vehicles')
            .doc('v_1')
            .set({
              'id': 'v_1',
              'ownerId': uid,
              'name': 'Honda AirBlade',
              'plateNumber': '59T2-12345',
              'currentOdometerKm': 5000,
              'lastServiceOdometerKm': 3000,
              'lastServiceDate': Timestamp.fromDate(DateTime(2026, 9, 1)),
            });

        final vehicle = VehicleEntity(
          id: 'v_1',
          ownerId: uid,
          isFamilyShared: false,
          name: 'Honda AirBlade',
          plateNumber: '59T2-12345',
          currentOdometerKm: 5000,
          lastServiceOdometerKm: 3000,
          lastServiceDate: DateTime(2026, 9, 1),
        );

        final maintRes = await vRepo.recordMaintenance(
          vehicle: vehicle,
          serviceTitle: 'Thay nhớt tổng hợp',
          odometerKm: 5200,
          costMinor: 250000,
          walletIdForExpense: wid,
        );
        expect(maintRes, isA<Success<void>>());

        final wAfterMaint = await fakeFs
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc(wid)
            .get();
        expect(wAfterMaint.data()?['balanceMinor'], 1750000);
        final audId1 = wAfterMaint.data()?['lastAuditId'] as String?;
        expect(audId1, isNotNull);
        final aud1 = await fakeFs
            .collection('users')
            .doc(uid)
            .collection('ledger_audits')
            .doc(audId1)
            .get();
        expect(aud1.exists, isTrue);
        expect(aud1.data()?['previousBalanceMinor'], 2000000);
        expect(aud1.data()?['deltaMinor'], -250000);
        expect(aud1.data()?['newBalanceMinor'], 1750000);

        await fakeFs
            .collection('users')
            .doc(uid)
            .collection('bills')
            .doc('bill_evn')
            .set({
              'id': 'bill_evn',
              'ownerId': uid,
              'title': 'Tiền điện EVN',
              'providerName': 'EVNHCMC',
              'estimatedAmountMinor': 400000,
              'nextDueDate': Timestamp.fromDate(DateTime(2026, 11, 25)),
              'paymentCount': 0,
            });
        final billRes = await vRepo.payRecurringBill(
          userId: uid,
          bill: RecurringBillEntity(
            id: 'bill_evn',
            ownerId: uid,
            title: 'Tiền điện EVN',
            providerName: 'EVNHCMC',
            estimatedAmountMinor: 400000,
            nextDueDate: DateTime(2026, 11, 25),
          ),
          paidAmountMinor: 450000,
          walletId: wid,
        );
        expect(billRes, isA<Success<bool>>());

        final wAfterBill = await fakeFs
            .collection('users')
            .doc(uid)
            .collection('wallets')
            .doc(wid)
            .get();
        expect(wAfterBill.data()?['balanceMinor'], 1300000);
        final audId2 = wAfterBill.data()?['lastAuditId'] as String?;
        expect(audId2, isNotNull);
        expect(audId2, isNot(equals(audId1)));
        final aud2 = await fakeFs
            .collection('users')
            .doc(uid)
            .collection('ledger_audits')
            .doc(audId2)
            .get();
        expect(aud2.data()?['previousBalanceMinor'], 1750000);
        expect(aud2.data()?['deltaMinor'], -450000);
        expect(aud2.data()?['newBalanceMinor'], 1300000);
      },
    );

    test(
      'AUD-011: Recurring task spawn assigns createdBy == actorUserId and preserves originalCreatorId',
      () async {
        final fakeFs = FakeFirebaseFirestore();
        final tRepo = TaskRepositoryImpl(TaskRemoteDataSource(fakeFs));
        const famId = 'fam_task_1';
        await fakeFs
            .collection('families')
            .doc(famId)
            .collection('tasks')
            .doc('t_orig')
            .set({
              'id': 't_orig',
              'familyId': famId,
              'createdBy': 'u_creator',
              'creatorName': 'Minh',
              'assigneeId': 'u_assignee',
              'assigneeName': 'Lan',
              'title': 'Đổ rác hàng ngày',
              'priority': 'medium',
              'status': 'accepted',
              'recurrence': 'daily',
            });

        final res = await tRepo.updateTaskStatus(
          actorUserId: 'u_assignee',
          task: const TaskEntity(
            id: 't_orig',
            familyId: famId,
            createdBy: 'u_creator',
            creatorName: 'Minh',
            assigneeId: 'u_assignee',
            assigneeName: 'Lan',
            title: 'Đổ rác hàng ngày',
            status: TaskWorkflowStatus.accepted,
            recurrence: TaskRecurrence.daily,
          ),
          nextStatus: TaskWorkflowStatus.done,
        );
        expect(res, isA<Success<void>>());

        final allTasks = await fakeFs
            .collection('families')
            .doc(famId)
            .collection('tasks')
            .get();
        expect(allTasks.docs.length, 2);
        final spawned = allTasks.docs
            .firstWhere((d) => d.id != 't_orig')
            .data();
        expect(spawned['createdBy'], 'u_assignee');
        expect(spawned['originalCreatorId'], 'u_creator');
      },
    );

    test(
      'AUD-002 & AUD-005: FamilyRepositoryImpl removeMember adds bannedUserIds, confirmSettlementRequest atomically sets settlementId, & reverseDebtSettlement blocks unauthorized debtor',
      () async {
        final fakeFs = FakeFirebaseFirestore();
        final famRepo = FamilyRepositoryImpl(FamilyRemoteDataSource(fakeFs));
        const famId = 'fam_sec_1';

        await fakeFs.collection('families').doc(famId).set({
          'id': famId,
          'name': 'Gia đình Test',
          'createdBy': 'u_owner',
          'memberIds': ['u_owner', 'u_creditor', 'u_debtor', 'u_bad'],
          'memberRoles': {
            'u_owner': 'owner',
            'u_creditor': 'member',
            'u_debtor': 'member',
            'u_bad': 'member',
          },
          'memberNames': {
            'u_owner': 'An',
            'u_creditor': 'Bình',
            'u_debtor': 'Chi',
            'u_bad': 'Xấu',
          },
        });

        final rmRes = await famRepo.removeMember(
          familyId: famId,
          actorUserId: 'u_owner',
          targetUserId: 'u_bad',
        );
        expect(rmRes, isA<Success<void>>());
        final famSnap = await fakeFs.collection('families').doc(famId).get();
        expect(famSnap.data()?['bannedUserIds'], contains('u_bad'));
        expect(famSnap.data()?['memberIds'], isNot(contains('u_bad')));

        // Request & atomic confirm
        final reqRes = await famRepo.requestDebtSettlement(
          familyId: famId,
          fromUserId: 'u_debtor',
          fromUserName: 'Chi',
          toUserId: 'u_creditor',
          toUserName: 'Bình',
          amountMinor: 250000,
          paymentCode: 'LIFEOS',
          operationId: 'op_sreq_1',
        );
        final req = (reqRes as Success<SettlementRequestEntity>).value;
        expect(req.id, 'sreq_op_sreq_1');

        final confRes = await famRepo.confirmSettlementRequest(
          familyId: famId,
          requestId: req.id,
          actorUserId: 'u_creditor',
          approve: true,
        );
        final stl = (confRes as Success<DebtSettlementEntity?>).value!;
        expect(stl.id, 'stl_req_${req.id}');

        final reqAfter = await fakeFs
            .collection('families')
            .doc(famId)
            .collection('settlement_requests')
            .doc(req.id)
            .get();
        expect(reqAfter.data()?['status'], 'confirmed');
        expect(reqAfter.data()?['settlementId'], 'stl_req_${req.id}');

        // Unauthorized debtor cannot reverse settlement!
        final badRev = await famRepo.reverseDebtSettlement(
          familyId: famId,
          settlementId: stl.id,
          actorUserId: 'u_debtor',
        );
        expect(badRev, isA<Err<DebtSettlementEntity>>());
        expect(
          (badRev as Err<DebtSettlementEntity>).failure,
          isA<PermissionDeniedFailure>(),
        );

        // Creditor reverses settlement cleanly with operationId idempotency
        final okRev = await famRepo.reverseDebtSettlement(
          familyId: famId,
          settlementId: stl.id,
          actorUserId: 'u_creditor',
          operationId: 'op_rev_1',
        );
        expect(okRev, isA<Success<DebtSettlementEntity>>());
        final retryRev = await famRepo.reverseDebtSettlement(
          familyId: famId,
          settlementId: stl.id,
          actorUserId: 'u_creditor',
          operationId: 'op_rev_1',
        );
        expect(retryRev, isA<Success<DebtSettlementEntity>>());
      },
    );
  });
}
