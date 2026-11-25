import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/voice_engine_capability.dart';
import '../../domain/entities/voice_event.dart';
import '../../domain/entities/voice_session.dart';
import '../../domain/services/monotonic_clock.dart';

/// Abstraction over platform channel calls so data source can be unit-tested cleanly.
abstract interface class VoiceMethodChannelClient {
  bool get isSupportedPlatform;

  Future<T?> invokeMethod<T>(String method, [Object? arguments]);

  Future<Map<String, dynamic>?> invokeMapMethod(
    String method, [
    Object? arguments,
  ]);

  void setMethodCallHandler(Future<dynamic> Function(MethodCall call)? handler);
}

class FlutterVoiceMethodChannelClient implements VoiceMethodChannelClient {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/voice_assistant',
  );

  const FlutterVoiceMethodChannelClient();

  @override
  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _hasServicesBinding {
    try {
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    if (!isSupportedPlatform || !_hasServicesBinding) return null;
    return _channel.invokeMethod<T>(method, arguments);
  }

  @override
  Future<Map<String, dynamic>?> invokeMapMethod(
    String method, [
    Object? arguments,
  ]) async {
    if (!isSupportedPlatform || !_hasServicesBinding) return null;
    return _channel.invokeMapMethod<String, dynamic>(method, arguments);
  }

  @override
  void setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    _channel.setMethodCallHandler(handler);
  }
}

/// Native bridge for `vn.lifeos.app/voice_assistant` supporting v2 envelope payloads
/// and full backward compatibility with legacy Kotlin voice callbacks.
class VoiceNativeChannelDataSource {
  final VoiceMethodChannelClient _client;
  final MonotonicClock _clock;
  final StreamController<VoiceEnvelopeEvent> _eventController =
      StreamController<VoiceEnvelopeEvent>.broadcast();

  bool _handlerInstalled = false;
  bool _disposed = false;
  String? _activeSessionId;
  int _activeAttemptId = 0;
  String _activeOwnerId = '';
  String _activeEngineId = VoiceEngineId.androidSpeech.wireValue;

  VoiceNativeChannelDataSource({
    VoiceMethodChannelClient? client,
    MonotonicClock? clock,
  }) : _client = client ?? const FlutterVoiceMethodChannelClient(),
       _clock = clock ?? SystemMonotonicClock();

  bool get isSupportedPlatform => _client.isSupportedPlatform;

  Stream<VoiceEnvelopeEvent> get events {
    _ensureHandlerInstalled();
    return _eventController.stream;
  }

  void _ensureHandlerInstalled() {
    if (_handlerInstalled || _disposed || !_client.isSupportedPlatform) return;
    _handlerInstalled = true;
    _client.setMethodCallHandler((call) async {
      if (call.method != 'onVoiceEvent') return null;
      final raw = call.arguments;
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final event = parseRawEvent(
        map,
        fallbackSessionId: _activeSessionId ?? '',
        fallbackAttemptId: _activeAttemptId,
        fallbackOwnerId: _activeOwnerId,
        fallbackEngineId: _activeEngineId,
        monotonicTimestampMs: _clock.elapsedMilliseconds,
      );
      if (event != null && !_disposed && !_eventController.isClosed) {
        _eventController.add(event);
      }
      return null;
    });
  }

