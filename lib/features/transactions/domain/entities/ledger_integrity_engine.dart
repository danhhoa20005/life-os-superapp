import 'package:equatable/equatable.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import 'transaction_entities.dart';

/// Canonical verification status constants stored in `ledger_audits` and
/// `transactions.verificationStatus`.
abstract final class LedgerVerificationStatuses {
  static const String provisional = 'PROVISIONAL';
  static const String userConfirmed = 'USER_CONFIRMED';
  static const String matchedPaymentOrder = 'MATCHED_PAYMENT_ORDER';
  static const String verified = 'VERIFIED';
  static const String rejected = 'REJECTED';
  static const String reversed = 'REVERSED';
  static const String needsReview = 'NEEDS_REVIEW';

  static const Set<String> allowed = {
    provisional,
    userConfirmed,
    matchedPaymentOrder,
    verified,
    rejected,
    reversed,
    needsReview,
  };

  static String fromVerification(
    TransactionVerification verification, {
    bool isReversed = false,
  }) {
    if (isReversed) return reversed;
    return switch (verification) {
      TransactionVerification.provisional => provisional,
      TransactionVerification.userConfirmed => userConfirmed,
      TransactionVerification.matchedPaymentOrder => matchedPaymentOrder,
      TransactionVerification.verified => verified,
      TransactionVerification.rejected => rejected,
      TransactionVerification.needsReview => needsReview,
    };
  }
}

/// Append-only wallet balance audit entry (`users/{uid}/ledger_audits/{auditId}`).
class LedgerAuditRecord extends Equatable {
  final String auditId;
  final String operationId;
  final String transactionId;
  final String walletId;
  final int previousBalanceMinor;
  final int deltaAmountMinor;
  final int newBalanceMinor;
  final DateTime createdAt;
  final String actorId;
  final String source;
  final String verificationStatus;
  final String? walletName;
  final String? kind;

  const LedgerAuditRecord({
    required this.auditId,
    required this.operationId,
    required this.transactionId,
    required this.walletId,
    required this.previousBalanceMinor,
    required this.deltaAmountMinor,
    required this.newBalanceMinor,
    required this.createdAt,
    required this.actorId,
    required this.source,
    required this.verificationStatus,
    this.walletName,
    this.kind,
  });

  bool get satisfiesBalanceInvariant =>
      previousBalanceMinor + deltaAmountMinor == newBalanceMinor;

  /// Pure JSON-safe map representation (Firestore Timestamps are added in data layer).
  Map<String, dynamic> toPayloadMap({required Object createdAtValue}) {
    return <String, dynamic>{
      'id': auditId,
      'auditId': auditId,
      'operationId': operationId,
      'transactionId': transactionId,
      'txId': transactionId,
      'ownerId': actorId,
      'actorId': actorId,
      'walletId': walletId,
      if (walletName != null && walletName!.isNotEmpty)
        'walletName': walletName,
      'previousBalanceMinor': previousBalanceMinor,
      'deltaAmountMinor': deltaAmountMinor,
      'deltaMinor': deltaAmountMinor,
      'newBalanceMinor': newBalanceMinor,
      'source': source,
      'verificationStatus': verificationStatus,
      if (kind != null && kind!.isNotEmpty) 'kind': kind,
      'createdAt': createdAtValue,
    };
  }

  @override
  List<Object?> get props => [
    auditId,
    operationId,
    transactionId,
    walletId,
    previousBalanceMinor,
    deltaAmountMinor,
    newBalanceMinor,
    createdAt,
    actorId,
    source,
    verificationStatus,
    walletName,
    kind,
  ];
}

/// Pure Dart invariant checker for double-entry / append-only wallet ledgers (`FIX-007`).
abstract final class LedgerIntegrityEngine {
  static bool isBalanceEquationValid(LedgerAuditRecord record) =>
      record.previousBalanceMinor + record.deltaAmountMinor ==
      record.newBalanceMinor;

  static bool isImmutableVerified(TransactionEntity tx) {
    return tx.verification == TransactionVerification.verified ||
        tx.verificationStatus?.toUpperCase() ==
            LedgerVerificationStatuses.verified;
  }

  /// Validates and constructs an immutable [LedgerAuditRecord].
  static Result<LedgerAuditRecord> buildAndValidateAudit({
    required String auditId,
    required String operationId,
    required String transactionId,
    required String walletId,
    required int previousBalanceMinor,
    required int deltaAmountMinor,
    required int newBalanceMinor,
    required DateTime createdAt,
    required String actorId,
    required String source,
    required String verificationStatus,
    String? walletName,
    String? kind,
  }) {
    if (auditId.trim().isEmpty ||
        operationId.trim().isEmpty ||
        transactionId.trim().isEmpty ||
        walletId.trim().isEmpty ||
        actorId.trim().isEmpty ||
        source.trim().isEmpty) {
      return const Err(
        ValidationFailure(
          message: 'Thiếu trường bắt buộc của bản ghi kiểm toán sổ cái.',
        ),
      );
    }

    final normalizedStatus = verificationStatus.trim().toUpperCase();
    if (!LedgerVerificationStatuses.allowed.contains(normalizedStatus)) {
      return Err(
        ValidationFailure(
          message:
              'Trạng thái xác minh sổ cái không hợp lệ: $verificationStatus',
        ),
      );
    }

    if (previousBalanceMinor + deltaAmountMinor != newBalanceMinor) {
      return Err(
        ValidationFailure(
          message:
              'Vi phạm bất biến số dư: $previousBalanceMinor + ($deltaAmountMinor) != $newBalanceMinor.',
        ),
      );
    }

    return Success(
      LedgerAuditRecord(
        auditId: auditId.trim(),
        operationId: operationId.trim(),
        transactionId: transactionId.trim(),
        walletId: walletId.trim(),
        previousBalanceMinor: previousBalanceMinor,
        deltaAmountMinor: deltaAmountMinor,
        newBalanceMinor: newBalanceMinor,
        createdAt: createdAt,
        actorId: actorId.trim(),
        source: source.trim(),
        verificationStatus: normalizedStatus,
        walletName: walletName,
        kind: kind,
      ),
    );
  }

