import 'package:equatable/equatable.dart';
import '../../domain/entities/transaction_entities.dart';

sealed class TransactionListEvent extends Equatable {
  const TransactionListEvent();

  @override
  List<Object?> get props => [];
}

final class TransactionsSubscriptionRequested extends TransactionListEvent {
  final String userId;
  final String? monthKey;

  const TransactionsSubscriptionRequested({
    required this.userId,
    this.monthKey,
  });

  @override
  List<Object?> get props => [userId, monthKey];
}

final class TransactionsSearchChanged extends TransactionListEvent {
  final String query;
  const TransactionsSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

final class TransactionsKindFilterChanged extends TransactionListEvent {
  final TransactionKind? kind;
  const TransactionsKindFilterChanged(this.kind);

  @override
  List<Object?> get props => [kind];
}

sealed class TransactionActionEvent extends Equatable {
  const TransactionActionEvent();

  @override
  List<Object?> get props => [];
}

final class WalletCreateSubmitted extends TransactionActionEvent {
  final String userId;
  final String name;
  final WalletType type;
  final int openingBalanceMinor;
  final String? bankCode;
  final String? maskedAccount;

  const WalletCreateSubmitted({
    required this.userId,
    required this.name,
    required this.type,
    required this.openingBalanceMinor,
    this.bankCode,
    this.maskedAccount,
  });

  @override
  List<Object?> get props => [
    userId,
    name,
    type,
    openingBalanceMinor,
    bankCode,
    maskedAccount,
  ];
}

final class TransactionCreateSubmitted extends TransactionActionEvent {
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

  const TransactionCreateSubmitted({
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

  @override
  List<Object?> get props => [
    operationId,
    userId,
    walletId,
    targetWalletId,
    categoryId,
    categoryName,
    kind,
    amountMinor,
    merchant,
    note,
    occurredAt,
    splitLines,
  ];
}

final class TransactionReverseRequested extends TransactionActionEvent {
  final String userId;
  final String transactionId;
  final String reason;

  const TransactionReverseRequested({
    required this.userId,
    required this.transactionId,
    this.reason = 'Hoàn tiền / Hủy giao dịch',
  });

  @override
  List<Object?> get props => [userId, transactionId, reason];
}

final class ProvisionalTransactionDecisionSubmitted
    extends TransactionActionEvent {
  final String userId;
  final String transactionId;
  final bool approve;
  final String? updatedCategoryName;
  final String? updatedMerchant;

  const ProvisionalTransactionDecisionSubmitted({
    required this.userId,
    required this.transactionId,
    required this.approve,
    this.updatedCategoryName,
    this.updatedMerchant,
  });

  @override
  List<Object?> get props => [
    userId,
    transactionId,
    approve,
    updatedCategoryName,
    updatedMerchant,
  ];
}
