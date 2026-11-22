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

  const ConsentConfigUpdated({
    required this.userId,
    required this.enabled,
    required this.allowedPackages,
    this.autoConfirmSignals,
  });

  @override
  List<Object?> get props => [userId, enabled, allowedPackages, autoConfirmSignals];
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

final class SePayLiveSyncSubmitted extends NotificationIngestionEvent {
  final String userId;
  final String walletId;
  final String? apiTokenOverride;

  const SePayLiveSyncSubmitted({
    required this.userId,
    required this.walletId,
    this.apiTokenOverride,
  });

  @override
  List<Object?> get props => [userId, walletId, apiTokenOverride];
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

final class NotificationIngestionState extends Equatable {
  final bool isLoading;
  final bool isSyncingSePay;
  final bool isNativePermissionGranted;
  final String? savedSePayMaskedToken;
  final SourceConsentEntity? consent;
  final IngestionOutcome? lastOutcome;
  final String? infoMessage;
  final String? exportedJson;
  final bool accountDeleted;
  final Failure? failure;

  const NotificationIngestionState({
    this.isLoading = false,
    this.isSyncingSePay = false,
    this.isNativePermissionGranted = false,
    this.savedSePayMaskedToken,
    this.consent,
    this.lastOutcome,
    this.infoMessage,
    this.exportedJson,
    this.accountDeleted = false,
    this.failure,
  });

  NotificationIngestionState copyWith({
    bool? isLoading,
    bool? isSyncingSePay,
    bool? isNativePermissionGranted,
    String? savedSePayMaskedToken,
    SourceConsentEntity? consent,
    IngestionOutcome? lastOutcome,
    String? infoMessage,
    String? exportedJson,
    bool? accountDeleted,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return NotificationIngestionState(
      isLoading: isLoading ?? this.isLoading,
      isSyncingSePay: isSyncingSePay ?? this.isSyncingSePay,
      isNativePermissionGranted: isNativePermissionGranted ?? this.isNativePermissionGranted,
      savedSePayMaskedToken: savedSePayMaskedToken ?? this.savedSePayMaskedToken,
      consent: consent ?? this.consent,
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
        isSyncingSePay,
        isNativePermissionGranted,
        savedSePayMaskedToken,
        consent,
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
    on<SePayLiveSyncSubmitted>(_onSePaySynced, transformer: droppable());
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
    final maskedTokenRes = await _repository.getSavedSePayMaskedToken(event.userId);
    final maskedToken = maskedTokenRes.fold((_) => null, (v) => v);
    emit(
      state.copyWith(
        isNativePermissionGranted: permGranted,
        savedSePayMaskedToken: maskedToken,
      ),
    );

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

    // Drain any notifications captured by Android OS while Life OS was closed in background!
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

    // Zero-touch automatic SePay background reconciliation when user has linked a token
    if (maskedToken != null) {
      add(
        SePayLiveSyncSubmitted(
          userId: event.userId,
          walletId: event.defaultWalletId,
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
      (outcome) => emit(state.copyWith(lastOutcome: outcome, clearFailure: true)),
    );
  }

  Future<void> _onSePaySynced(
    SePayLiveSyncSubmitted event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    emit(state.copyWith(isSyncingSePay: true, clearFailure: true));
    final res = await _repository.syncSePayTransactions(
      userId: event.userId,
      walletId: event.walletId,
      apiTokenOverride: event.apiTokenOverride,
    );
    final refreshedMaskRes = await _repository.getSavedSePayMaskedToken(event.userId);
    final refreshedMask = refreshedMaskRes.fold((_) => state.savedSePayMaskedToken, (v) => v);
    res.fold(
      (f) => emit(
        state.copyWith(
          isSyncingSePay: false,
          savedSePayMaskedToken: refreshedMask,
          failure: f,
        ),
      ),
      (count) => emit(
        state.copyWith(
          isSyncingSePay: false,
          savedSePayMaskedToken: refreshedMask,
          infoMessage: count > 0
              ? 'Đã đồng bộ xác thực $count giao dịch mới trực tiếp từ SePay!'
              : 'Sổ cái đã đồng bộ mới nhất với SePay (0 giao dịch mới).',
          clearFailure: true,
        ),
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
          infoMessage:
              'Đã nhập thành công $count giao dịch mới từ sao kê CSV (bỏ qua dòng trùng lặp).',
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
      (jsonStr) => emit(state.copyWith(exportedJson: jsonStr, clearFailure: true)),
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
    return super.close();
  }
}
