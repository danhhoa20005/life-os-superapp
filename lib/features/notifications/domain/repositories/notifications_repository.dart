import '../../../../core/error/app_exception.dart';
import '../entities/notification_entities.dart';

abstract interface class NotificationsRepository {
  Stream<Result<SourceConsentEntity>> watchAndroidNotificationConsent(String userId);

  Future<Result<void>> updateAndroidNotificationConsent({
    required String userId,
    required bool enabled,
    required List<String> allowedPackages,
    bool? autoConfirmSignals,
    bool? voiceSoundboxEnabled,
    bool? syncObservedBalance,
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

  /// Watches the user's linked receiving bank accounts for native VietQR generation & routing.
  Stream<Result<List<LinkedBankAccountEntity>>> watchLinkedBankAccounts(String userId);

  Future<Result<LinkedBankAccountEntity>> saveLinkedBankAccount({
    required String userId,
    required String walletId,
    required String bankBin,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolderName,
    bool isDefault = true,
  });

  Future<Result<void>> deleteLinkedBankAccount({
    required String userId,
    required String accountId,
  });

  /// Watches native Dynamic VietQR payment collection orders (`Chờ nhận tiền` / `Đã nhận đủ`).
  Stream<Result<List<PaymentOrderEntity>>> watchPaymentOrders(String userId);

  Future<Result<PaymentOrderEntity>> createPaymentOrder({
    required String userId,
    required String walletId,
    required String bankBin,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolderName,
    required int amountMinor,
    required String description,
  });

  Future<Result<void>> markPaymentOrderStatus({
    required String userId,
    required String orderId,
    required PaymentOrderStatus status,
  });

  /// Imports CSV bank statement rows idempotently (SHA-256 per-file & per-row key prevents duplicate imports).
  Future<Result<int>> importCsvStatement({
    required String userId,
    required String walletId,
    required String csvContent,
  });

  Future<Result<String>> exportPersonalDataJson(String userId);

  /// Permanently deletes personal data & revokes family memberships.
  Future<Result<void>> deleteAccountAndPersonalData(String userId);

  Future<bool> isNativeNotificationAccessGranted();

  Future<void> openNativeNotificationAccessSettings();

  Future<void> speakSoundboxTest(String message);

  Stream<Map<String, dynamic>> watchLiveAndroidBankSignals();

  Future<List<Map<String, dynamic>>> drainQueuedAndroidBankSignals();
}
