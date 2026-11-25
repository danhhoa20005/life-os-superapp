import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Formal 9-state Finite State Machine for voice capture lifecycle (`AUD-015`).
enum VoiceCaptureState {
  idle('idle'),
  requestingPermission('requesting_permission'),
  initializing('initializing'),
  listening('listening'),
  processing('processing'),
  review('review'),
  completed('completed'),
  error('error'),
  cancelled('cancelled');

  final String wireValue;
  const VoiceCaptureState(this.wireValue);

  bool get isRecordingSessionActive =>
      this == VoiceCaptureState.initializing ||
      this == VoiceCaptureState.listening ||
      this == VoiceCaptureState.processing;

  static VoiceCaptureState fromWireStatus(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    return switch (normalized) {
      'requesting_permission' => VoiceCaptureState.requestingPermission,
      'initializing' => VoiceCaptureState.initializing,
      'listening' => VoiceCaptureState.listening,
      'processing' => VoiceCaptureState.processing,
      'review' => VoiceCaptureState.review,
      'completed' => VoiceCaptureState.completed,
      'error' => VoiceCaptureState.error,
      'cancelled' || 'canceled' => VoiceCaptureState.cancelled,
      _ => VoiceCaptureState.idle,
    };
  }

  static const Map<VoiceCaptureState, Set<VoiceCaptureState>>
  _allowedTransitions = <VoiceCaptureState, Set<VoiceCaptureState>>{
    VoiceCaptureState.idle: <VoiceCaptureState>{
      VoiceCaptureState.idle,
      VoiceCaptureState.requestingPermission,
      VoiceCaptureState.initializing,
      VoiceCaptureState.listening,
      VoiceCaptureState.review,
      VoiceCaptureState.error,
      VoiceCaptureState.cancelled,
    },
    VoiceCaptureState.requestingPermission: <VoiceCaptureState>{
      VoiceCaptureState.requestingPermission,
      VoiceCaptureState.initializing,
      VoiceCaptureState.listening,
      VoiceCaptureState.review,
      VoiceCaptureState.error,
      VoiceCaptureState.cancelled,
      VoiceCaptureState.idle,
    },
    VoiceCaptureState.initializing: <VoiceCaptureState>{
      VoiceCaptureState.initializing,
      VoiceCaptureState.requestingPermission,
      VoiceCaptureState.listening,
      VoiceCaptureState.processing,
      VoiceCaptureState.review,
      VoiceCaptureState.error,
      VoiceCaptureState.cancelled,
      VoiceCaptureState.idle,
    },
    VoiceCaptureState.listening: <VoiceCaptureState>{
      VoiceCaptureState.listening,
      VoiceCaptureState.requestingPermission,
      VoiceCaptureState.processing,
      VoiceCaptureState.review,
      VoiceCaptureState.error,
      VoiceCaptureState.cancelled,
      VoiceCaptureState.idle,
    },
    VoiceCaptureState.processing: <VoiceCaptureState>{
      VoiceCaptureState.processing,
      VoiceCaptureState.review,
      VoiceCaptureState.completed,
      VoiceCaptureState.error,
      VoiceCaptureState.cancelled,
      VoiceCaptureState.idle,
    },
    VoiceCaptureState.review: <VoiceCaptureState>{
      VoiceCaptureState.review,
      VoiceCaptureState.initializing,
      VoiceCaptureState.listening,
      VoiceCaptureState.completed,
      VoiceCaptureState.error,
      VoiceCaptureState.cancelled,
      VoiceCaptureState.idle,
    },
    VoiceCaptureState.completed: <VoiceCaptureState>{
      VoiceCaptureState.completed,
      VoiceCaptureState.idle,
      VoiceCaptureState.initializing,
      VoiceCaptureState.review,
    },
    VoiceCaptureState.error: <VoiceCaptureState>{
      VoiceCaptureState.error,
      VoiceCaptureState.idle,
      VoiceCaptureState.requestingPermission,
      VoiceCaptureState.initializing,
      VoiceCaptureState.listening,
      VoiceCaptureState.review,
      VoiceCaptureState.cancelled,
    },
    VoiceCaptureState.cancelled: <VoiceCaptureState>{
      VoiceCaptureState.cancelled,
      VoiceCaptureState.idle,
      VoiceCaptureState.requestingPermission,
      VoiceCaptureState.initializing,
      VoiceCaptureState.listening,
      VoiceCaptureState.review,
      VoiceCaptureState.error,
    },
  };

