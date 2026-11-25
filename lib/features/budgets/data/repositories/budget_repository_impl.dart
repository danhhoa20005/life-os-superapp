import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/utils/stream_combiner.dart';
import '../../../transactions/data/models/transaction_models.dart';
import '../../../transactions/domain/entities/financial_aggregation_engine.dart';
import '../../domain/entities/budget_entities.dart';
import '../../domain/repositories/budget_repository.dart';

class BudgetRemoteDataSource {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  const BudgetRemoteDataSource(this._firestore);

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

  Future<FundEntity> _hydrateFund(
    DocumentSnapshot<Map<String, dynamic>> doc,
    FundScope scope,
  ) async {
    final d = doc.data() ?? const <String, dynamic>{};
    final contribSnap = await doc.reference
        .collection('contributions')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();
    final expSnap = await doc.reference
        .collection('expenses')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();

    final contributions = contribSnap.docs.map((c) {
      final cd = c.data();
      final ts = cd['createdAt'];
      return FundContributionEntity(
        id: (cd['id'] as String?) ?? c.id,
        contributorId: (cd['contributorId'] as String?) ?? '',
        contributorName: (cd['contributorName'] as String?) ?? 'Thành viên',
        amountMinor: (cd['amountMinor'] as num?)?.toInt() ?? 0,
        note: cd['note'] as String?,
        createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      );
    }).toList();

    final expenses = expSnap.docs.map((e) {
      final ed = e.data();
      final ts = ed['createdAt'];
      final status = switch (ed['status'] as String?) {
        'approved' => FundExpenseStatus.approved,
        'rejected' => FundExpenseStatus.rejected,
        _ => FundExpenseStatus.pending,
      };
      return FundExpenseRequestEntity(
        id: (ed['id'] as String?) ?? e.id,
        requesterId: (ed['requesterId'] as String?) ?? '',
        requesterName: (ed['requesterName'] as String?) ?? 'Thành viên',
        title: (ed['title'] as String?) ?? '',
        amountMinor: (ed['amountMinor'] as num?)?.toInt() ?? 0,
        status: status,
        createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      );
    }).toList();

    return FundEntity(
      id: (d['id'] as String?) ?? doc.id,
      scope: scope,
      ownerId: d['ownerId'] as String?,
      familyId: d['familyId'] as String?,
      name: (d['name'] as String?) ?? 'Quỹ',
      targetAmountMinor: (d['targetAmountMinor'] as num?)?.toInt() ?? 0,
      balanceMinor: (d['balanceMinor'] as num?)?.toInt() ?? 0,
      recentContributions: contributions,
      expenseRequests: expenses,
    );
  }

  Stream<List<FundEntity>> watchFunds({
    required String userId,
    String? familyId,
  }) {
    final personalStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('personal_funds')
        .snapshots()
        .asyncMap(
          (snap) => Future.wait(
            snap.docs.map((d) => _hydrateFund(d, FundScope.personal)),
          ),
        );

    if (familyId == null || familyId.isEmpty) {
      return personalStream;
    }

    final familyStream = _firestore
        .collection('families')
        .doc(familyId)
        .collection('funds')
        .snapshots()
        .asyncMap(
          (snap) => Future.wait(
            snap.docs.map((d) => _hydrateFund(d, FundScope.family)),
          ),
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
  }) async {
    final fundRef = _fundDocRef(
      scope: scope,
      userId: userId,
      familyId: familyId,
      fundId: fundId,
    );
    final contribId = _uuid.v4();
    final contribRef = fundRef.collection('contributions').doc(contribId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(fundRef);
      if (!snap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy quỹ.',
        );
      }
      final currentBal = (snap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      final now = DateTime.now();

      // Strictly records contribution receipt without exposing personal bank account balances!
      tx.set(contribRef, {
        'id': contribId,
        'contributorId': userId,
        'contributorName': userName,
        'amountMinor': amountMinor,
        'note': note,
        'createdAt': Timestamp.fromDate(now),
      });
      tx.update(fundRef, {
        'balanceMinor': currentBal + amountMinor,
        'updatedAt': Timestamp.fromDate(now),
      });
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
  }) async {
    final fundRef = _fundDocRef(
      scope: scope,
      userId: userId,
      familyId: familyId,
      fundId: fundId,
    );
    final expId = _uuid.v4();
    final expRef = fundRef.collection('expenses').doc(expId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(fundRef);
      if (!snap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy quỹ.',
        );
      }
      final currentBal = (snap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      final autoApprove = scope == FundScope.personal || canAutoApprove;
      if (autoApprove && currentBal < amountMinor) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Số dư sổ sách của quỹ không đủ để chi khoản này.',
        );
      }

      final now = DateTime.now();
      tx.set(expRef, {
        'id': expId,
        'requesterId': userId,
        'requesterName': userName,
        'title': title,
        'amountMinor': amountMinor,
        'status': autoApprove ? 'approved' : 'pending',
        'createdAt': Timestamp.fromDate(now),
      });

      if (autoApprove) {
        tx.update(fundRef, {
          'balanceMinor': currentBal - amountMinor,
          'updatedAt': Timestamp.fromDate(now),
        });
      } else {
        tx.update(fundRef, {'updatedAt': Timestamp.fromDate(now)});
      }
    });
  }

  Future<void> decideFundExpense({
    required String familyId,
    required String fundId,
    required String expenseId,
    required bool approve,
  }) async {
    final fundRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('funds')
        .doc(fundId);
    final expRef = fundRef.collection('expenses').doc(expenseId);

    await _firestore.runTransaction((tx) async {
      final fundSnap = await tx.get(fundRef);
      final expSnap = await tx.get(expRef);
      if (!fundSnap.exists || !expSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy đề xuất chi quỹ.',
        );
      }
      final status = expSnap.data()?['status'] as String?;
      if (status != 'pending') {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Đề xuất chi này đã được xử lý.',
        );
      }
      final amountMinor =
          (expSnap.data()?['amountMinor'] as num?)?.toInt() ?? 0;
      final currentBal =
          (fundSnap.data()?['balanceMinor'] as num?)?.toInt() ?? 0;
      if (approve && currentBal < amountMinor) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Số dư quỹ không đủ để phê duyệt khoản chi.',
        );
      }
      final now = DateTime.now();
      tx.update(expRef, {
        'status': approve ? 'approved' : 'rejected',
        'decidedAt': Timestamp.fromDate(now),
      });
      if (approve) {
        tx.update(fundRef, {
          'balanceMinor': currentBal - amountMinor,
          'updatedAt': Timestamp.fromDate(now),
        });
      } else {
        tx.update(fundRef, {'updatedAt': Timestamp.fromDate(now)});
      }
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
  }) async {
    try {
      await _remoteDataSource.decideFundExpense(
        familyId: familyId,
        fundId: fundId,
        expenseId: expenseId,
        approve: approve,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