  /// Allows tests or synthetic native drivers to inject raw channel maps directly.
  @visibleForTesting
  void handleRawNativeMap(Map<String, dynamic> raw) {
    final event = parseRawEvent(
      raw,
      fallbackSessionId: _activeSessionId ?? '',
      fallbackAttemptId: _activeAttemptId,
      fallbackOwnerId: _activeOwnerId,
      fallbackEngineId: _activeEngineId,
      monotonicTimestampMs: _clock.elapsedMilliseconds,
    );
    if (event != null && !_disposed && !_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  Future<String> startListening({
    required String sessionId,
    required int attemptId,
    required String ownerId,
    required String engineMode,
    required bool preferSystemDialog,
    required bool strictOffline,
    required String locale,
    bool forceInlineProbe = false,
  }) async {
    if (!_client.isSupportedPlatform) return 'UNSUPPORTED';
    _ensureHandlerInstalled();

    _activeSessionId = sessionId;
    _activeAttemptId = attemptId;
    _activeOwnerId = ownerId;
    _activeEngineId = engineMode;

    try {
      final result = await _client
          .invokeMethod<String>('startListening', <String, dynamic>{
            'sessionToken': sessionId,
            'sessionId': sessionId,
            'attemptId': attemptId,
            'ownerId': ownerId,
            'preferSystemDialog': preferSystemDialog,
            'engineMode': engineMode,
            'strictOffline': strictOffline,
            'locale': locale,
            'forceInlineProbe': forceInlineProbe,
          });
      return result ?? 'STARTED';
    } on MissingPluginException {
      return 'UNSUPPORTED';
    } catch (_) {
      return 'ERROR';
    }
  }

  Future<void> stopListening({String? sessionId, int? attemptId}) async {
    if (!_client.isSupportedPlatform) return;
    try {
      await _client.invokeMethod<Object?>('stopListening', <String, dynamic>{
        if (sessionId != null) 'sessionToken': sessionId,
        if (sessionId != null) 'sessionId': sessionId,
        if (attemptId != null) 'attemptId': attemptId,
      });
    } on MissingPluginException {
      // Unsupported in host harness
    } catch (_) {}
  }

  Future<void> cancelListening({String? sessionId, int? attemptId}) async {
    if (sessionId == null || sessionId == _activeSessionId) {
      _activeSessionId = null;
      _activeAttemptId = 0;
    }
    if (!_client.isSupportedPlatform) return;
    try {
      await _client.invokeMethod<Object?>('cancelListening', <String, dynamic>{
        if (sessionId != null) 'sessionToken': sessionId,
        if (sessionId != null) 'sessionId': sessionId,
        if (attemptId != null) 'attemptId': attemptId,
      });
    } on MissingPluginException {
      // Unsupported in host harness
    } catch (_) {}
  }

  Future<bool> hasRecordPermission() async {
    if (!_client.isSupportedPlatform) return false;
    try {
      final granted = await _client.invokeMethod<bool>('hasRecordPermission');
      return granted ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openMicrophoneSettings() async {
    if (!_client.isSupportedPlatform) return false;
    try {
      final ok = await _client.invokeMethod<bool>('openMicrophoneSettings');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> checkRecognitionSupport({
    String locale = 'vi-VN',
  }) async {
    if (!_client.isSupportedPlatform) {
      return const <String, dynamic>{
        'supported': false,
        'locale': 'vi-VN',
        'isOnDeviceAvailable': false,
        'isGoogleSpeechAvailable': false,
        'hasSystemSpeechDialog': false,
      };
    }
    try {
      final raw = await _client.invokeMapMethod(
        'checkRecognitionSupport',
        <String, dynamic>{'locale': locale},
      );
      if (raw != null) return raw;
    } on MissingPluginException {
      // Fall back to legacy getDiagnostics
    } catch (_) {}
    return getVoiceDiagnosticsV2();
  }

  Future<bool> resetCapabilityCache() async {
    if (!_client.isSupportedPlatform) return false;
    try {
      final ok = await _client.invokeMethod<bool>('resetCapabilityCache');
      return ok ?? true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> runMicrophoneSelfTest() async {
    if (!_client.isSupportedPlatform) {
      return const <String, dynamic>{
        'supported': false,
        'passed': false,
        'reason': 'PLATFORM_UNSUPPORTED',
      };
    }
    try {
      final raw = await _client.invokeMapMethod('runMicrophoneSelfTest');
      if (raw != null) return raw;
    } on MissingPluginException {
      return const <String, dynamic>{
        'supported': false,
        'passed': false,
        'reason': 'SELF_TEST_NOT_IMPLEMENTED',
      };
    } catch (_) {}
    return const <String, dynamic>{
      'supported': true,
      'passed': false,
      'reason': 'SELF_TEST_FAILED',
    };
  }

  Future<Map<String, dynamic>> getVoiceDiagnosticsV2() async {
    if (!_client.isSupportedPlatform) {
      return const <String, dynamic>{
        'hardwareMicAvailable': false,
        'hasRecordPermission': false,
        'isRecognitionAvailable': false,
        'isOnDeviceAvailable': false,
        'hasSystemSpeechDialog': false,
        'availableEngines': <String>[],
        'sdkInt': 0,
        'manufacturer': 'unknown',
      };
    }
    try {
      final rawV2 = await _client.invokeMapMethod('getVoiceDiagnosticsV2');
      if (rawV2 != null) return rawV2;
    } on MissingPluginException {
      // Fallback to v1 getDiagnostics
    } catch (_) {}

    try {
      final rawV1 = await _client.invokeMapMethod('getDiagnostics');
      if (rawV1 != null) return rawV1;
    } on MissingPluginException {
      // Ignore
    } catch (_) {}

    return const <String, dynamic>{
      'hardwareMicAvailable': false,
      'hasRecordPermission': false,
      'isRecognitionAvailable': false,
      'isOnDeviceAvailable': false,
      'hasSystemSpeechDialog': false,
      'availableEngines': <String>[],
      'sdkInt': 0,
      'manufacturer': 'unknown',
    };
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_handlerInstalled) {
      _client.setMethodCallHandler(null);
      _handlerInstalled = false;
    }
    await _eventController.close();
  }

  /// Parses v2 envelope events and legacy Kotlin event maps into [VoiceEnvelopeEvent].
  static VoiceEnvelopeEvent? parseRawEvent(
    Map<String, dynamic> map, {
    required String fallbackSessionId,
    required int fallbackAttemptId,
    required String fallbackOwnerId,
    required String fallbackEngineId,
    required int monotonicTimestampMs,
  }) {
    final explicitSessionId =
        map['sessionId']?.toString() ?? map['sessionToken']?.toString();
    final sessionId =
        (explicitSessionId != null && explicitSessionId.isNotEmpty)
        ? explicitSessionId
        : fallbackSessionId;

    final rawAttempt = (map['attemptId'] as num?)?.toInt();
    final attemptId =
        rawAttempt ?? (sessionId == fallbackSessionId ? fallbackAttemptId : 0);

    final ownerId = map['ownerId']?.toString() ?? fallbackOwnerId;
    final sequenceNumber = (map['sequenceNumber'] as num?)?.toInt() ?? 0;
    final engineId = map['engineId']?.toString() ?? fallbackEngineId;
    final tsMs =
        (map['monotonicTimestampMs'] as num?)?.toInt() ?? monotonicTimestampMs;

    // 1. V2 structured `eventType` payload
    final rawEventType = map['eventType']?.toString();
    if (rawEventType != null && rawEventType.isNotEmpty) {
      final parsedType = _parseEnvelopeEventType(rawEventType);
      if (parsedType == null) return null;
      final errCode = map['errorCode']?.toString() ?? map['code']?.toString();
      final errKind = _parseErrorKind(
        map['errorKind']?.toString(),
        errCode,
        (map['androidErrorCode'] as num?)?.toInt(),
      );
      return VoiceEnvelopeEvent(
        sessionId: sessionId,
        attemptId: attemptId,
        ownerId: ownerId,
        sequenceNumber: sequenceNumber,
        engineId: engineId,
        eventType: parsedType,
        monotonicTimestampMs: tsMs,
        text: map['text']?.toString(),
        rmsDb: (map['rmsDb'] as num? ?? map['rms'] as num?)?.toDouble(),
        isRealPcmEnergy: map['isRealPcmEnergy'] == true,
        errorKind: errKind,
        errorCode: errCode,
        errorMessageVi:
            map['errorMessageVi']?.toString() ?? map['message']?.toString(),
        audioRoute: map['audioRoute']?.toString(),
      );
    }

    // 2. Legacy v1 payload compatibility (`type`: state / rms / partial / final / error / engine_switched)
    final legacyType = (map['type'] ?? '').toString().trim().toLowerCase();
    switch (legacyType) {
      case 'state':
        final status = (map['status'] ?? '').toString().trim().toLowerCase();
        final eventType = switch (status) {
          'requesting_permission' => VoiceEnvelopeEventType.permissionRequested,
          'initializing' || 'preparing' => VoiceEnvelopeEventType.preparing,
          'listening' => VoiceEnvelopeEventType.readyForSpeech,
          'processing' || 'finalizing' => VoiceEnvelopeEventType.endOfSpeech,
          'cancelled' || 'canceled' => VoiceEnvelopeEventType.cancelled,
          'error' => VoiceEnvelopeEventType.error,
          _ => null,
        };
        if (eventType == null) return null;
        return VoiceEnvelopeEvent(
          sessionId: sessionId,
          attemptId: attemptId,
          ownerId: ownerId,
          sequenceNumber: sequenceNumber,
          engineId: engineId,
          eventType: eventType,
          monotonicTimestampMs: tsMs,
        );
      case 'rms':
        return VoiceEnvelopeEvent(
          sessionId: sessionId,
          attemptId: attemptId,
          ownerId: ownerId,
          sequenceNumber: sequenceNumber,
          engineId: engineId,
          eventType: VoiceEnvelopeEventType.rmsChanged,
          monotonicTimestampMs: tsMs,
          rmsDb: (map['rms'] as num?)?.toDouble() ?? 0.0,
          isRealPcmEnergy: false,
        );
      case 'pcm_energy':
        return VoiceEnvelopeEvent(
          sessionId: sessionId,
          attemptId: attemptId,
          ownerId: ownerId,
          sequenceNumber: sequenceNumber,
          engineId: engineId,
          eventType: VoiceEnvelopeEventType.pcmEnergy,
          monotonicTimestampMs: tsMs,
          rmsDb:
              (map['rmsDb'] as num? ?? map['rms'] as num?)?.toDouble() ?? -60.0,
          isRealPcmEnergy: true,
        );
      case 'partial':
        return VoiceEnvelopeEvent(
          sessionId: sessionId,
          attemptId: attemptId,
          ownerId: ownerId,
          sequenceNumber: sequenceNumber,
          engineId: engineId,
          eventType: VoiceEnvelopeEventType.partialResult,
          monotonicTimestampMs: tsMs,
          text: (map['text'] ?? '').toString(),
        );
      case 'final':
        return VoiceEnvelopeEvent(
          sessionId: sessionId,
          attemptId: attemptId,
          ownerId: ownerId,
          sequenceNumber: sequenceNumber,
          engineId: engineId,
          eventType: VoiceEnvelopeEventType.finalResult,
          monotonicTimestampMs: tsMs,
          text: (map['text'] ?? '').toString(),
        );
      case 'error':
        final errCode = map['code']?.toString();
        final errKind = VoiceErrorKind.fromNativeCode(
          errCode,
          androidErrorCode: (map['androidErrorCode'] as num?)?.toInt(),
        );
        return VoiceEnvelopeEvent(
          sessionId: sessionId,
          attemptId: attemptId,
          ownerId: ownerId,
          sequenceNumber: sequenceNumber,
          engineId: engineId,
          eventType: VoiceEnvelopeEventType.error,
          monotonicTimestampMs: tsMs,
          errorKind: errKind,
          errorCode: errCode,
          errorMessageVi:
              map['message']?.toString() ?? errKind.friendlyMessageVi,
        );
      case 'engine_switched':
        final mode = (map['mode'] ?? 'system_dialog').toString();
        final resolvedEngine =
            VoiceEngineId.tryFromWireValue(mode)?.wireValue ?? mode;
        return VoiceEnvelopeEvent(
          sessionId: sessionId,
          attemptId: attemptId,
          ownerId: ownerId,
          sequenceNumber: sequenceNumber,
          engineId: resolvedEngine,
          eventType: VoiceEnvelopeEventType.engineSwitched,
          monotonicTimestampMs: tsMs,
        );
      case 'audio_route':
        return VoiceEnvelopeEvent(
          sessionId: sessionId,
          attemptId: attemptId,
          ownerId: ownerId,
          sequenceNumber: sequenceNumber,
          engineId: engineId,
          eventType: VoiceEnvelopeEventType.audioRouteChanged,
          monotonicTimestampMs: tsMs,
          audioRoute: map['audioRoute']?.toString(),
        );
      case 'audio_focus_lost':
        return VoiceEnvelopeEvent(
          sessionId: sessionId,
          attemptId: attemptId,
          ownerId: ownerId,
          sequenceNumber: sequenceNumber,
          engineId: engineId,
          eventType: VoiceEnvelopeEventType.audioFocusLost,
          monotonicTimestampMs: tsMs,
          errorKind: VoiceErrorKind.audioFocusLost,
          errorCode: 'AUDIO_FOCUS_LOST',
        );
      default:
        return null;
    }
  }

  static VoiceEnvelopeEventType? _parseEnvelopeEventType(String raw) {
    final norm = raw.trim();
    for (final val in VoiceEnvelopeEventType.values) {
      if (val.name == norm) return val;
    }
    return null;
  }

  static VoiceErrorKind? _parseErrorKind(
    String? rawKind,
    String? rawCode,
    int? androidErrorCode,
  ) {
    if (rawKind != null && rawKind.isNotEmpty) {
      for (final kind in VoiceErrorKind.values) {
        if (kind.name == rawKind) return kind;
      }
    }
    if (rawCode != null || androidErrorCode != null) {
      return VoiceErrorKind.fromNativeCode(
        rawCode,
        androidErrorCode: androidErrorCode,
      );
    }
    return null;
  }
}
