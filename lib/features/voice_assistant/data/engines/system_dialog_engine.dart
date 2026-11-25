import 'dart:async';

import '../../domain/entities/voice_engine_capability.dart';
import '../../domain/entities/voice_event.dart';
import '../../domain/entities/voice_session.dart';
import '../../domain/services/speech_engine_adapter.dart';
import '../datasources/voice_native_channel_datasource.dart';

/// System `RecognizerIntent.ACTION_RECOGNIZE_SPEECH` dialog adapter (awaits external Activity).
class SystemDialogEngine implements SpeechEngineAdapter {
  final VoiceNativeChannelDataSource _dataSource;

  SystemDialogEngine(this._dataSource);

  @override
  VoiceEngineId get engineId => VoiceEngineId.systemDialog;

  @override
  bool get isStrictlyOffline => false;

  @override
  bool get supportsStreamingPartials => false;

  @override
  Stream<VoiceEnvelopeEvent> get events => _dataSource.events.where(
    (e) =>
        e.engineId == engineId.wireValue ||
        e.engineId == 'system_speech_dialog',
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
    final hasDialog = diag['hasSystemSpeechDialog'] == true;
    return EngineAvailabilityCheck(
      engineId: engineId,
      isAvailable: hasDialog,
      supportsVietnamese: hasDialog,
      serviceVersion: 'system_speech_dialog',
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
        errorCode: 'STRICT_OFFLINE_REJECTED_DIALOG',
      );
    }
    final status = await _dataSource.startListening(
      sessionId: sessionId,
      attemptId: attemptId,
      ownerId: ownerId,
      engineMode: 'system_dialog',
      preferSystemDialog: true,
      strictOffline: false,
      locale: locale,
    );
    if (status == 'UNSUPPORTED' || status == 'ERROR') {
      return EngineStartOutcome.failure(
        errorKind: VoiceErrorKind.noEngineAvailable,
        errorCode: status,
      );
    }
    return const EngineStartOutcome.success(awaitsExternalActivity: true);
  }

  @override
  Future<void> stopSession({
    required String sessionId,
    required int attemptId,
  }) async {
    // External dialog manages its own stop button; no-op.
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
