import 'package:equatable/equatable.dart';

/// Endpointing strategy (`VOICE-005`): explicit stop is default for Vietnamese stability.
enum VoiceEndpointMode {
  explicitStopOnly('explicit_stop_only', 'Bấm dừng thủ công (Ổn định nhất)'),
  smartAutoEndpoint('smart_auto_endpoint', 'Tự động dừng khi ngưng nói');

  final String wireValue;
  final String labelVi;

  const VoiceEndpointMode(this.wireValue, this.labelVi);
}

/// Configurable duration guards for speech capture lifecycle.
class EndpointPolicyConfig extends Equatable {
  final VoiceEndpointMode mode;
  final Duration initialSpeechTimeout;
  final Duration minimumSpeechDuration;
  final Duration normalTrailingSilence;
  final Duration incompleteClauseSilence;
  final Duration maxUtteranceDuration;
  final Duration finalizingTimeout;
  final Duration preparingTimeout;

  const EndpointPolicyConfig({
    this.mode = VoiceEndpointMode.explicitStopOnly,
    this.initialSpeechTimeout = const Duration(seconds: 8),
    this.minimumSpeechDuration = const Duration(milliseconds: 400),
    this.normalTrailingSilence = const Duration(milliseconds: 2000),
    this.incompleteClauseSilence = const Duration(milliseconds: 3200),
    this.maxUtteranceDuration = const Duration(seconds: 45),
    this.finalizingTimeout = const Duration(milliseconds: 2200),
    this.preparingTimeout = const Duration(milliseconds: 4000),
  });

  EndpointPolicyConfig copyWith({
    VoiceEndpointMode? mode,
    Duration? initialSpeechTimeout,
    Duration? minimumSpeechDuration,
    Duration? normalTrailingSilence,
    Duration? incompleteClauseSilence,
    Duration? maxUtteranceDuration,
    Duration? finalizingTimeout,
    Duration? preparingTimeout,
  }) {
    return EndpointPolicyConfig(
      mode: mode ?? this.mode,
      initialSpeechTimeout: initialSpeechTimeout ?? this.initialSpeechTimeout,
      minimumSpeechDuration:
          minimumSpeechDuration ?? this.minimumSpeechDuration,
      normalTrailingSilence:
          normalTrailingSilence ?? this.normalTrailingSilence,
      incompleteClauseSilence:
          incompleteClauseSilence ?? this.incompleteClauseSilence,
      maxUtteranceDuration: maxUtteranceDuration ?? this.maxUtteranceDuration,
      finalizingTimeout: finalizingTimeout ?? this.finalizingTimeout,
      preparingTimeout: preparingTimeout ?? this.preparingTimeout,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    mode,
    initialSpeechTimeout,
    minimumSpeechDuration,
    normalTrailingSilence,
    incompleteClauseSilence,
    maxUtteranceDuration,
    finalizingTimeout,
    preparingTimeout,
  ];
}

/// Acoustic-only observations measured on monotonic clock.
class AcousticEndpointSignal extends Equatable {
  final bool hasSpeechStarted;
  final int speechDurationMs;
  final int silenceDurationMs;
  final int utteranceElapsedMs;
  final bool hasActiveRmsOrVad;

  const AcousticEndpointSignal({
    required this.hasSpeechStarted,
    required this.speechDurationMs,
    required this.silenceDurationMs,
    required this.utteranceElapsedMs,
    required this.hasActiveRmsOrVad,
  });

  @override
  List<Object?> get props => <Object?>[
    hasSpeechStarted,
    speechDurationMs,
    silenceDurationMs,
    utteranceElapsedMs,
    hasActiveRmsOrVad,
  ];
}

/// Advisory-only semantic completeness hint from Vietnamese utterance parser.
class SemanticCompletenessHint extends Equatable {
  final bool hasTranscript;
  final bool hasActionableIntent;
  final bool hasDanglingConnector;
  final bool endsWithBareNumber;

  const SemanticCompletenessHint({
    required this.hasTranscript,
    required this.hasActionableIntent,
    required this.hasDanglingConnector,
    required this.endsWithBareNumber,
  });

  @override
  List<Object?> get props => <Object?>[
    hasTranscript,
    hasActionableIntent,
    hasDanglingConnector,
    endsWithBareNumber,
  ];
}

enum EndpointDecisionKind {
  continueListening,
  triggerGracefulStop,
  emitSpeechTimeout,
}

class EndpointDecision extends Equatable {
  final EndpointDecisionKind kind;
  final String reason;
  final int? remainingSilenceMs;

  const EndpointDecision({
    required this.kind,
    required this.reason,
    this.remainingSilenceMs,
  });

  @override
  List<Object?> get props => <Object?>[kind, reason, remainingSilenceMs];
}

/// Evaluates whether an active listening turn should continue, gracefully stop, or time out.
class EndpointPolicyEvaluator {
  const EndpointPolicyEvaluator();

  EndpointDecision evaluate({
    required EndpointPolicyConfig config,
    required AcousticEndpointSignal acoustic,
    SemanticCompletenessHint? semanticHint,
  }) {
    final maxMs = config.maxUtteranceDuration.inMilliseconds;
    if (acoustic.utteranceElapsedMs >= maxMs) {
      return const EndpointDecision(
        kind: EndpointDecisionKind.triggerGracefulStop,
        reason: 'max_utterance_duration',
      );
    }

    // In explicitStopOnly mode, NEVER auto-stop based on semantic hints or trailing silence.
    if (config.mode == VoiceEndpointMode.explicitStopOnly) {
      return const EndpointDecision(
        kind: EndpointDecisionKind.continueListening,
        reason: 'explicit_stop_only',
      );
    }

    final hasTranscript = semanticHint?.hasTranscript ?? false;
    if (!acoustic.hasSpeechStarted && !hasTranscript) {
      if (acoustic.utteranceElapsedMs >=
          config.initialSpeechTimeout.inMilliseconds) {
        return const EndpointDecision(
          kind: EndpointDecisionKind.emitSpeechTimeout,
          reason: 'initial_speech_timeout',
        );
      }
      return EndpointDecision(
        kind: EndpointDecisionKind.continueListening,
        reason: 'awaiting_initial_speech',
        remainingSilenceMs:
            config.initialSpeechTimeout.inMilliseconds -
            acoustic.utteranceElapsedMs,
      );
    }

    final minSpeechMs = config.minimumSpeechDuration.inMilliseconds;
    if (acoustic.speechDurationMs < minSpeechMs && !hasTranscript) {
      return const EndpointDecision(
        kind: EndpointDecisionKind.continueListening,
        reason: 'below_minimum_speech_duration',
      );
    }

    final isIncomplete =
        (semanticHint?.hasDanglingConnector ?? false) ||
        (semanticHint?.endsWithBareNumber ?? false);

    final requiredSilenceMs = isIncomplete
        ? config.incompleteClauseSilence.inMilliseconds
        : config.normalTrailingSilence.inMilliseconds;

    if (acoustic.silenceDurationMs >= requiredSilenceMs) {
      return EndpointDecision(
        kind: EndpointDecisionKind.triggerGracefulStop,
        reason: isIncomplete
            ? 'incomplete_clause_silence_elapsed'
            : 'trailing_silence_elapsed',
      );
    }

    return EndpointDecision(
      kind: EndpointDecisionKind.continueListening,
      reason: isIncomplete ? 'waiting_incomplete_clause' : 'waiting_silence',
      remainingSilenceMs: requiredSilenceMs - acoustic.silenceDurationMs,
    );
  }
}
