import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum VoiceEngineMode {
  googleService('google_service', 'Google Speech (Trực tiếp)'),
  systemDialog('system_dialog', 'Hộp thoại Google'),
  auto('auto', 'Google Speech (Trực tiếp)'),
  onDevice('on_device', 'Google Offline');

  final String wireValue;
  final String labelVi;
  const VoiceEngineMode(this.wireValue, this.labelVi);

  /// Only the two verified Google Vietnamese modes are surfaced in the UI selector
  /// so users never land on broken OEM or unsupported non-Vietnamese offline stubs.
  static const List<VoiceEngineMode> selectableGoogleModes = <VoiceEngineMode>[
    VoiceEngineMode.googleService,
    VoiceEngineMode.systemDialog,
  ];

  static VoiceEngineMode fromWireValue(String? raw) {
    if (raw == systemDialog.wireValue) return systemDialog;
    return googleService;
  }
}

class VoiceDiagnosticsSnapshot {
  final bool hardwareMicAvailable;
  final bool hasRecordPermission;
  final bool isRecognitionAvailable;
  final bool isOnDeviceAvailable;
  final bool hasSystemSpeechDialog;
  final List<String> availableEngines;
  final String activeEngineLabel;
  final int sdkInt;
  final String manufacturer;

  const VoiceDiagnosticsSnapshot({
    required this.hardwareMicAvailable,
    required this.hasRecordPermission,
    required this.isRecognitionAvailable,
    required this.isOnDeviceAvailable,
    required this.hasSystemSpeechDialog,
    required this.availableEngines,
    required this.activeEngineLabel,
    required this.sdkInt,
    required this.manufacturer,
  });

  const VoiceDiagnosticsSnapshot.fallback({
    bool supported = false,
  }) : hardwareMicAvailable = supported,
       hasRecordPermission = supported,
       isRecognitionAvailable = supported,
       isOnDeviceAvailable = false,
       hasSystemSpeechDialog = supported,
       availableEngines = const <String>[],
       activeEngineLabel = 'auto',
       sdkInt = 0,
       manufacturer = 'unknown';

  factory VoiceDiagnosticsSnapshot.fromMap(Map<String, dynamic> map) {
    final rawEngines = map['availableEngines'];
    final engines = rawEngines is Iterable
        ? rawEngines.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return VoiceDiagnosticsSnapshot(
      hardwareMicAvailable: map['hardwareMicAvailable'] == true,
      hasRecordPermission: map['hasRecordPermission'] == true,
      isRecognitionAvailable: map['isRecognitionAvailable'] == true,
      isOnDeviceAvailable: map['isOnDeviceAvailable'] == true,
      hasSystemSpeechDialog: map['hasSystemSpeechDialog'] == true,
      availableEngines: engines,
      activeEngineLabel: (map['activeEngineLabel'] ?? 'auto').toString(),
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      manufacturer: (map['manufacturer'] ?? 'unknown').toString(),
    );
  }

  String get readableEngineSummaryVi {
    if (activeEngineLabel == 'system_default') {
      return 'Kênh hệ thống Android';
    }
    if (activeEngineLabel == 'on_device_android13') {
      return 'Nhận diện Offline trên máy';
    }
    if (activeEngineLabel == 'system_speech_dialog') {
      return 'Hộp thoại giọng nói hệ thống';
    }
    if (activeEngineLabel.startsWith('service:com.google.')) {
      return 'Speech Services by Google';
    }
    if (activeEngineLabel.startsWith('service:')) {
      return activeEngineLabel.substring('service:'.length);
    }
    if (availableEngines.isNotEmpty) {
      return 'Sẵn sàng (${availableEngines.length} kênh)';
    }
    return isRecognitionAvailable ? 'Sẵn sàng' : 'Chưa phát hiện dịch vụ';
  }
}

sealed class VoiceAssistantSignal {
  const VoiceAssistantSignal();
}

final class VoiceStateSignal extends VoiceAssistantSignal {
  /// 'requesting_permission' | 'initializing' | 'listening' | 'processing' | 'idle'
  final String status;
  const VoiceStateSignal(this.status);
}

final class VoiceRmsSignal extends VoiceAssistantSignal {
  final double rmsDb;
  const VoiceRmsSignal(this.rmsDb);
}

final class VoiceTranscriptSignal extends VoiceAssistantSignal {
  final String text;
  final bool isFinal;
  const VoiceTranscriptSignal({required this.text, required this.isFinal});
}

final class VoiceErrorSignal extends VoiceAssistantSignal {
  final String message;
  final String? code;
  const VoiceErrorSignal(this.message, {this.code});

  bool get isPermissionError =>
      code == 'PERMISSION_DENIED' || code == 'PERMISSION_PERMANENTLY_DENIED';

  bool get isPermanentlyDenied => code == 'PERMISSION_PERMANENTLY_DENIED';
}