  bool canTransitionTo(VoiceCaptureState next) {
    return _allowedTransitions[this]?.contains(next) ?? false;
  }
}

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

  const VoiceDiagnosticsSnapshot.fallback({bool supported = false})
    : hardwareMicAvailable = supported,
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
  final String? sessionToken;
  const VoiceAssistantSignal({this.sessionToken});
}

final class VoiceStateSignal extends VoiceAssistantSignal {
  /// 'idle' | 'requesting_permission' | 'initializing' | 'listening' | 'processing' | 'review' | 'completed' | 'error' | 'cancelled'
  final String status;
  const VoiceStateSignal(this.status, {super.sessionToken});

  VoiceCaptureState get captureState =>
      VoiceCaptureState.fromWireStatus(status);
}

final class VoiceRmsSignal extends VoiceAssistantSignal {
  final double rmsDb;
  const VoiceRmsSignal(this.rmsDb, {super.sessionToken});
}

final class VoiceTranscriptSignal extends VoiceAssistantSignal {
  final String text;
  final bool isFinal;
  const VoiceTranscriptSignal({
    required this.text,
    required this.isFinal,
    super.sessionToken,
  });
}

final class VoiceErrorSignal extends VoiceAssistantSignal {
  final String message;
  final String? code;
  const VoiceErrorSignal(this.message, {this.code, super.sessionToken});

  bool get isPermissionError =>
      code == 'PERMISSION_DENIED' || code == 'PERMISSION_PERMANENTLY_DENIED';

  bool get isPermanentlyDenied => code == 'PERMISSION_PERMANENTLY_DENIED';
}

final class VoiceEngineSwitchedSignal extends VoiceAssistantSignal {
  final String modeWireValue;
  const VoiceEngineSwitchedSignal(this.modeWireValue, {super.sessionToken});
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

class MethodChannelVoiceAssistantDriver
    implements AdvancedVoiceAssistantDriver {
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
    final sessionToken = map['sessionToken']?.toString();
    switch (type) {
      case 'state':
        return VoiceStateSignal(
          (map['status'] ?? 'idle').toString(),
          sessionToken: sessionToken,
        );
      case 'rms':
        return VoiceRmsSignal(
          (map['rms'] as num?)?.toDouble() ?? 0.0,
          sessionToken: sessionToken,
        );
      case 'partial':
        return VoiceTranscriptSignal(
          text: (map['text'] ?? '').toString(),
          isFinal: false,
          sessionToken: sessionToken,
        );
      case 'final':
        return VoiceTranscriptSignal(
          text: (map['text'] ?? '').toString(),
          isFinal: true,
          sessionToken: sessionToken,
        );
      case 'error':
        return VoiceErrorSignal(
          (map['message'] ?? 'Không nghe rõ giọng nói. Bạn có thể bấm Nói lại.')
              .toString(),
          code: map['code']?.toString(),
          sessionToken: sessionToken,
        );
      case 'engine_switched':
        return VoiceEngineSwitchedSignal(
          (map['mode'] ?? 'system_dialog').toString(),
          sessionToken: sessionToken,
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
      final status = await _methodChannel
          .invokeMethod<String>('startListening', <String, dynamic>{
            if (sessionToken != null) 'sessionToken': sessionToken,
            'preferSystemDialog': useDialog,
            'engineMode': normalizedMode,
            'forceInlineProbe': forceInlineProbe,
          });
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

  static bool isSignalForSession(
    VoiceAssistantSignal signal,
    String? expectedSessionToken,
  ) {
    if (expectedSessionToken == null || expectedSessionToken.isEmpty) {
      return true;
    }
    final sigToken = signal.sessionToken;
    if (sigToken == null || sigToken.isEmpty) {
      return true;
    }
    return sigToken == expectedSessionToken;
  }

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

  Stream<VoiceAssistantSignal> watchSignals({String? sessionToken}) {
    final stream = _driver.watchSignals();
    if (sessionToken == null || sessionToken.isEmpty) {
      return stream;
    }
    return stream.where((sig) => isSignalForSession(sig, sessionToken));
  }
}
