import 'dart:async';

import '../../domain/entities/voice_engine_capability.dart';
import '../../domain/entities/voice_event.dart';
import '../../domain/entities/voice_session.dart';
import '../../domain/services/speech_engine_adapter.dart';
import '../datasources/voice_native_channel_datasource.dart';

/// Online/Hybrid Android `SpeechRecognizer` adapter (`com.google.android.tts` / system broker).
class AndroidSpeechEngine implements SpeechEngineAdapter {
  final VoiceNativeChannelDataSource _dataSource;

  AndroidSpeechEngine(this._dataSource);

  @override
  VoiceEngineId get engineId => VoiceEngineId.androidSpeech;

  @override
  bool get isStrictlyOffline => false;

  @override
  bool get supportsStreamingPartials => true;

  @override
  Stream<VoiceEnvelopeEvent> get events => _dataSource.events.where(
    (e) =>
        VoiceEngineId.tryFromWireValue(e.engineId) == engineId ||
        e.engineId == engineId.wireValue ||
        e.engineId == 'google_service' ||
        e.engineId == 'system_default' ||
        e.engineId == 'auto' ||
        e.engineId.startsWith('service:'),
  );

  @override
  Future<EngineAvailabilityCheck> checkAvailability({
    required String locale,
  }) async {
    if (!_dataSource.isSupportedPlatform) {
      return EngineAvailabilityCheck(
        engineId: engineId,
        isAvailable: false,
        supportsVietnamese: false,
        reason: 'PLATFORM_UNSUPPORTED',
      );
    }
    final diag = await _dataSource.getVoiceDiagnosticsV2();
    final isAvailable = diag['isRecognitionAvailable'] == true;
    final activeLabel = (diag['activeEngineLabel'] ?? 'unknown').toString();
    return EngineAvailabilityCheck(
      engineId: engineId,
      isAvailable: isAvailable,
      supportsVietnamese: isAvailable,
      serviceVersion: activeLabel,
      checkedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<EngineStartOutcome> startSession({
    required String sessionId,
    required int attemptId,
    required String ownerId,
    required String locale,
    required bool strictOffline,
  }) async {
    if (strictOffline) {
      return const EngineStartOutcome.failure(
        errorKind: VoiceErrorKind.noEngineAvailable,
        errorCode: 'STRICT_OFFLINE_REJECTED_ONLINE_ENGINE',
      );
    }
    final status = await _dataSource.startListening(
      sessionId: sessionId,
      attemptId: attemptId,
      ownerId: ownerId,
      engineMode: 'google_service',
      preferSystemDialog: false,
      strictOffline: false,
      locale: locale,
    );
    if (status == 'UNSUPPORTED' || status == 'ERROR') {
      return EngineStartOutcome.failure(
        errorKind: status == 'UNSUPPORTED'
            ? VoiceErrorKind.noEngineAvailable
            : VoiceErrorKind.clientError,
        errorCode: status,
      );
    }
    return EngineStartOutcome.success(
      awaitsExternalActivity: status == 'PERMISSION_REQUESTED',
    );
  }

  @override
  Future<void> stopSession({
    required String sessionId,
    required int attemptId,
  }) {
    return _dataSource.stopListening(
      sessionId: sessionId,
      attemptId: attemptId,
    );
  }

  @override
  Future<void> cancelSession({
    required String sessionId,
    required int attemptId,
  }) {
    return _dataSource.cancelListening(
      sessionId: sessionId,
      attemptId: attemptId,
    );
  }

  @override
  Future<void> dispose() async {}
}
