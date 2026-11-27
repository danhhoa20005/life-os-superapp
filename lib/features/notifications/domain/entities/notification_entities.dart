import 'package:equatable/equatable.dart';

export 'bank_capability_and_connection_entities.dart';

class SourceConsentEntity extends Equatable {
  final String sourceId;
  final String ownerId;
  final bool enabled;
  final bool autoConfirmSignals;
  final bool voiceSoundboxEnabled;
  final bool syncObservedBalance;
  final List<String> allowedPackages;
  final DateTime updatedAt;

  const SourceConsentEntity({
    required this.sourceId,
    required this.ownerId,
    required this.enabled,
    this.autoConfirmSignals = false,
    this.voiceSoundboxEnabled = false,
    this.syncObservedBalance = true,
    required this.allowedPackages,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
    sourceId,
    ownerId,
    enabled,
    autoConfirmSignals,
    voiceSoundboxEnabled,
    syncObservedBalance,
    allowedPackages,
    updatedAt,
  ];
}

/// User's own receiving bank account configured directly inside LifeOS for VietQR generation
/// and automatic incoming/outgoing bank notification routing (zero passwords, zero 3rd-party API).
class LinkedBankAccountEntity extends Equatable {
  final String id;
  final String ownerId;
  final String walletId;
  final String bankBin;
  final String bankCode;
  final String bankName;
  final String accountNumber;
  final String accountHolderName;
  final bool isDefault;
  final DateTime createdAt;

  const LinkedBankAccountEntity({
    required this.id,
    required this.ownerId,
    required this.walletId,
    required this.bankBin,
    required this.bankCode,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolderName,
    this.isDefault = true,
    required this.createdAt,
  });

  String get maskedAccount {
    final clean = accountNumber.trim();
    if (clean.length <= 4) return clean;
    return '•••• ${clean.substring(clean.length - 4)}';
  }

  String get accountTail {
    final digits = accountNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 4) return digits;
    return digits.substring(digits.length - 4);
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    walletId,
    bankBin,
    bankCode,
    bankName,
    accountNumber,
    accountHolderName,
    isDefault,
    createdAt,
  ];
}

enum PaymentOrderStatus {
  pending,
  partial,
  paid,
  needsReview,
  expired,
  cancelled;

  String get statusLabelVi => switch (this) {
    PaymentOrderStatus.pending => 'Chờ chuyển khoản',
    PaymentOrderStatus.partial => 'Đã nhận một phần',
    PaymentOrderStatus.paid => 'Đã nhận đủ',
    PaymentOrderStatus.needsReview => 'Cần đối soát',
    PaymentOrderStatus.expired => 'Hết hạn',
    PaymentOrderStatus.cancelled => 'Đã hủy',
  };

  String get displayLabel => statusLabelVi;
}

/// Native In-App Dynamic VietQR Payment Collection Order ("Mã QR Thu Tiền Tự Động").
/// Automatically transitions through `pending` -> `partial` -> `paid` (or `needsReview`)
/// inside transactional verification when matching bank notifications arrive.
class PaymentOrderEntity extends Equatable {
  final String id;
  final String ownerId;
  final String walletId;
  final String bankBin;
  final String bankCode;
  final String bankName;
  final String accountNumber;
  final String accountHolderName;
  final int amountMinor;
  final int receivedAmountMinor;
  final String currency;
  final Map<String, int> receivedContributions;
  final String paymentCode;
  final String description;
  final String emvQrPayload;
  final PaymentOrderStatus status;
  final String? matchedTransactionId;
  final List<String> matchedTransactionIds;
  final String? reviewReason;
  final DateTime createdAt;
  final DateTime? paidAt;

  const PaymentOrderEntity({
    required this.id,
    required this.ownerId,
    required this.walletId,
    required this.bankBin,
    required this.bankCode,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolderName,
    required this.amountMinor,
    this.receivedAmountMinor = 0,
    this.currency = 'VND',
    this.receivedContributions = const <String, int>{},
    required this.paymentCode,
    required this.description,
    required this.emvQrPayload,
    this.status = PaymentOrderStatus.pending,
    this.matchedTransactionId,
    this.matchedTransactionIds = const <String>[],
    this.reviewReason,
    required this.createdAt,
    this.paidAt,
  });

  int get remainingAmountMinor => (amountMinor - receivedAmountMinor) > 0
      ? (amountMinor - receivedAmountMinor)
      : 0;

  bool get isPaid => status == PaymentOrderStatus.paid;
  bool get isPartial => status == PaymentOrderStatus.partial;
  bool get isNeedsReview => status == PaymentOrderStatus.needsReview;

  @override
  List<Object?> get props => [
    id,
    ownerId,
    walletId,
    bankBin,
    bankCode,
    bankName,
    accountNumber,
    accountHolderName,
    amountMinor,
    receivedAmountMinor,
    currency,
    receivedContributions,
    paymentCode,
    description,
    emvQrPayload,
    status,
    matchedTransactionId,
    matchedTransactionIds,
    reviewReason,
    createdAt,
    paidAt,
  ];
}

enum IngestionOutcomeKind {
  createdProvisional,
  autoReconciledOrder,
  upgradedToVerified,
  duplicateIgnored,
  blockedOtpOrSecret,
  blockedConsentDisabled,
  ignoredPackageOrFormat,
}

class IngestionOutcome extends Equatable {
  final IngestionOutcomeKind kind;
  final String? transactionId;
  final String? matchedOrderId;
  final String? matchedPaymentCode;
  final String message;

  const IngestionOutcome({
    required this.kind,
    this.transactionId,
    this.matchedOrderId,
    this.matchedPaymentCode,
    required this.message,
  });

  @override
  List<Object?> get props => [
    kind,
    transactionId,
    matchedOrderId,
    matchedPaymentCode,
    message,
  ];
}
