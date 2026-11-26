import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../domain/entities/financial_aggregation_engine.dart';
import '../../domain/entities/ledger_integrity_engine.dart';
import '../../domain/entities/transaction_entities.dart';
import '../models/transaction_models.dart';

class TransactionRemoteDataSource {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  const TransactionRemoteDataSource(this._firestore);

  CollectionReference<Map<String, dynamic>> _walletsCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('wallets');

  CollectionReference<Map<String, dynamic>> _categoriesCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('categories');

  CollectionReference<Map<String, dynamic>> _txCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('transactions');

  CollectionReference<Map<String, dynamic>> _auditCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('ledger_audits');

  CollectionReference<Map<String, dynamic>> _snapshotCol(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('net_worth_snapshots');

  CollectionReference<Map<String, dynamic>> _monthlySummaryCol(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('monthly_summaries');

  static int _walletTypeRank(WalletType type) => switch (type) {
    WalletType.cash => 0,
    WalletType.bank => 1,
    WalletType.savings => 2,
    WalletType.creditCard => 3,
  };

  Stream<List<WalletModel>> watchWallets(String userId) {
    return _walletsCol(userId).snapshots(includeMetadataChanges: true).map((
      snap,
    ) {
      final list = snap.docs.map(WalletModel.fromFirestore).toList();
      list.sort((a, b) {
        if (a.id == 'wallet_cash_default') return -1;
        if (b.id == 'wallet_cash_default') return 1;
        final r = _walletTypeRank(a.type).compareTo(_walletTypeRank(b.type));
        return r != 0 ? r : a.name.compareTo(b.name);
      });
      return list;
    });
  }

  Stream<List<CategoryModel>> watchCategories(String userId) {
    return _categoriesCol(userId).snapshots().map(
      (snap) => snap.docs.map(CategoryModel.fromFirestore).toList(),
    );
  }

  Stream<List<TransactionModel>> watchTransactions({
    required String userId,
    required String monthKey,
    int limit = 100,
  }) {
    return _txCol(userId)
        .where('monthKey', isEqualTo: monthKey)
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs.map(TransactionModel.fromFirestore).toList());
  }

  /// Unbounded stream of all transactions in [monthKey] for exact VND aggregation (`FIX-001`).
  Stream<List<TransactionModel>> watchAllTransactionsForAggregation({
    required String userId,
    required String monthKey,
  }) {
    return _txCol(userId)
        .where('monthKey', isEqualTo: monthKey)
        .orderBy('occurredAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs.map(TransactionModel.fromFirestore).toList());
  }

  Stream<List<TransactionModel>> watchTransactionsRange({
    required String userId,
    required DateTime startInclusive,
    required DateTime endExclusive,
    int limit = 600,
  }) {
    return _txCol(userId)
        .where(
          'occurredAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive),
        )
        .where('occurredAt', isLessThan: Timestamp.fromDate(endExclusive))
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs.map(TransactionModel.fromFirestore).toList());
  }

  /// Unbounded period stream `[startInclusive, endExclusive)` without artificial 100/600 cap (`FIX-001`).
  Stream<List<TransactionModel>> watchTransactionsInPeriod({
    required String userId,
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) {
    return _txCol(userId)
        .where(
          'occurredAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive),
        )
        .where('occurredAt', isLessThan: Timestamp.fromDate(endExclusive))
        .orderBy('occurredAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs.map(TransactionModel.fromFirestore).toList());
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchAllDocsPaginated(
    Query<Map<String, dynamic>> baseQuery, {
    int pageSize = 200,
  }) async {
    final safePageSize = pageSize < 1 ? 1 : pageSize;
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      var query = baseQuery.orderBy(FieldPath.documentId);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }
      final snap = await query.limit(safePageSize).get();
      if (snap.docs.isEmpty) break;
      docs.addAll(snap.docs);
      if (snap.docs.length < safePageSize) break;
      cursor = snap.docs.last;
    }
    return docs;
  }

  /// Reads ALL wallets for [userId] across cursor pages without artificial limits.
  Future<List<WalletModel>> fetchAllWalletsPaginated({
    required String userId,
    int pageSize = 200,
  }) async {
    final docs = await _fetchAllDocsPaginated(
      _walletsCol(userId),
      pageSize: pageSize,
    );
    final list = docs.map(WalletModel.fromFirestore).toList();
    list.sort((a, b) {
      if (a.id == 'wallet_cash_default') return -1;
      if (b.id == 'wallet_cash_default') return 1;
      final r = _walletTypeRank(a.type).compareTo(_walletTypeRank(b.type));
      return r != 0 ? r : a.name.compareTo(b.name);
    });
    return list;
  }

  /// Reads ALL categories for [userId] across cursor pages without artificial limits.
  Future<List<CategoryModel>> fetchAllCategoriesPaginated({
    required String userId,
    int pageSize = 200,
  }) async {
    final docs = await _fetchAllDocsPaginated(
      _categoriesCol(userId),
      pageSize: pageSize,
    );
    final list = docs.map(CategoryModel.fromFirestore).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Reads ALL transactions for [userId] across all months using cursor pagination
  /// (no 100-item cap and no `monthKey` filter).
  Future<List<TransactionModel>> fetchAllTransactionsPaginated({
    required String userId,
    int pageSize = 200,
  }) async {
    final docs = await _fetchAllDocsPaginated(
      _txCol(userId),
      pageSize: pageSize,
    );
    final list = docs.map(TransactionModel.fromFirestore).toList();
    list.sort((a, b) {
      final cmp = b.entity.occurredAt.compareTo(a.entity.occurredAt);
      return cmp != 0 ? cmp : a.entity.id.compareTo(b.entity.id);
    });
    return list;
  }

  Future<WalletModel> createWallet({
    required String userId,
    required String name,
    required WalletType type,
    required int openingBalanceMinor,
    String? bankCode,
    String? maskedAccount,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final docRef = _walletsCol(userId).doc(id);
    await docRef.set({
      'id': id,
      'ownerId': userId,
      'name': name,
      'type': type.name,
      'bankCode': bankCode,
      'maskedAccount': maskedAccount,
      'balanceMinor': openingBalanceMinor,
      'isEstimatedBalance': true,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    final snap = await docRef.get();
    return WalletModel.fromFirestore(snap);
  }

  Future<TransactionModel> createTransaction({
    required String operationId,
    required String userId,
    required String walletId,
    String? targetWalletId,
    String? categoryId,
    required String categoryName,
    required TransactionKind kind,
    required int amountMinor,
    required String merchant,
    String? note,
    required DateTime occurredAt,
    List<TransactionSplitLine> splitLines = const [],
  }) async {
    final txRef = _txCol(userId).doc(operationId);
    final sourceWalletRef = _walletsCol(userId).doc(walletId);
    final targetWalletRef = targetWalletId != null
        ? _walletsCol(userId).doc(targetWalletId)
        : null;

    await _firestore.runTransaction((tx) async {
      // Idempotency guard: if operationId already exists, return without double-applying!
      final existingTx = await tx.get(txRef);
      if (existingTx.exists) {
        return;
      }

      final sourceSnap = await tx.get(sourceWalletRef);
      final autoCreateDefaultCash =
          !sourceSnap.exists &&
          walletId == 'wallet_cash_default' &&
          targetWalletRef == null;
      if (!sourceSnap.exists && !autoCreateDefaultCash) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy ví nguồn.',
        );
      }
      final sourceData = sourceSnap.data() ?? const <String, dynamic>{};
      final sourceBal = (sourceData['balanceMinor'] as num?)?.toInt() ?? 0;
      final sourceName = autoCreateDefaultCash
          ? 'Ví tiền mặt'
          : ((sourceData['name'] as String?) ?? 'Ví nguồn');

      int? targetBal;
      String? targetName;
      if (targetWalletRef != null) {
        final targetSnap = await tx.get(targetWalletRef);
        if (!targetSnap.exists) {
          throw const AppException(
            code: 'NOT_FOUND',
            message: 'Không tìm thấy ví đích.',
          );
        }
        final targetData = targetSnap.data() ?? const <String, dynamic>{};
        targetBal = (targetData['balanceMinor'] as num?)?.toInt() ?? 0;
        targetName = (targetData['name'] as String?) ?? 'Ví đích';
      }

      final now = DateTime.now();
      final direction = kind == TransactionKind.income ? 'credit' : 'debit';
      final inferred = BankNotificationParser.inferCategory(
        '$merchant ${note ?? ''}',
        direction,
      );
      final fingerprint = BankNotificationParser.computeCrossSourceFingerprint(
        ownerId: userId,
        direction: direction,
        amountMinor: amountMinor,
        occurredAt: occurredAt,
      );

      late final int newSourceBal;
      if (kind == TransactionKind.transfer ||
          kind == TransactionKind.creditCardPayment) {
        newSourceBal = sourceBal - amountMinor;
        final newTargetBal = targetBal! + amountMinor;
        final conservationCheck =
            LedgerIntegrityEngine.validateTransferBalanceConservation(
              sourceBeforeMinor: sourceBal,
              sourceAfterMinor: newSourceBal,
              targetBeforeMinor: targetBal,
              targetAfterMinor: newTargetBal,
              amountMinor: amountMinor,
            );
        if (conservationCheck is Err<void>) {
          throw AppException(
            code: conservationCheck.failure.code,
            message: conservationCheck.failure.message,
          );
        }

        final srcAuditId = 'aud_${operationId}_src';
        final dstAuditId = 'aud_${operationId}_dst';
        final srcAuditRes = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: srcAuditId,
          operationId: operationId,
          transactionId: operationId,
          walletId: walletId,
          previousBalanceMinor: sourceBal,
          deltaAmountMinor: -amountMinor,
          newBalanceMinor: newSourceBal,
          createdAt: now,
          actorId: userId,
          source: 'manual',
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
          walletName: sourceName,
          kind: kind.name,
        );
        final dstAuditRes = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: dstAuditId,
          operationId: operationId,
          transactionId: operationId,
          walletId: targetWalletId!,
          previousBalanceMinor: targetBal,
          deltaAmountMinor: amountMinor,
          newBalanceMinor: newTargetBal,
          createdAt: now,
          actorId: userId,
          source: 'manual',
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
          walletName: targetName,
          kind: kind.name,
        );
        if (srcAuditRes is Err<LedgerAuditRecord>) {
          throw AppException(
            code: srcAuditRes.failure.code,
            message: srcAuditRes.failure.message,
          );
        }
        if (dstAuditRes is Err<LedgerAuditRecord>) {
          throw AppException(
            code: dstAuditRes.failure.code,
            message: dstAuditRes.failure.message,
          );
        }

        final createdTs = Timestamp.fromDate(now);
        tx.update(sourceWalletRef, {
          'balanceMinor': newSourceBal,
          'lastAuditId': srcAuditId,
          'updatedAt': createdTs,
        });
        tx.update(targetWalletRef!, {
          'balanceMinor': newTargetBal,
          'lastAuditId': dstAuditId,
          'updatedAt': createdTs,
        });
        tx.set(
          _auditCol(userId).doc(srcAuditId),
          (srcAuditRes as Success<LedgerAuditRecord>).value.toPayloadMap(
            createdAtValue: createdTs,
          ),
        );
        tx.set(
          _auditCol(userId).doc(dstAuditId),
          (dstAuditRes as Success<LedgerAuditRecord>).value.toPayloadMap(
            createdAtValue: createdTs,
          ),
        );
      } else {
        final delta = direction == 'credit' ? amountMinor : -amountMinor;
        newSourceBal = sourceBal + delta;
        final auditId = 'aud_$operationId';
        final auditRes = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: auditId,
          operationId: operationId,
          transactionId: operationId,
          walletId: walletId,
          previousBalanceMinor: sourceBal,
          deltaAmountMinor: delta,
          newBalanceMinor: newSourceBal,
          createdAt: now,
          actorId: userId,
          source: 'manual',
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
          walletName: sourceName,
          kind: kind.name,
        );
        if (auditRes is Err<LedgerAuditRecord>) {
          throw AppException(
            code: auditRes.failure.code,
            message: auditRes.failure.message,
          );
        }

        final createdTs = Timestamp.fromDate(now);
        if (autoCreateDefaultCash) {
          tx.set(sourceWalletRef, {
            'id': walletId,
            'ownerId': userId,
            'name': sourceName,
            'type': WalletType.cash.name,
            'bankCode': null,
            'maskedAccount': null,
            'balanceMinor': newSourceBal,
            'isEstimatedBalance': true,
            'lastAuditId': auditId,
            'createdAt': createdTs,
            'updatedAt': createdTs,
          });
        } else {
          tx.update(sourceWalletRef, {
            'balanceMinor': newSourceBal,
            'lastAuditId': auditId,
            'updatedAt': createdTs,
          });
        }
        tx.set(
          _auditCol(userId).doc(auditId),
          (auditRes as Success<LedgerAuditRecord>).value.toPayloadMap(
            createdAtValue: createdTs,
          ),
        );
      }

      tx.set(
        txRef,
        TransactionModel.toFirestoreMap(
          id: operationId,
          operationId: operationId,
          ownerId: userId,
          walletId: walletId,
          targetWalletId: targetWalletId,
          categoryId: categoryId,
          categoryName: categoryName,
          kind: kind,
          direction: direction,
          amountMinor: amountMinor,
          merchant: merchant,
          note: note,
          occurredAt: occurredAt,
          sourceKind: TransactionSourceKind.manual,
          verification: TransactionVerification.userConfirmed,
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
          crossSourceFingerprint: fingerprint,
          isVehicleMaintenanceHint:
              inferred.isVehicleMaintenance ||
              splitLines.any((l) => l.categoryName.contains('Bảo dưỡng')),
          splitLines: splitLines,
          balanceAfterMinor: newSourceBal,
          walletName: sourceName,
          now: now,
        ),
      );
    });

    final createdSnap = await txRef.get();
    return TransactionModel.fromFirestore(createdSnap);
  }

  Future<TransactionModel> reverseTransaction({
    required String userId,
    required String transactionId,
    required String reason,
  }) async {
    final origRef = _txCol(userId).doc(transactionId);
    final revId = 'rev_$transactionId';
    final revRef = _txCol(userId).doc(revId);

    await _firestore.runTransaction((tx) async {
      final origSnap = await tx.get(origRef);
      final existingRevSnap = await tx.get(revRef);
      if (existingRevSnap.exists) {
        // Idempotent reversal guard (`FIX-007`): return existing reversal record cleanly.
        return;
      }
      if (!origSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy giao dịch gốc.',
        );
      }
      final orig = TransactionModel.fromFirestore(origSnap).entity;
      if (orig.isReversed || orig.kind == TransactionKind.reversal) {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Giao dịch này đã được đảo bút toán trước đó.',
        );
      }
      if (!orig.isConfirmedInLedger) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Chỉ đảo bút toán cho giao dịch đã xác nhận ghi sổ.',
        );
      }

