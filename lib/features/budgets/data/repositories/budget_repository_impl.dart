import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../../transactions/data/models/transaction_models.dart';
import '../../../transactions/domain/entities/financial_aggregation_engine.dart';
import '../../../transactions/domain/entities/ledger_integrity_engine.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../domain/entities/budget_entities.dart';
import '../../domain/repositories/budget_repository.dart';

class BudgetRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseAuth? _firebaseAuth;
  static const Uuid _uuid = Uuid();

  const BudgetRemoteDataSource(
    this._firestore, {
    FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth;

  Stream<List<BudgetEntity>> watchBudgets({
    required String userId,
    required String monthKey,
  }) {
    final budgetsStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('budgets')
        .where('monthKey', isEqualTo: monthKey)
        .snapshots();

    final txsStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('monthKey', isEqualTo: monthKey)
        .snapshots();

    return StreamCombiner.combine2(budgetsStream, txsStream, (bSnap, txSnap) {
      final txs = txSnap.docs
          .map((doc) => TransactionModel.fromFirestore(doc).entity)
          .toList(growable: false);
      final agg = FinancialAggregationEngine.aggregate(txs);
      final spentByCat = agg.expenseByCategory;

      return bSnap.docs.map((doc) {
        final d = doc.data();
        final catName = (d['categoryName'] as String?) ?? 'Danh mục';
        return BudgetEntity(
          id: (d['id'] as String?) ?? doc.id,
          ownerId: (d['ownerId'] as String?) ?? userId,
          categoryId: (d['categoryId'] as String?) ?? '',
          categoryName: catName,
          monthKey: (d['monthKey'] as String?) ?? monthKey,
          limitMinor: (d['limitMinor'] as num?)?.toInt() ?? 0,
          spentMinor: spentByCat[catName] ?? 0,
          alertThresholdPct: (d['alertThresholdPct'] as num?)?.toInt() ?? 80,
        );
      }).toList();
    });
  }

  DateTime _readDateTime(dynamic value, DateTime fallback) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return fallback;
  }

  FundEntity _mapHydratedFund({
    required DocumentSnapshot<Map<String, dynamic>> doc,
    required QuerySnapshot<Map<String, dynamic>> contribSnap,
    required QuerySnapshot<Map<String, dynamic>> expSnap,
    required QuerySnapshot<Map<String, dynamic>> auditSnap,
    required FundScope scope,
  }) {
    final d = doc.data() ?? const <String, dynamic>{};
    final now = DateTime.now();
    final fundId = (d['id'] as String?) ?? doc.id;

    final contributions = contribSnap.docs.map((c) {
      final cd = c.data();
      return FundContributionEntity(
        id: (cd['id'] as String?) ?? c.id,
        fundId: (cd['fundId'] as String?) ?? fundId,
        contributorId: (cd['contributorId'] as String?) ?? '',
        contributorName: (cd['contributorName'] as String?) ?? 'Thành viên',
        amountMinor: (cd['amountMinor'] as num?)?.toInt() ?? 0,
        note: cd['note'] as String?,
        operationId: cd['operationId'] as String?,
        sourceWalletId: cd['sourceWalletId'] as String?,
        createdAt: _readDateTime(cd['createdAt'], now),
      );
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final expenses = expSnap.docs.map((e) {
      final ed = e.data();
      return FundExpenseRequestEntity(
        id: (ed['id'] as String?) ?? e.id,
        fundId: (ed['fundId'] as String?) ?? fundId,
        requesterId: (ed['requesterId'] as String?) ?? '',
        requesterName: (ed['requesterName'] as String?) ?? 'Thành viên',
        title: (ed['title'] as String?) ?? '',
        amountMinor: (ed['amountMinor'] as num?)?.toInt() ?? 0,
        status: FundExpenseStatus.fromWireValue(ed['status'] as String?),
        operationId: ed['operationId'] as String?,
        decidedBy: ed['decidedBy'] as String?,
        decidedAt: ed['decidedAt'] != null
            ? _readDateTime(ed['decidedAt'], now)
            : null,
        executedBy: ed['executedBy'] as String?,
        executedAt: ed['executedAt'] != null
            ? _readDateTime(ed['executedAt'], now)
            : null,
        reconciledTxId: ed['reconciledTxId'] as String?,
        disputeReason: ed['disputeReason'] as String?,
        disputedBy: ed['disputedBy'] as String?,
        disputedAt: ed['disputedAt'] != null
            ? _readDateTime(ed['disputedAt'], now)
            : null,
        reversalReason: ed['reversalReason'] as String?,
        createdAt: _readDateTime(ed['createdAt'], now),
      );
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final audits = auditSnap.docs.map((a) {
      final ad = a.data();
      return FundAuditEntry(
        id: (ad['id'] as String?) ?? a.id,
        fundId: (ad['fundId'] as String?) ?? fundId,
        actorId: (ad['actorId'] as String?) ?? '',
        eventType: (ad['eventType'] as String?) ?? '',
        eventId: (ad['eventId'] as String?) ?? '',
        previousBalanceMinor:
            (ad['previousBalanceMinor'] as num?)?.toInt() ?? 0,
        deltaMinor: (ad['deltaMinor'] as num?)?.toInt() ?? 0,
        newBalanceMinor: (ad['newBalanceMinor'] as num?)?.toInt() ?? 0,
        createdAt: _readDateTime(ad['createdAt'], now),
      );
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final computedIn = contributions.fold<int>(0, (s, c) => s + c.amountMinor);
    final computedOut = expenses
        .where((e) => e.status.affectsBalance)
        .fold<int>(0, (s, e) => s + e.amountMinor);

    return FundEntity(
      id: fundId,
      scope: scope,
      ownerId: d['ownerId'] as String?,
      familyId: d['familyId'] as String?,
      name: (d['name'] as String?) ?? 'Quỹ',
      targetAmountMinor: (d['targetAmountMinor'] as num?)?.toInt() ?? 0,
      balanceMinor: (d['balanceMinor'] as num?)?.toInt() ?? 0,
      totalContributedMinor:
          (d['totalContributedMinor'] as num?)?.toInt() ?? computedIn,
      totalExecutedMinor:
          (d['totalExecutedMinor'] as num?)?.toInt() ?? computedOut,
      recentContributions: List.unmodifiable(contributions),
      expenseRequests: List.unmodifiable(expenses),
      auditTrail: List.unmodifiable(audits),
    );
  }

  Stream<FundEntity?> _watchSingleFund(
    DocumentReference<Map<String, dynamic>> docRef,
    FundScope scope,
  ) {
    return StreamCombiner.combine4<
      DocumentSnapshot<Map<String, dynamic>>,
      QuerySnapshot<Map<String, dynamic>>,
      QuerySnapshot<Map<String, dynamic>>,
      QuerySnapshot<Map<String, dynamic>>,
      FundEntity?
    >(
      docRef.snapshots(),
      docRef.collection('contributions').snapshots(),
      docRef.collection('expenses').snapshots(),
      docRef.collection('fund_audits').snapshots(),
      (docSnap, contribSnap, expSnap, auditSnap) {
        if (!docSnap.exists) return null;
        return _mapHydratedFund(
          doc: docSnap,
          contribSnap: contribSnap,
          expSnap: expSnap,
          auditSnap: auditSnap,
          scope: scope,
        );
      },
    );
  }

  Stream<List<FundEntity>> _watchFundsCollection(
    CollectionReference<Map<String, dynamic>> colRef,
    FundScope scope,
  ) {
    return Stream<List<FundEntity>>.multi((controller) {
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? colSub;
      final childSubs = <String, StreamSubscription<FundEntity?>>{};
      final latestFunds = <String, FundEntity?>{};
      var orderedIds = <String>[];

      void emitIfReady() {
        if (controller.isClosed) return;
        if (orderedIds.isEmpty) {
          controller.add(const <FundEntity>[]);
          return;
        }
        if (orderedIds.every((id) => latestFunds.containsKey(id))) {
          final items = <FundEntity>[
            for (final id in orderedIds)
              if (latestFunds[id] != null) latestFunds[id]!,
          ];
          controller.add(items);
        }
      }

      colSub = colRef.snapshots().listen(
        (snap) {
          final nextIds = snap.docs.map((d) => d.id).toList();
          final nextSet = nextIds.toSet();

          for (final existingId in childSubs.keys.toList()) {
            if (!nextSet.contains(existingId)) {
              unawaited(childSubs.remove(existingId)?.cancel());
              latestFunds.remove(existingId);
            }
          }

          orderedIds = nextIds;
          if (orderedIds.isEmpty) {
            emitIfReady();
            return;
          }

          for (final doc in snap.docs) {
            if (!childSubs.containsKey(doc.id)) {
              childSubs[doc.id] = _watchSingleFund(doc.reference, scope).listen(
                (fund) {
                  latestFunds[doc.id] = fund;
                  emitIfReady();
                },
                onError: (Object e, StackTrace st) {
                  if (!controller.isClosed) {
                    controller.addError(e, st);
                  }
                },
              );
            }
          }
          emitIfReady();
        },
        onError: (Object e, StackTrace st) {
          if (!controller.isClosed) {
            controller.addError(e, st);
          }
        },
      );

      controller.onCancel = () async {
        await colSub?.cancel();
        for (final sub in childSubs.values) {
          await sub.cancel();
        }
        childSubs.clear();
      };
    });
  }

  Stream<List<FundEntity>> watchFunds({
    required String userId,
    String? familyId,
  }) {
    final personalStream = _watchFundsCollection(
      _firestore.collection('users').doc(userId).collection('personal_funds'),
      FundScope.personal,
    );

    if (familyId == null || familyId.isEmpty) {
      return personalStream;
    }

    final familyStream = _watchFundsCollection(
      _firestore.collection('families').doc(familyId).collection('funds'),
      FundScope.family,
    );

    return StreamCombiner.combine2(
      personalStream,
      familyStream,
      (p, f) => <FundEntity>[...f, ...p],
    );
  }

  Future<void> upsertBudget({
    required String userId,
    required String categoryId,
    required String categoryName,
    required String monthKey,
    required int limitMinor,
    required int alertThresholdPct,
  }) async {
    final id = '${monthKey}_$categoryId';
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('budgets')
        .doc(id)
        .set({
          'id': id,
          'ownerId': userId,
          'categoryId': categoryId,
          'categoryName': categoryName,
          'monthKey': monthKey,
          'limitMinor': limitMinor,
          'alertThresholdPct': alertThresholdPct,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
  }

  DocumentReference<Map<String, dynamic>> _fundDocRef({
    required FundScope scope,
    required String userId,
    String? familyId,
    required String fundId,
  }) {
    if (scope == FundScope.personal) {
      return _firestore
          .collection('users')
          .doc(userId)
          .collection('personal_funds')
          .doc(fundId);
    }
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('funds')
        .doc(fundId);
  }

  Future<void> createFund({
    required String userId,
    String? familyId,
    required FundScope scope,
    required String name,
    required int targetAmountMinor,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final ref = _fundDocRef(
      scope: scope,
      userId: userId,
      familyId: familyId,
      fundId: id,
    );
    await ref.set({
      'id': id,
      'ownerId': userId,
      'familyId': scope == FundScope.family ? familyId : null,
      'scope': scope.name,
      'name': name,
      'targetAmountMinor': targetAmountMinor,
      'balanceMinor': 0,
      'totalContributedMinor': 0,
      'totalExecutedMinor': 0,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  Future<void> contributeToFund({
    required String userId,
    required String userName,
    required FundScope scope,
    String? familyId,
    required String fundId,
    required int amountMinor,
    String? note,
    String? sourceWalletId,
    String? operationId,
  }) async {
    if (amountMinor <= 0) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Số tiền đóng góp quỹ phải lớn hơn 0 ₫.',
      );
    }

    final fundRef = _fundDocRef(
      scope: scope,
      userId: userId,
      familyId: familyId,
      fundId: fundId,
    );
    final cleanOpId = (operationId != null && operationId.trim().isNotEmpty)
        ? operationId.trim()
        : _uuid.v4();
    final contribId = (operationId != null && operationId.trim().isNotEmpty)
        ? 'cnt_$cleanOpId'
        : _uuid.v4();
    final contribRef = fundRef.collection('contributions').doc(contribId);
    final cleanWalletId = sourceWalletId?.trim();
    final hasSourceWallet = cleanWalletId != null && cleanWalletId.isNotEmpty;

    await _firestore.runTransaction((tx) async {
      // Idempotency guard: avoid duplicate balance effect on operationId replay
      final existingContrib = await tx.get(contribRef);
      if (existingContrib.exists) {
        return;
      }

      final snap = await tx.get(fundRef);
      if (!snap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy quỹ.',
        );
      }

      DocumentReference<Map<String, dynamic>>? walletRef;
      DocumentSnapshot<Map<String, dynamic>>? walletSnap;
      if (hasSourceWallet) {
        walletRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('wallets')
            .doc(cleanWalletId);
        walletSnap = await tx.get(walletRef);
        if (!walletSnap.exists) {
          throw const AppException(
            code: 'NOT_FOUND',
            message: 'Không tìm thấy ví nguồn thanh toán.',
          );
        }
      }

      final fundData = snap.data() ?? const <String, dynamic>{};
      final currentBal = (fundData['balanceMinor'] as num?)?.toInt() ?? 0;
      final currentTotalContributed =
          (fundData['totalContributedMinor'] as num?)?.toInt() ?? currentBal;
      final fundName = (fundData['name'] as String?) ?? 'Quỹ gia đình';
      final newFundBal = currentBal + amountMinor;
      final now = DateTime.now();
      final tsNow = Timestamp.fromDate(now);
      final fundAuditId = 'faud_$contribId';

      LedgerAuditRecord? walletAuditRecord;
      int? newWalletBal;
      String? walletName;
      String? ledgerTxId;
      String? ledgerAuditId;

      if (hasSourceWallet && walletSnap != null) {
        final wData = walletSnap.data() ?? const <String, dynamic>{};
        final wBal = (wData['balanceMinor'] as num?)?.toInt() ?? 0;
        final wType = (wData['type'] as String?) ?? 'cash';
        walletName = (wData['name'] as String?) ?? 'Ví nguồn';
        if (wType != WalletType.creditCard.name && wBal < amountMinor) {
          throw const AppException(
            code: 'VALIDATION_FAILURE',
            message: 'Số dư ví nguồn không đủ để đóng góp vào quỹ.',
          );
        }
        newWalletBal = wBal - amountMinor;
        ledgerTxId = 'fund_cnt_$contribId';
        ledgerAuditId = 'aud_$ledgerTxId';
        final auditRes = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: ledgerAuditId,
          operationId: ledgerTxId,
          transactionId: ledgerTxId,
          walletId: cleanWalletId,
          previousBalanceMinor: wBal,
          deltaAmountMinor: -amountMinor,
          newBalanceMinor: newWalletBal,
          createdAt: now,
          actorId: userId,
          source: 'fund_contribution',
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
          walletName: walletName,
          kind: TransactionKind.expense.name,
        );
        if (auditRes is Err<LedgerAuditRecord>) {
          throw AppException(
            code: auditRes.failure.code,
            message: auditRes.failure.message,
          );
        }
        walletAuditRecord = (auditRes as Success<LedgerAuditRecord>).value;
      }

      tx.set(contribRef, {
        'id': contribId,
        'fundId': fundId,
        'contributorId': userId,
        'contributorName': userName,
        'amountMinor': amountMinor,
        if (note != null && note.isNotEmpty) 'note': note,
        'operationId': cleanOpId,
        if (hasSourceWallet) 'sourceWalletId': cleanWalletId,
        'createdAt': tsNow,
      });

      tx.set(fundRef.collection('fund_audits').doc(fundAuditId), {
        'id': fundAuditId,
        'fundId': fundId,
        'actorId': userId,
        'eventType': 'contribution',
        'eventId': contribId,
        'previousBalanceMinor': currentBal,
        'deltaMinor': amountMinor,
        'newBalanceMinor': newFundBal,
        'createdAt': tsNow,
      });

      tx.update(fundRef, {
        'balanceMinor': newFundBal,
        'totalContributedMinor': currentTotalContributed + amountMinor,
        'lastAuditId': fundAuditId,
        'lastEventType': 'contribution',
        'lastEventId': contribId,
        'updatedAt': tsNow,
      });

      if (hasSourceWallet &&
          walletRef != null &&
          walletAuditRecord != null &&
          newWalletBal != null &&
          ledgerTxId != null &&
          ledgerAuditId != null) {
        final txRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('transactions')
            .doc(ledgerTxId);
        final auditRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('ledger_audits')
            .doc(ledgerAuditId);
        final fp = BankNotificationParser.computeCrossSourceFingerprint(
          ownerId: userId,
          direction: 'debit',
          amountMinor: amountMinor,
          occurredAt: now,
        );

        tx.update(walletRef, {
          'balanceMinor': newWalletBal,
          'lastAuditId': ledgerAuditId,
          'updatedAt': tsNow,
        });
        tx.set(auditRef, walletAuditRecord.toPayloadMap(createdAtValue: tsNow));
        tx.set(
          txRef,
          TransactionModel.toFirestoreMap(
            id: ledgerTxId,
            operationId: ledgerTxId,
            ownerId: userId,
            walletId: cleanWalletId,
            categoryName: scope == FundScope.family
                ? 'Hiếu hỉ & Đối ngoại'
                : 'Chi tiêu khác',
            kind: TransactionKind.expense,
            direction: 'debit',
            amountMinor: amountMinor,
            merchant: 'Nạp quỹ: $fundName',
            note: note,
            occurredAt: now,
            sourceKind: TransactionSourceKind.manual,
            verification: TransactionVerification.userConfirmed,
            verificationStatus: LedgerVerificationStatuses.userConfirmed,
            crossSourceFingerprint: fp,
            balanceAfterMinor: newWalletBal,
            walletName: walletName,
            now: now,
          ),
        );
      }
    });
  }

  Future<void> requestFundExpense({
    required String userId,
    required String userName,
    required FundScope scope,
    String? familyId,
    required String fundId,
    required String title,
    required int amountMinor,
    required bool canAutoApprove,
    bool saveAsDraft = false,
    String? operationId,
  }) async {
    if (amountMinor <= 0) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Số tiền đề xuất chi phải lớn hơn 0 ₫.',
      );
    }
    final fundRef = _fundDocRef(
      scope: scope,
      userId: userId,
      familyId: familyId,
      fundId: fundId,
    );
    final cleanOpId = (operationId != null && operationId.trim().isNotEmpty)
        ? operationId.trim()
        : _uuid.v4();
    final expId = (operationId != null && operationId.trim().isNotEmpty)
        ? 'exp_$cleanOpId'
        : _uuid.v4();
    final expRef = fundRef.collection('expenses').doc(expId);

    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(expRef);
      if (existing.exists) {
        return;
      }

      final snap = await tx.get(fundRef);
      if (!snap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy quỹ.',
        );
      }

      final fundData = snap.data() ?? const <String, dynamic>{};
      final currentBal = (fundData['balanceMinor'] as num?)?.toInt() ?? 0;
      final currentTotalExecuted =
          (fundData['totalExecutedMinor'] as num?)?.toInt() ?? 0;

      // AUD-006: NEVER allow auto-approval on FundScope.family!
      final personalAutoExecute =
          scope == FundScope.personal && canAutoApprove && !saveAsDraft;
      if (personalAutoExecute && currentBal < amountMinor) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Số dư sổ sách của quỹ không đủ để chi khoản này.',
        );
      }

      final now = DateTime.now();
      final tsNow = Timestamp.fromDate(now);

      if (personalAutoExecute) {
        final newBal = currentBal - amountMinor;
        final auditId = 'faud_exec_$expId';
        tx.set(expRef, {
          'id': expId,
          'fundId': fundId,
          'requesterId': userId,
          'requesterName': userName,
          'title': title,
          'amountMinor': amountMinor,
          'status': FundExpenseStatus.executed.toWireValue(),
          'operationId': cleanOpId,
          'decidedBy': userId,
          'decidedAt': tsNow,
          'executedBy': userId,
          'executedAt': tsNow,
          'createdAt': tsNow,
          'updatedAt': tsNow,
        });
        tx.set(fundRef.collection('fund_audits').doc(auditId), {
          'id': auditId,
          'fundId': fundId,
          'actorId': userId,
          'eventType': 'expense_executed',
          'eventId': expId,
          'previousBalanceMinor': currentBal,
          'deltaMinor': -amountMinor,
          'newBalanceMinor': newBal,
          'createdAt': tsNow,
        });
        tx.update(fundRef, {
          'balanceMinor': newBal,
          'totalExecutedMinor': currentTotalExecuted + amountMinor,
          'lastAuditId': auditId,
          'lastEventType': 'expense_executed',
          'lastEventId': expId,
          'updatedAt': tsNow,
        });
      } else {
        final initialStatus = saveAsDraft
            ? FundExpenseStatus.draft
            : FundExpenseStatus.pendingApproval;
        tx.set(expRef, {
          'id': expId,
          'fundId': fundId,
          'requesterId': userId,
          'requesterName': userName,
          'title': title,
          'amountMinor': amountMinor,
          'status': initialStatus.toWireValue(),
          'operationId': cleanOpId,
          'createdAt': tsNow,
          'updatedAt': tsNow,
        });
      }
    });
  }

  Future<void> submitFundExpenseDraft({
    required FundScope scope,
    required String userId,
    String? familyId,
    required String fundId,
    required String expenseId,
    String? updatedTitle,
    int? updatedAmountMinor,
  }) async {
    final fundRef = _fundDocRef(
      scope: scope,
      userId: userId,
      familyId: familyId,
      fundId: fundId,
    );
    final expRef = fundRef.collection('expenses').doc(expenseId);

    await _firestore.runTransaction((tx) async {
      final expSnap = await tx.get(expRef);
      if (!expSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy bản nháp đề xuất chi quỹ.',
        );
      }
      final ed = expSnap.data() ?? const <String, dynamic>{};
      final currentStatus = FundExpenseStatus.fromWireValue(
        ed['status'] as String?,
      );
      final requesterId = (ed['requesterId'] as String?) ?? '';
      if (!FundExpenseStateMachine.canUserSubmitDraft(
        currentStatus: currentStatus,
        actorUserId: userId,
        requesterId: requesterId,
      )) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message: 'Chỉ người tạo bản nháp mới có thể gửi phê duyệt.',
        );
      }

      final now = DateTime.now();
      tx.update(expRef, {
        'status': FundExpenseStatus.pendingApproval.toWireValue(),
        if (updatedTitle != null && updatedTitle.trim().length >= 2)
          'title': updatedTitle.trim(),
        if (updatedAmountMinor != null && updatedAmountMinor > 0)
          'amountMinor': updatedAmountMinor,
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<({List<String> memberIds, bool isManager})> _loadFamilyRoleContext(
    Transaction tx, {
    required String familyId,
    required String actorUserId,
  }) async {
    final famRef = _firestore.collection('families').doc(familyId);
    final famSnap = await tx.get(famRef);
    if (!famSnap.exists) {
      throw const AppException(
        code: 'NOT_FOUND',
        message: 'Không tìm thấy nhóm gia đình.',
      );
    }
    final famData = famSnap.data() ?? const <String, dynamic>{};
    final memberIds =
        (famData['memberIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList();
    final memberRoles = Map<String, dynamic>.from(
      (famData['memberRoles'] as Map<dynamic, dynamic>?) ??
          const <dynamic, dynamic>{},
    );
    final role = memberRoles[actorUserId]?.toString();
    final isManager =
        memberIds.contains(actorUserId) &&
        (role == 'owner' || role == 'admin');
    return (memberIds: memberIds, isManager: isManager);
  }

  String _resolveActorUserId(String? actorUserId) {
    final direct = actorUserId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final authUid = _firebaseAuth?.currentUser?.uid.trim();
    if (authUid != null && authUid.isNotEmpty) return authUid;
    return '';
  }

  Future<void> decideFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required bool approve,
    String? actorUserId,
    String? operationId,
  }) async {
    final resolvedActor = _resolveActorUserId(actorUserId);
    if (resolvedActor.isEmpty) {
      throw const AppException(
        code: 'PERMISSION_DENIED',
        message: 'Thiếu thông tin người thực hiện duyệt chi.',
      );
    }

    final fundRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('funds')
        .doc(fundId);
    final expRef = fundRef.collection('expenses').doc(expenseId);

    await _firestore.runTransaction((tx) async {
      final roleCtx = await _loadFamilyRoleContext(
        tx,
        familyId: familyId,
        actorUserId: resolvedActor,
      );
      if (!roleCtx.isManager) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message:
              'Chỉ trưởng nhóm hoặc quản trị viên mới có quyền phê duyệt chi quỹ.',
        );
      }

      final fundSnap = await tx.get(fundRef);
      final expSnap = await tx.get(expRef);
      if (!fundSnap.exists || !expSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy đề xuất chi quỹ.',
        );
      }

      final ed = expSnap.data() ?? const <String, dynamic>{};
      final currentStatus = FundExpenseStatus.fromWireValue(
        ed['status'] as String?,
      );
      final nextStatus = approve
          ? FundExpenseStatus.approved
          : FundExpenseStatus.rejected;
      if (!FundExpenseStateMachine.canTransition(currentStatus, nextStatus)) {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Đề xuất chi này đã được xử lý.',
        );
      }

      final requesterId = (ed['requesterId'] as String?) ?? '';
      if (!FundExpenseStateMachine.canUserDecide(
        isManager: roleCtx.isManager,
        actorUserId: resolvedActor,
        requesterId: requesterId,
        memberCount: roleCtx.memberIds.length,
      )) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message:
              'Người đề xuất không thể tự duyệt khoản chi của chính mình trong nhóm nhiều thành viên.',
        );
      }

      final amountMinor = (ed['amountMinor'] as num?)?.toInt() ?? 0;
      final currentBal = (fundSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      if (approve && currentBal < amountMinor) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Số dư quỹ không đủ để phê duyệt khoản chi.',
        );
      }

      final now = DateTime.now();
      tx.update(expRef, {
        'status': nextStatus.toWireValue(),
        'decidedBy': resolvedActor,
        'decidedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> executeFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    String? operationId,
  }) async {
    final resolvedActor = _resolveActorUserId(actorUserId);
    if (resolvedActor.isEmpty) {
      throw const AppException(
        code: 'PERMISSION_DENIED',
        message: 'Thiếu thông tin người giải ngân.',
      );
    }

    final fundRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('funds')
        .doc(fundId);
    final expRef = fundRef.collection('expenses').doc(expenseId);

    await _firestore.runTransaction((tx) async {
      final roleCtx = await _loadFamilyRoleContext(
        tx,
        familyId: familyId,
        actorUserId: resolvedActor,
      );
      if (!roleCtx.isManager) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message: 'Chỉ trưởng nhóm hoặc quản trị viên mới có quyền giải ngân.',
        );
      }

      final fundSnap = await tx.get(fundRef);
      final expSnap = await tx.get(expRef);
      if (!fundSnap.exists || !expSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy khoản chi quỹ.',
        );
      }

      final ed = expSnap.data() ?? const <String, dynamic>{};
      final currentStatus = FundExpenseStatus.fromWireValue(
        ed['status'] as String?,
      );
      if (currentStatus == FundExpenseStatus.executed) {
        return; // Idempotent replay
      }
      if (!FundExpenseStateMachine.canTransition(
        currentStatus,
        FundExpenseStatus.executed,
      )) {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Chỉ khoản chi đã phê duyệt mới có thể giải ngân.',
        );
      }

      final amountMinor = (ed['amountMinor'] as num?)?.toInt() ?? 0;
      final fundData = fundSnap.data() ?? const <String, dynamic>{};
      final currentBal = (fundData['balanceMinor'] as num?)?.toInt() ?? 0;
      final currentTotalExecuted =
          (fundData['totalExecutedMinor'] as num?)?.toInt() ?? 0;

      if (currentBal < amountMinor) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Số dư quỹ hiện tại không đủ để giải ngân khoản chi này.',
        );
      }

      final newBal = currentBal - amountMinor;
      final now = DateTime.now();
      final tsNow = Timestamp.fromDate(now);
      final cleanOp = (operationId != null && operationId.trim().isNotEmpty)
          ? operationId.trim()
          : expenseId;
      final auditId = 'faud_exec_$cleanOp';

      tx.update(expRef, {
        'status': FundExpenseStatus.executed.toWireValue(),
        'executedBy': resolvedActor,
        'executedAt': tsNow,
        'updatedAt': tsNow,
      });

      tx.set(fundRef.collection('fund_audits').doc(auditId), {
        'id': auditId,
        'fundId': fundId,
        'actorId': resolvedActor,
        'eventType': 'expense_executed',
        'eventId': expenseId,
        'previousBalanceMinor': currentBal,
        'deltaMinor': -amountMinor,
        'newBalanceMinor': newBal,
        'createdAt': tsNow,
      });

      tx.update(fundRef, {
        'balanceMinor': newBal,
        'totalExecutedMinor': currentTotalExecuted + amountMinor,
        'lastAuditId': auditId,
        'lastEventType': 'expense_executed',
        'lastEventId': expenseId,
        'updatedAt': tsNow,
      });
    });
  }

  Future<void> reconcileFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    required String reconciledTxId,
    String? operationId,
  }) async {
    final resolvedActor = _resolveActorUserId(actorUserId);
    final fundRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('funds')
        .doc(fundId);
    final expRef = fundRef.collection('expenses').doc(expenseId);

    await _firestore.runTransaction((tx) async {
      final roleCtx = await _loadFamilyRoleContext(
        tx,
        familyId: familyId,
        actorUserId: resolvedActor,
      );
      if (!roleCtx.isManager) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message: 'Chỉ trưởng nhóm hoặc quản trị viên mới có quyền đối soát.',
        );
      }

      final expSnap = await tx.get(expRef);
      if (!expSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy khoản chi quỹ.',
        );
      }
      final ed = expSnap.data() ?? const <String, dynamic>{};
      final currentStatus = FundExpenseStatus.fromWireValue(
        ed['status'] as String?,
      );
      if (!FundExpenseStateMachine.canTransition(
        currentStatus,
        FundExpenseStatus.reconciled,
      )) {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Chỉ khoản chi đã giải ngân mới có thể đối soát.',
        );
      }

      final now = DateTime.now();
      tx.update(expRef, {
        'status': FundExpenseStatus.reconciled.toWireValue(),
        'reconciledTxId': reconciledTxId.trim(),
        'reconciledBy': resolvedActor,
        'reconciledAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> disputeFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    required String reason,
    String? operationId,
  }) async {
    final resolvedActor = _resolveActorUserId(actorUserId);
    final fundRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('funds')
        .doc(fundId);
    final expRef = fundRef.collection('expenses').doc(expenseId);

    await _firestore.runTransaction((tx) async {
      final roleCtx = await _loadFamilyRoleContext(
        tx,
        familyId: familyId,
        actorUserId: resolvedActor,
      );
      if (!roleCtx.memberIds.contains(resolvedActor)) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message: 'Chỉ thành viên trong nhóm mới có quyền gửi khiếu nại.',
        );
      }

      final expSnap = await tx.get(expRef);
      if (!expSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy khoản chi quỹ.',
        );
      }
      final ed = expSnap.data() ?? const <String, dynamic>{};
      final currentStatus = FundExpenseStatus.fromWireValue(
        ed['status'] as String?,
      );
      if (!FundExpenseStateMachine.canTransition(
        currentStatus,
        FundExpenseStatus.disputed,
      )) {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Chỉ khoản chi đã giải ngân mới có thể khiếu nại.',
        );
      }

      final now = DateTime.now();
      final tsNow = Timestamp.fromDate(now);
      tx.update(expRef, {
        'status': FundExpenseStatus.disputed.toWireValue(),
        'disputedBy': resolvedActor,
        'disputedAt': tsNow,
        'disputeReason': reason.trim(),
        'updatedAt': tsNow,
      });
    });
  }

  Future<void> reverseFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    String? reason,
    String? operationId,
  }) async {
    final resolvedActor = _resolveActorUserId(actorUserId);
    final fundRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('funds')
        .doc(fundId);
    final expRef = fundRef.collection('expenses').doc(expenseId);

    await _firestore.runTransaction((tx) async {
      final roleCtx = await _loadFamilyRoleContext(
        tx,
        familyId: familyId,
        actorUserId: resolvedActor,
      );
      if (!roleCtx.isManager) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message: 'Chỉ trưởng nhóm hoặc quản trị viên mới có quyền hoàn tác.',
        );
      }

      final fundSnap = await tx.get(fundRef);
      final expSnap = await tx.get(expRef);
      if (!fundSnap.exists || !expSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy khoản chi quỹ.',
        );
      }

      final ed = expSnap.data() ?? const <String, dynamic>{};
      final currentStatus = FundExpenseStatus.fromWireValue(
        ed['status'] as String?,
      );
      final cleanReverseOp = operationId?.trim();
      if (currentStatus == FundExpenseStatus.reversed &&
          cleanReverseOp != null &&
          cleanReverseOp.isNotEmpty &&
          ed['reverseOperationId'] == cleanReverseOp) {
        return; // Idempotent replay
      }
      if (!FundExpenseStateMachine.canTransition(
        currentStatus,
        FundExpenseStatus.reversed,
      )) {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Không thể hoàn tác khoản chi ở trạng thái hiện tại.',
        );
      }

      final now = DateTime.now();
      final tsNow = Timestamp.fromDate(now);
      final restoreBalance = FundExpenseStateMachine.doesReverseRestoreBalance(
        currentStatus,
      );

      tx.update(expRef, {
        'status': FundExpenseStatus.reversed.toWireValue(),
        'reversedBy': resolvedActor,
        'reversedAt': tsNow,
        if (cleanReverseOp != null && cleanReverseOp.isNotEmpty)
          'reverseOperationId': cleanReverseOp,
        if (reason != null && reason.trim().isNotEmpty)
          'reversalReason': reason.trim(),
        'updatedAt': tsNow,
      });

      if (restoreBalance) {
        final amountMinor = (ed['amountMinor'] as num?)?.toInt() ?? 0;
        final fundData = fundSnap.data() ?? const <String, dynamic>{};
        final currentBal = (fundData['balanceMinor'] as num?)?.toInt() ?? 0;
        final currentTotalExecuted =
            (fundData['totalExecutedMinor'] as num?)?.toInt() ?? 0;
        final newBal = currentBal + amountMinor;
        final cleanOp = (operationId != null && operationId.trim().isNotEmpty)
            ? operationId.trim()
            : expenseId;
        final auditId = 'faud_rev_$cleanOp';

        tx.set(fundRef.collection('fund_audits').doc(auditId), {
          'id': auditId,
          'fundId': fundId,
          'actorId': resolvedActor,
          'eventType': 'expense_reversed',
          'eventId': expenseId,
          'previousBalanceMinor': currentBal,
          'deltaMinor': amountMinor,
          'newBalanceMinor': newBal,
          'createdAt': tsNow,
        });

        tx.update(fundRef, {
          'balanceMinor': newBal,
          'totalExecutedMinor': currentTotalExecuted >= amountMinor
              ? currentTotalExecuted - amountMinor
              : 0,
          'lastAuditId': auditId,
          'lastEventType': 'expense_reversed',
          'lastEventId': expenseId,
          'updatedAt': tsNow,
        });
      }
    });
  }

  Future<void> cancelFundExpense({
    required FundScope scope,
    required String userId,
    String? familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    String? operationId,
  }) async {
    final resolvedActor = _resolveActorUserId(actorUserId);
    final fundRef = _fundDocRef(
      scope: scope,
      userId: userId,
      familyId: familyId,
      fundId: fundId,
    );
    final expRef = fundRef.collection('expenses').doc(expenseId);

    await _firestore.runTransaction((tx) async {
      final expSnap = await tx.get(expRef);
      if (!expSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy đề xuất chi quỹ.',
        );
      }
      final ed = expSnap.data() ?? const <String, dynamic>{};
      final currentStatus = FundExpenseStatus.fromWireValue(
        ed['status'] as String?,
      );
      final requesterId = (ed['requesterId'] as String?) ?? '';
      if (!FundExpenseStateMachine.canUserCancel(
        currentStatus: currentStatus,
        actorUserId: resolvedActor,
        requesterId: requesterId,
      )) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message:
              'Chỉ người đề xuất mới có thể hủy khi khoản chi đang ở nháp hoặc chờ duyệt.',
        );
      }

      final now = DateTime.now();
      tx.update(expRef, {
        'status': FundExpenseStatus.cancelled.toWireValue(),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }
}