  /// Guards against duplicate `operationId` execution on the same wallet/ledger.
  static Result<void> validateUniqueOperationId({
    required String operationId,
    required Iterable<String> existingOperationIds,
  }) {
    final trimmed = operationId.trim();
    if (trimmed.isEmpty) {
      return const Err(
        ValidationFailure(message: 'operationId không được để trống.'),
      );
    }
    if (existingOperationIds.contains(trimmed)) {
      return Err(
        ConflictFailure(
          message: 'Thao tác với operationId "$trimmed" đã được ghi sổ trước đó.',
        ),
      );
    }
    return const Success(null);
  }

  /// Blocks client-side mutation of `amountMinor`, `walletId`, `kind`, or
  /// `verification` once a transaction has reached `VERIFIED` bank status.
  static Result<void> validateClientMutation({
    required TransactionEntity existing,
    int? newAmountMinor,
    String? newWalletId,
    TransactionKind? newKind,
    TransactionVerification? newVerification,
    String? newVerificationStatus,
  }) {
    if (!isImmutableVerified(existing)) {
      return const Success(null);
    }

    if (newAmountMinor != null && newAmountMinor != existing.amountMinor) {
      return const Err(
        PermissionDeniedFailure(
          message:
              'Không thể sửa amountMinor của giao dịch ngân hàng đã VERIFIED.',
        ),
      );
    }
    if (newWalletId != null && newWalletId != existing.walletId) {
      return const Err(
        PermissionDeniedFailure(
          message: 'Không thể sửa walletId của giao dịch ngân hàng đã VERIFIED.',
        ),
      );
    }
    if (newKind != null && newKind != existing.kind) {
      return const Err(
        PermissionDeniedFailure(
          message: 'Không thể sửa kind của giao dịch ngân hàng đã VERIFIED.',
        ),
      );
    }
    if (newVerification != null && newVerification != existing.verification) {
      return const Err(
        PermissionDeniedFailure(
          message:
              'Không thể hạ cấp verification của giao dịch ngân hàng đã VERIFIED.',
        ),
      );
    }
    if (newVerificationStatus != null &&
        newVerificationStatus.toUpperCase() !=
            LedgerVerificationStatuses.verified) {
      return const Err(
        PermissionDeniedFailure(
          message:
              'Không thể thay đổi verificationStatus của giao dịch đã VERIFIED từ client.',
        ),
      );
    }
    return const Success(null);
  }

  /// Enforces conservation of total asset balance across two-wallet transfers.
  static Result<void> validateTransferBalanceConservation({
    required int sourceBeforeMinor,
    required int sourceAfterMinor,
    required int targetBeforeMinor,
    required int targetAfterMinor,
    required int amountMinor,
  }) {
    if (amountMinor <= 0) {
      return const Err(
        ValidationFailure(message: 'Số tiền chuyển ví phải lớn hơn 0 ₫.'),
      );
    }
    if (sourceAfterMinor != sourceBeforeMinor - amountMinor ||
        targetAfterMinor != targetBeforeMinor + amountMinor) {
      return const Err(
        ValidationFailure(
          message: 'Số dư sau chuyển ví không khớp định luật bảo toàn tài sản.',
        ),
      );
    }
    if (sourceBeforeMinor + targetBeforeMinor !=
        sourceAfterMinor + targetAfterMinor) {
      return const Err(
        ValidationFailure(
          message: 'Tổng tài sản hai ví trước và sau chuyển khoản bị sai lệch.',
        ),
      );
    }
    return const Success(null);
  }

  /// Verifies an ordered or unordered list of [LedgerAuditRecord]s:
  /// - Each record satisfies `previous + delta == new`.
  /// - No duplicate `auditId`.
  /// - No duplicate `(operationId, walletId)` execution.
  static Result<void> verifyAuditTrail(List<LedgerAuditRecord> records) {
    final seenAuditIds = <String>{};
    final seenOpWalletPairs = <String>{};
    for (final rec in records) {
      if (!isBalanceEquationValid(rec)) {
        return Err(
          ValidationFailure(
            message:
                'Audit "${rec.auditId}" sai lệch phương trình số dư: ${rec.previousBalanceMinor} + ${rec.deltaAmountMinor} != ${rec.newBalanceMinor}.',
          ),
        );
      }
      if (!seenAuditIds.add(rec.auditId)) {
        return Err(
          ConflictFailure(message: 'Trùng lặp auditId "${rec.auditId}".'),
        );
      }
      final opWalletKey = '${rec.operationId}::${rec.walletId}';
      if (!seenOpWalletPairs.add(opWalletKey)) {
        return Err(
          ConflictFailure(
            message:
                'Thao tác "${rec.operationId}" bị ghi trùng trên ví "${rec.walletId}".',
          ),
        );
      }
    }
    return const Success(null);
  }
}
