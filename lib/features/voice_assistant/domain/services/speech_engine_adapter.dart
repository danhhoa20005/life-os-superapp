import 'package:equatable/equatable.dart';

import '../entities/voice_engine_capability.dart';
import '../entities/voice_event.dart';
import '../entities/voice_session.dart';

class EngineAvailabilityCheck extends Equatable {
  final VoiceEngineId engineId;
  final bool isAvailable;
  final bool supportsVietnamese;
  final String? reason;
  final String serviceVersion;
  final int checkedAtEpochMs;

  const EngineAvailabilityCheck({
    required this.engineId,
    required this.isAvailable,
    required this.supportsVietnamese,
    this.reason,
    this.serviceVersion = 'unknown',
    this.checkedAtEpochMs = 0,
  });

  @override
  List<Object?> get props => <Object?>[
    engineId,
    isAvailable,
    supportsVietnamese,
    reason,
    serviceVersion,
    checkedAtEpochMs,
  ];
}

class EngineStartOutcome extends Equatable {
  final bool started;
  final VoiceErrorKind? errorKind;
  final String? errorCode;
  final String? errorMessageVi;
  final bool awaitsExternalActivity;

  const EngineStartOutcome({
    required this.started,
    this.errorKind,
    this.errorCode,
    this.errorMessageVi,
    this.awaitsExternalActivity = false,
  });

  const EngineStartOutcome.success({this.awaitsExternalActivity = false})
    : started = true,
      errorKind = null,
      errorCode = null,
      errorMessageVi = null;

  const EngineStartOutcome.failure({
    required VoiceErrorKind this.errorKind,
    this.errorCode,
    this.errorMessageVi,
  }) : started = false,
       awaitsExternalActivity = false;

  @override
  List<Object?> get props => <Object?>[
    started,
    errorKind,
    errorCode,
    errorMessageVi,
    awaitsExternalActivity,
  ];
}

/// Abstract adapter implemented by each speech recognition engine.
abstract interface class SpeechEngineAdapter {
  VoiceEngineId get engineId;

  bool get isStrictlyOffline;

  bool get supportsStreamingPartials;

  Future<EngineAvailabilityCheck> checkAvailability({required String locale});

  Future<EngineStartOutcome> startSession({
    required String sessionId,
    required int attemptId,
    required String ownerId,
    required String locale,
    required bool strictOffline,
  });

  Future<void> stopSession({required String sessionId, required int attemptId});

  Future<void> cancelSession({
    required String sessionId,
    required int attemptId,
  });

  Stream<VoiceEnvelopeEvent> get events;

  Future<void> dispose();
}

/// Registry holding available [SpeechEngineAdapter] implementations by [VoiceEngineId].
class SpeechEngineRegistry {
  final Map<VoiceEngineId, SpeechEngineAdapter> _adapters;

  SpeechEngineRegistry(Iterable<SpeechEngineAdapter> adapters)
    : _adapters = <VoiceEngineId, SpeechEngineAdapter>{
        for (final adapter in adapters) adapter.engineId: adapter,
      };

  SpeechEngineAdapter? adapterFor(VoiceEngineId id) => _adapters[id];

  List<SpeechEngineAdapter> get allAdapters =>
      List<SpeechEngineAdapter>.unmodifiable(_adapters.values);

  Future<Map<VoiceEngineId, EngineAvailabilityCheck>> checkAll({
    required String locale,
  }) async {
    final out = <VoiceEngineId, EngineAvailabilityCheck>{};
    for (final entry in _adapters.entries) {
      out[entry.key] = await entry.value.checkAvailability(locale: locale);
    }
    return out;
  }

  Future<void> disposeAll() async {
    for (final adapter in _adapters.values) {
      await adapter.dispose();
    }
  }
}