final class VoiceEngineSwitchedSignal extends VoiceAssistantSignal {
  final String modeWireValue;
  const VoiceEngineSwitchedSignal(this.modeWireValue);
}

abstract interface class VoiceAssistantDriver {
  bool get isSupportedPlatform;
  Future<String> startListening();
  Future<void> stopListening();
  Stream<VoiceAssistantSignal> watchSignals();
}

/// Extended native driver contract supporting session-token ownership isolation,
/// multi-engine routing (`auto` / `on_device` / `google_service` / `system_dialog`),
/// live hardware/service diagnostics, and 1-tap OS Microphone Settings.
abstract interface class AdvancedVoiceAssistantDriver
    implements VoiceAssistantDriver {
  Future<String> startListeningSession({
    String? sessionToken,
    bool preferSystemDialog = false,
    String engineMode = 'auto',
    bool forceInlineProbe = false,
  });

  Future<void> cancelListeningSession({String? sessionToken});

  Future<bool> openMicrophoneSettings();

  Future<VoiceDiagnosticsSnapshot> getDiagnostics();
}

class MethodChannelVoiceAssistantDriver implements AdvancedVoiceAssistantDriver {
  static const MethodChannel _methodChannel = MethodChannel(
    'vn.lifeos.app/voice_assistant',
  );

  /// Permanent broadcast stream wired ONCE to `MethodChannel.setMethodCallHandler` (`onVoiceEvent`).
  /// Eliminates Flutter `EventChannel.receiveBroadcastStream()` clobbering when multiple screens
  /// or modal sheets subscribe and dispose across overlapping route transitions.
  static final StreamController<VoiceAssistantSignal> _signalBus =
      StreamController<VoiceAssistantSignal>.broadcast();
  static bool _handlerInstalled = false;

  const MethodChannelVoiceAssistantDriver();

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

  void _ensureMethodHandlerInstalled() {
    if (_handlerInstalled || !isSupportedPlatform || !_hasServicesBinding) {
      return;
    }
    _handlerInstalled = true;
    _methodChannel.setMethodCallHandler((call) async {
      if (call.method != 'onVoiceEvent') return null;
      final raw = call.arguments;
      if (raw is! Map) return null;
      final parsed = parseRawVoiceEvent(Map<String, dynamic>.from(raw));
      if (parsed != null && !_signalBus.isClosed) {
        _signalBus.add(parsed);
      }
      return null;
    });
  }

  @visibleForTesting
  static VoiceAssistantSignal? parseRawVoiceEvent(Map<String, dynamic> map) {
    final type = (map['type'] ?? '').toString();
    switch (type) {
      case 'state':
        return VoiceStateSignal((map['status'] ?? 'idle').toString());
      case 'rms':
        return VoiceRmsSignal((map['rms'] as num?)?.toDouble() ?? 0.0);
      case 'partial':
        return VoiceTranscriptSignal(
          text: (map['text'] ?? '').toString(),
          isFinal: false,
        );
      case 'final':
        return VoiceTranscriptSignal(
          text: (map['text'] ?? '').toString(),
          isFinal: true,
        );
      case 'error':
        return VoiceErrorSignal(
          (map['message'] ?? 'Không nghe rõ giọng nói. Bạn có thể bấm Nói lại.')
              .toString(),
          code: map['code']?.toString(),
        );
      case 'engine_switched':
        return VoiceEngineSwitchedSignal(
          (map['mode'] ?? 'system_dialog').toString(),
        );
      default:
        return null;
    }
  }

  @override
  Future<String> startListening() => startListeningSession();

  @override
  Future<String> startListeningSession({
    String? sessionToken,
    bool preferSystemDialog = false,
    String engineMode = 'google_service',
    bool forceInlineProbe = false,
  }) async {
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return 'UNSUPPORTED';
    }
    _ensureMethodHandlerInstalled();
    try {
      final useDialog = preferSystemDialog || engineMode == 'system_dialog';
      final normalizedMode = useDialog
          ? 'system_dialog'
          : (engineMode == 'on_device' ? 'on_device' : 'google_service');
      final status = await _methodChannel.invokeMethod<String>(
        'startListening',
        <String, dynamic>{
          if (sessionToken != null) 'sessionToken': sessionToken,
          'preferSystemDialog': useDialog,
          'engineMode': normalizedMode,
          'forceInlineProbe': forceInlineProbe,
        },
      );
      return status ?? 'STARTED';
    } catch (_) {
      return 'ERROR';
    }
  }

  @override
  Future<void> stopListening() async {
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _methodChannel.invokeMethod<void>('stopListening');
    } catch (_) {}
  }

  @override
  Future<void> cancelListeningSession({String? sessionToken}) async {
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _methodChannel.invokeMethod<void>(
        'cancelListening',
        <String, dynamic>{
          if (sessionToken != null) 'sessionToken': sessionToken,
        },
      );
    } catch (_) {}
  }

  @override
  Future<bool> openMicrophoneSettings() async {
    if (!isSupportedPlatform || !_hasServicesBinding) return false;
    try {
      final ok = await _methodChannel.invokeMethod<bool>(
        'openMicrophoneSettings',
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<VoiceDiagnosticsSnapshot> getDiagnostics() async {
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return const VoiceDiagnosticsSnapshot.fallback();
    }
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getDiagnostics',
      );
      if (raw == null) {
        return const VoiceDiagnosticsSnapshot.fallback(supported: true);
      }
      return VoiceDiagnosticsSnapshot.fromMap(raw);
    } catch (_) {
      return const VoiceDiagnosticsSnapshot.fallback(supported: true);
    }
  }

  @override
  Stream<VoiceAssistantSignal> watchSignals() {
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return const Stream<VoiceAssistantSignal>.empty();
    }
    _ensureMethodHandlerInstalled();
    return _signalBus.stream;
  }
}

