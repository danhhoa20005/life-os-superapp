import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../entities/transaction_entities.dart';
import '../repositories/transaction_repository.dart';

final class CreateWalletParams {
  final String userId;
  final String name;
  final WalletType type;
  final int openingBalanceMinor;
  final String? bankCode;
  final String? maskedAccount;

  const CreateWalletParams({
    required this.userId,
    required this.name,
    required this.type,
    required this.openingBalanceMinor,
    this.bankCode,
    this.maskedAccount,
  });
}

class CreateWalletUseCase implements UseCase<WalletEntity, CreateWalletParams> {
  final TransactionRepository _repository;
  const CreateWalletUseCase(this._repository);

  @override
  Future<Result<WalletEntity>> call(CreateWalletParams params) async {
    final cleanName = params.name.trim();
    if (cleanName.length < 2) {
      return const Err(
        ValidationFailure(message: 'Tên ví/tài khoản phải có ít nhất 2 ký tự.'),
      );
    }
    if (params.openingBalanceMinor.abs() > VndAmount.maxAllowedMinor) {
      return const Err(
        ValidationFailure(message: 'Số dư đầu kỳ vượt ngoài phạm vi cho phép.'),
      );
    }
    return _repository.createWallet(
      userId: params.userId,
      name: cleanName,
      type: params.type,
      openingBalanceMinor: params.openingBalanceMinor,
      bankCode: params.bankCode,
      maskedAccount: params.maskedAccount,
    );
  }
}

final class CreateTransactionParams {
  final String operationId;
  final String userId;
  final String walletId;
  final String? targetWalletId;
  final String? categoryId;
  final String categoryName;
  final TransactionKind kind;
  final int amountMinor;
  final String merchant;
  final String? note;
  final DateTime occurredAt;
  final List<TransactionSplitLine> splitLines;

  const CreateTransactionParams({
    required this.operationId,
    required this.userId,
    required this.walletId,
    this.targetWalletId,
    this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.amountMinor,
    required this.merchant,
    this.note,
    required this.occurredAt,
    this.splitLines = const [],
  });
}

class CreateTransactionUseCase
    implements UseCase<TransactionEntity, CreateTransactionParams> {
  final TransactionRepository _repository;
  const CreateTransactionUseCase(this._repository);

  @override
  Future<Result<TransactionEntity>> call(CreateTransactionParams params) async {
    if (params.operationId.trim().isEmpty) {
      return const Err(
        ValidationFailure(
          message: 'Thiếu mã định danh thao tác (operationId).',
        ),
      );
    }
    if (params.amountMinor <= 0 ||
        params.amountMinor > VndAmount.maxAllowedMinor) {
      return const Err(
        ValidationFailure(
          message: 'Số tiền giao dịch phải là số nguyên dương (VND).',
        ),
      );
    }
    if (params.splitLines.isNotEmpty) {
      if (params.kind != TransactionKind.expense) {
        return const Err(
          ValidationFailure(
            message:
                'Tách khoản đa danh mục chỉ áp dụng cho bút toán chi tiêu.',
          ),
        );
      }
      var splitSum = 0;
      for (final line in params.splitLines) {
        if (line.categoryName.trim().isEmpty || line.amountMinor <= 0) {
          return const Err(
            ValidationFailure(
              message:
                  'Mỗi dòng tách khoản phải có danh mục và số tiền nguyên dương.',
            ),
          );
        }
        splitSum += line.amountMinor;
      }
      if (splitSum != params.amountMinor) {
        return Err(
          ValidationFailure(
            message:
                'Tổng các khoản tách (${VndAmount.format(splitSum)}) phải khớp chính xác tổng tiền (${VndAmount.format(params.amountMinor)}).',
          ),
        );
      }
    }
    if (params.kind == TransactionKind.transfer ||
        params.kind == TransactionKind.creditCardPayment) {
      if (params.targetWalletId == null || params.targetWalletId!.isEmpty) {
        return const Err(
          ValidationFailure(message: 'Vui lòng chọn ví/tài khoản đích.'),
        );
      }
      if (params.targetWalletId == params.walletId) {
        return const Err(
          ValidationFailure(
            message: 'Ví nguồn và ví đích không được trùng nhau.',
          ),
        );
      }
    }
    final primaryCategory = params.splitLines.length > 1
        ? '${params.splitLines.first.categoryName} (+${params.splitLines.length - 1} khoản)'
        : params.categoryName;

    final cleanMerchant = params.merchant.trim().isEmpty
        ? (params.kind == TransactionKind.transfer
              ? 'Chuyển tiền nội bộ'
              : params.kind == TransactionKind.creditCardPayment
              ? 'Thanh toán dư nợ thẻ tín dụng'
              : primaryCategory)
        : params.merchant.trim();

    return _repository.createTransaction(
      operationId: params.operationId.trim(),
      userId: params.userId,
      walletId: params.walletId,
      targetWalletId: params.targetWalletId,
      categoryId: params.categoryId,
      categoryName: primaryCategory,
      kind: params.kind,
      amountMinor: params.amountMinor,
      merchant: cleanMerchant,
      note: params.note?.trim(),
      occurredAt: params.occurredAt,
      splitLines: params.splitLines,
    );
  }
}

final class ReverseTransactionParams {
  final String userId;
  final String transactionId;
  final String reason;

  const ReverseTransactionParams({
    required this.userId,
    required this.transactionId,
    this.reason = 'Hoàn tiền / Đảo bút toán',
  });
}

class ReverseTransactionUseCase
    implements UseCase<TransactionEntity, ReverseTransactionParams> {
  final TransactionRepository _repository;
  const ReverseTransactionUseCase(this._repository);

  @override
  Future<Result<TransactionEntity>> call(ReverseTransactionParams params) {
    return _repository.reverseTransaction(
      userId: params.userId,
      transactionId: params.transactionId,
      reason: params.reason.trim().isEmpty
          ? 'Hoàn tiền / Đảo bút toán'
          : params.reason.trim(),
    );
  }
}

final class DecideProvisionalParams {
  final String userId;
  final String transactionId;
  final bool approve;
  final String? updatedCategoryName;
  final String? updatedMerchant;

  const DecideProvisionalParams({
    required this.userId,
    required this.transactionId,
    required this.approve,
    this.updatedCategoryName,
    this.updatedMerchant,
  });
}

class DecideProvisionalTransactionUseCase
    implements UseCase<void, DecideProvisionalParams> {
  final TransactionRepository _repository;
  const DecideProvisionalTransactionUseCase(this._repository);

  @override
  Future<Result<void>> call(DecideProvisionalParams params) {
    return _repository.decideProvisionalTransaction(
      userId: params.userId,
      transactionId: params.transactionId,
      approve: params.approve,
      updatedCategoryName: params.updatedCategoryName?.trim(),
      updatedMerchant: params.updatedMerchant?.trim(),
    );
  }
}
