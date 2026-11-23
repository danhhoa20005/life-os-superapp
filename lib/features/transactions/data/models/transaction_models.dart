import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/transaction_entities.dart';

class WalletModel {
  final String id;
  final String ownerId;
  final String name;
  final WalletType type;
  final String? bankCode;
  final String? maskedAccount;
  final int balanceMinor;
  final int? creditLimitMinor;
  final bool isEstimatedBalance;
  final bool hasPendingWrites;

  const WalletModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    this.bankCode,
    this.maskedAccount,
    required this.balanceMinor,
    this.creditLimitMinor,
    required this.isEstimatedBalance,
    required this.hasPendingWrites,
  });

  factory WalletModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawType = (d['type'] as String?) ?? 'cash';
    final type = switch (rawType) {
      'bank' => WalletType.bank,
      'creditCard' || 'credit_card' => WalletType.creditCard,
      'savings' || 'investment' => WalletType.savings,
      _ => WalletType.cash,
    };
    return WalletModel(
      id: (d['id'] as String?) ?? doc.id,
      ownerId: (d['ownerId'] as String?) ?? '',
      name: (d['name'] as String?) ?? 'Ví',
      type: type,
      bankCode: d['bankCode'] as String?,
      maskedAccount: d['maskedAccount'] as String?,
      balanceMinor: (d['balanceMinor'] as num?)?.toInt() ?? 0,
      creditLimitMinor: (d['creditLimitMinor'] as num?)?.toInt(),
      isEstimatedBalance: (d['isEstimatedBalance'] as bool?) ?? true,
      hasPendingWrites: doc.metadata.hasPendingWrites,
    );
  }

  WalletEntity toEntity() {
    return WalletEntity(
      id: id,
      ownerId: ownerId,
      name: name,
      type: type,
      bankCode: bankCode,
      maskedAccount: maskedAccount,
      balanceMinor: balanceMinor,
      creditLimitMinor: creditLimitMinor,
      isEstimatedBalance: isEstimatedBalance,
      hasPendingWrites: hasPendingWrites,
    );
  }
}

class CategoryModel {
  final String id;
  final String ownerId;
  final String name;
  final String direction;
  final String iconKey;

  const CategoryModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.direction,
    required this.iconKey,
  });

  factory CategoryModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CategoryModel(
      id: (d['id'] as String?) ?? doc.id,
      ownerId: (d['ownerId'] as String?) ?? '',
      name: (d['name'] as String?) ?? 'Khác',
      direction: (d['direction'] as String?) ?? 'debit',
      iconKey: (d['iconKey'] as String?) ?? 'category',
    );
  }

  CategoryEntity toEntity() {
    return CategoryEntity(
      id: id,
      ownerId: ownerId,
      name: name,
      direction: direction,
      iconKey: iconKey,
    );
  }
}

class TransactionModel {
  final TransactionEntity entity;

  const TransactionModel(this.entity);

  factory TransactionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final occurredRaw = d['occurredAt'];
    final occurredAt = occurredRaw is Timestamp
        ? occurredRaw.toDate()
        : DateTime.now();

    final kind = switch (d['kind'] as String?) {
      'income' => TransactionKind.income,
      'transfer' => TransactionKind.transfer,
      'creditCardPayment' => TransactionKind.creditCardPayment,
      'reversal' => TransactionKind.reversal,
      _ => TransactionKind.expense,
    };

    final verification = switch (d['verification'] as String?) {
      'provisional' => TransactionVerification.provisional,
      'verified' => TransactionVerification.verified,
      'rejected' => TransactionVerification.rejected,
      'needsReview' => TransactionVerification.needsReview,
      _ => TransactionVerification.userConfirmed,
    };

    final sourceKind = switch (d['sourceKind'] as String?) {
      'androidNotification' => TransactionSourceKind.androidNotification,
      'csv' => TransactionSourceKind.csv,
      'bankApi' => TransactionSourceKind.bankApi,
      'bankWebhook' => TransactionSourceKind.bankWebhook,
      _ => TransactionSourceKind.manual,
    };

    final balanceType = switch (d['balanceType'] as String?) {
      'observedBankBalance' => TransactionBalanceType.observedBankBalance,
      'estimatedWalletBalance' => TransactionBalanceType.estimatedWalletBalance,
      _ => TransactionBalanceType.unknownBalance,
    };

    final receivedRaw = d['receivedAt'];
    final receivedAt = receivedRaw is Timestamp ? receivedRaw.toDate() : null;

    final monthKey =
        (d['monthKey'] as String?) ??
        '${occurredAt.year.toString().padLeft(4, '0')}-${occurredAt.month.toString().padLeft(2, '0')}';