      final sourceRef = _walletsCol(userId).doc(orig.walletId);
      final sourceSnap = await tx.get(sourceRef);
      final sourceBal =
          (sourceSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      final sourceName =
          (sourceSnap.data()?['name'] as String?) ?? orig.walletName;

      DocumentReference<Map<String, dynamic>>? targetRef;
      int? targetBal;
      String? targetName;
      var targetExists = false;
      if (orig.targetWalletId != null) {
        targetRef = _walletsCol(userId).doc(orig.targetWalletId);
        final targetSnap = await tx.get(targetRef);
        targetExists = targetSnap.exists;
        targetBal = (targetSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
        targetName = targetSnap.data()?['name'] as String?;
      }

      final now = DateTime.now();
      final revTs = Timestamp.fromDate(now);
      final srcAuditId = 'aud_rev_$transactionId';
      late final int newSourceBal;

      if (orig.kind == TransactionKind.transfer ||
          orig.kind == TransactionKind.creditCardPayment) {
        newSourceBal = sourceBal + orig.amountMinor;
        final srcAuditRes = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: srcAuditId,
          operationId: revId,
          transactionId: revId,
          walletId: orig.walletId,
          previousBalanceMinor: sourceBal,
          deltaAmountMinor: orig.amountMinor,
          newBalanceMinor: newSourceBal,
          createdAt: now,
          actorId: userId,
          source: 'manual_reversal',
          verificationStatus: LedgerVerificationStatuses.reversed,
          walletName: sourceName,
          kind: TransactionKind.reversal.name,
        );
        if (srcAuditRes is Err<LedgerAuditRecord>) {
          throw AppException(
            code: srcAuditRes.failure.code,
            message: srcAuditRes.failure.message,
          );
        }

        if (sourceSnap.exists) {
          tx.update(sourceRef, {
            'balanceMinor': newSourceBal,
            'lastAuditId': srcAuditId,
            'updatedAt': revTs,
          });
        }
        tx.set(
          _auditCol(userId).doc(srcAuditId),
          (srcAuditRes as Success<LedgerAuditRecord>).value.toPayloadMap(
            createdAtValue: revTs,
          ),
        );

        if (targetRef != null && targetBal != null) {
          final newTargetBal = targetBal - orig.amountMinor;
          final dstAuditId = 'aud_rev_${transactionId}_dst';
          final dstAuditRes = LedgerIntegrityEngine.buildAndValidateAudit(
            auditId: dstAuditId,
            operationId: revId,
            transactionId: revId,
            walletId: orig.targetWalletId!,
            previousBalanceMinor: targetBal,
            deltaAmountMinor: -orig.amountMinor,
            newBalanceMinor: newTargetBal,
            createdAt: now,
            actorId: userId,
            source: 'manual_reversal',
            verificationStatus: LedgerVerificationStatuses.reversed,
            walletName: targetName,
            kind: TransactionKind.reversal.name,
          );
          if (dstAuditRes is Err<LedgerAuditRecord>) {
            throw AppException(
              code: dstAuditRes.failure.code,
              message: dstAuditRes.failure.message,
            );
          }
          if (targetExists) {
            tx.update(targetRef, {
              'balanceMinor': newTargetBal,
              'lastAuditId': dstAuditId,
              'updatedAt': revTs,
            });
          }
          tx.set(
            _auditCol(userId).doc(dstAuditId),
            (dstAuditRes as Success<LedgerAuditRecord>).value.toPayloadMap(
              createdAtValue: revTs,
            ),
          );
        }
      } else {
        final inverseDelta = orig.direction == 'credit'
            ? -orig.amountMinor
            : orig.amountMinor;
        newSourceBal = sourceBal + inverseDelta;
        final auditRes = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: srcAuditId,
          operationId: revId,
          transactionId: revId,
          walletId: orig.walletId,
          previousBalanceMinor: sourceBal,
          deltaAmountMinor: inverseDelta,
          newBalanceMinor: newSourceBal,
          createdAt: now,
          actorId: userId,
          source: 'manual_reversal',
          verificationStatus: LedgerVerificationStatuses.reversed,
          walletName: sourceName,
          kind: TransactionKind.reversal.name,
        );
        if (auditRes is Err<LedgerAuditRecord>) {
          throw AppException(
            code: auditRes.failure.code,
            message: auditRes.failure.message,
          );
        }
        if (sourceSnap.exists) {
          tx.update(sourceRef, {
            'balanceMinor': newSourceBal,
            'lastAuditId': srcAuditId,
            'updatedAt': revTs,
          });
        }
        tx.set(
          _auditCol(userId).doc(srcAuditId),
          (auditRes as Success<LedgerAuditRecord>).value.toPayloadMap(
            createdAtValue: revTs,
          ),
        );
      }

