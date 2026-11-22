import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

sealed class VoiceAssistantSignal {
  const VoiceAssistantSignal();
}

final class VoiceStateSignal extends VoiceAssistantSignal {
  final String status; // 'listening' | 'processing' | 'idle'
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
  const VoiceErrorSignal(this.message);
}

class NativeVoiceAssistantBridge {
  static const MethodChannel _methodChannel = MethodChannel('vn.lifeos.app/voice_assistant');
  static const EventChannel _eventChannel = EventChannel('vn.lifeos.app/voice_events');

  const NativeVoiceAssistantBridge();

  bool get isSupportedPlatform => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _hasServicesBinding {
    try {
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> startListening() async {
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return 'UNSUPPORTED';
    }
    try {
      final status = await _methodChannel.invokeMethod<String>('startListening');
      return status ?? 'STARTED';
    } catch (_) {
      return 'ERROR';
    }
  }

  Future<void> stopListening() async {
    if (!isSupportedPlatform || !_hasServicesBinding) return;
    try {
      await _methodChannel.invokeMethod<void>('stopListening');
    } catch (_) {}
  }

  Stream<VoiceAssistantSignal> watchSignals() {
    if (!isSupportedPlatform || !_hasServicesBinding) {
      return const Stream<VoiceAssistantSignal>.empty();
    }
    return Stream<VoiceAssistantSignal>.multi((controller) {
      StreamSubscription<dynamic>? sub;
      try {
        sub = _eventChannel.receiveBroadcastStream().listen(
          (raw) {
            if (raw is! Map) return;
            final map = Map<String, dynamic>.from(raw);
            final type = (map['type'] ?? '').toString();
            switch (type) {
              case 'state':
                controller.add(VoiceStateSignal((map['status'] ?? 'idle').toString()));
              case 'rms':
                controller.add(VoiceRmsSignal((map['rms'] as num?)?.toDouble() ?? 0.0));
              case 'partial':
                controller.add(
                  VoiceTranscriptSignal(text: (map['text'] ?? '').toString(), isFinal: false),
                );
              case 'final':
                controller.add(
                  VoiceTranscriptSignal(text: (map['text'] ?? '').toString(), isFinal: true),
                );
              case 'error':
                controller.add(
                  VoiceErrorSignal(
                    (map['message'] ?? 'Không nghe rõ giọng nói. Bạn có thể bấm mic nói lại.')
                        .toString(),
                  ),
                );
            }
          },
          onError: (_) {},
        );
      } catch (_) {
        controller.close();
        return;
      }
      controller.onCancel = () async {
        try {
          await sub?.cancel();
        } catch (_) {}
      };
    });
  }
}
