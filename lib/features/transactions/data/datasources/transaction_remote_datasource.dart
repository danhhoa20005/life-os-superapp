import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/security/bank_notification_parser.dart';
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
      _firestore.collection('users').doc(userId).collection('net_worth_snapshots');

  static int _walletTypeRank(WalletType type) => switch (type) {
        WalletType.cash => 0,
        WalletType.bank => 1,
        WalletType.savings => 2,
        WalletType.creditCard => 3,
      };

  Stream<List<WalletModel>> watchWallets(String userId) {
    return _walletsCol(userId)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
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
    return _categoriesCol(userId)
        .snapshots()
        .map((snap) => snap.docs.map(CategoryModel.fromFirestore).toList());
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
    final targetWalletRef =
        targetWalletId != null ? _walletsCol(userId).doc(targetWalletId) : null;

    await _firestore.runTransaction((tx) async {
      // Idempotency guard: if operationId already exists, return without double-applying!
      final existingTx = await tx.get(txRef);
      if (existingTx.exists) {
        return;
      }

      final sourceSnap = await tx.get(sourceWalletRef);
      final autoCreateDefaultCash =
          !sourceSnap.exists && walletId == 'wallet_cash_default' && targetWalletRef == null;
      if (!sourceSnap.exists && !autoCreateDefaultCash) {
        throw const AppException(code: 'NOT_FOUND', message: 'Không tìm thấy ví nguồn.');
      }
      final sourceData = sourceSnap.data() ?? const <String, dynamic>{};
      final sourceBal = (sourceData['balanceMinor'] as num?)?.toInt() ?? 0;
      final sourceName =
          autoCreateDefaultCash ? 'Ví tiền mặt' : ((sourceData['name'] as String?) ?? 'Ví nguồn');

      int? targetBal;
      String? targetName;
      if (targetWalletRef != null) {
        final targetSnap = await tx.get(targetWalletRef);
        if (!targetSnap.exists) {
          throw const AppException(code: 'NOT_FOUND', message: 'Không tìm thấy ví đích.');
        }
        final targetData = targetSnap.data() ?? const <String, dynamic>{};
        targetBal = (targetData['balanceMinor'] as num?)?.toInt() ?? 0;
        targetName = (targetData['name'] as String?) ?? 'Ví đích';
      }

      final now = DateTime.now();
      final direction = kind == TransactionKind.income ? 'credit' : 'debit';
      final inferred = BankNotificationParser.inferCategory('$merchant ${note ?? ''}', direction);
      final fingerprint = BankNotificationParser.computeCrossSourceFingerprint(
        ownerId: userId,
        direction: direction,
        amountMinor: amountMinor,
        occurredAt: occurredAt,
      );

      late final int newSourceBal;
      if (kind == TransactionKind.transfer || kind == TransactionKind.creditCardPayment) {
        newSourceBal = sourceBal - amountMinor;
        final newTargetBal = targetBal! + amountMinor;
        tx.update(sourceWalletRef, {
          'balanceMinor': newSourceBal,
          'updatedAt': Timestamp.fromDate(now),
        });
        tx.update(targetWalletRef!, {
          'balanceMinor': newTargetBal,
          'updatedAt': Timestamp.fromDate(now),
        });
        tx.set(_auditCol(userId).doc('aud_${operationId}_src'), {
          'id': 'aud_${operationId}_src',
          'ownerId': userId,
          'txId': operationId,
          'walletId': walletId,
          'walletName': sourceName,
          'previousBalanceMinor': sourceBal,
          'deltaMinor': -amountMinor,
          'newBalanceMinor': newSourceBal,
          'kind': kind.name,
          'createdAt': Timestamp.fromDate(now),
        });
        tx.set(_auditCol(userId).doc('aud_${operationId}_dst'), {
          'id': 'aud_${operationId}_dst',
          'ownerId': userId,
          'txId': operationId,
          'walletId': targetWalletId,
          'walletName': targetName,
          'previousBalanceMinor': targetBal,
          'deltaMinor': amountMinor,
          'newBalanceMinor': newTargetBal,
          'kind': kind.name,
          'createdAt': Timestamp.fromDate(now),
        });
      } else {
        final delta = direction == 'credit' ? amountMinor : -amountMinor;
        newSourceBal = sourceBal + delta;
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
            'createdAt': Timestamp.fromDate(now),
            'updatedAt': Timestamp.fromDate(now),
          });
        } else {
          tx.update(sourceWalletRef, {
            'balanceMinor': newSourceBal,
            'updatedAt': Timestamp.fromDate(now),
          });
        }
        tx.set(_auditCol(userId).doc('aud_$operationId'), {
          'id': 'aud_$operationId',
          'ownerId': userId,
          'txId': operationId,
          'walletId': walletId,
          'walletName': sourceName,
          'previousBalanceMinor': sourceBal,
          'deltaMinor': delta,
          'newBalanceMinor': newSourceBal,
          'kind': kind.name,
          'createdAt': Timestamp.fromDate(now),
        });
      }

      tx.set(
        txRef,
        TransactionModel.toFirestoreMap(
          id: operationId,
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
          crossSourceFingerprint: fingerprint,
          isVehicleMaintenanceHint: inferred.isVehicleMaintenance ||
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
      if (!origSnap.exists) {
        throw const AppException(code: 'NOT_FOUND', message: 'Không tìm thấy giao dịch gốc.');
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
      final sourceBal = (sourceSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;

      DocumentReference<Map<String, dynamic>>? targetRef;
      int? targetBal;
      if (orig.targetWalletId != null) {
        targetRef = _walletsCol(userId).doc(orig.targetWalletId);
        final targetSnap = await tx.get(targetRef);
        targetBal = (targetSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      }

      final now = DateTime.now();
      if (orig.kind == TransactionKind.transfer ||
          orig.kind == TransactionKind.creditCardPayment) {
        tx.update(sourceRef, {
          'balanceMinor': sourceBal + orig.amountMinor,
          'updatedAt': Timestamp.fromDate(now),
        });
        if (targetRef != null && targetBal != null) {
          tx.update(targetRef, {
            'balanceMinor': targetBal - orig.amountMinor,
            'updatedAt': Timestamp.fromDate(now),
          });
        }
      } else {
        final inverseDelta = orig.direction == 'credit' ? -orig.amountMinor : orig.amountMinor;
        tx.update(sourceRef, {
          'balanceMinor': sourceBal + inverseDelta,
          'updatedAt': Timestamp.fromDate(now),
        });
      }

      final revDirection = orig.direction == 'debit' ? 'credit' : 'debit';
      tx.update(origRef, {
        'reversedById': revId,
        'updatedAt': Timestamp.fromDate(now),
      });
      tx.set(
        revRef,
        TransactionModel.toFirestoreMap(
          id: revId,
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
          crossSourceFingerprint: 'rev_${orig.crossSourceFingerprint}',
          reversalOfId: orig.id,
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
  }) async {
    final txRef = _txCol(userId).doc(transactionId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(txRef);
      if (!snap.exists) {
        throw const AppException(code: 'NOT_FOUND', message: 'Không tìm thấy giao dịch chờ duyệt.');
      }
      final current = TransactionModel.fromFirestore(snap).entity;
      if (current.verification != TransactionVerification.provisional) {
        return;
      }

      final now = DateTime.now();
      if (!approve) {
        tx.update(txRef, {
          'verification': TransactionVerification.rejected.name,
          'updatedAt': Timestamp.fromDate(now),
        });
        return;
      }

      final walletRef = _walletsCol(userId).doc(current.walletId);
      final walletSnap = await tx.get(walletRef);
      if (walletSnap.exists) {
        final bal = (walletSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
        final delta = current.direction == 'credit' ? current.amountMinor : -current.amountMinor;
        tx.update(walletRef, {
          'balanceMinor': bal + delta,
          'updatedAt': Timestamp.fromDate(now),
        });
      }

      tx.update(txRef, {
        'verification': TransactionVerification.userConfirmed.name,
        if (updatedCategoryName != null && updatedCategoryName.isNotEmpty)
          'categoryName': updatedCategoryName,
        if (updatedMerchant != null && updatedMerchant.isNotEmpty) 'merchant': updatedMerchant,
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> upsertNetWorthSnapshot({
    required String userId,
    required String monthKey,
    required FinanceOverviewSummary summary,
  }) async {
    final now = DateTime.now();
    await _snapshotCol(userId).doc(monthKey).set(
      {
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
      },
      SetOptions(merge: true),
    );
  }
}
