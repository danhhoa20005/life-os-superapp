import 'dart:async';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/transaction_entities.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../datasources/transaction_remote_datasource.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  final TransactionRemoteDataSource _remoteDataSource;

  const TransactionRepositoryImpl(this._remoteDataSource);

  @override
  Stream<Result<List<WalletEntity>>> watchWallets(String userId) {
    return _remoteDataSource
        .watchWallets(userId)
        .map<Result<List<WalletEntity>>>(
          (models) => Success(models.map((m) => m.toEntity()).toList()),
        )
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (Object error, StackTrace _, EventSink<Result<List<WalletEntity>>> sink) {
              sink.add(Err(ErrorMapper.map(error)));
            },
          ),
        );
  }

  @override
  Stream<Result<List<CategoryEntity>>> watchCategories(String userId) {
    return _remoteDataSource
        .watchCategories(userId)
        .map<Result<List<CategoryEntity>>>(
          (models) => Success(models.map((m) => m.toEntity()).toList()),
        )
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (Object error, StackTrace _, EventSink<Result<List<CategoryEntity>>> sink) {
              sink.add(Err(ErrorMapper.map(error)));
            },
          ),
        );
  }

  @override
  Stream<Result<List<TransactionEntity>>> watchTransactions({
    required String userId,
    required String monthKey,
    int limit = 100,
  }) {
    return _remoteDataSource
        .watchTransactions(userId: userId, monthKey: monthKey, limit: limit)
        .map<Result<List<TransactionEntity>>>(
          (models) => Success(models.map((m) => m.entity).toList()),
        )
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (
              Object error,
              StackTrace _,
              EventSink<Result<List<TransactionEntity>>> sink,
            ) {
              sink.add(Err(ErrorMapper.map(error)));
            },
          ),
        );
  }

  @override
  Future<Result<WalletEntity>> createWallet({
    required String userId,
    required String name,
    required WalletType type,
    required int openingBalanceMinor,
    String? bankCode,
    String? maskedAccount,
  }) async {
    try {
      final model = await _remoteDataSource.createWallet(
        userId: userId,
        name: name,
        type: type,
        openingBalanceMinor: openingBalanceMinor,
        bankCode: bankCode,
        maskedAccount: maskedAccount,
      );
      return Success(model.toEntity());
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<TransactionEntity>> createTransaction({
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
    try {
      final model = await _remoteDataSource.createTransaction(
        operationId: operationId,
        userId: userId,
        walletId: walletId,
        targetWalletId: targetWalletId,
        categoryId: categoryId,
        categoryName: categoryName,
        kind: kind,
        amountMinor: amountMinor,
        merchant: merchant,
        note: note,
        occurredAt: occurredAt,
        splitLines: splitLines,
      );
      return Success(model.entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<TransactionEntity>> reverseTransaction({
    required String userId,
    required String transactionId,
    required String reason,
  }) async {
    try {
      final model = await _remoteDataSource.reverseTransaction(
        userId: userId,
        transactionId: transactionId,
        reason: reason,
      );
      return Success(model.entity);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> decideProvisionalTransaction({
    required String userId,
    required String transactionId,
    required bool approve,
    String? updatedCategoryName,
    String? updatedMerchant,
  }) async {
    try {
      await _remoteDataSource.decideProvisionalTransaction(
        userId: userId,
        transactionId: transactionId,
        approve: approve,
        updatedCategoryName: updatedCategoryName,
        updatedMerchant: updatedMerchant,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> saveNetWorthSnapshot({
    required String userId,
    required String monthKey,
    required FinanceOverviewSummary summary,
  }) async {
    try {
      await _remoteDataSource.upsertNetWorthSnapshot(
        userId: userId,
        monthKey: monthKey,
        summary: summary,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
