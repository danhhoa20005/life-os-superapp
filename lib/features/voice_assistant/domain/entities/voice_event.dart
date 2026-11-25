import 'package:equatable/equatable.dart';

import 'voice_session.dart';

/// Envelope event types emitted by speech engine adapters toward [VoiceSessionCoordinator].
enum VoiceEnvelopeEventType {
  permissionRequested,
  permissionGranted,
  permissionDenied,
  preparing,
  readyForSpeech,
  beginningOfSpeech,
  rmsChanged,
  pcmEnergy,
  partialResult,
  endOfSpeech,
  finalResult,
  error,
  cancelled,
  audioFocusLost,
  audioRouteChanged,
  engineSwitched,
  diagnosticsUpdated,
}

/// Sequenced, monotonic-timestamped event envelope stamped with session & attempt identity.
class VoiceEnvelopeEvent extends Equatable {
  final String sessionId;
  final int attemptId;
  final String ownerId;
  final int sequenceNumber;
  final String engineId;
  final VoiceEnvelopeEventType eventType;
  final int monotonicTimestampMs;
  final String? text;
  final double? rmsDb;
  final bool isRealPcmEnergy;
  final VoiceErrorKind? errorKind;
  final String? errorCode;
  final String? errorMessageVi;
  final String? audioRoute;

  const VoiceEnvelopeEvent({
    required this.sessionId,
    required this.attemptId,
    required this.ownerId,
    required this.sequenceNumber,
    required this.engineId,
    required this.eventType,
    required this.monotonicTimestampMs,
    this.text,
    this.rmsDb,
    this.isRealPcmEnergy = false,
    this.errorKind,
    this.errorCode,
    this.errorMessageVi,
    this.audioRoute,
  });

  VoiceEnvelopeEvent copyWith({
    String? sessionId,
    int? attemptId,
    String? ownerId,
    int? sequenceNumber,
    String? engineId,
    VoiceEnvelopeEventType? eventType,
    int? monotonicTimestampMs,
    String? text,
    double? rmsDb,
    bool? isRealPcmEnergy,
    VoiceErrorKind? errorKind,
    String? errorCode,
    String? errorMessageVi,
    String? audioRoute,
  }) {
    return VoiceEnvelopeEvent(
      sessionId: sessionId ?? this.sessionId,
      attemptId: attemptId ?? this.attemptId,
      ownerId: ownerId ?? this.ownerId,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      engineId: engineId ?? this.engineId,
      eventType: eventType ?? this.eventType,
      monotonicTimestampMs: monotonicTimestampMs ?? this.monotonicTimestampMs,
      text: text ?? this.text,
      rmsDb: rmsDb ?? this.rmsDb,
      isRealPcmEnergy: isRealPcmEnergy ?? this.isRealPcmEnergy,
      errorKind: errorKind ?? this.errorKind,
      errorCode: errorCode ?? this.errorCode,
      errorMessageVi: errorMessageVi ?? this.errorMessageVi,
      audioRoute: audioRoute ?? this.audioRoute,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    sessionId,
    attemptId,
    ownerId,
    sequenceNumber,
    engineId,
    eventType,
    monotonicTimestampMs,
    text,
    rmsDb,
    isRealPcmEnergy,
    errorKind,
    errorCode,
    errorMessageVi,
    audioRoute,
  ];
}
