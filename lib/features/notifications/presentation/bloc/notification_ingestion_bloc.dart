import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/services/fcm_banking_messaging_service.dart';
import '../../domain/entities/notification_entities.dart';
import '../../domain/repositories/notifications_repository.dart';

sealed class NotificationIngestionEvent extends Equatable {
  const NotificationIngestionEvent();

  @override
  List<Object?> get props => [];
}

final class NotificationsCenterStarted extends NotificationIngestionEvent {
  final String userId;
  final String defaultWalletId;

  const NotificationsCenterStarted(
    this.userId, {
    this.defaultWalletId = 'wallet_cash_default',
  });

  @override
  List<Object?> get props => [userId, defaultWalletId];
}

final class NativePermissionStatusRefreshed extends NotificationIngestionEvent {
  const NativePermissionStatusRefreshed();
}

final class OpenNativePermissionSettingsRequested
    extends NotificationIngestionEvent {
  const OpenNativePermissionSettingsRequested();
}

final class ConsentConfigUpdated extends NotificationIngestionEvent {
  final String userId;
  final bool enabled;
  final List<String> allowedPackages;
  final bool? autoConfirmSignals;
  final bool? voiceSoundboxEnabled;
  final bool? syncObservedBalance;

  const ConsentConfigUpdated({
    required this.userId,
    required this.enabled,
    required this.allowedPackages,
    this.autoConfirmSignals,
    this.voiceSoundboxEnabled,
    this.syncObservedBalance,
  });

  @override
  List<Object?> get props => [
    userId,
    enabled,
    allowedPackages,
    autoConfirmSignals,
    voiceSoundboxEnabled,
    syncObservedBalance,
  ];
}

final class BankNotificationSignalReceived extends NotificationIngestionEvent {
  final String userId;
  final String defaultWalletId;
  final String packageName;
  final String title;
  final String body;
  final DateTime? postedAt;
  final String? notificationId;

  const BankNotificationSignalReceived({
    required this.userId,
    required this.defaultWalletId,
    required this.packageName,
    required this.title,
    required this.body,
    this.postedAt,
    this.notificationId,
  });

  @override
  List<Object?> get props => [
    userId,
    defaultWalletId,
    packageName,
    title,
    body,
    postedAt,
    notificationId,
  ];
}

final class LinkedBankAccountSaved extends NotificationIngestionEvent {
  final String userId;
  final String walletId;
  final String bankBin;
  final String bankCode;
  final String bankName;
  final String accountNumber;
  final String accountHolderName;
  final bool isDefault;

  const LinkedBankAccountSaved({
    required this.userId,
    required this.walletId,
    required this.bankBin,
    required this.bankCode,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolderName,
    this.isDefault = true,
  });

  @override
  List<Object?> get props => [
    userId,
    walletId,
    bankBin,
    bankCode,
    bankName,
    accountNumber,
    accountHolderName,
    isDefault,
  ];
}

final class LinkedBankAccountDeleted extends NotificationIngestionEvent {
  final String userId;
  final String accountId;

  const LinkedBankAccountDeleted({
    required this.userId,
    required this.accountId,
  });

  @override
  List<Object?> get props => [userId, accountId];
}

final class PaymentOrderCreated extends NotificationIngestionEvent {
  final String userId;
  final String walletId;
  final String bankBin;
  final String bankCode;
  final String bankName;
  final String accountNumber;
  final String accountHolderName;
  final int amountMinor;
  final String description;

  const PaymentOrderCreated({
    required this.userId,
    required this.walletId,
    required this.bankBin,
    required this.bankCode,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolderName,
    required this.amountMinor,
    required this.description,
  });

  @override
  List<Object?> get props => [
    userId,
    walletId,
    bankBin,
    bankCode,
    bankName,
    accountNumber,
    accountHolderName,
    amountMinor,
    description,
  ];
}

final class PaymentOrderStatusMarked extends NotificationIngestionEvent {
  final String userId;
  final String orderId;
  final PaymentOrderStatus status;

  const PaymentOrderStatusMarked({
    required this.userId,
    required this.orderId,
    required this.status,
  });

  @override
  List<Object?> get props => [userId, orderId, status];
}

