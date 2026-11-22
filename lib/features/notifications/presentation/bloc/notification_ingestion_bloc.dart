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
  const NotificationsCenterStarted(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class ConsentConfigUpdated extends NotificationIngestionEvent {
  final String userId;
  final bool enabled;
  final List<String> allowedPackages;

  const ConsentConfigUpdated({
    required this.userId,
    required this.enabled,
    required this.allowedPackages,
  });

  @override
  List<Object?> get props => [userId, enabled, allowedPackages];
}

final class BankNotificationSignalReceived extends NotificationIngestionEvent {
  final String userId;
  final String defaultWalletId;
  final String packageName;
  final String title;
  final String body;

  const BankNotificationSignalReceived({
    required this.userId,
    required this.defaultWalletId,
    required this.packageName,
    required this.title,
    required this.body,
  });

  @override
  List<Object?> get props => [userId, defaultWalletId, packageName, title, body];
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
  final SourceConsentEntity? consent;
  final IngestionOutcome? lastOutcome;
  final String? infoMessage;
  final String? exportedJson;
  final bool accountDeleted;
  final Failure? failure;

  const NotificationIngestionState({
    this.isLoading = false,
    this.consent,
    this.lastOutcome,
    this.infoMessage,
    this.exportedJson,
    this.accountDeleted = false,
    this.failure,
  });

  NotificationIngestionState copyWith({
    bool? isLoading,
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

  NotificationIngestionBloc({required NotificationsRepository repository})
      : _repository = repository,
        super(const NotificationIngestionState()) {
    on<NotificationsCenterStarted>(_onStarted, transformer: restartable());
    on<ConsentConfigUpdated>(_onConsentUpdated, transformer: sequential());
    on<BankNotificationSignalReceived>(_onSignalReceived, transformer: sequential());
    on<CsvStatementImportSubmitted>(_onCsvImported, transformer: sequential());
    on<PersonalDataExportRequested>(_onExportRequested, transformer: droppable());
    on<AccountDeletionConfirmed>(_onAccountDeletionConfirmed, transformer: sequential());
  }

  Future<void> _onStarted(
    NotificationsCenterStarted event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    await emit.forEach<Result<SourceConsentEntity>>(
      _repository.watchAndroidNotificationConsent(event.userId),
      onData: (res) => res.fold(
        (f) => state.copyWith(isLoading: false, failure: f),
        (c) => state.copyWith(isLoading: false, consent: c, clearFailure: true),
      ),
    );
  }

  Future<void> _onConsentUpdated(
    ConsentConfigUpdated event,
    Emitter<NotificationIngestionState> emit,
  ) async {
    final res = await _repository.updateAndroidNotificationConsent(
      userId: event.userId,
      enabled: event.enabled,
      allowedPackages: event.allowedPackages,
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
    );
    res.fold(
      (f) => emit(state.copyWith(failure: f)),
      (outcome) => emit(state.copyWith(lastOutcome: outcome, clearFailure: true)),
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
}
