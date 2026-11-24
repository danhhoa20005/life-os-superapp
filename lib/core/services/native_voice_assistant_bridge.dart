import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

sealed class VoiceAssistantSignal {
  const VoiceAssistantSignal();
}

final class VoiceStateSignal extends VoiceAssistantSignal {
  /// 'requesting_permission' | 'listening' | 'processing' | 'idle'
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

abstract interface class VoiceAssistantDriver {
  bool get isSupportedPlatform;
  Future<String> startListening();
  Future<void> stopListening();
  Stream<VoiceAssistantSignal> watchSignals();
}

/// Extended native driver contract supporting session-token ownership isolation,
/// direct Android System Speech Dialog fallback, and 1-tap OS Microphone Settings.
abstract interface class AdvancedVoiceAssistantDriver
    implements VoiceAssistantDriver {
  Future<String> startListeningSession({
    String? sessionToken,
    bool preferSystemDialog = false,
  });

  Future<void> cancelListeningSession({String? sessionToken});

  Future<bool> openMicrophoneSettings();
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
  }) async {
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return 'UNSUPPORTED';
    }
    _ensureMethodHandlerInstalled();
    try {
      final status = await _methodChannel.invokeMethod<String>(
        'startListening',
        <String, dynamic>{
          if (sessionToken != null) 'sessionToken': sessionToken,
          'preferSystemDialog': preferSystemDialog,
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

  Future<String> startListening({
    String? sessionToken,
    bool preferSystemDialog = false,
  }) {
    if (sessionToken != null && sessionToken.isNotEmpty) {
      _activeOwnerSessionToken = sessionToken;
    }
    final drv = _driver;
    if (drv is AdvancedVoiceAssistantDriver) {
      return drv.startListeningSession(
        sessionToken: sessionToken,
        preferSystemDialog: preferSystemDialog,
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

  Stream<VoiceAssistantSignal> watchSignals() => _driver.watchSignals();
}