final class SoundboxTestRequested extends NotificationIngestionEvent {
  final String message;

  const SoundboxTestRequested({
    this.message = 'Đã nhận 250.000 đồng vào tài khoản',
  });

  @override
  List<Object?> get props => [message];
}

final class CsvStatementImportSubmitted extends NotificationIngestionEvent {
  final String userId;
  final String walletId;
  final String csvContent;

  const CsvStatementImportSubmitted({
    required this.userId,
    required this.walletId,
    required this.csvContent,
  });

  @override
  List<Object?> get props => [userId, walletId, csvContent];
}

final class PersonalDataExportRequested extends NotificationIngestionEvent {
  final String userId;
  const PersonalDataExportRequested(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class AccountDeletionConfirmed extends NotificationIngestionEvent {
  final String userId;
  const AccountDeletionConfirmed(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class VerifiedSePayBankLinkSubmitted extends NotificationIngestionEvent {
  final String userId;
  final String bankCode;
  final String accountNumber;
  final String subAccount;
  final String linkedWalletId;
  final String sepayApiToken;

  const VerifiedSePayBankLinkSubmitted({
    required this.userId,
    required this.bankCode,
    required this.accountNumber,
    this.subAccount = '',
    required this.linkedWalletId,
    required this.sepayApiToken,
  });

  @override
  List<Object?> get props => [
    userId,
    bankCode,
    accountNumber,
    subAccount,
    linkedWalletId,
    sepayApiToken,
  ];
}

final class BankConnectionDisconnected extends NotificationIngestionEvent {
  final String userId;
  final String connectionId;

  const BankConnectionDisconnected({
    required this.userId,
    required this.connectionId,
  });

  @override
  List<Object?> get props => [userId, connectionId];
}

final class BankConnectionReconcileRequested
    extends NotificationIngestionEvent {
  final String userId;
  final String connectionId;
  final String sepayApiToken;

  const BankConnectionReconcileRequested({
    required this.userId,
    required this.connectionId,
    required this.sepayApiToken,
  });

  @override
  List<Object?> get props => [userId, connectionId, sepayApiToken];
}

final class BankingPrivacyPreferencesUpdated
    extends NotificationIngestionEvent {
  final BankingNotificationPreferencesEntity preferences;

  const BankingPrivacyPreferencesUpdated(this.preferences);

  @override
  List<Object?> get props => [preferences];
}

final class SendTestBankingNotificationRequested
    extends NotificationIngestionEvent {
  final String userId;

  const SendTestBankingNotificationRequested(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class SaveMerchantRuleSubmitted extends NotificationIngestionEvent {
  final String userId;
  final String keyword;
  final String categoryName;

  const SaveMerchantRuleSubmitted({
    required this.userId,
    required this.keyword,
    required this.categoryName,
  });

  @override
  List<Object?> get props => [userId, keyword, categoryName];
}

final class NotificationsSessionClearedOnLogout
    extends NotificationIngestionEvent {
  const NotificationsSessionClearedOnLogout();
}

final class _BankConnectionsUpdated extends NotificationIngestionEvent {
  final List<BankConnectionEntity> connections;
  const _BankConnectionsUpdated(this.connections);

  @override
  List<Object?> get props => [connections];
}

final class _FinancialNotificationsUpdated extends NotificationIngestionEvent {
  final List<FinancialNotificationEntity> notifications;
  const _FinancialNotificationsUpdated(this.notifications);

  @override
  List<Object?> get props => [notifications];
}

final class _BankingPrefsUpdated extends NotificationIngestionEvent {
  final BankingNotificationPreferencesEntity prefs;
  const _BankingPrefsUpdated(this.prefs);

  @override
  List<Object?> get props => [prefs];
}

final class _MerchantRulesUpdated extends NotificationIngestionEvent {
  final List<MerchantCategoryRuleEntity> rules;
  const _MerchantRulesUpdated(this.rules);

  @override
  List<Object?> get props => [rules];
}

final class _LinkedBankAccountsUpdated extends NotificationIngestionEvent {
  final List<LinkedBankAccountEntity> accounts;
  const _LinkedBankAccountsUpdated(this.accounts);

  @override
  List<Object?> get props => [accounts];
}

final class _PaymentOrdersUpdated extends NotificationIngestionEvent {
  final List<PaymentOrderEntity> orders;
  const _PaymentOrdersUpdated(this.orders);

  @override
  List<Object?> get props => [orders];
}

final class NotificationIngestionState extends Equatable {
  final bool isLoading;
  final bool isSubmittingOrder;
  final bool isNativePermissionGranted;
  final bool isPushPermissionGranted;
  final SourceConsentEntity? consent;
  final List<LinkedBankAccountEntity> linkedBankAccounts;
  final List<BankConnectionEntity> bankConnections;
  final List<FinancialNotificationEntity> financialNotifications;
  final BankingNotificationPreferencesEntity? notificationPreferences;
  final List<MerchantCategoryRuleEntity> merchantRules;
  final List<PaymentOrderEntity> paymentOrders;
  final PaymentOrderEntity? latestCreatedOrder;
  final IngestionOutcome? lastOutcome;
  final String? infoMessage;
  final String? exportedJson;
  final bool accountDeleted;
  final Failure? failure;

  const NotificationIngestionState({
    this.isLoading = false,
    this.isSubmittingOrder = false,
    this.isNativePermissionGranted = false,
    this.isPushPermissionGranted = false,
    this.consent,
    this.linkedBankAccounts = const <LinkedBankAccountEntity>[],
    this.bankConnections = const <BankConnectionEntity>[],
    this.financialNotifications = const <FinancialNotificationEntity>[],
    this.notificationPreferences,
    this.merchantRules = const <MerchantCategoryRuleEntity>[],
    this.paymentOrders = const <PaymentOrderEntity>[],
    this.latestCreatedOrder,
    this.lastOutcome,
    this.infoMessage,
    this.exportedJson,
    this.accountDeleted = false,
    this.failure,
  });

  LinkedBankAccountEntity? get defaultBankAccount =>
      linkedBankAccounts.where((a) => a.isDefault).firstOrNull ??
      linkedBankAccounts.firstOrNull;

  NotificationIngestionState copyWith({
    bool? isLoading,
    bool? isSubmittingOrder,
    bool? isNativePermissionGranted,
    bool? isPushPermissionGranted,
    SourceConsentEntity? consent,
    List<LinkedBankAccountEntity>? linkedBankAccounts,
    List<BankConnectionEntity>? bankConnections,
    List<FinancialNotificationEntity>? financialNotifications,
    BankingNotificationPreferencesEntity? notificationPreferences,
    List<MerchantCategoryRuleEntity>? merchantRules,
    List<PaymentOrderEntity>? paymentOrders,
    PaymentOrderEntity? latestCreatedOrder,
    bool clearLatestCreatedOrder = false,
    IngestionOutcome? lastOutcome,
    String? infoMessage,
    bool clearInfoMessage = false,
    String? exportedJson,
    bool? accountDeleted,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return NotificationIngestionState(
      isLoading: isLoading ?? this.isLoading,
      isSubmittingOrder: isSubmittingOrder ?? this.isSubmittingOrder,
      isNativePermissionGranted:
          isNativePermissionGranted ?? this.isNativePermissionGranted,
      isPushPermissionGranted:
          isPushPermissionGranted ?? this.isPushPermissionGranted,
      consent: consent ?? this.consent,
      linkedBankAccounts: linkedBankAccounts ?? this.linkedBankAccounts,
      bankConnections: bankConnections ?? this.bankConnections,
      financialNotifications:
          financialNotifications ?? this.financialNotifications,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
      merchantRules: merchantRules ?? this.merchantRules,
      paymentOrders: paymentOrders ?? this.paymentOrders,
      latestCreatedOrder: clearLatestCreatedOrder
          ? null
          : (latestCreatedOrder ?? this.latestCreatedOrder),
      lastOutcome: lastOutcome ?? this.lastOutcome,
      infoMessage: clearInfoMessage ? null : (infoMessage ?? this.infoMessage),
      exportedJson: exportedJson ?? this.exportedJson,
      accountDeleted: accountDeleted ?? this.accountDeleted,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isSubmittingOrder,
    isNativePermissionGranted,
    isPushPermissionGranted,
    consent,
    linkedBankAccounts,
    bankConnections,
    financialNotifications,
    notificationPreferences,
    merchantRules,
    paymentOrders,
    latestCreatedOrder,
    lastOutcome,
    infoMessage,
    exportedJson,
    accountDeleted,
    failure,
  ];
}

class NotificationIngestionBloc
    extends Bloc<NotificationIngestionEvent, NotificationIngestionState> {
  final NotificationsRepository _repository;
  final FcmBankingMessagingService? _fcmService;
  StreamSubscription<Map<String, dynamic>>? _nativeSignalsSub;
  StreamSubscription<Result<List<LinkedBankAccountEntity>>>? _bankAccountsSub;
  StreamSubscription<Result<List<BankConnectionEntity>>>? _bankConnectionsSub;
  StreamSubscription<Result<List<FinancialNotificationEntity>>>?
  _financialNotifsSub;
  StreamSubscription<Result<BankingNotificationPreferencesEntity>>?
  _bankingPrefsSub;
  StreamSubscription<Result<List<MerchantCategoryRuleEntity>>>?
  _merchantRulesSub;
  StreamSubscription<Result<List<PaymentOrderEntity>>>? _ordersSub;

  NotificationIngestionBloc({
    required NotificationsRepository repository,
    FcmBankingMessagingService? fcmService,
  }) : _repository = repository,
       _fcmService = fcmService,
       super(const NotificationIngestionState()) {
    on<NotificationsCenterStarted>(_onStarted, transformer: restartable());
    on<NativePermissionStatusRefreshed>(
      _onNativePermRefreshed,
      transformer: droppable(),
    );
    on<OpenNativePermissionSettingsRequested>(
      _onOpenNativePermSettings,
      transformer: droppable(),
    );
    on<ConsentConfigUpdated>(_onConsentUpdated, transformer: sequential());
    on<BankNotificationSignalReceived>(
      _onSignalReceived,
      transformer: sequential(),
    );
    on<LinkedBankAccountSaved>(_onBankAccountSaved, transformer: sequential());
    on<LinkedBankAccountDeleted>(
      _onBankAccountDeleted,
      transformer: sequential(),
    );
    on<VerifiedSePayBankLinkSubmitted>(
      _onVerifiedSePayLinkSubmitted,
      transformer: sequential(),
    );
    on<BankConnectionDisconnected>(
      _onBankConnectionDisconnected,
      transformer: sequential(),
    );
    on<BankConnectionReconcileRequested>(
      _onBankConnectionReconciled,
      transformer: sequential(),
    );
    on<BankingPrivacyPreferencesUpdated>(
      _onBankingPrefsSubmitted,
      transformer: sequential(),
    );
    on<SendTestBankingNotificationRequested>(
      _onSendTestNotification,
      transformer: droppable(),
    );
    on<SaveMerchantRuleSubmitted>(
      _onSaveMerchantRule,
      transformer: sequential(),
    );
    on<NotificationsSessionClearedOnLogout>(
      _onSessionClearedOnLogout,
      transformer: sequential(),
    );
    on<PaymentOrderCreated>(_onPaymentOrderCreated, transformer: sequential());
    on<PaymentOrderStatusMarked>(
      _onPaymentOrderStatusMarked,
      transformer: sequential(),
    );
    on<SoundboxTestRequested>(_onSoundboxTest, transformer: droppable());
    on<_LinkedBankAccountsUpdated>(_onBankAccountsUpdated);
    on<_BankConnectionsUpdated>(
      (e, emit) => emit(state.copyWith(bankConnections: e.connections)),
    );
    on<_FinancialNotificationsUpdated>(
      (e, emit) =>
          emit(state.copyWith(financialNotifications: e.notifications)),
    );
    on<_BankingPrefsUpdated>(
      (e, emit) => emit(state.copyWith(notificationPreferences: e.prefs)),
    );
    on<_MerchantRulesUpdated>(
      (e, emit) => emit(state.copyWith(merchantRules: e.rules)),
    );
    on<_PaymentOrdersUpdated>(_onOrdersUpdated);
    on<CsvStatementImportSubmitted>(_onCsvImported, transformer: sequential());
    on<PersonalDataExportRequested>(
      _onExportRequested,
      transformer: droppable(),
    );
    on<AccountDeletionConfirmed>(
      _onAccountDeletionConfirmed,
      transformer: sequential(),
    );
  }

  Future<void> _cancelAllUserSubscriptions() async {
    await _nativeSignalsSub?.cancel();
    await _bankAccountsSub?.cancel();
    await _bankConnectionsSub?.cancel();
    await _financialNotifsSub?.cancel();
    await _bankingPrefsSub?.cancel();
    await _merchantRulesSub?.cancel();
    await _ordersSub?.cancel();
    _nativeSignalsSub = null;
    _bankAccountsSub = null;
    _bankConnectionsSub = null;
    _financialNotifsSub = null;
    _bankingPrefsSub = null;
    _merchantRulesSub = null;
    _ordersSub = null;
  }

  Future<void> _onStarted(
    NotificationsCenterStarted event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));

    // Phase 4 Migration: purge/migrate any legacy `consents/sepay_api` plaintext token safely!
    await _repository.migrateLegacySePayConsentIfPresent(event.userId);

    final permGranted = await _repository.isNativeNotificationAccessGranted();
    final pushGranted =
        await (_fcmService?.bindAuthenticatedUser(event.userId) ??
            Future.value(false));
    emit(
      state.copyWith(
        isNativePermissionGranted: permGranted,
        isPushPermissionGranted: pushGranted,
      ),
    );

    await _cancelAllUserSubscriptions();

    _bankAccountsSub = _repository.watchLinkedBankAccounts(event.userId).listen(
      (res) {
        res.fold((_) {}, (list) => add(_LinkedBankAccountsUpdated(list)));
      },
    );

    _bankConnectionsSub = _repository.watchBankConnections(event.userId).listen(
      (res) {
        res.fold((_) {}, (list) => add(_BankConnectionsUpdated(list)));
      },
    );

    _financialNotifsSub = _repository
        .watchFinancialNotifications(event.userId)
        .listen((res) {
          res.fold((_) {}, (list) => add(_FinancialNotificationsUpdated(list)));
        });

    _bankingPrefsSub = _repository
        .watchBankingNotificationPreferences(event.userId)
        .listen((res) {
          res.fold((_) {}, (prefs) => add(_BankingPrefsUpdated(prefs)));
        });

    _merchantRulesSub = _repository
        .watchMerchantCategoryRules(event.userId)
        .listen((res) {
          res.fold((_) {}, (rules) => add(_MerchantRulesUpdated(rules)));
        });

    _ordersSub = _repository.watchPaymentOrders(event.userId).listen((res) {
      res.fold((_) {}, (list) => add(_PaymentOrdersUpdated(list)));
    });

    _nativeSignalsSub = _repository.watchLiveAndroidBankSignals().listen((
      payload,
    ) {
      final pkg = (payload['packageName'] ?? '').toString().trim();
      final title = (payload['title'] ?? '').toString();
      final body = (payload['body'] ?? '').toString();
      if (pkg.isEmpty || (title.isEmpty && body.isEmpty)) return;
      final epochMs = (payload['postedAtEpochMs'] as num?)?.toInt();
      final notifKey = payload['notificationKey']?.toString();
      add(
        BankNotificationSignalReceived(
          userId: event.userId,
          defaultWalletId: event.defaultWalletId,
          packageName: pkg,
          title: title,
          body: body,
          postedAt: epochMs != null
              ? DateTime.fromMillisecondsSinceEpoch(epochMs)
              : null,
          notificationId: notifKey,
        ),
      );
    });

    // Drain any notifications captured by Android OS while LifeOS was closed in background!
    final queued = await _repository.drainQueuedAndroidBankSignals();
    for (final payload in queued) {
      final pkg = (payload['packageName'] ?? '').toString().trim();
      final title = (payload['title'] ?? '').toString();
      final body = (payload['body'] ?? '').toString();
      if (pkg.isEmpty || (title.isEmpty && body.isEmpty)) continue;
      final epochMs = (payload['postedAtEpochMs'] as num?)?.toInt();
      final notifKey = payload['notificationKey']?.toString();
      add(
        BankNotificationSignalReceived(
          userId: event.userId,
          defaultWalletId: event.defaultWalletId,
          packageName: pkg,
          title: title,
          body: body,
          postedAt: epochMs != null
              ? DateTime.fromMillisecondsSinceEpoch(epochMs)
              : null,
          notificationId: notifKey,
        ),
      );
    }

    await emit.forEach<Result<SourceConsentEntity>>(
      _repository.watchAndroidNotificationConsent(event.userId),
      onData: (res) => res.fold(
        (f) => state.copyWith(isLoading: false, failure: f),
        (c) => state.copyWith(isLoading: false, consent: c, clearFailure: true),
      ),
    );
  }

  void _onBankAccountsUpdated(
    _LinkedBankAccountsUpdated event,
    Emitter<NotificationIngestionState> emit,
  ) {
    emit(state.copyWith(linkedBankAccounts: event.accounts));
  }

  void _onOrdersUpdated(
    _PaymentOrdersUpdated event,
    Emitter<NotificationIngestionState> emit,
  ) {
    emit(state.copyWith(paymentOrders: event.orders));
  }

  Future<void> _onNativePermRefreshed(
    NativePermissionStatusRefreshed event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final granted = await _repository.isNativeNotificationAccessGranted();
    emit(state.copyWith(isNativePermissionGranted: granted));
  }

  Future<void> _onOpenNativePermSettings(
    OpenNativePermissionSettingsRequested event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    await _repository.openNativeNotificationAccessSettings();
  }

  Future<void> _onConsentUpdated(
    ConsentConfigUpdated event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.updateAndroidNotificationConsent(
      userId: event.userId,
      enabled: event.enabled,
      allowedPackages: event.allowedPackages,
      autoConfirmSignals: event.autoConfirmSignals,
      voiceSoundboxEnabled: event.voiceSoundboxEnabled,
      syncObservedBalance: event.syncObservedBalance,
    );
    res.fold((f) => emit(state.copyWith(failure: f)), (_) {});
  }

  Future<void> _onSignalReceived(
    BankNotificationSignalReceived event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.ingestAndroidNotification(
      userId: event.userId,
      defaultWalletId: event.defaultWalletId,
      packageName: event.packageName,
      title: event.title,
      body: event.body,
      postedAt: event.postedAt,
      notificationId: event.notificationId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (outcome) => emit(
        state.copyWith(
          lastOutcome: outcome,
          infoMessage: outcome.kind == IngestionOutcomeKind.autoReconciledOrder
              ? outcome.message
              : state.infoMessage,
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onBankAccountSaved(
    LinkedBankAccountSaved event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.saveLinkedBankAccount(
      userId: event.userId,
      walletId: event.walletId,
      bankBin: event.bankBin,
      bankCode: event.bankCode,
      bankName: event.bankName,
      accountNumber: event.accountNumber,
      accountHolderName: event.accountHolderName,
      isDefault: event.isDefault,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (acc) => emit(
        state.copyWith(
          infoMessage:
              'Đã lưu tài khoản nhận tiền ${acc.bankName} (${acc.maskedAccount}).',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onBankAccountDeleted(
    LinkedBankAccountDeleted event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.deleteLinkedBankAccount(
      userId: event.userId,
      accountId: event.accountId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          infoMessage: 'Đã gỡ tài khoản ngân hàng.',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onPaymentOrderCreated(
    PaymentOrderCreated event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    emit(state.copyWith(isSubmittingOrder: true, clearFailure: true));
    final res = await _repository.createPaymentOrder(
      userId: event.userId,
      walletId: event.walletId,
      bankBin: event.bankBin,
      bankCode: event.bankCode,
      bankName: event.bankName,
      accountNumber: event.accountNumber,
      accountHolderName: event.accountHolderName,
      amountMinor: event.amountMinor,
      description: event.description,
    );
    res.fold(
      (f) => emit(state.copyWith(isSubmittingOrder: false, failure: f)),
      (order) => emit(
        state.copyWith(
          isSubmittingOrder: false,
          latestCreatedOrder: order,
          infoMessage: 'Đã tạo mã QR thu tiền ${order.paymentCode}!',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onPaymentOrderStatusMarked(
    PaymentOrderStatusMarked event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.markPaymentOrderStatus(
      userId: event.userId,
      orderId: event.orderId,
      status: event.status,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          infoMessage: 'Đã cập nhật trạng thái lệnh thu tiền.',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onSoundboxTest(
    SoundboxTestRequested event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    await _repository.speakSoundboxTest(event.message);
    emit(
      state.copyWith(
        infoMessage: 'Đang phát thử giọng đọc loa báo tiền về.',
        clearFailure: true,
      ),
    );
  }

  Future<void> _onCsvImported(
    CsvStatementImportSubmitted event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.importCsvStatement(
      userId: event.userId,
      walletId: event.walletId,
      csvContent: event.csvContent,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (count) => emit(
        state.copyWith(
          infoMessage: 'Đã nhập $count giao dịch từ sao kê CSV.',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onExportRequested(
    PersonalDataExportRequested event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.exportPersonalDataJson(event.userId);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (jsonStr) => emit(
        state.copyWith(
          exportedJson: jsonStr,
          infoMessage: 'Đã tạo bản sao lưu dữ liệu cá nhân.',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onVerifiedSePayLinkSubmitted(
    VerifiedSePayBankLinkSubmitted event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    final res = await _repository.linkVerifiedSePayConnection(
      userId: event.userId,
      bankCode: event.bankCode,
      accountNumber: event.accountNumber,
      subAccount: event.subAccount,
      linkedWalletId: event.linkedWalletId,
      sepayApiToken: event.sepayApiToken,
    );
    res.fold(
      (f) => emit(state.copyWith(isLoading: false, failure: f)),
      (conn) => emit(
        state.copyWith(
          isLoading: false,
          infoMessage:
              'Đã xác minh & kết nối ${conn.bankName} (${conn.accountMasked}) qua SePay!',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onBankConnectionDisconnected(
    BankConnectionDisconnected event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.disconnectBankConnection(
      userId: event.userId,
      connectionId: event.connectionId,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          infoMessage:
              'Đã ngắt kết nối tài khoản ngân hàng & dừng nhận sự kiện.',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onBankConnectionReconciled(
    BankConnectionReconcileRequested event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    final res = await _repository.reconcileBankConnection(
      userId: event.userId,
      connectionId: event.connectionId,
      sepayApiToken: event.sepayApiToken,
    );
    res.fold(
      (f) => emit(state.copyWith(isLoading: false, failure: f)),
      (count) => emit(
        state.copyWith(
          isLoading: false,
          infoMessage:
              'Đã đối soát bù từ máy chủ SePay ($count giao dịch mới).',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onBankingPrefsSubmitted(
    BankingPrivacyPreferencesUpdated event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.updateBankingNotificationPreferences(
      event.preferences,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          notificationPreferences: event.preferences,
          infoMessage: 'Đã lưu tùy chọn thông báo & quyền riêng tư.',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onSendTestNotification(
    SendTestBankingNotificationRequested event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.sendTestBankingNotification(event.userId);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          infoMessage:
              '🧪 Đã gửi thông báo kiểm thử (không tạo giao dịch tài chính thật trong Sổ cái).',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onSaveMerchantRule(
    SaveMerchantRuleSubmitted event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.saveMerchantCategoryRule(
      userId: event.userId,
      keyword: event.keyword,
      categoryName: event.categoryName,
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(
        state.copyWith(
          infoMessage:
              'Đã lưu quy tắc phân loại tự động "${event.keyword}" → ${event.categoryName}.',
          clearFailure: true,
        ),
      ),
    );
  }

  Future<void> _onSessionClearedOnLogout(
    NotificationsSessionClearedOnLogout event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    await _cancelAllUserSubscriptions();
    await _fcmService?.unbindAndDeactivateOnLogout();
    emit(const NotificationIngestionState());
  }

  Future<void> _onAccountDeletionConfirmed(
    AccountDeletionConfirmed event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    await _cancelAllUserSubscriptions();
    await _fcmService?.unbindAndDeactivateOnLogout();
    final res = await _repository.deleteAccountAndPersonalData(event.userId);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(accountDeleted: true, clearFailure: true)),
    );
  }

  @override
  Future<void> close() async {
    await _cancelAllUserSubscriptions();
    await _fcmService?.unbindAndDeactivateOnLogout();
    return super.close();
  }
}