    final rawSplits = d['splitLines'] as List<dynamic>? ?? const <dynamic>[];
    final splitLines = rawSplits
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => TransactionSplitLine(
            categoryName: (item['categoryName'] as String?) ?? 'Chi tiêu khác',
            amountMinor: (item['amountMinor'] as num?)?.toInt() ?? 0,
            note: item['note'] as String?,
          ),
        )
        .where((line) => line.amountMinor > 0)
        .toList(growable: false);

    return TransactionModel(
      TransactionEntity(
        id: (d['id'] as String?) ?? doc.id,
        ownerId: (d['ownerId'] as String?) ?? '',
        walletId: (d['walletId'] as String?) ?? '',
        targetWalletId: d['targetWalletId'] as String?,
        categoryId: d['categoryId'] as String?,
        categoryName: (d['categoryName'] as String?) ?? 'Chưa phân loại',
        kind: kind,
        direction: (d['direction'] as String?) ?? 'debit',
        amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
        currencyCode: (d['currencyCode'] as String?) ?? 'VND',
        merchant: (d['merchant'] as String?) ?? '',
        note: d['note'] as String?,
        occurredAt: occurredAt,
        monthKey: monthKey,
        sourceKind: sourceKind,
        verification: verification,
        crossSourceFingerprint: (d['crossSourceFingerprint'] as String?) ?? '',
        reversalOfId: d['reversalOfId'] as String?,
        reversedById: d['reversedById'] as String?,
        isVehicleMaintenanceHint:
            (d['isVehicleMaintenanceHint'] as bool?) ?? false,
        splitLines: splitLines,
        balanceAfterMinor: (d['balanceAfterMinor'] as num?)?.toInt(),
        balanceType: balanceType,
        ledgerApplied: d['ledgerApplied'] as bool?,
        walletName: d['walletName'] as String?,
        connectionId: d['connectionId'] as String?,
        sourceProvider: d['sourceProvider'] as String?,
        externalTransactionId: d['externalTransactionId']?.toString(),
        referenceCode: d['referenceCode'] as String?,
        bankCode: d['bankCode'] as String?,
        accountMasked: d['accountMasked'] as String?,
        counterpartyDisplay: d['counterpartyDisplay'] as String?,
        receivedAt: receivedAt,
        reconciliationStatus: d['reconciliationStatus'] as String?,
        sourceEventKey: d['sourceEventKey'] as String?,
        isRecurringCandidate: (d['isRecurringCandidate'] as bool?) ?? false,
        hasPendingWrites: doc.metadata.hasPendingWrites,
      ),
    );
  }

  static Map<String, dynamic> toFirestoreMap({
    required String id,
    required String ownerId,
    required String walletId,
    String? targetWalletId,
    String? categoryId,
    required String categoryName,
    required TransactionKind kind,
    required String direction,
    required int amountMinor,
    required String merchant,
    String? note,
    required DateTime occurredAt,
    required TransactionSourceKind sourceKind,
    required TransactionVerification verification,
    required String crossSourceFingerprint,
    String? reversalOfId,
    String? reversedById,
    bool isVehicleMaintenanceHint = false,
    List<TransactionSplitLine> splitLines = const [],
    int? balanceAfterMinor,
    String? walletName,
    required DateTime now,
  }) {
    final monthKey =
        '${occurredAt.year.toString().padLeft(4, '0')}-${occurredAt.month.toString().padLeft(2, '0')}';
    return {
      'id': id,
      'ownerId': ownerId,
      'walletId': walletId,
      'targetWalletId': targetWalletId,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'kind': kind.name,
      'direction': direction,
      'amountMinor': amountMinor,
      'currencyCode': 'VND',
      'merchant': merchant,
      'note': note,
      'occurredAt': Timestamp.fromDate(occurredAt),
      'monthKey': monthKey,
      'sourceKind': sourceKind.name,
      'verification': verification.name,
      'crossSourceFingerprint': crossSourceFingerprint,
      'reversalOfId': reversalOfId,
      'reversedById': reversedById,
      'isVehicleMaintenanceHint': isVehicleMaintenanceHint,
      if (balanceAfterMinor != null) 'balanceAfterMinor': balanceAfterMinor,
      'balanceType': balanceAfterMinor != null
          ? 'estimatedWalletBalance'
          : 'unknownBalance',
      'ledgerApplied':
          verification == TransactionVerification.userConfirmed ||
          verification == TransactionVerification.verified,
      if (walletName != null && walletName.isNotEmpty) 'walletName': walletName,
      'splitLines': splitLines
          .map(
            (l) => <String, dynamic>{
              'categoryName': l.categoryName,
              'amountMinor': l.amountMinor,
              if (l.note != null && l.note!.isNotEmpty) 'note': l.note,
            },
          )
          .toList(growable: false),
      'schemaVersion': 2,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    };
  }
}
