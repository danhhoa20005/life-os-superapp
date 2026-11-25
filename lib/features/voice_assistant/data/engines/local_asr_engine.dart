import 'dart:async';

import '../../domain/entities/voice_engine_capability.dart';
import '../../domain/entities/voice_event.dart';
import '../../domain/entities/voice_session.dart';
import '../../domain/repositories/local_asr_model_repository.dart';
import '../../domain/services/speech_engine_adapter.dart';
import '../datasources/voice_native_channel_datasource.dart';

/// Optional local offline ASR adapter backed by downloaded Apache-2.0 / MIT model packages.
class LocalAsrEngine implements SpeechEngineAdapter {
  final LocalAsrModelRepository _modelRepository;
  final VoiceNativeChannelDataSource _dataSource;

  LocalAsrEngine({
    required LocalAsrModelRepository modelRepository,
    required VoiceNativeChannelDataSource dataSource,
  }) : _modelRepository = modelRepository,
       _dataSource = dataSource;

  @override
  VoiceEngineId get engineId => VoiceEngineId.localAsr;

  @override
  bool get isStrictlyOffline => true;

  @override
  bool get supportsStreamingPartials => true;

  @override
  Stream<VoiceEnvelopeEvent> get events =>
      _dataSource.events.where((e) => e.engineId == engineId.wireValue);

  @override
  Future<EngineAvailabilityCheck> checkAvailability({
    required String locale,
  }) async {
    final hasModel = await _modelRepository.hasVerifiedInstalledAsrModel();
    return EngineAvailabilityCheck(
      engineId: engineId,
      isAvailable: hasModel,
      supportsVietnamese: hasModel,
      reason: hasModel ? 'VERIFIED_LOCAL_MODEL' : 'OFFLINE_MODEL_MISSING',
      serviceVersion: 'local_asr_v2',
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
    final hasModel = await _modelRepository.hasVerifiedInstalledAsrModel();
    if (!hasModel) {
      return const EngineStartOutcome.failure(
        errorKind: VoiceErrorKind.offlineModelMissing,
        errorCode: 'OFFLINE_MODEL_MISSING',
      );
    }

    final status = await _dataSource.startListening(
      sessionId: sessionId,
      attemptId: attemptId,
      ownerId: ownerId,
      engineMode: engineId.wireValue,
      preferSystemDialog: false,
      strictOffline: true,
      locale: locale,
    );
    if (status == 'UNSUPPORTED' || status == 'ERROR') {
      return EngineStartOutcome.failure(
        errorKind: VoiceErrorKind.noEngineAvailable,
        errorCode: status,
      );
    }
    return const EngineStartOutcome.success();
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