      final revDirection = orig.direction == 'debit' ? 'credit' : 'debit';
      tx.update(origRef, {
        'reversedById': revId,
        'verificationStatus': LedgerVerificationStatuses.reversed,
        'updatedAt': revTs,
      });
      tx.set(
        revRef,
        TransactionModel.toFirestoreMap(
          id: revId,
          operationId: revId,
          ownerId: userId,
          walletId: orig.walletId,
          targetWalletId: orig.targetWalletId,
          categoryId: orig.categoryId,
          categoryName: orig.categoryName,
          kind: TransactionKind.reversal,
          direction: revDirection,
          amountMinor: orig.amountMinor,
          merchant: '[Đảo bút toán] ${orig.merchant}',
          note: reason,
          occurredAt: now,
          sourceKind: TransactionSourceKind.manual,
          verification: TransactionVerification.userConfirmed,
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
          crossSourceFingerprint: 'rev_${orig.crossSourceFingerprint}',
          reversalOfId: orig.id,
          balanceAfterMinor: newSourceBal,
          walletName: sourceName,
          now: now,
        ),
      );
    });

    final revSnap = await revRef.get();
    return TransactionModel.fromFirestore(revSnap);
  }

  Future<void> decideProvisionalTransaction({
    required String userId,
    required String transactionId,
    required bool approve,
    String? updatedCategoryName,
    String? updatedMerchant,
    int? updatedAmountMinor,
    String? updatedNote,
  }) async {
    final txRef = _txCol(userId).doc(transactionId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(txRef);
      if (!snap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy giao dịch chờ duyệt.',
        );
      }
      final current = TransactionModel.fromFirestore(snap).entity;
      if (LedgerIntegrityEngine.isImmutableVerified(current)) {
        final mutationGuard = LedgerIntegrityEngine.validateClientMutation(
          existing: current,
          newAmountMinor: updatedAmountMinor,
          newVerification: approve
              ? TransactionVerification.userConfirmed
              : TransactionVerification.rejected,
        );
        if (mutationGuard is Err<void>) {
          throw AppException(
            code: mutationGuard.failure.code,
            message: mutationGuard.failure.message,
          );
        }
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message:
              'Không thể sửa đổi hoặc duyệt lại giao dịch ngân hàng đã VERIFIED.',
        );
      }

      if (current.verification != TransactionVerification.provisional &&
          current.verification != TransactionVerification.needsReview) {
        return;
      }

      final walletRef = _walletsCol(userId).doc(current.walletId);
      final walletSnap = await tx.get(walletRef);
      final now = DateTime.now();
      final tsNow = Timestamp.fromDate(now);

      if (!approve) {
        int? newBalAfterReject;
        if (current.ledgerApplied && walletSnap.exists) {
          final bal =
              (walletSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
          final walletName =
              (walletSnap.data()?['name'] as String?) ?? current.walletName;
          final reverseDelta = current.direction == 'credit'
              ? -current.amountMinor
              : current.amountMinor;
          newBalAfterReject = bal + reverseDelta;
          final auditId = 'aud_reject_$transactionId';
          final auditRes = LedgerIntegrityEngine.buildAndValidateAudit(
            auditId: auditId,
            operationId: current.operationId ?? 'reject_$transactionId',
            transactionId: transactionId,
            walletId: current.walletId,
            previousBalanceMinor: bal,
            deltaAmountMinor: reverseDelta,
            newBalanceMinor: newBalAfterReject,
            createdAt: now,
            actorId: userId,
            source: 'provisional_rejection',
            verificationStatus: LedgerVerificationStatuses.rejected,
            walletName: walletName,
            kind: current.kind.name,
          );
          if (auditRes is Err<LedgerAuditRecord>) {
            throw AppException(
              code: auditRes.failure.code,
              message: auditRes.failure.message,
            );
          }
          tx.update(walletRef, {
            'balanceMinor': newBalAfterReject,
            'lastAuditId': auditId,
            'updatedAt': tsNow,
          });
          tx.set(
            _auditCol(userId).doc(auditId),
            (auditRes as Success<LedgerAuditRecord>).value.toPayloadMap(
              createdAtValue: tsNow,
            ),
          );
        }

        tx.update(txRef, {
          'verification': TransactionVerification.rejected.name,
          'verificationStatus': LedgerVerificationStatuses.rejected,
          'ledgerApplied': false,
          if (newBalAfterReject != null) 'balanceAfterMinor': newBalAfterReject,
          'updatedAt': tsNow,
        });
        return;
      }

      final effectiveAmount =
          (updatedAmountMinor != null && updatedAmountMinor > 0)
          ? updatedAmountMinor
          : current.amountMinor;

      int? newBalAfterConfirm;
      // Single-balance-effect guard: ONLY apply delta if ledgerApplied was false!
      if (!current.ledgerApplied && walletSnap.exists) {
        final bal = (walletSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
        final walletName =
            (walletSnap.data()?['name'] as String?) ?? current.walletName;
        final delta = current.direction == 'credit'
            ? effectiveAmount
            : -effectiveAmount;
        newBalAfterConfirm = bal + delta;
        final auditId = 'aud_confirm_$transactionId';
        final auditRes = LedgerIntegrityEngine.buildAndValidateAudit(
          auditId: auditId,
          operationId: current.operationId ?? 'confirm_$transactionId',
          transactionId: transactionId,
          walletId: current.walletId,
          previousBalanceMinor: bal,
          deltaAmountMinor: delta,
          newBalanceMinor: newBalAfterConfirm,
          createdAt: now,
          actorId: userId,
          source: 'provisional_approval',
          verificationStatus: LedgerVerificationStatuses.userConfirmed,
          walletName: walletName,
          kind: current.kind.name,
        );
        if (auditRes is Err<LedgerAuditRecord>) {
          throw AppException(
            code: auditRes.failure.code,
            message: auditRes.failure.message,
          );
        }
        tx.update(walletRef, {
          'balanceMinor': newBalAfterConfirm,
          'lastAuditId': auditId,
          'updatedAt': tsNow,
        });
        tx.set(
          _auditCol(userId).doc(auditId),
          (auditRes as Success<LedgerAuditRecord>).value.toPayloadMap(
            createdAtValue: tsNow,
          ),
        );
      }

      tx.update(txRef, {
        'verification': TransactionVerification.userConfirmed.name,
        'verificationStatus': LedgerVerificationStatuses.userConfirmed,
        'ledgerApplied': true,
        'amountMinor': effectiveAmount,
        if (newBalAfterConfirm != null) 'balanceAfterMinor': newBalAfterConfirm,
        if (newBalAfterConfirm != null &&
            current.balanceType == TransactionBalanceType.unknownBalance)
          'balanceType': TransactionBalanceType.estimatedWalletBalance.name,
        if (updatedCategoryName != null && updatedCategoryName.isNotEmpty)
          'categoryName': updatedCategoryName,
        if (updatedMerchant != null && updatedMerchant.isNotEmpty)
          'merchant': updatedMerchant,
        if (updatedNote != null) 'note': updatedNote,
        'updatedAt': tsNow,
      });
    });
  }

  Future<void> upsertNetWorthSnapshot({
    required String userId,
    required String monthKey,
    required FinanceOverviewSummary summary,
  }) async {
    final now = DateTime.now();
    await _snapshotCol(userId).doc(monthKey).set({
      'id': monthKey,
      'ownerId': userId,
      'monthKey': monthKey,
      'netWorthMinor': summary.netWorthMinor,
      'liquidAssetsMinor': summary.liquidAssetsMinor,
      'savingsAssetsMinor': summary.savingsAssetsMinor,
      'creditLiabilityMinor': summary.creditLiabilityMinor,
      'monthlyIncomeMinor': summary.monthlyIncomeMinor,
      'monthlyExpenseMinor': summary.monthlyExpenseMinor,
      'financialHealthScore': summary.financialHealthScore,
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }

  Future<void> upsertMonthlySummary({
    required String userId,
    required String monthKey,
    required FinancialAggregationResult summary,
  }) async {
    final now = DateTime.now();
    await _monthlySummaryCol(userId).doc(monthKey).set({
      'id': monthKey,
      'ownerId': userId,
      'monthKey': monthKey,
      'incomeMinor': summary.incomeMinor,
      'grossExpenseMinor': summary.grossExpenseMinor,
      'refundMinor': summary.refundMinor,
      'netExpenseMinor': summary.netExpenseMinor,
      'internalTransferMinor': summary.internalTransferMinor,
      'netCashFlowMinor': summary.netCashFlowMinor,
      'unconfirmedCount': summary.unconfirmedCount,
      'provisionalAmountMinor': summary.provisionalAmountMinor,
      'verifiedCount': summary.verifiedCount,
      'userConfirmedCount': summary.userConfirmedCount,
      'matchedPaymentOrderCount': summary.matchedPaymentOrderCount,
      'totalEvaluatedCount': summary.totalEvaluatedCount,
      'expenseByCategory': summary.expenseByCategory,
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }
}