class BudgetRepositoryImpl implements BudgetRepository {
  final BudgetRemoteDataSource _remoteDataSource;
  const BudgetRepositoryImpl(this._remoteDataSource);

  @override
  Stream<Result<List<BudgetEntity>>> watchBudgets({
    required String userId,
    required String monthKey,
  }) {
    return _remoteDataSource
        .watchBudgets(userId: userId, monthKey: monthKey)
        .map<Result<List<BudgetEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<BudgetEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Stream<Result<List<FundEntity>>> watchFunds({
    required String userId,
    String? familyId,
  }) {
    return _remoteDataSource
        .watchFunds(userId: userId, familyId: familyId)
        .map<Result<List<FundEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<FundEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<void>> upsertBudget({
    required String userId,
    required String categoryId,
    required String categoryName,
    required String monthKey,
    required int limitMinor,
    int alertThresholdPct = 80,
  }) async {
    try {
      await _remoteDataSource.upsertBudget(
        userId: userId,
        categoryId: categoryId,
        categoryName: categoryName,
        monthKey: monthKey,
        limitMinor: limitMinor,
        alertThresholdPct: alertThresholdPct,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> createFund({
    required String userId,
    String? familyId,
    required FundScope scope,
    required String name,
    required int targetAmountMinor,
  }) async {
    try {
      await _remoteDataSource.createFund(
        userId: userId,
        familyId: familyId,
        scope: scope,
        name: name,
        targetAmountMinor: targetAmountMinor,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> contributeToFund({
    required String userId,
    required String userName,
    required FundScope scope,
    String? familyId,
    required String fundId,
    required int amountMinor,
    String? note,
    String? sourceWalletId,
    String? operationId,
  }) async {
    try {
      await _remoteDataSource.contributeToFund(
        userId: userId,
        userName: userName,
        scope: scope,
        familyId: familyId,
        fundId: fundId,
        amountMinor: amountMinor,
        note: note,
        sourceWalletId: sourceWalletId,
        operationId: operationId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> requestFundExpense({
    required String userId,
    required String userName,
    required FundScope scope,
    String? familyId,
    required String fundId,
    required String title,
    required int amountMinor,
    required bool canAutoApprove,
    bool saveAsDraft = false,
    String? operationId,
  }) async {
    try {
      await _remoteDataSource.requestFundExpense(
        userId: userId,
        userName: userName,
        scope: scope,
        familyId: familyId,
        fundId: fundId,
        title: title,
        amountMinor: amountMinor,
        canAutoApprove: canAutoApprove,
        saveAsDraft: saveAsDraft,
        operationId: operationId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> submitFundExpenseDraft({
    required FundScope scope,
    required String userId,
    String? familyId,
    required String fundId,
    required String expenseId,
    String? updatedTitle,
    int? updatedAmountMinor,
  }) async {
    try {
      await _remoteDataSource.submitFundExpenseDraft(
        scope: scope,
        userId: userId,
        familyId: familyId,
        fundId: fundId,
        expenseId: expenseId,
        updatedTitle: updatedTitle,
        updatedAmountMinor: updatedAmountMinor,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> decideFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required bool approve,
    String? actorUserId,
    String? operationId,
  }) async {
    try {
      await _remoteDataSource.decideFundExpense(
        familyId: familyId,
        fundId: fundId,
        expenseId: expenseId,
        approve: approve,
        actorUserId: actorUserId,
        operationId: operationId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> executeFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    String? operationId,
  }) async {
    try {
      await _remoteDataSource.executeFundExpense(
        familyId: familyId,
        fundId: fundId,
        expenseId: expenseId,
        actorUserId: actorUserId,
        operationId: operationId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> reconcileFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    required String reconciledTxId,
    String? operationId,
  }) async {
    try {
      await _remoteDataSource.reconcileFundExpense(
        familyId: familyId,
        fundId: fundId,
        expenseId: expenseId,
        actorUserId: actorUserId,
        reconciledTxId: reconciledTxId,
        operationId: operationId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> disputeFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    required String reason,
    String? operationId,
  }) async {
    try {
      await _remoteDataSource.disputeFundExpense(
        familyId: familyId,
        fundId: fundId,
        expenseId: expenseId,
        actorUserId: actorUserId,
        reason: reason,
        operationId: operationId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> reverseFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    String? reason,
    String? operationId,
  }) async {
    try {
      await _remoteDataSource.reverseFundExpense(
        familyId: familyId,
        fundId: fundId,
        expenseId: expenseId,
        actorUserId: actorUserId,
        reason: reason,
        operationId: operationId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> cancelFundExpense({
    required FundScope scope,
    required String userId,
    String? familyId,
    required String fundId,
    required String expenseId,
    required String actorUserId,
    String? operationId,
  }) async {
    try {
      await _remoteDataSource.cancelFundExpense(
        scope: scope,
        userId: userId,
        familyId: familyId,
        fundId: fundId,
        expenseId: expenseId,
        actorUserId: actorUserId,
        operationId: operationId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