class NativeVoiceAssistantBridge {
  static VoiceAssistantDriver _driver =
      const MethodChannelVoiceAssistantDriver();
  static String? _activeOwnerSessionToken;

  const NativeVoiceAssistantBridge();

  @visibleForTesting
  static void setDriverOverride(VoiceAssistantDriver? overrideDriver) {
    _driver = overrideDriver ?? const MethodChannelVoiceAssistantDriver();
    _activeOwnerSessionToken = null;
  }

  bool get isSupportedPlatform => _driver.isSupportedPlatform;

  /// Joins an existing spoken/typed prefix with a newly recognized utterance segment
  /// without wiping earlier clauses when the user taps Mic again to append.
  static String combinePrefixAndSegment(String prefix, String segment) {
    final cleanPrefix = prefix
        .trim()
        .replaceAll(RegExp(r'[,;\s]+$'), '')
        .trim();
    final cleanSegment = segment.trim();
    if (cleanPrefix.isEmpty) return cleanSegment;
    if (cleanSegment.isEmpty) return cleanPrefix;
    // Avoid duplicating if the speech engine re-emitted the full string
    if (cleanSegment.toLowerCase().startsWith(cleanPrefix.toLowerCase())) {
      return cleanSegment;
    }
    return '$cleanPrefix, $cleanSegment';
  }

  Future<String> startListening({
    String? sessionToken,
    bool preferSystemDialog = false,
    VoiceEngineMode engineMode = VoiceEngineMode.googleService,
    bool forceInlineProbe = false,
  }) {
    if (sessionToken != null && sessionToken.isNotEmpty) {
      _activeOwnerSessionToken = sessionToken;
    }
    final drv = _driver;
    if (drv is AdvancedVoiceAssistantDriver) {
      final useDialog =
          preferSystemDialog || engineMode == VoiceEngineMode.systemDialog;
      final effectiveWire = useDialog
          ? VoiceEngineMode.systemDialog.wireValue
          : (engineMode == VoiceEngineMode.onDevice
                ? VoiceEngineMode.onDevice.wireValue
                : VoiceEngineMode.googleService.wireValue);
      return drv.startListeningSession(
        sessionToken: sessionToken,
        preferSystemDialog: useDialog,
        engineMode: effectiveWire,
        forceInlineProbe: forceInlineProbe,
      );
    }
    return drv.startListening();
  }

  Future<void> stopListening() => _driver.stopListening();

  /// Safely cancels listening on widget `dispose()` ONLY if [sessionToken] still owns
  /// the active voice session — preventing a closing sheet from killing a newly opened sheet!
  Future<void> cancelListening({String? sessionToken}) async {
    if (sessionToken != null &&
        _activeOwnerSessionToken != null &&
        sessionToken != _activeOwnerSessionToken) {
      return;
    }
    if (sessionToken != null && sessionToken == _activeOwnerSessionToken) {
      _activeOwnerSessionToken = null;
    }
    final drv = _driver;
    if (drv is AdvancedVoiceAssistantDriver) {
      await drv.cancelListeningSession(sessionToken: sessionToken);
      return;
    }
    await drv.stopListening();
  }

  Future<bool> openMicrophoneSettings() async {
    final drv = _driver;
    if (drv is AdvancedVoiceAssistantDriver) {
      return drv.openMicrophoneSettings();
    }
    return false;
  }

  Future<VoiceDiagnosticsSnapshot> getDiagnostics() async {
    final drv = _driver;
    if (drv is AdvancedVoiceAssistantDriver) {
      return drv.getDiagnostics();
    }
    return VoiceDiagnosticsSnapshot.fallback(
      supported: drv.isSupportedPlatform,
    );
  }

  Stream<VoiceAssistantSignal> watchSignals() => _driver.watchSignals();
}
