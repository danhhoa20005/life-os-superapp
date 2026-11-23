import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
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

final class OpenNativePermissionSettingsRequested extends NotificationIngestionEvent {
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
  final SourceConsentEntity? consent;
  final List<LinkedBankAccountEntity> linkedBankAccounts;
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
    this.consent,
    this.linkedBankAccounts = const <LinkedBankAccountEntity>[],
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
    SourceConsentEntity? consent,
    List<LinkedBankAccountEntity>? linkedBankAccounts,
    List<PaymentOrderEntity>? paymentOrders,
    PaymentOrderEntity? latestCreatedOrder,
    bool clearLatestCreatedOrder = false,
    IngestionOutcome? lastOutcome,
    String? infoMessage,
    String? exportedJson,
    bool? accountDeleted,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return NotificationIngestionState(
      isLoading: isLoading ?? this.isLoading,
      isSubmittingOrder: isSubmittingOrder ?? this.isSubmittingOrder,
      isNativePermissionGranted: isNativePermissionGranted ?? this.isNativePermissionGranted,
      consent: consent ?? this.consent,
      linkedBankAccounts: linkedBankAccounts ?? this.linkedBankAccounts,
      paymentOrders: paymentOrders ?? this.paymentOrders,
      latestCreatedOrder: clearLatestCreatedOrder
          ? null
          : (latestCreatedOrder ?? this.latestCreatedOrder),
      lastOutcome: lastOutcome ?? this.lastOutcome,
      infoMessage: infoMessage ?? this.infoMessage,
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
        consent,
        linkedBankAccounts,
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
  StreamSubscription<Map<String, dynamic>>? _nativeSignalsSub;
  StreamSubscription<Result<List<LinkedBankAccountEntity>>>? _bankAccountsSub;
  StreamSubscription<Result<List<PaymentOrderEntity>>>? _ordersSub;

  NotificationIngestionBloc({required NotificationsRepository repository})
      : _repository = repository,
        super(const NotificationIngestionState()) {
    on<NotificationsCenterStarted>(_onStarted, transformer: restartable());
    on<NativePermissionStatusRefreshed>(_onNativePermRefreshed, transformer: droppable());
    on<OpenNativePermissionSettingsRequested>(
      _onOpenNativePermSettings,
      transformer: droppable(),
    );
    on<ConsentConfigUpdated>(_onConsentUpdated, transformer: sequential());
    on<BankNotificationSignalReceived>(_onSignalReceived, transformer: sequential());
    on<LinkedBankAccountSaved>(_onBankAccountSaved, transformer: sequential());
    on<LinkedBankAccountDeleted>(_onBankAccountDeleted, transformer: sequential());
    on<PaymentOrderCreated>(_onPaymentOrderCreated, transformer: sequential());
    on<PaymentOrderStatusMarked>(_onPaymentOrderStatusMarked, transformer: sequential());
    on<SoundboxTestRequested>(_onSoundboxTest, transformer: droppable());
    on<_LinkedBankAccountsUpdated>(_onBankAccountsUpdated);
    on<_PaymentOrdersUpdated>(_onOrdersUpdated);
    on<CsvStatementImportSubmitted>(_onCsvImported, transformer: sequential());
    on<PersonalDataExportRequested>(_onExportRequested, transformer: droppable());
    on<AccountDeletionConfirmed>(_onAccountDeletionConfirmed, transformer: sequential());
  }

  Future<void> _onStarted(
    NotificationsCenterStarted event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    final permGranted = await _repository.isNativeNotificationAccessGranted();
    emit(state.copyWith(isNativePermissionGranted: permGranted));

    await _bankAccountsSub?.cancel();
    _bankAccountsSub = _repository.watchLinkedBankAccounts(event.userId).listen((res) {
      res.fold((_) {}, (list) => add(_LinkedBankAccountsUpdated(list)));
    });

    await _ordersSub?.cancel();
    _ordersSub = _repository.watchPaymentOrders(event.userId).listen((res) {
      res.fold((_) {}, (list) => add(_PaymentOrdersUpdated(list)));
    });

    await _nativeSignalsSub?.cancel();
    _nativeSignalsSub = _repository.watchLiveAndroidBankSignals().listen((payload) {
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
          postedAt: epochMs != null ? DateTime.fromMillisecondsSinceEpoch(epochMs) : null,
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
          postedAt: epochMs != null ? DateTime.fromMillisecondsSinceEpoch(epochMs) : null,
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
          infoMessage: 'Đã lưu tài khoản nhận tiền ${acc.bankName} (${acc.maskedAccount}).',
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
      (_) => emit(state.copyWith(infoMessage: 'Đã gỡ tài khoản ngân hàng.', clearFailure: true)),
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

  Future<void> _onAccountDeletionConfirmed(
    AccountDeletionConfirmed event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.deleteAccountAndPersonalData(event.userId);
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (_) => emit(state.copyWith(accountDeleted: true, clearFailure: true)),
    );
  }

  @override
  Future<void> close() async {
    await _nativeSignalsSub?.cancel();
    await _bankAccountsSub?.cancel();
    await _ordersSub?.cancel();
    return super.close();
  }
}
