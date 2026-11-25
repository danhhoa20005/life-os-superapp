import 'package:equatable/equatable.dart';

import '../../domain/entities/voice_engine_capability.dart';
import '../../domain/entities/voice_model_package.dart';
import '../../domain/entities/voice_session.dart';
import '../../domain/services/endpoint_policy.dart';
import '../../domain/services/voice_session_coordinator.dart';

sealed class VoiceAssistantEvent extends Equatable {
  const VoiceAssistantEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

final class VoiceAssistantInitialized extends VoiceAssistantEvent {
  const VoiceAssistantInitialized();
}

final class VoiceStartRequested extends VoiceAssistantEvent {
  final String ownerId;
  final VoiceEntryPoint entryPoint;
  final VoiceRecognitionPreference? preference;
  final bool clearTranscript;
  final bool? allowOnlineConsent;
  final String locale;

  const VoiceStartRequested({
    required this.ownerId,
    required this.entryPoint,
    this.preference,
    this.clearTranscript = false,
    this.allowOnlineConsent,
    this.locale = 'vi-VN',
  });

  @override
  List<Object?> get props => <Object?>[
    ownerId,
    entryPoint,
    preference,
    clearTranscript,
    allowOnlineConsent,
    locale,
  ];
}

final class VoiceStopRequested extends VoiceAssistantEvent {
  final String? sessionId;

  const VoiceStopRequested({this.sessionId});

  @override
  List<Object?> get props => <Object?>[sessionId];
}

final class VoiceCancelRequested extends VoiceAssistantEvent {
  final String? sessionId;
  final String? reason;

  const VoiceCancelRequested({this.sessionId, this.reason});

  @override
  List<Object?> get props => <Object?>[sessionId, reason];
}

final class VoiceRetryRequested extends VoiceAssistantEvent {
  final String ownerId;
  final VoiceEntryPoint entryPoint;
  final VoiceRecognitionPreference? preference;
  final bool clearTranscript;
  final bool? allowOnlineConsent;
  final String locale;

  const VoiceRetryRequested({
    required this.ownerId,
    required this.entryPoint,
    this.preference,
    this.clearTranscript = false,
    this.allowOnlineConsent,
    this.locale = 'vi-VN',
  });

  @override
  List<Object?> get props => <Object?>[
    ownerId,
    entryPoint,
    preference,
    clearTranscript,
    allowOnlineConsent,
    locale,
  ];
}

final class VoiceTranscriptEdited extends VoiceAssistantEvent {
  final String text;

  const VoiceTranscriptEdited(this.text);

  @override
  List<Object?> get props => <Object?>[text];
}

final class VoicePreferenceChanged extends VoiceAssistantEvent {
  final VoiceRecognitionPreference preference;

  const VoicePreferenceChanged(this.preference);

  @override
  List<Object?> get props => <Object?>[preference];
}

final class VoiceEndpointModeChanged extends VoiceAssistantEvent {
  final VoiceEndpointMode mode;

  const VoiceEndpointModeChanged(this.mode);

  @override
  List<Object?> get props => <Object?>[mode];
}

final class VoiceOnlineConsentChanged extends VoiceAssistantEvent {
  final bool allowed;

  const VoiceOnlineConsentChanged(this.allowed);

  @override
  List<Object?> get props => <Object?>[allowed];
}

final class VoicePermissionCallbackReceived extends VoiceAssistantEvent {
  final String sessionId;
  final int attemptId;
  final bool granted;
  final bool permanentlyDenied;
  final bool isForegroundFocused;

  const VoicePermissionCallbackReceived({
    required this.sessionId,
    required this.attemptId,
    required this.granted,
    required this.permanentlyDenied,
    required this.isForegroundFocused,
  });

  @override
  List<Object?> get props => <Object?>[
    sessionId,
    attemptId,
    granted,
    permanentlyDenied,
    isForegroundFocused,
  ];
}

final class VoiceAppLifecycleChanged extends VoiceAssistantEvent {
  final bool isBackgrounded;

  const VoiceAppLifecycleChanged(this.isBackgrounded);

  @override
  List<Object?> get props => <Object?>[isBackgrounded];
}

final class VoiceAccountResetRequested extends VoiceAssistantEvent {
  const VoiceAccountResetRequested();
}

final class VoiceSubmitStarted extends VoiceAssistantEvent {
  const VoiceSubmitStarted();
}

final class VoiceSubmitCompleted extends VoiceAssistantEvent {
  const VoiceSubmitCompleted();
}

final class VoiceSubmitReverted extends VoiceAssistantEvent {
  final String? errorMessageVi;

  const VoiceSubmitReverted({this.errorMessageVi});

  @override
  List<Object?> get props => <Object?>[errorMessageVi];
}

final class VoiceResetToIdleRequested extends VoiceAssistantEvent {
  final bool clearTranscript;

  const VoiceResetToIdleRequested({this.clearTranscript = true});

  @override
  List<Object?> get props => <Object?>[clearTranscript];
}

final class VoiceCapabilitiesResetRequested extends VoiceAssistantEvent {
  const VoiceCapabilitiesResetRequested();
}

final class VoiceDiagnosticsRefreshed extends VoiceAssistantEvent {
  const VoiceDiagnosticsRefreshed();
}

final class VoiceModelsRefreshRequested extends VoiceAssistantEvent {
  const VoiceModelsRefreshRequested();
}

final class VoiceModelDownloadRequested extends VoiceAssistantEvent {
  final LocalAsrModelSpec spec;
  final bool enforceCommercialLicense;

  const VoiceModelDownloadRequested(
    this.spec, {
    this.enforceCommercialLicense = true,
  });

  @override
  List<Object?> get props => <Object?>[spec, enforceCommercialLicense];
}

final class VoiceModelDeleteRequested extends VoiceAssistantEvent {
  final String modelId;

  const VoiceModelDeleteRequested(this.modelId);

  @override
  List<Object?> get props => <Object?>[modelId];
}

final class VoiceModelRollbackRequested extends VoiceAssistantEvent {
  final String modelId;

  const VoiceModelRollbackRequested(this.modelId);

  @override
  List<Object?> get props => <Object?>[modelId];
}

final class VoiceToastCleared extends VoiceAssistantEvent {
  const VoiceToastCleared();
}

final class VoiceCoordinatorSnapshotUpdated extends VoiceAssistantEvent {
  final VoiceSessionStateSnapshot snapshot;

  const VoiceCoordinatorSnapshotUpdated(this.snapshot);

  @override
  List<Object?> get props => <Object?>[snapshot];
}

final class VoiceModelProgressUpdated extends VoiceAssistantEvent {
  final LocalAsrDownloadProgress progress;

  const VoiceModelProgressUpdated(this.progress);

  @override
  List<Object?> get props => <Object?>[progress];
}
