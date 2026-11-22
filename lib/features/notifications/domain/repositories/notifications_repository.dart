import '../../../../core/error/app_exception.dart';
import '../entities/notification_entities.dart';

abstract interface class NotificationsRepository {
  Stream<Result<SourceConsentEntity>> watchAndroidNotificationConsent(String userId);

  Future<Result<void>> updateAndroidNotificationConsent({
    required String userId,
    required bool enabled,
    required List<String> allowedPackages,
    bool? autoConfirmSignals,
  });

  Future<Result<IngestionOutcome>> ingestAndroidNotification({
    required String userId,
    required String defaultWalletId,
    required String packageName,
    required String title,
    required String body,
    DateTime? postedAt,
    String? notificationId,
  });

  Future<Result<IngestionOutcome>> ingestVerifiedBankFeedEvent({
    required String userId,
    required String walletId,
    required String externalTransactionId,
    required String direction,
    required int amountMinor,
    required String content,
    required DateTime occurredAt,
    String? referenceCode,
  });

  /// Imports CSV bank statement rows idempotently (SHA-256 per-file & per-row key prevents duplicate imports).
  Future<Result<int>> importCsvStatement({
    required String userId,
    required String walletId,
    required String csvContent,
  });

  Future<Result<String>> exportPersonalDataJson(String userId);

  /// Permanently deletes personal data & revokes family memberships (PDPL 91/2025 & Google Play User Data Policy).
  Future<Result<void>> deleteAccountAndPersonalData(String userId);

  Future<bool> isNativeNotificationAccessGranted();

  Future<void> openNativeNotificationAccessSettings();

  Stream<Map<String, dynamic>> watchLiveAndroidBankSignals();

  Future<List<Map<String, dynamic>>> drainQueuedAndroidBankSignals();

  Future<Result<String?>> getSavedSePayMaskedToken(String userId);

  Future<Result<int>> syncSePayTransactions({
    required String userId,
    required String walletId,
    String? apiTokenOverride,
    int limit = 40,
  });
}
