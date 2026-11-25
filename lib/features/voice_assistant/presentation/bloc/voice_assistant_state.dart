import 'package:equatable/equatable.dart';

import '../../domain/entities/voice_engine_capability.dart';
import '../../domain/entities/voice_model_package.dart';
import '../../domain/entities/voice_session.dart';
import '../../domain/entities/voice_transcript.dart';
import '../../domain/services/endpoint_policy.dart';
import '../../domain/services/voice_activity_detector.dart';
import '../../domain/services/voice_diagnostics.dart';
import '../../domain/services/voice_session_coordinator.dart';

final class VoiceAssistantState extends Equatable {
  final VoiceSessionStateSnapshot snapshot;
  final List<LocalAsrModelInstallState> models;
  final LocalAsrDownloadProgress? activeDownloadProgress;
  final bool isModelOperationBusy;
  final String? toastMessageVi;
  final bool isToastError;

  const VoiceAssistantState({
    required this.snapshot,
    this.models = const <LocalAsrModelInstallState>[],
    this.activeDownloadProgress,
    this.isModelOperationBusy = false,
    this.toastMessageVi,
    this.isToastError = false,
  });

  factory VoiceAssistantState.fromCoordinator(
    VoiceSessionCoordinator coordinator,
  ) {
    return VoiceAssistantState(snapshot: coordinator.currentSnapshot);
  }

  VoiceSession get session => snapshot.session;
  VoiceSessionPhase get phase => snapshot.session.phase;
  VoiceTranscriptState get transcript => snapshot.transcript;
  String get effectiveText => snapshot.transcript.effectiveText;
  VoiceWaveformSample get waveform => snapshot.waveform;
  VoiceDiagnosticsReport get diagnostics => snapshot.diagnostics;
  VoiceRecognitionPreference get activePreference => snapshot.activePreference;
  VoiceEndpointMode get endpointMode => snapshot.endpointMode;
  bool get allowOnlineConsent => snapshot.allowOnlineConsent;
  String? get actionableHintVi => snapshot.actionableHintVi;

  bool get isListening => phase == VoiceSessionPhase.listening;
  bool get isPreparing => phase == VoiceSessionPhase.preparing;
  bool get isFinalizing => phase == VoiceSessionPhase.finalizing;
  bool get isReview => phase == VoiceSessionPhase.review;
  bool get isSubmitting => phase == VoiceSessionPhase.submitting;
  bool get isActiveCapture => phase.isActiveCapture;

  VoiceAssistantState copyWith({
    VoiceSessionStateSnapshot? snapshot,
    List<LocalAsrModelInstallState>? models,
    LocalAsrDownloadProgress? activeDownloadProgress,
    bool clearDownloadProgress = false,
    bool? isModelOperationBusy,
    String? toastMessageVi,
    bool clearToast = false,
    bool? isToastError,
  }) {
    return VoiceAssistantState(
      snapshot: snapshot ?? this.snapshot,
      models: models ?? this.models,
      activeDownloadProgress: clearDownloadProgress
          ? null
          : (activeDownloadProgress ?? this.activeDownloadProgress),
      isModelOperationBusy: isModelOperationBusy ?? this.isModelOperationBusy,
      toastMessageVi: clearToast
          ? null
          : (toastMessageVi ?? this.toastMessageVi),
      isToastError: clearToast ? false : (isToastError ?? this.isToastError),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    snapshot,
    models,
    activeDownloadProgress,
    isModelOperationBusy,
    toastMessageVi,
    isToastError,
  ];
}
