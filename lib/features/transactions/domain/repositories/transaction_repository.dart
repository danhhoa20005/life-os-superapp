import '../../../../core/error/app_exception.dart';
import '../entities/transaction_entities.dart';

abstract interface class TransactionRepository {
  Stream<Result<List<WalletEntity>>> watchWallets(String userId);

  Stream<Result<List<CategoryEntity>>> watchCategories(String userId);

  Stream<Result<List<TransactionEntity>>> watchTransactions({
    required String userId,
    required String monthKey,
    int limit = 100,
  });

  Stream<Result<List<TransactionEntity>>> watchTransactionsRange({
    required String userId,
    required DateTime startInclusive,
    required DateTime endExclusive,
    int limit = 600,
  });

  Future<Result<WalletEntity>> createWallet({
    required String userId,
    required String name,
    required WalletType type,
    required int openingBalanceMinor,
    String? bankCode,
    String? maskedAccount,
  });

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
  });

  Future<Result<TransactionEntity>> reverseTransaction({
    required String userId,
    required String transactionId,
    required String reason,
  });

  Future<Result<void>> decideProvisionalTransaction({
    required String userId,
    required String transactionId,
    required bool approve,
    String? updatedCategoryName,
    String? updatedMerchant,
    int? updatedAmountMinor,
    String? updatedNote,
  });

  Future<Result<void>> saveNetWorthSnapshot({
    required String userId,
    required String monthKey,
    required FinanceOverviewSummary summary,
  });
}
