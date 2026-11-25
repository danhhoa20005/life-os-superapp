import 'dart:async';

import '../../domain/entities/voice_engine_capability.dart';
import '../../domain/entities/voice_event.dart';
import '../../domain/entities/voice_session.dart';
import '../../domain/services/speech_engine_adapter.dart';
import '../datasources/voice_native_channel_datasource.dart';

/// Strict on-device Android 12+ (`API 31+` / Android 13+ `createOnDeviceSpeechRecognizer`) adapter.
class AndroidOnDeviceEngine implements SpeechEngineAdapter {
  final VoiceNativeChannelDataSource _dataSource;

  AndroidOnDeviceEngine(this._dataSource);

  @override
  VoiceEngineId get engineId => VoiceEngineId.androidOnDevice;

  @override
  bool get isStrictlyOffline => true;

  @override
  bool get supportsStreamingPartials => true;

  @override
  Stream<VoiceEnvelopeEvent> get events => _dataSource.events.where(
    (e) =>
        e.engineId == engineId.wireValue ||
        e.engineId == 'on_device' ||
        e.engineId == 'on_device_android13',
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
    final diag = await _dataSource.checkRecognitionSupport(locale: locale);
    final sdkInt = (diag['sdkInt'] as num?)?.toInt() ?? 0;
    final onDeviceFlag = diag['isOnDeviceAvailable'] == true;
    final vnFlag = diag['supportsVietnameseOnDevice'] as bool? ?? onDeviceFlag;
    final eligible = sdkInt >= 31 && onDeviceFlag;
    return EngineAvailabilityCheck(
      engineId: engineId,
      isAvailable: eligible,
      supportsVietnamese: eligible && vnFlag,
      serviceVersion: (diag['activeEngineLabel'] ?? 'android_on_device')
          .toString(),
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
    final status = await _dataSource.startListening(
      sessionId: sessionId,
      attemptId: attemptId,
      ownerId: ownerId,
      engineMode: 'on_device',
      preferSystemDialog: false,
      strictOffline: true,
      locale: locale,
    );
    if (status == 'UNSUPPORTED' || status == 'ERROR') {
      return EngineStartOutcome.failure(
        errorKind: status == 'UNSUPPORTED'
            ? VoiceErrorKind.noEngineAvailable
            : VoiceErrorKind.offlineModelMissing,
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
