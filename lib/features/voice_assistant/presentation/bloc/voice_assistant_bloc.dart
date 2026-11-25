import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';

import '../../data/datasources/local_asr_model_manager.dart';
import '../../domain/repositories/local_asr_model_repository.dart';
import '../../domain/services/voice_session_coordinator.dart';
import 'voice_assistant_event.dart';
import 'voice_assistant_state.dart';

/// Pure event-driven BLoC delegating session orchestration to [VoiceSessionCoordinator]
/// and offline model operations to [LocalAsrModelRepository].
class VoiceAssistantBloc
    extends Bloc<VoiceAssistantEvent, VoiceAssistantState> {
  final VoiceSessionCoordinator _coordinator;
  final LocalAsrModelRepository _modelRepository;
  final bool _disposeCoordinatorOnClose;
  StreamSubscription<VoiceSessionStateSnapshot>? _snapshotSubscription;

  VoiceAssistantBloc({
    required VoiceSessionCoordinator coordinator,
    required LocalAsrModelRepository modelRepository,
    bool disposeCoordinatorOnClose = false,
  }) : _coordinator = coordinator,
       _modelRepository = modelRepository,
       _disposeCoordinatorOnClose = disposeCoordinatorOnClose,
       super(VoiceAssistantState.fromCoordinator(coordinator)) {
    _snapshotSubscription = _coordinator.snapshots.listen((snapshot) {
      if (!isClosed) {
        add(VoiceCoordinatorSnapshotUpdated(snapshot));
      }
    });

    on<VoiceAssistantInitialized>(_onInitialized, transformer: droppable());
    on<VoiceStartRequested>(_onStartRequested);
    on<VoiceStopRequested>(_onStopRequested);
    on<VoiceCancelRequested>(_onCancelRequested);
    on<VoiceRetryRequested>(_onRetryRequested);
    on<VoiceTranscriptEdited>(_onTranscriptEdited);
    on<VoicePreferenceChanged>(_onPreferenceChanged);
    on<VoiceEndpointModeChanged>(_onEndpointModeChanged);
    on<VoiceOnlineConsentChanged>(_onOnlineConsentChanged);
    on<VoicePermissionCallbackReceived>(_onPermissionCallbackReceived);
    on<VoiceAppLifecycleChanged>(_onAppLifecycleChanged);
    on<VoiceAccountResetRequested>(_onAccountResetRequested);
    on<VoiceSubmitStarted>(_onSubmitStarted);
    on<VoiceSubmitCompleted>(_onSubmitCompleted);
    on<VoiceSubmitReverted>(_onSubmitReverted);
    on<VoiceResetToIdleRequested>(_onResetToIdleRequested);
    on<VoiceCapabilitiesResetRequested>(_onCapabilitiesResetRequested);
    on<VoiceDiagnosticsRefreshed>(_onDiagnosticsRefreshed);
    on<VoiceModelsRefreshRequested>(_onModelsRefreshRequested);
    on<VoiceModelDownloadRequested>(
      _onModelDownloadRequested,
      transformer: droppable(),
    );
    on<VoiceModelDeleteRequested>(_onModelDeleteRequested);
    on<VoiceModelRollbackRequested>(_onModelRollbackRequested);
    on<VoiceToastCleared>(_onToastCleared);
    on<VoiceCoordinatorSnapshotUpdated>(_onCoordinatorSnapshotUpdated);
    on<VoiceModelProgressUpdated>(_onModelProgressUpdated);
  }

  Future<void> _onInitialized(
    VoiceAssistantInitialized event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    await _coordinator.initializeDiagnostics();
    final models = await _modelRepository.listModels();
    emit(
      state.copyWith(snapshot: _coordinator.currentSnapshot, models: models),
    );
  }

  Future<void> _onStartRequested(
    VoiceStartRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    final result = await _coordinator.startSession(
      ownerId: event.ownerId,
      entryPoint: event.entryPoint,
      preference: event.preference,
      clearTranscript: event.clearTranscript,
      allowOnlineConsent: event.allowOnlineConsent,
      locale: event.locale,
    );
    emit(
      state.copyWith(
        snapshot: _coordinator.currentSnapshot,
        toastMessageVi:
            !result.accepted && result.rejectionReason == 'session_finalizing'
            ? 'Đang hoàn tất câu nói trước, vui lòng đợi trong giây lát.'
            : null,
        isToastError: false,
      ),
    );
  }

  Future<void> _onStopRequested(
    VoiceStopRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    final targetSessionId =
        event.sessionId ?? _coordinator.currentSession.sessionId;
    await _coordinator.stopSession(sessionId: targetSessionId);
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  Future<void> _onCancelRequested(
    VoiceCancelRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    final targetSessionId =
        event.sessionId ?? _coordinator.currentSession.sessionId;
    await _coordinator.cancelSession(
      sessionId: targetSessionId,
      reason: event.reason,
    );
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  Future<void> _onRetryRequested(
    VoiceRetryRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    await _coordinator.retrySession(
      ownerId: event.ownerId,
      entryPoint: event.entryPoint,
      preference: event.preference,
      clearTranscript: event.clearTranscript,
      allowOnlineConsent: event.allowOnlineConsent,
      locale: event.locale,
    );
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  void _onTranscriptEdited(
    VoiceTranscriptEdited event,
    Emitter<VoiceAssistantState> emit,
  ) {
    _coordinator.onUserEditTranscript(event.text);
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  void _onPreferenceChanged(
    VoicePreferenceChanged event,
    Emitter<VoiceAssistantState> emit,
  ) {
    _coordinator.setPreference(event.preference);
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  void _onEndpointModeChanged(
    VoiceEndpointModeChanged event,
    Emitter<VoiceAssistantState> emit,
  ) {
    _coordinator.setEndpointMode(event.mode);
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  void _onOnlineConsentChanged(
    VoiceOnlineConsentChanged event,
    Emitter<VoiceAssistantState> emit,
  ) {
    _coordinator.setAllowOnlineConsent(event.allowed);
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  Future<void> _onPermissionCallbackReceived(
    VoicePermissionCallbackReceived event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    await _coordinator.onPermissionResult(
      sessionId: event.sessionId,
      attemptId: event.attemptId,
      granted: event.granted,
      permanentlyDenied: event.permanentlyDenied,
      isForegroundFocused: event.isForegroundFocused,
    );
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  Future<void> _onAppLifecycleChanged(
    VoiceAppLifecycleChanged event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    await _coordinator.onAppLifecycleChanged(event.isBackgrounded);
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  Future<void> _onAccountResetRequested(
    VoiceAccountResetRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    await _coordinator.onUserAccountChangedOrSignedOut();
    emit(
      state.copyWith(snapshot: _coordinator.currentSnapshot, clearToast: true),
    );
  }

  void _onSubmitStarted(
    VoiceSubmitStarted event,
    Emitter<VoiceAssistantState> emit,
  ) {
    _coordinator.beginSubmitting();
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  void _onSubmitCompleted(
    VoiceSubmitCompleted event,
    Emitter<VoiceAssistantState> emit,
  ) {
    _coordinator.markCompleted();
    emit(state.copyWith(snapshot: _coordinator.currentSnapshot));
  }

  void _onSubmitReverted(
    VoiceSubmitReverted event,
    Emitter<VoiceAssistantState> emit,
  ) {
    _coordinator.revertSubmitToReview(errorMessageVi: event.errorMessageVi);
    emit(
      state.copyWith(
        snapshot: _coordinator.currentSnapshot,
        toastMessageVi: event.errorMessageVi,
        isToastError: event.errorMessageVi != null,
      ),
    );
  }

  Future<void> _onResetToIdleRequested(
    VoiceResetToIdleRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    await _coordinator.resetToIdle(clearTranscript: event.clearTranscript);
    emit(
      state.copyWith(snapshot: _coordinator.currentSnapshot, clearToast: true),
    );
  }

  Future<void> _onCapabilitiesResetRequested(
    VoiceCapabilitiesResetRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    await _coordinator.resetCapabilities();
    emit(
      state.copyWith(
        snapshot: _coordinator.currentSnapshot,
        toastMessageVi: 'Đã làm mới bộ nhớ thiết bị nhận diện giọng nói.',
        isToastError: false,
      ),
    );
  }

  Future<void> _onDiagnosticsRefreshed(
    VoiceDiagnosticsRefreshed event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    await _coordinator.refreshDiagnostics();
    final models = await _modelRepository.listModels();
    emit(
      state.copyWith(snapshot: _coordinator.currentSnapshot, models: models),
    );
  }

  Future<void> _onModelsRefreshRequested(
    VoiceModelsRefreshRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    final models = await _modelRepository.listModels();
    emit(state.copyWith(models: models));
  }

  Future<void> _onModelDownloadRequested(
    VoiceModelDownloadRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    emit(state.copyWith(isModelOperationBusy: true, clearToast: true));
    try {
      await _modelRepository.downloadModel(
        event.spec,
        enforceCommercialLicense: event.enforceCommercialLicense,
        onProgress: (progress) {
          if (!isClosed) {
            add(VoiceModelProgressUpdated(progress));
          }
        },
      );
      final models = await _modelRepository.listModels();
      await _coordinator.refreshDiagnostics();
      emit(
        state.copyWith(
          snapshot: _coordinator.currentSnapshot,
          models: models,
          clearDownloadProgress: true,
          isModelOperationBusy: false,
          toastMessageVi:
              'Đã cài đặt mô hình Offline ${event.spec.displayNameVi}.',
          isToastError: false,
        ),
      );
    } on LocalAsrModelException catch (e) {
      final models = await _modelRepository.listModels();
      emit(
        state.copyWith(
          models: models,
          clearDownloadProgress: true,
          isModelOperationBusy: false,
          toastMessageVi: e.messageVi,
          isToastError: true,
        ),
      );
    } catch (_) {
      final models = await _modelRepository.listModels();
      emit(
        state.copyWith(
          models: models,
          clearDownloadProgress: true,
          isModelOperationBusy: false,
          toastMessageVi: 'Không thể tải gói mô hình Offline lúc này.',
          isToastError: true,
        ),
      );
    }
  }

  Future<void> _onModelDeleteRequested(
    VoiceModelDeleteRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    emit(state.copyWith(isModelOperationBusy: true, clearToast: true));
    await _modelRepository.deleteModel(event.modelId);
    final models = await _modelRepository.listModels();
    await _coordinator.refreshDiagnostics();
    emit(
      state.copyWith(
        snapshot: _coordinator.currentSnapshot,
        models: models,
        isModelOperationBusy: false,
        toastMessageVi: 'Đã gỡ gói mô hình Offline.',
        isToastError: false,
      ),
    );
  }

  Future<void> _onModelRollbackRequested(
    VoiceModelRollbackRequested event,
    Emitter<VoiceAssistantState> emit,
  ) async {
    emit(state.copyWith(isModelOperationBusy: true, clearToast: true));
    final ok = await _modelRepository.rollbackModel(event.modelId);
    final models = await _modelRepository.listModels();
    await _coordinator.refreshDiagnostics();
    emit(
      state.copyWith(
        snapshot: _coordinator.currentSnapshot,
        models: models,
        isModelOperationBusy: false,
        toastMessageVi: ok
            ? 'Đã khôi phục phiên bản mô hình trước đó.'
            : 'Không có bản sao lưu mô hình hợp lệ để khôi phục.',
        isToastError: !ok,
      ),
    );
  }

  void _onToastCleared(
    VoiceToastCleared event,
    Emitter<VoiceAssistantState> emit,
  ) {
    emit(state.copyWith(clearToast: true));
  }

  void _onCoordinatorSnapshotUpdated(
    VoiceCoordinatorSnapshotUpdated event,
    Emitter<VoiceAssistantState> emit,
  ) {
    emit(state.copyWith(snapshot: event.snapshot));
  }

  void _onModelProgressUpdated(
    VoiceModelProgressUpdated event,
    Emitter<VoiceAssistantState> emit,
  ) {
    emit(state.copyWith(activeDownloadProgress: event.progress));
  }

  @override
  Future<void> close() async {
    await _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    if (_disposeCoordinatorOnClose) {
      await _coordinator.dispose();
    }
    return super.close();
  }
}
