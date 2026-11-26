import 'dart:async';

import 'package:equatable/equatable.dart';

import '../entities/voice_engine_capability.dart';
import '../entities/voice_event.dart';
import '../entities/voice_session.dart';
import '../entities/voice_transcript.dart';
import '../repositories/local_asr_model_repository.dart';
import '../repositories/voice_capability_repository.dart';
import 'endpoint_policy.dart';
import 'engine_selection_policy.dart';
import 'monotonic_clock.dart';
import 'speech_engine_adapter.dart';
import 'transcript_manager.dart';
import 'voice_activity_detector.dart';
import 'voice_diagnostics.dart';

/// Unified state snapshot emitted by [VoiceSessionCoordinator] toward Presentation BLoC.
class VoiceSessionStateSnapshot extends Equatable {
  final VoiceSession session;
  final VoiceTranscriptState transcript;
  final VoiceWaveformSample waveform;
  final VoiceDiagnosticsReport diagnostics;
  final VoiceRecognitionPreference activePreference;
  final VoiceEndpointMode endpointMode;
  final bool allowOnlineConsent;
  final String? actionableHintVi;
  final bool isCapabilitiesInitialized;

  const VoiceSessionStateSnapshot({
    required this.session,
    required this.transcript,
    required this.waveform,
    required this.diagnostics,
    required this.activePreference,
    required this.endpointMode,
    required this.allowOnlineConsent,
    this.actionableHintVi,
    this.isCapabilitiesInitialized = false,
  });

  VoiceSessionStateSnapshot copyWith({
    VoiceSession? session,
    VoiceTranscriptState? transcript,
    VoiceWaveformSample? waveform,
    VoiceDiagnosticsReport? diagnostics,
    VoiceRecognitionPreference? activePreference,
    VoiceEndpointMode? endpointMode,
    bool? allowOnlineConsent,
    String? actionableHintVi,
    bool clearActionableHint = false,
    bool? isCapabilitiesInitialized,
  }) {
    return VoiceSessionStateSnapshot(
      session: session ?? this.session,
      transcript: transcript ?? this.transcript,
      waveform: waveform ?? this.waveform,
      diagnostics: diagnostics ?? this.diagnostics,
      activePreference: activePreference ?? this.activePreference,
      endpointMode: endpointMode ?? this.endpointMode,
      allowOnlineConsent: allowOnlineConsent ?? this.allowOnlineConsent,
      actionableHintVi: clearActionableHint
          ? null
          : (actionableHintVi ?? this.actionableHintVi),
      isCapabilitiesInitialized:
          isCapabilitiesInitialized ?? this.isCapabilitiesInitialized,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    session,
    transcript,
    waveform,
    diagnostics,
    activePreference,
    endpointMode,
    allowOnlineConsent,
    actionableHintVi,
    isCapabilitiesInitialized,
  ];
}

class VoiceStartResult extends Equatable {
  final bool accepted;
  final String? sessionId;
  final int attemptId;
  final String? rejectionReason;
  final VoiceErrorKind? errorKind;

  const VoiceStartResult({
    required this.accepted,
    this.sessionId,
    this.attemptId = 0,
    this.rejectionReason,
    this.errorKind,
  });

  factory VoiceStartResult.accepted({
    required String sessionId,
    required int attemptId,
  }) {
    return VoiceStartResult(
      accepted: true,
      sessionId: sessionId,
      attemptId: attemptId,
    );
  }

  factory VoiceStartResult.rejected({
    required String reason,
    String? sessionId,
    int attemptId = 0,
    VoiceErrorKind? errorKind,
  }) {
    return VoiceStartResult(
      accepted: false,
      sessionId: sessionId,
      attemptId: attemptId,
      rejectionReason: reason,
      errorKind: errorKind,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    accepted,
    sessionId,
    attemptId,
    rejectionReason,
    errorKind,
  ];
}

/// Single Source of Truth orchestrating mic mutex, 10-state FSM, engine routing,
/// monotonic timeouts, transcript merging, capability memory, and diagnostics.
class VoiceSessionCoordinator {
  static const int _maxTimelineEntries = 60;
  static const Duration _busyRetryDelay = Duration(milliseconds: 200);

  final SpeechEngineRegistry _engineRegistry;
  final VoiceCapabilityRepository _capabilityRepository;
  final LocalAsrModelRepository _modelRepository;
  final MonotonicClock _clock;
  final VoiceTimerFactory _timerFactory;
  EndpointPolicyConfig _endpointConfig;
  final EndpointPolicyEvaluator _endpointEvaluator;
  final EngineSelectionPolicy _engineSelectionPolicy;
  final TranscriptManager _transcriptManager;
  final Future<bool> Function({
    required String sessionId,
    required int attemptId,
  })?
  _permissionChecker;
  final Future<void> Function({
    required String sessionId,
    required int attemptId,
  })?
  _permissionRequester;
  final Future<VoiceEnvironmentSnapshot> Function()? _environmentProvider;
  final Future<Map<String, dynamic>> Function()? _nativeDiagnosticsProvider;
  final SemanticCompletenessHint Function(String text)? _semanticHintBuilder;
  final String Function()? _sessionIdGenerator;

  final StreamController<VoiceSessionStateSnapshot> _snapshotController =
      StreamController<VoiceSessionStateSnapshot>.broadcast();
  final List<StreamSubscription<VoiceEnvelopeEvent>> _eventSubscriptions =
      <StreamSubscription<VoiceEnvelopeEvent>>[];

  late VoiceSessionStateSnapshot _snapshot;
  final List<VoiceTimelineEntry> _timeline = <VoiceTimelineEntry>[];
  List<VoiceEngineId> _candidateEngines = const <VoiceEngineId>[];
  int _candidateIndex = 0;
  VoiceEnvironmentSnapshot? _lastEnvironment;

  bool _isStartInFlight = false;
  bool _disposed = false;
  int _sessionCounter = 0;
  int _generationToken = 0;

  bool _hasReceivedRms = false;
  bool _hasSpeechStarted = false;
  int? _listeningStartedMs;
  int? _speechStartedMs;
  int? _lastAcousticActivityMs;

  VoiceTimerHandle? _preparingTimer;
  VoiceTimerHandle? _finalizingTimer;
  VoiceTimerHandle? _maxUtteranceTimer;
  VoiceTimerHandle? _autoEndpointTimer;
  VoiceTimerHandle? _retryTimer;

  VoiceSessionCoordinator({
    required SpeechEngineRegistry engineRegistry,
    required VoiceCapabilityRepository capabilityRepository,
    required LocalAsrModelRepository modelRepository,
    MonotonicClock? clock,
    VoiceTimerFactory? timerFactory,
    EndpointPolicyConfig endpointConfig = const EndpointPolicyConfig(),
    EndpointPolicyEvaluator endpointEvaluator = const EndpointPolicyEvaluator(),
    EngineSelectionPolicy engineSelectionPolicy = const EngineSelectionPolicy(),
    TranscriptManager? transcriptManager,
    VoiceRecognitionPreference initialPreference =
        VoiceRecognitionPreference.hybridAuto,
    bool initialAllowOnlineConsent = true,
    Future<bool> Function({required String sessionId, required int attemptId})?
    permissionChecker,
    Future<void> Function({required String sessionId, required int attemptId})?
    permissionRequester,
    Future<VoiceEnvironmentSnapshot> Function()? environmentProvider,
    Future<Map<String, dynamic>> Function()? nativeDiagnosticsProvider,
    SemanticCompletenessHint Function(String text)? semanticHintBuilder,
    String Function()? sessionIdGenerator,
  }) : _engineRegistry = engineRegistry,
       _capabilityRepository = capabilityRepository,
       _modelRepository = modelRepository,
       _clock = clock ?? SystemMonotonicClock(),
       _timerFactory = timerFactory ?? const RealVoiceTimerFactory(),
       _endpointConfig = endpointConfig,
       _endpointEvaluator = endpointEvaluator,
       _engineSelectionPolicy = engineSelectionPolicy,
       _transcriptManager = transcriptManager ?? TranscriptManager(),
       _permissionChecker = permissionChecker,
       _permissionRequester = permissionRequester,
       _environmentProvider = environmentProvider,
       _nativeDiagnosticsProvider = nativeDiagnosticsProvider,
       _semanticHintBuilder = semanticHintBuilder,
       _sessionIdGenerator = sessionIdGenerator {
    _snapshot = VoiceSessionStateSnapshot(
      session: VoiceSession.idle(mode: initialPreference),
      transcript: _transcriptManager.state,
      waveform: VoiceWaveformSample.silent(),
      diagnostics: VoiceDiagnosticsReport.empty,
      activePreference: initialPreference,
      endpointMode: _endpointConfig.mode,
      allowOnlineConsent: initialAllowOnlineConsent,
    );

    for (final adapter in _engineRegistry.allAdapters) {
      _eventSubscriptions.add(adapter.events.listen(_handleEnvelopeEvent));
    }
  }

  Stream<VoiceSessionStateSnapshot> get snapshots => _snapshotController.stream;

  VoiceSessionStateSnapshot get currentSnapshot => _snapshot;

  VoiceSession get currentSession => _snapshot.session;

  bool get isDisposed => _disposed;

  Future<void> initializeDiagnostics() async {
    if (_disposed) return;
    await _refreshDiagnosticsData(locale: _snapshot.session.locale);
  }

  Future<VoiceStartResult> startSession({
    required String ownerId,
    required VoiceEntryPoint entryPoint,
    VoiceRecognitionPreference? preference,
    bool clearTranscript = false,
    bool? allowOnlineConsent,
    String locale = 'vi-VN',
  }) async {
    if (_disposed) {
      return VoiceStartResult.rejected(reason: 'coordinator_disposed');
    }
    if (_isStartInFlight || _snapshot.session.phase.blocksNewStart) {
      final busyReason = _snapshot.session.phase == VoiceSessionPhase.finalizing
          ? 'session_finalizing'
          : 'microphone_busy';
      return VoiceStartResult.rejected(
        reason: busyReason,
        sessionId: _snapshot.session.sessionId,
        attemptId: _snapshot.session.attemptId,
      );
    }

    _isStartInFlight = true;
    try {
      final effectivePreference = preference ?? _snapshot.activePreference;
      final effectiveConsent =
          allowOnlineConsent ?? _snapshot.allowOnlineConsent;
      final sessionId = _nextSessionId();
      const attemptId = 1;
      _generationToken += 1;
      final genToken = _generationToken;

      _cancelAllTimers();
      _resetAcousticTrackers();
      _transcriptManager.beginTurn(
        sessionId: sessionId,
        attemptId: attemptId,
        clearExisting: clearTranscript,
      );

      final initialSession = VoiceSession(
        sessionId: sessionId,
        attemptId: attemptId,
        ownerId: ownerId,
        entryPoint: entryPoint,
        mode: effectivePreference,
        phase: VoiceSessionPhase.idle,
        terminalOutcome: VoiceTerminalOutcome.none,
        startedAtMonotonicMs: _clock.elapsedMilliseconds,
        locale: locale,
        generationToken: genToken,
      );
      _updateSession(
        initialSession,
        activePreference: effectivePreference,
        allowOnlineConsent: effectiveConsent,
        clearHint: true,
        emitNow: false,
      );

      if (_permissionChecker != null) {
        _transitionPhase(
          VoiceSessionPhase.requestingPermission,
          isAwaitingExternalActivity: true,
          eventNote: 'permission_check_started',
        );
        final hasPerm = await _permissionChecker(
          sessionId: sessionId,
          attemptId: attemptId,
        );
        if (_isStaleSession(sessionId, attemptId, genToken)) {
          return VoiceStartResult.rejected(
            reason: 'cancelled_during_permission_check',
            sessionId: sessionId,
            attemptId: attemptId,
          );
        }
        if (!hasPerm) {
          _recordTimeline(
            'permissionRequested',
            VoiceSessionPhase.requestingPermission,
          );
          if (_permissionRequester != null) {
            await _permissionRequester(
              sessionId: sessionId,
              attemptId: attemptId,
            );
          }
          return VoiceStartResult.accepted(
            sessionId: sessionId,
            attemptId: attemptId,
          );
        }
      }

      return await _prepareAndLaunch(
        sessionId: sessionId,
        attemptId: attemptId,
        preference: effectivePreference,
        allowOnlineConsent: effectiveConsent,
        locale: locale,
        genToken: genToken,
      );
    } finally {
      _isStartInFlight = false;
    }
  }

  Future<VoiceStartResult> onPermissionResult({
    required String sessionId,
    required int attemptId,
    required bool granted,
    required bool permanentlyDenied,
    required bool isForegroundFocused,
  }) async {
    if (_disposed ||
        sessionId != _snapshot.session.sessionId ||
        attemptId != _snapshot.session.attemptId ||
        _snapshot.session.terminalOutcome.isTerminal ||
        _snapshot.session.phase != VoiceSessionPhase.requestingPermission) {
      return VoiceStartResult.rejected(
        reason: 'stale_permission_callback',
        sessionId: sessionId,
        attemptId: attemptId,
      );
    }

    // VOICE-003: Never start mic when permission returns in background / unfocused state.
    if (!isForegroundFocused) {
      _cancelAllTimers();
      _recordTimeline(
        'permissionUnfocusedCancelled',
        VoiceSessionPhase.cancelled,
        errorKind: VoiceErrorKind.interruptedByBackground,
      );
      _updateSession(
        _snapshot.session.copyWith(
          phase: VoiceSessionPhase.cancelled,
          terminalOutcome: VoiceTerminalOutcome.cancelled,
          isAwaitingExternalActivity: false,
          lastErrorKind: VoiceErrorKind.interruptedByBackground,
          lastErrorCode: 'UNFOCUSED_PERMISSION_CALLBACK',
          lastErrorMessageVi:
              VoiceErrorKind.interruptedByBackground.friendlyMessageVi,
        ),
        waveform: VoiceWaveformSample.silent(
          monotonicTimestampMs: _clock.elapsedMilliseconds,
        ),
        actionableHintVi:
            VoiceErrorKind.interruptedByBackground.friendlyMessageVi,
      );
      return VoiceStartResult.rejected(
        reason: 'unfocused_on_permission_result',
        sessionId: sessionId,
        attemptId: attemptId,
        errorKind: VoiceErrorKind.interruptedByBackground,
      );
    }

    if (!granted) {
      _cancelAllTimers();
      final errKind = permanentlyDenied
          ? VoiceErrorKind.permissionPermanentlyDenied
          : VoiceErrorKind.permissionDenied;
      _recordTimeline(
        'permissionDenied',
        VoiceSessionPhase.error,
        errorKind: errKind,
      );
      _updateSession(
        _snapshot.session.copyWith(
          phase: VoiceSessionPhase.error,
          terminalOutcome: VoiceTerminalOutcome.error,
          isAwaitingExternalActivity: false,
          lastErrorKind: errKind,
          lastErrorCode: permanentlyDenied
              ? 'PERMISSION_PERMANENTLY_DENIED'
              : 'PERMISSION_DENIED',
          lastErrorMessageVi: errKind.friendlyMessageVi,
        ),
        waveform: VoiceWaveformSample.silent(
          monotonicTimestampMs: _clock.elapsedMilliseconds,
        ),
        actionableHintVi: errKind.friendlyMessageVi,
      );
      return VoiceStartResult.rejected(
        reason: 'permission_denied',
        sessionId: sessionId,
        attemptId: attemptId,
        errorKind: errKind,
      );
    }

    _recordTimeline(
      'permissionGranted',
      VoiceSessionPhase.requestingPermission,
    );
    _updateSession(
      _snapshot.session.copyWith(isAwaitingExternalActivity: false),
      emitNow: false,
    );
    return _prepareAndLaunch(
      sessionId: sessionId,
      attemptId: attemptId,
      preference: _snapshot.session.mode,
      allowOnlineConsent: _snapshot.allowOnlineConsent,
      locale: _snapshot.session.locale,
      genToken: _snapshot.session.generationToken,
    );
  }

  Future<bool> stopSession({required String sessionId}) async {
    if (_disposed ||
        sessionId.isEmpty ||
        sessionId != _snapshot.session.sessionId ||
        _snapshot.session.terminalOutcome.isTerminal) {
      return false;
    }

    final phase = _snapshot.session.phase;
    if (phase != VoiceSessionPhase.listening &&
        phase != VoiceSessionPhase.preparing) {
      return false;
    }

    final attemptId = _snapshot.session.attemptId;
    final genToken = _snapshot.session.generationToken;
    final engineId = _snapshot.session.engineId;

    _maxUtteranceTimer?.cancel();
    _autoEndpointTimer?.cancel();
    _preparingTimer?.cancel();

    // Strict FSM: listening -> finalizing (NEVER directly to review).
    _transitionPhase(VoiceSessionPhase.finalizing, eventNote: 'stop_requested');
    _armFinalizingTimer(sessionId, attemptId, genToken);

    if (engineId != null) {
      final adapter = _engineRegistry.adapterFor(engineId);
      if (adapter != null) {
        await adapter.stopSession(sessionId: sessionId, attemptId: attemptId);
      }
    }
    return true;
  }

  Future<bool> cancelSession({
    required String sessionId,
    String? reason,
  }) async {
    if (_disposed ||
        sessionId.isEmpty ||
        sessionId != _snapshot.session.sessionId ||
        _snapshot.session.terminalOutcome.isTerminal) {
      return false;
    }

    _generationToken += 1;
    _cancelAllTimers();

    final attemptId = _snapshot.session.attemptId;
    final engineId = _snapshot.session.engineId;

    _recordTimeline(
      'cancelled',
      VoiceSessionPhase.cancelled,
      engineId: engineId?.wireValue,
      note: reason,
    );
    _updateSession(
      _snapshot.session.copyWith(
        phase: VoiceSessionPhase.cancelled,
        terminalOutcome: VoiceTerminalOutcome.cancelled,
        isAwaitingExternalActivity: false,
        generationToken: _generationToken,
      ),
      waveform: VoiceWaveformSample.silent(
        monotonicTimestampMs: _clock.elapsedMilliseconds,
      ),
      clearHint: true,
    );

    if (engineId != null) {
      final adapter = _engineRegistry.adapterFor(engineId);
      if (adapter != null) {
        await adapter.cancelSession(sessionId: sessionId, attemptId: attemptId);
      }
    }
    return true;
  }

  /// Terminates prior active attempt cleanly, increments attemptId, and starts a new capture.
  Future<VoiceStartResult> retrySession({
    required String ownerId,
    required VoiceEntryPoint entryPoint,
    VoiceRecognitionPreference? preference,
    bool clearTranscript = false,
    bool? allowOnlineConsent,
    String locale = 'vi-VN',
  }) async {
    if (_disposed) {
      return VoiceStartResult.rejected(reason: 'coordinator_disposed');
    }
    if (_snapshot.session.phase == VoiceSessionPhase.finalizing ||
        _snapshot.session.phase == VoiceSessionPhase.submitting) {
      return VoiceStartResult.rejected(
        reason: 'session_finalizing',
        sessionId: _snapshot.session.sessionId,
        attemptId: _snapshot.session.attemptId,
      );
    }

    final previousAttempt = _snapshot.session.attemptId;
    if (_snapshot.session.phase.isActiveCapture &&
        _snapshot.session.sessionId.isNotEmpty) {
      await cancelSession(
        sessionId: _snapshot.session.sessionId,
        reason: 'retry_terminated_previous',
      );
    }

    final effectivePreference = preference ?? _snapshot.activePreference;
    final effectiveConsent = allowOnlineConsent ?? _snapshot.allowOnlineConsent;
    final sessionId = _nextSessionId();
    final nextAttemptId = previousAttempt + 1;
    _generationToken += 1;
    final genToken = _generationToken;

    _isStartInFlight = true;
    try {
      _cancelAllTimers();
      _resetAcousticTrackers();
      _transcriptManager.beginTurn(
        sessionId: sessionId,
        attemptId: nextAttemptId,
        clearExisting: clearTranscript,
      );

      final retrySession = VoiceSession(
        sessionId: sessionId,
        attemptId: nextAttemptId,
        ownerId: ownerId,
        entryPoint: entryPoint,
        mode: effectivePreference,
        phase: VoiceSessionPhase.idle,
        terminalOutcome: VoiceTerminalOutcome.none,
        startedAtMonotonicMs: _clock.elapsedMilliseconds,
        locale: locale,
        generationToken: genToken,
      );
      _updateSession(
        retrySession,
        activePreference: effectivePreference,
        allowOnlineConsent: effectiveConsent,
        clearHint: true,
        emitNow: false,
      );

      return await _prepareAndLaunch(
        sessionId: sessionId,
        attemptId: nextAttemptId,
        preference: effectivePreference,
        allowOnlineConsent: effectiveConsent,
        locale: locale,
        genToken: genToken,
      );
    } finally {
      _isStartInFlight = false;
    }
  }

  /// Handles background/foreground transitions without killing OS permission/dialog flows.
  Future<void> onAppLifecycleChanged(bool isBackgrounded) async {
    if (_disposed || !isBackgrounded) {
      // Never auto-restart the microphone when returning to foreground.
      return;
    }
    final current = _snapshot.session;
    if (current.isAwaitingExternalActivity) {
      return;
    }
    if (!current.phase.isActiveCapture || current.terminalOutcome.isTerminal) {
      return;
    }

    _generationToken += 1;
    _cancelAllTimers();
    final sessionId = current.sessionId;
    final attemptId = current.attemptId;
    final engineId = current.engineId;

    if (engineId != null) {
      final adapter = _engineRegistry.adapterFor(engineId);
      if (adapter != null) {
        await adapter.cancelSession(sessionId: sessionId, attemptId: attemptId);
      }
    }

    if (_transcriptManager.currentPartial.trim().isNotEmpty) {
      _transcriptManager.onFinal(
        sessionId: sessionId,
        attemptId: attemptId,
        sequenceNumber: 0,
        text: '',
        rescuePartialOnEmptyFinal: true,
      );
    }

    if (_transcriptManager.effectiveText.trim().isNotEmpty) {
      if (current.phase == VoiceSessionPhase.listening ||
          current.phase == VoiceSessionPhase.preparing) {
        _transitionPhase(
          VoiceSessionPhase.finalizing,
          eventNote: 'background_preserve_transcript',
          emitNow: false,
        );
      }
      _recordTimeline(
        'interruptedByBackgroundPreserved',
        VoiceSessionPhase.review,
        errorKind: VoiceErrorKind.interruptedByBackground,
      );
      _updateSession(
        _snapshot.session.copyWith(
          phase: VoiceSessionPhase.review,
          terminalOutcome: VoiceTerminalOutcome.finalResult,
          isAwaitingExternalActivity: false,
          lastErrorKind: VoiceErrorKind.interruptedByBackground,
          lastErrorCode: 'INTERRUPTED_BY_BACKGROUND',
          lastErrorMessageVi:
              VoiceErrorKind.interruptedByBackground.friendlyMessageVi,
          generationToken: _generationToken,
        ),
        waveform: VoiceWaveformSample.silent(
          monotonicTimestampMs: _clock.elapsedMilliseconds,
        ),
        actionableHintVi:
            VoiceErrorKind.interruptedByBackground.friendlyMessageVi,
      );
      return;
    }

    _recordTimeline(
      'interruptedByBackgroundCancelled',
      VoiceSessionPhase.cancelled,
      errorKind: VoiceErrorKind.interruptedByBackground,
    );
    _updateSession(
      _snapshot.session.copyWith(
        phase: VoiceSessionPhase.cancelled,
        terminalOutcome: VoiceTerminalOutcome.cancelled,
        isAwaitingExternalActivity: false,
        lastErrorKind: VoiceErrorKind.interruptedByBackground,
        lastErrorCode: 'INTERRUPTED_BY_BACKGROUND',
        lastErrorMessageVi:
            VoiceErrorKind.interruptedByBackground.friendlyMessageVi,
        generationToken: _generationToken,
      ),
      waveform: VoiceWaveformSample.silent(
        monotonicTimestampMs: _clock.elapsedMilliseconds,
      ),
      actionableHintVi:
          VoiceErrorKind.interruptedByBackground.friendlyMessageVi,
    );
  }

  /// Clears active sessions and in-memory transcript when switching accounts or signing out.
  Future<void> onUserAccountChangedOrSignedOut() async {
    if (_disposed) return;
    final current = _snapshot.session;
    if (current.phase.isActiveCapture &&
        current.sessionId.isNotEmpty &&
        !current.terminalOutcome.isTerminal) {
      await cancelSession(
        sessionId: current.sessionId,
        reason: 'account_changed_or_signed_out',
      );
    }
    _generationToken += 1;
    _cancelAllTimers();
    _resetAcousticTrackers();
    _transcriptManager.clear();
    _timeline.clear();
    _updateSession(
      VoiceSession.idle(
        mode: _snapshot.activePreference,
        generationToken: _generationToken,
      ),
      waveform: VoiceWaveformSample.silent(
        monotonicTimestampMs: _clock.elapsedMilliseconds,
      ),
      clearHint: true,
    );
  }

  void onUserEditTranscript(String text) {
    if (_disposed || _snapshot.session.phase == VoiceSessionPhase.finalizing) {
      return;
    }
    _transcriptManager.onUserEdit(text);
    _updateSession(_snapshot.session, clearHint: true);
  }

  bool beginSubmitting() {
    if (_disposed || _snapshot.session.phase.blocksConfirm) {
      return false;
    }
    if (_snapshot.session.phase != VoiceSessionPhase.review) {
      return false;
    }
    _transitionPhase(
      VoiceSessionPhase.submitting,
      eventNote: 'confirm_submitting',
    );
    return true;
  }

  bool markCompleted() {
    if (_disposed || _snapshot.session.phase != VoiceSessionPhase.submitting) {
      return false;
    }
    _recordTimeline('completed', VoiceSessionPhase.completed);
    _updateSession(
      _snapshot.session.copyWith(
        phase: VoiceSessionPhase.completed,
        terminalOutcome: VoiceTerminalOutcome.completed,
      ),
      waveform: VoiceWaveformSample.silent(
        monotonicTimestampMs: _clock.elapsedMilliseconds,
      ),
      clearHint: true,
    );
    return true;
  }

  bool revertSubmitToReview({String? errorMessageVi}) {
    if (_disposed || _snapshot.session.phase != VoiceSessionPhase.submitting) {
      return false;
    }
    _transitionPhase(
      VoiceSessionPhase.review,
      eventNote: 'submit_reverted_to_review',
      emitNow: false,
    );
    _updateSession(_snapshot.session, actionableHintVi: errorMessageVi);
    return true;
  }

  Future<void> resetToIdle({bool clearTranscript = true}) async {
    if (_disposed) return;
    if (_snapshot.session.phase.isActiveCapture &&
        _snapshot.session.sessionId.isNotEmpty &&
        !_snapshot.session.terminalOutcome.isTerminal) {
      await cancelSession(
        sessionId: _snapshot.session.sessionId,
        reason: 'reset_to_idle',
      );
    }
    _generationToken += 1;
    _cancelAllTimers();
    _resetAcousticTrackers();
    if (clearTranscript) {
      _transcriptManager.clear();
    }
    _updateSession(
      VoiceSession.idle(
        mode: _snapshot.activePreference,
        generationToken: _generationToken,
      ),
      waveform: VoiceWaveformSample.silent(
        monotonicTimestampMs: _clock.elapsedMilliseconds,
      ),
      clearHint: true,
    );
  }

  void setEndpointMode(VoiceEndpointMode mode) {
    if (_disposed) return;
    _endpointConfig = _endpointConfig.copyWith(mode: mode);
    _autoEndpointTimer?.cancel();
    _snapshot = _snapshot.copyWith(endpointMode: mode);
    _emitSnapshot();
  }

  void setPreference(VoiceRecognitionPreference preference) {
    if (_disposed) return;
    _snapshot = _snapshot.copyWith(
      activePreference: preference,
      session: _snapshot.session.phase == VoiceSessionPhase.idle
          ? _snapshot.session.copyWith(mode: preference)
          : _snapshot.session,
    );
    _emitSnapshot();
  }

  void setAllowOnlineConsent(bool allowed) {
    if (_disposed) return;
    _snapshot = _snapshot.copyWith(allowOnlineConsent: allowed);
    _emitSnapshot();
  }

  Future<void> resetCapabilities() async {
    if (_disposed) return;
    await _capabilityRepository.clearAll();
    _recordTimeline('capabilitiesReset', _snapshot.session.phase);
    await _refreshDiagnosticsData(locale: _snapshot.session.locale);
  }

  Future<void> refreshDiagnostics() async {
    if (_disposed) return;
    await _refreshDiagnosticsData(locale: _snapshot.session.locale);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generationToken += 1;
    _cancelAllTimers();
    for (final sub in _eventSubscriptions) {
      unawaited(sub.cancel());
    }
    _eventSubscriptions.clear();
    if (!_snapshotController.isClosed) {
      unawaited(_snapshotController.close());
    }
  }

  Future<VoiceStartResult> _prepareAndLaunch({
    required String sessionId,
    required int attemptId,
    required VoiceRecognitionPreference preference,
    required bool allowOnlineConsent,
    required String locale,
    required int genToken,
  }) async {
    _transitionPhase(
      VoiceSessionPhase.preparing,
      isAwaitingExternalActivity: false,
      eventNote: 'preparing_engine_selection',
    );

    final environment = await _resolveEnvironment(locale);
    final caps = await _capabilityRepository.loadEntries();
    final hasLocalModel = await _modelRepository.hasVerifiedInstalledAsrModel();

    if (_isStaleSession(sessionId, attemptId, genToken)) {
      return VoiceStartResult.rejected(
        reason: 'cancelled_during_prepare',
        sessionId: sessionId,
        attemptId: attemptId,
      );
    }

    _lastEnvironment = environment;
    final selection = _engineSelectionPolicy.selectEngines(
      preference: preference,
      environment: environment,
      capabilityEntries: caps,
      allowOnlineConsent: allowOnlineConsent,
      localModelInstalled: hasLocalModel,
    );

    if (selection.isBlocked || selection.orderedEngines.isEmpty) {
      final errKind =
          selection.blockedErrorKind ?? VoiceErrorKind.noEngineAvailable;
      final msg = selection.blockedMessageVi ?? errKind.friendlyMessageVi;
      _recordTimeline(
        'selectionBlocked',
        VoiceSessionPhase.error,
        errorKind: errKind,
      );
      _updateSession(
        _snapshot.session.copyWith(
          phase: VoiceSessionPhase.error,
          terminalOutcome: VoiceTerminalOutcome.error,
          isAwaitingExternalActivity: false,
          lastErrorKind: errKind,
          lastErrorCode: errKind.name.toUpperCase(),
          lastErrorMessageVi: msg,
          audioRoute: environment.audioRoute,
        ),
        waveform: VoiceWaveformSample.silent(
          monotonicTimestampMs: _clock.elapsedMilliseconds,
        ),
        actionableHintVi: msg,
      );
      return VoiceStartResult.rejected(
        reason: msg,
        sessionId: sessionId,
        attemptId: attemptId,
        errorKind: errKind,
      );
    }

    _candidateEngines = selection.orderedEngines;
    _candidateIndex = 0;
    _updateSession(
      _snapshot.session.copyWith(audioRoute: environment.audioRoute),
      emitNow: false,
    );

    return _launchCandidateAttempt(
      sessionId: sessionId,
      attemptId: attemptId,
      genToken: genToken,
    );
  }

  Future<VoiceStartResult> _launchCandidateAttempt({
    required String sessionId,
    required int attemptId,
    required int genToken,
  }) async {
    if (_isStaleSession(sessionId, attemptId, genToken)) {
      return VoiceStartResult.rejected(
        reason: 'stale_before_launch',
        sessionId: sessionId,
        attemptId: attemptId,
      );
    }

    if (_candidateIndex >= _candidateEngines.length) {
      final errKind = VoiceErrorKind.noEngineAvailable;
      _finalizeTerminalError(
        errorKind: errKind,
        errorCode: 'NO_ENGINE_AVAILABLE',
        errorMessageVi: errKind.friendlyMessageVi,
      );
      return VoiceStartResult.rejected(
        reason: 'no_remaining_candidates',
        sessionId: sessionId,
        attemptId: attemptId,
        errorKind: errKind,
      );
    }

    final engineId = _candidateEngines[_candidateIndex];
    final adapter = _engineRegistry.adapterFor(engineId);
    if (adapter == null) {
      _candidateIndex += 1;
      return _launchCandidateAttempt(
        sessionId: sessionId,
        attemptId: attemptId,
        genToken: genToken,
      );
    }

    final strictOffline = _snapshot.session.mode.requiresStrictOffline;
    if (strictOffline && !adapter.isStrictlyOffline) {
      _candidateIndex += 1;
      return _launchCandidateAttempt(
        sessionId: sessionId,
        attemptId: attemptId,
        genToken: genToken,
      );
    }

    _updateSession(
      _snapshot.session.copyWith(
        engineId: engineId,
        isAwaitingExternalActivity: engineId == VoiceEngineId.systemDialog,
        lastProcessedSequence: 0,
      ),
      emitNow: false,
    );
    _recordTimeline(
      'launchAttempt',
      _snapshot.session.phase,
      engineId: engineId.wireValue,
    );

    _armPreparingTimer(sessionId, attemptId, genToken);

    final outcome = await adapter.startSession(
      sessionId: sessionId,
      attemptId: attemptId,
      ownerId: _snapshot.session.ownerId,
      locale: _snapshot.session.locale,
      strictOffline: strictOffline,
    );

    if (_isStaleSession(sessionId, attemptId, genToken)) {
      await adapter.cancelSession(sessionId: sessionId, attemptId: attemptId);
      return VoiceStartResult.rejected(
        reason: 'cancelled_during_engine_start',
        sessionId: sessionId,
        attemptId: attemptId,
      );
    }

    if (!outcome.started) {
      _preparingTimer?.cancel();
      await _handleAttemptFailure(
        errorKind: outcome.errorKind ?? VoiceErrorKind.unknown,
        errorCode: outcome.errorCode,
        errorMessageVi: outcome.errorMessageVi,
      );
      if (_snapshot.session.terminalOutcome == VoiceTerminalOutcome.error) {
        return VoiceStartResult.rejected(
          reason: _snapshot.session.lastErrorMessageVi ?? 'engine_start_failed',
          sessionId: sessionId,
          attemptId: attemptId,
          errorKind: _snapshot.session.lastErrorKind,
        );
      }
      return VoiceStartResult.accepted(
        sessionId: sessionId,
        attemptId: _snapshot.session.attemptId,
      );
    }

    if (outcome.awaitsExternalActivity) {
      _preparingTimer?.cancel();
      if (engineId != VoiceEngineId.systemDialog &&
          _snapshot.session.phase == VoiceSessionPhase.preparing) {
        _transitionPhase(
          VoiceSessionPhase.requestingPermission,
          isAwaitingExternalActivity: true,
          engineId: engineId.wireValue,
          eventNote: 'awaiting_runtime_permission',
        );
      } else if (!_snapshot.session.isAwaitingExternalActivity) {
        _updateSession(
          _snapshot.session.copyWith(isAwaitingExternalActivity: true),
        );
      }
    }

    return VoiceStartResult.accepted(
      sessionId: sessionId,
      attemptId: attemptId,
    );
  }

  void _handleEnvelopeEvent(VoiceEnvelopeEvent event) {
    if (_disposed) return;

    final current = _snapshot.session;
    if (current.sessionId.isEmpty ||
        event.sessionId != current.sessionId ||
        event.attemptId != current.attemptId ||
        current.terminalOutcome.isTerminal) {
      return;
    }

    if (event.sequenceNumber > 0 &&
        event.sequenceNumber <= current.lastProcessedSequence) {
      return;
    }

    final nextSeq = event.sequenceNumber > 0
        ? event.sequenceNumber
        : current.lastProcessedSequence;
    if (nextSeq != current.lastProcessedSequence) {
      _updateSession(
        current.copyWith(lastProcessedSequence: nextSeq),
        emitNow: false,
      );
    }

    final coordinatorNowMs = _clock.elapsedMilliseconds;

    switch (event.eventType) {
      case VoiceEnvelopeEventType.permissionRequested:
        _preparingTimer?.cancel();
        _recordTimeline(
          'permissionRequested',
          _snapshot.session.phase,
          engineId: event.engineId,
        );
        if (_snapshot.session.phase == VoiceSessionPhase.idle ||
            _snapshot.session.phase == VoiceSessionPhase.preparing) {
          _transitionPhase(
            VoiceSessionPhase.requestingPermission,
            isAwaitingExternalActivity: true,
            engineId: event.engineId,
          );
        } else {
          _updateSession(
            _snapshot.session.copyWith(isAwaitingExternalActivity: true),
          );
        }
      case VoiceEnvelopeEventType.permissionGranted:
        _recordTimeline(
          'permissionGranted',
          _snapshot.session.phase,
          engineId: event.engineId,
        );
        _updateSession(
          _snapshot.session.copyWith(isAwaitingExternalActivity: false),
          emitNow: false,
        );
        if (_snapshot.session.phase == VoiceSessionPhase.requestingPermission) {
          _transitionPhase(
            VoiceSessionPhase.preparing,
            isAwaitingExternalActivity: false,
            engineId: event.engineId,
          );
          _armPreparingTimer(
            _snapshot.session.sessionId,
            _snapshot.session.attemptId,
            _snapshot.session.generationToken,
          );
        } else {
          _emitSnapshot();
        }
      case VoiceEnvelopeEventType.permissionDenied:
        unawaited(
          _handleAttemptFailure(
            errorKind: event.errorKind ?? VoiceErrorKind.permissionDenied,
            errorCode: event.errorCode ?? 'PERMISSION_DENIED',
            errorMessageVi: event.errorMessageVi,
          ),
        );
      case VoiceEnvelopeEventType.preparing:
        _recordTimeline(
          'preparing',
          _snapshot.session.phase,
          engineId: event.engineId,
        );
        if (_snapshot.session.phase == VoiceSessionPhase.idle ||
            _snapshot.session.phase == VoiceSessionPhase.requestingPermission) {
          final wasAwaitingPerm =
              _snapshot.session.phase == VoiceSessionPhase.requestingPermission;
          _transitionPhase(
            VoiceSessionPhase.preparing,
            isAwaitingExternalActivity: false,
            engineId: event.engineId,
          );
          if (wasAwaitingPerm) {
            _armPreparingTimer(
              _snapshot.session.sessionId,
              _snapshot.session.attemptId,
              _snapshot.session.generationToken,
            );
          }
        }
      case VoiceEnvelopeEventType.readyForSpeech:
      case VoiceEnvelopeEventType.beginningOfSpeech:
        _preparingTimer?.cancel();
        final nowMs = coordinatorNowMs;
        final isBeginning =
            event.eventType == VoiceEnvelopeEventType.beginningOfSpeech;
        if (isBeginning) {
          _hasSpeechStarted = true;
          _speechStartedMs ??= nowMs;
          _lastAcousticActivityMs = nowMs;
        }
        _listeningStartedMs ??= nowMs;
        final readyAt = _snapshot.session.readyAtMonotonicMs ?? nowMs;
        final nextWaveform = _hasReceivedRms
            ? _snapshot.waveform
            : VoiceWaveformSample.indeterminateActive(
                monotonicTimestampMs: nowMs,
              );
        if (_snapshot.session.phase == VoiceSessionPhase.preparing ||
            _snapshot.session.phase == VoiceSessionPhase.requestingPermission) {
          _updateSession(
            _snapshot.session.copyWith(
              phase: VoiceSessionPhase.listening,
              isAwaitingExternalActivity: false,
              readyAtMonotonicMs: readyAt,
            ),
            waveform: nextWaveform,
            emitNow: false,
          );
          _recordTimeline(
            event.eventType.name,
            VoiceSessionPhase.listening,
            engineId: event.engineId,
          );
          _armMaxUtteranceTimer(
            _snapshot.session.sessionId,
            _snapshot.session.attemptId,
            _snapshot.session.generationToken,
          );
          _scheduleAutoEndpointCheckIfNeeded();
          _emitSnapshot();
        } else {
          _updateSession(
            _snapshot.session.copyWith(readyAtMonotonicMs: readyAt),
            waveform: nextWaveform,
          );
          _scheduleAutoEndpointCheckIfNeeded();
        }
      case VoiceEnvelopeEventType.rmsChanged:
      case VoiceEnvelopeEventType.pcmEnergy:
        final rmsDb = event.rmsDb;
        if (rmsDb != null) {
          _hasReceivedRms = true;
          final sample =
              event.eventType == VoiceEnvelopeEventType.pcmEnergy ||
                  event.isRealPcmEnergy
              ? VoiceWaveformSample.fromPcmEnergy(
                  rmsDb,
                  monotonicTimestampMs: coordinatorNowMs,
                )
              : VoiceWaveformSample.fromRmsDb(
                  rmsDb,
                  monotonicTimestampMs: coordinatorNowMs,
                );
          final speechThreshold =
              event.eventType == VoiceEnvelopeEventType.pcmEnergy ||
                  event.isRealPcmEnergy
              ? -38.0
              : 3.0;
          if (rmsDb >= speechThreshold) {
            _hasSpeechStarted = true;
            _speechStartedMs ??= coordinatorNowMs;
            _lastAcousticActivityMs = coordinatorNowMs;
          }
          _updateSession(_snapshot.session, waveform: sample);
          _scheduleAutoEndpointCheckIfNeeded();
        }
      case VoiceEnvelopeEventType.partialResult:
        _preparingTimer?.cancel();
        final nowMs = coordinatorNowMs;
        _listeningStartedMs ??= nowMs;
        _hasSpeechStarted = true;
        _speechStartedMs ??= nowMs;
        _lastAcousticActivityMs = nowMs;

        if (_snapshot.session.phase == VoiceSessionPhase.preparing ||
            _snapshot.session.phase == VoiceSessionPhase.requestingPermission) {
          _updateSession(
            _snapshot.session.copyWith(
              phase: VoiceSessionPhase.listening,
              isAwaitingExternalActivity: false,
              readyAtMonotonicMs: _snapshot.session.readyAtMonotonicMs ?? nowMs,
            ),
            emitNow: false,
          );
          _armMaxUtteranceTimer(
            _snapshot.session.sessionId,
            _snapshot.session.attemptId,
            _snapshot.session.generationToken,
          );
        }

        // Strict rule: do NOT mutate transcript prefix via partial while finalizing!
        if (_snapshot.session.phase == VoiceSessionPhase.listening) {
          final updated = _transcriptManager.onPartial(
            sessionId: event.sessionId,
            attemptId: event.attemptId,
            sequenceNumber: event.sequenceNumber,
            text: event.text ?? '',
          );
          if (updated) {
            final firstPartial =
                _snapshot.session.firstPartialAtMonotonicMs ?? nowMs;
            _recordTimeline(
              'partialResult',
              VoiceSessionPhase.listening,
              engineId: event.engineId,
            );
            _updateSession(
              _snapshot.session.copyWith(
                firstPartialAtMonotonicMs: firstPartial,
              ),
            );
            _scheduleAutoEndpointCheckIfNeeded();
          }
        }
      case VoiceEnvelopeEventType.endOfSpeech:
        if (_snapshot.session.phase == VoiceSessionPhase.listening) {
          _maxUtteranceTimer?.cancel();
          _autoEndpointTimer?.cancel();
          _transitionPhase(
            VoiceSessionPhase.finalizing,
            engineId: event.engineId,
            eventNote: 'end_of_speech',
          );
          _armFinalizingTimer(
            _snapshot.session.sessionId,
            _snapshot.session.attemptId,
            _snapshot.session.generationToken,
          );
        }
      case VoiceEnvelopeEventType.finalResult:
        _handleFinalResultEvent(event);
      case VoiceEnvelopeEventType.error:
        unawaited(
          _handleAttemptFailure(
            errorKind:
                event.errorKind ??
                VoiceErrorKind.fromNativeCode(event.errorCode),
            errorCode: event.errorCode,
            errorMessageVi: event.errorMessageVi,
          ),
        );
      case VoiceEnvelopeEventType.cancelled:
        _cancelAllTimers();
        _recordTimeline(
          'cancelledByEngine',
          VoiceSessionPhase.cancelled,
          engineId: event.engineId,
        );
        _updateSession(
          _snapshot.session.copyWith(
            phase: VoiceSessionPhase.cancelled,
            terminalOutcome: VoiceTerminalOutcome.cancelled,
            isAwaitingExternalActivity: false,
          ),
          waveform: VoiceWaveformSample.silent(
            monotonicTimestampMs: coordinatorNowMs,
          ),
        );
      case VoiceEnvelopeEventType.audioFocusLost:
        unawaited(
          _handleAttemptFailure(
            errorKind: VoiceErrorKind.audioFocusLost,
            errorCode: event.errorCode ?? 'AUDIO_FOCUS_LOST',
            errorMessageVi: event.errorMessageVi,
          ),
        );
      case VoiceEnvelopeEventType.audioRouteChanged:
        final nextRoute = VoiceAudioRoute.fromWireValue(event.audioRoute);
        _recordTimeline(
          'audioRouteChanged',
          _snapshot.session.phase,
          engineId: event.engineId,
          note: nextRoute.wireValue,
        );
        _updateSession(_snapshot.session.copyWith(audioRoute: nextRoute));
      case VoiceEnvelopeEventType.engineSwitched:
        final switched = VoiceEngineId.tryFromWireValue(event.engineId);
        // VOICE-007: Never accept an online engine switch while in strict offline mode.
        if (switched != null &&
            _snapshot.session.mode.requiresStrictOffline &&
            !switched.isStrictlyOffline) {
          return;
        }
        _recordTimeline(
          'engineSwitched',
          _snapshot.session.phase,
          engineId: event.engineId,
        );
        _updateSession(
          _snapshot.session.copyWith(
            engineId: switched ?? _snapshot.session.engineId,
            fallbackCount: _snapshot.session.fallbackCount + 1,
            isAwaitingExternalActivity: switched == VoiceEngineId.systemDialog,
          ),
        );
      case VoiceEnvelopeEventType.diagnosticsUpdated:
        unawaited(_refreshDiagnosticsData(locale: _snapshot.session.locale));
    }
  }

  void _handleFinalResultEvent(VoiceEnvelopeEvent event) {
    _cancelAllTimers();
    final coordinatorNowMs = _clock.elapsedMilliseconds;

    // Enforce strict FSM path through finalizing before entering review/error.
    if (_snapshot.session.phase == VoiceSessionPhase.preparing ||
        _snapshot.session.phase == VoiceSessionPhase.requestingPermission ||
        _snapshot.session.phase == VoiceSessionPhase.listening) {
      _transitionPhase(
        VoiceSessionPhase.finalizing,
        engineId: event.engineId,
        eventNote: 'final_result_transition',
        emitNow: false,
      );
    }

    _transcriptManager.onFinal(
      sessionId: event.sessionId,
      attemptId: event.attemptId,
      sequenceNumber: event.sequenceNumber,
      text: event.text ?? '',
      rescuePartialOnEmptyFinal: true,
    );

    final finalText = _transcriptManager.effectiveText.trim();
    if (finalText.isEmpty) {
      _recordTimeline(
        'finalResultEmpty',
        VoiceSessionPhase.error,
        engineId: event.engineId,
        errorKind: VoiceErrorKind.noMatch,
      );
      _updateSession(
        _snapshot.session.copyWith(
          phase: VoiceSessionPhase.error,
          terminalOutcome: VoiceTerminalOutcome.error,
          finalAtMonotonicMs: coordinatorNowMs,
          isAwaitingExternalActivity: false,
          lastErrorKind: VoiceErrorKind.noMatch,
          lastErrorCode: 'NO_MATCH',
          lastErrorMessageVi: VoiceErrorKind.noMatch.friendlyMessageVi,
        ),
        waveform: VoiceWaveformSample.silent(
          monotonicTimestampMs: coordinatorNowMs,
        ),
        actionableHintVi: VoiceErrorKind.noMatch.friendlyMessageVi,
      );
      return;
    }

    final engineId =
        VoiceEngineId.tryFromWireValue(event.engineId) ??
        _snapshot.session.engineId;
    if (engineId != null && _lastEnvironment != null) {
      unawaited(
        _capabilityRepository.recordSuccess(
          engineId: engineId,
          environment: _lastEnvironment!,
        ),
      );
    }

    _recordTimeline(
      'finalResult',
      VoiceSessionPhase.review,
      engineId: event.engineId,
    );
    _updateSession(
      _snapshot.session.copyWith(
        phase: VoiceSessionPhase.review,
        terminalOutcome: VoiceTerminalOutcome.finalResult,
        finalAtMonotonicMs: coordinatorNowMs,
        isAwaitingExternalActivity: false,
        clearLastError: true,
      ),
      waveform: VoiceWaveformSample.silent(
        monotonicTimestampMs: coordinatorNowMs,
      ),
      clearHint: true,
    );
  }

  Future<void> _handleAttemptFailure({
    required VoiceErrorKind errorKind,
    String? errorCode,
    String? errorMessageVi,
  }) async {
    if (_disposed || _snapshot.session.terminalOutcome.isTerminal) return;

    _preparingTimer?.cancel();
    _finalizingTimer?.cancel();
    _maxUtteranceTimer?.cancel();
    _autoEndpointTimer?.cancel();

    final current = _snapshot.session;
    final engineId = current.engineId;

    if (engineId != null && _lastEnvironment != null) {
      final stillAvailable =
          errorKind != VoiceErrorKind.noEngineAvailable &&
          errorKind != VoiceErrorKind.languageNotSupported &&
          errorKind != VoiceErrorKind.languageUnavailable;
      final stillVn =
          errorKind != VoiceErrorKind.languageNotSupported &&
          errorKind != VoiceErrorKind.languageUnavailable;
      await _capabilityRepository.recordError(
        engineId: engineId,
        environment: _lastEnvironment!,
        errorCode: errorCode ?? errorKind.name.toUpperCase(),
        stillAvailable: stillAvailable,
        stillSupportsVietnamese: stillVn,
      );
      if (_isStaleSession(
        current.sessionId,
        current.attemptId,
        current.generationToken,
      )) {
        return;
      }
    }

    // Rescue captured partial if recognizer erred right during finalizing.
    if (current.phase == VoiceSessionPhase.finalizing &&
        (errorKind == VoiceErrorKind.noMatch ||
            errorKind == VoiceErrorKind.speechTimeout ||
            errorKind == VoiceErrorKind.clientError ||
            errorKind == VoiceErrorKind.serverError) &&
        _transcriptManager.effectiveText.trim().isNotEmpty) {
      _transcriptManager.onFinal(
        sessionId: current.sessionId,
        attemptId: current.attemptId,
        sequenceNumber: 0,
        text: '',
        rescuePartialOnEmptyFinal: true,
      );
      _recordTimeline(
        'finalizingRescuedOnError',
        VoiceSessionPhase.review,
        engineId: engineId?.wireValue,
        errorKind: errorKind,
      );
      _updateSession(
        current.copyWith(
          phase: VoiceSessionPhase.review,
          terminalOutcome: VoiceTerminalOutcome.finalResult,
          finalAtMonotonicMs: _clock.elapsedMilliseconds,
          isAwaitingExternalActivity: false,
        ),
        waveform: VoiceWaveformSample.silent(
          monotonicTimestampMs: _clock.elapsedMilliseconds,
        ),
        clearHint: true,
      );
      return;
    }

    // Bounded transient retry: ONLY `recognizerBusy` and MAX 1 retry.
    if (errorKind.isRetryableTransient && current.retryCount < 1) {
      if (engineId != null) {
        final adapter = _engineRegistry.adapterFor(engineId);
        await adapter?.cancelSession(
          sessionId: current.sessionId,
          attemptId: current.attemptId,
        );
      }
      if (_isStaleSession(
        current.sessionId,
        current.attemptId,
        current.generationToken,
      )) {
        return;
      }
      final nextAttemptId = current.attemptId + 1;
      _transcriptManager.beginTurn(
        sessionId: current.sessionId,
        attemptId: nextAttemptId,
        clearExisting: false,
      );
      if (current.phase == VoiceSessionPhase.listening) {
        _transitionPhase(
          VoiceSessionPhase.error,
          engineId: engineId?.wireValue,
          errorKind: errorKind,
          emitNow: false,
        );
      }
      _updateSession(
        _snapshot.session.copyWith(
          attemptId: nextAttemptId,
          phase: VoiceSessionPhase.preparing,
          retryCount: current.retryCount + 1,
          lastProcessedSequence: 0,
          isAwaitingExternalActivity: false,
          lastErrorKind: errorKind,
          lastErrorCode: errorCode,
        ),
        actionableHintVi: errorKind.friendlyMessageVi,
      );
      _recordTimeline(
        'retryScheduled',
        VoiceSessionPhase.preparing,
        engineId: engineId?.wireValue,
        errorKind: errorKind,
      );
      _armRetryTimer(current.sessionId, nextAttemptId, current.generationToken);
      return;
    }

    final allowsFallback =
        errorKind != VoiceErrorKind.permissionDenied &&
        errorKind != VoiceErrorKind.permissionPermanentlyDenied &&
        errorKind != VoiceErrorKind.microphoneInUse &&
        errorKind != VoiceErrorKind.noMatch &&
        errorKind != VoiceErrorKind.speechTimeout &&
        errorKind != VoiceErrorKind.audioFocusLost &&
        errorKind != VoiceErrorKind.interruptedByBackground;

    if (allowsFallback && _candidateIndex + 1 < _candidateEngines.length) {
      final nextEngine = _candidateEngines[_candidateIndex + 1];
      final strictOffline = current.mode.requiresStrictOffline;
      if (!strictOffline || nextEngine.isStrictlyOffline) {
        if (engineId != null) {
          final adapter = _engineRegistry.adapterFor(engineId);
          await adapter?.cancelSession(
            sessionId: current.sessionId,
            attemptId: current.attemptId,
          );
        }
        if (_isStaleSession(
          current.sessionId,
          current.attemptId,
          current.generationToken,
        )) {
          return;
        }
        _candidateIndex += 1;
        final nextAttemptId = current.attemptId + 1;
        _transcriptManager.beginTurn(
          sessionId: current.sessionId,
          attemptId: nextAttemptId,
          clearExisting: false,
        );
        if (current.phase == VoiceSessionPhase.listening) {
          _transitionPhase(
            VoiceSessionPhase.error,
            engineId: engineId?.wireValue,
            errorKind: errorKind,
            emitNow: false,
          );
        }
        _updateSession(
          _snapshot.session.copyWith(
            attemptId: nextAttemptId,
            phase: VoiceSessionPhase.preparing,
            fallbackCount: current.fallbackCount + 1,
            lastProcessedSequence: 0,
            isAwaitingExternalActivity: false,
          ),
          emitNow: false,
        );
        _recordTimeline(
          'fallbackEngine',
          VoiceSessionPhase.preparing,
          engineId: nextEngine.wireValue,
          errorKind: errorKind,
        );
        await _launchCandidateAttempt(
          sessionId: current.sessionId,
          attemptId: nextAttemptId,
          genToken: current.generationToken,
        );
        return;
      }
    }

    _finalizeTerminalError(
      errorKind: errorKind,
      errorCode: errorCode,
      errorMessageVi: errorMessageVi,
    );
  }

  void _finalizeTerminalError({
    required VoiceErrorKind errorKind,
    String? errorCode,
    String? errorMessageVi,
  }) {
    final current = _snapshot.session;
    if (current.terminalOutcome.isTerminal) return;

    final resolvedMessage =
        (errorMessageVi != null && errorMessageVi.trim().isNotEmpty)
        ? errorMessageVi.trim()
        : errorKind.friendlyMessageVi;

    _cancelAllTimers();
    _recordTimeline(
      'terminalError',
      VoiceSessionPhase.error,
      engineId: current.engineId?.wireValue,
      errorKind: errorKind,
      errorCode: errorCode,
    );
    _updateSession(
      current.copyWith(
        phase: VoiceSessionPhase.error,
        terminalOutcome: VoiceTerminalOutcome.error,
        isAwaitingExternalActivity: false,
        lastErrorKind: errorKind,
        lastErrorCode: errorCode ?? errorKind.name.toUpperCase(),
        lastErrorMessageVi: resolvedMessage,
      ),
      waveform: VoiceWaveformSample.silent(
        monotonicTimestampMs: _clock.elapsedMilliseconds,
      ),
      actionableHintVi: resolvedMessage,
    );
  }

  void _armPreparingTimer(String sessionId, int attemptId, int genToken) {
    _preparingTimer?.cancel();
    _preparingTimer = _timerFactory.createTimer(
      _endpointConfig.preparingTimeout,
      () {
        if (_isStaleSession(sessionId, attemptId, genToken)) return;
        if (_snapshot.session.phase != VoiceSessionPhase.preparing ||
            _snapshot.session.isAwaitingExternalActivity) {
          return;
        }
        unawaited(
          _handleAttemptFailure(
            errorKind: VoiceErrorKind.clientError,
            errorCode: 'PREPARING_TIMEOUT',
            errorMessageVi:
                'Bộ nhận diện giọng nói phản hồi chậm. Bạn hãy thử lại hoặc chọn chế độ khác.',
          ),
        );
      },
    );
  }

  void _armFinalizingTimer(String sessionId, int attemptId, int genToken) {
    _finalizingTimer?.cancel();
    _finalizingTimer = _timerFactory.createTimer(
      _endpointConfig.finalizingTimeout,
      () {
        if (_isStaleSession(sessionId, attemptId, genToken)) return;
        if (_snapshot.session.phase != VoiceSessionPhase.finalizing) return;

        final engineId = _snapshot.session.engineId;
        if (engineId != null) {
          final adapter = _engineRegistry.adapterFor(engineId);
          unawaited(
            adapter?.cancelSession(sessionId: sessionId, attemptId: attemptId),
          );
        }

        if (_transcriptManager.currentPartial.trim().isNotEmpty) {
          _transcriptManager.onFinal(
            sessionId: sessionId,
            attemptId: attemptId,
            sequenceNumber: 0,
            text: '',
            rescuePartialOnEmptyFinal: true,
          );
        }

        if (_transcriptManager.effectiveText.trim().isNotEmpty) {
          _recordTimeline(
            'finalizingTimeoutRescued',
            VoiceSessionPhase.review,
            engineId: engineId?.wireValue,
            errorKind: VoiceErrorKind.finalizingTimeout,
          );
          _updateSession(
            _snapshot.session.copyWith(
              phase: VoiceSessionPhase.review,
              terminalOutcome: VoiceTerminalOutcome.finalResult,
              finalAtMonotonicMs: _clock.elapsedMilliseconds,
              isAwaitingExternalActivity: false,
            ),
            waveform: VoiceWaveformSample.silent(
              monotonicTimestampMs: _clock.elapsedMilliseconds,
            ),
            actionableHintVi: 'Đã hoàn tất ghi nhận từ nội dung vừa nghe.',
          );
        } else {
          _finalizeTerminalError(
            errorKind: VoiceErrorKind.finalizingTimeout,
            errorCode: 'FINALIZING_TIMEOUT',
          );
        }
      },
    );
  }

  void _armMaxUtteranceTimer(String sessionId, int attemptId, int genToken) {
    _maxUtteranceTimer?.cancel();
    _maxUtteranceTimer = _timerFactory.createTimer(
      _endpointConfig.maxUtteranceDuration,
      () {
        if (_isStaleSession(sessionId, attemptId, genToken)) return;
        if (_snapshot.session.phase != VoiceSessionPhase.listening) return;
        unawaited(stopSession(sessionId: sessionId));
      },
    );
  }

  void _armRetryTimer(String sessionId, int attemptId, int genToken) {
    _retryTimer?.cancel();
    _retryTimer = _timerFactory.createTimer(_busyRetryDelay, () {
      if (_isStaleSession(sessionId, attemptId, genToken)) return;
      unawaited(
        _launchCandidateAttempt(
          sessionId: sessionId,
          attemptId: attemptId,
          genToken: genToken,
        ),
      );
    });
  }

  void _scheduleAutoEndpointCheckIfNeeded() {
    if (_disposed ||
        _endpointConfig.mode != VoiceEndpointMode.smartAutoEndpoint ||
        _snapshot.session.phase != VoiceSessionPhase.listening ||
        _snapshot.session.terminalOutcome.isTerminal) {
      return;
    }

    final nowMs = _clock.elapsedMilliseconds;
    final startMs = _listeningStartedMs ?? nowMs;
    final activityMs = _lastAcousticActivityMs ?? startMs;
    final speechStartMs = _speechStartedMs;
    final silenceMs = nowMs - activityMs;
    final speechDurMs = (_hasSpeechStarted && speechStartMs != null)
        ? (activityMs - speechStartMs).clamp(0, 600000)
        : 0;

    final semanticHint = _buildSemanticHint();
    final decision = _endpointEvaluator.evaluate(
      config: _endpointConfig,
      acoustic: AcousticEndpointSignal(
        hasSpeechStarted: _hasSpeechStarted,
        speechDurationMs: speechDurMs,
        silenceDurationMs: silenceMs,
        utteranceElapsedMs: nowMs - startMs,
        hasActiveRmsOrVad: _hasReceivedRms,
      ),
      semanticHint: semanticHint,
    );

    final sessionId = _snapshot.session.sessionId;
    final attemptId = _snapshot.session.attemptId;
    final genToken = _snapshot.session.generationToken;

    if (decision.kind == EndpointDecisionKind.triggerGracefulStop) {
      _autoEndpointTimer?.cancel();
      unawaited(stopSession(sessionId: sessionId));
      return;
    }

    if (decision.kind == EndpointDecisionKind.emitSpeechTimeout) {
      _autoEndpointTimer?.cancel();
      unawaited(
        _handleAttemptFailure(
          errorKind: VoiceErrorKind.speechTimeout,
          errorCode: 'SPEECH_TIMEOUT',
        ),
      );
      return;
    }

    final waitMs = (decision.remainingSilenceMs ?? 500).clamp(50, 60000);
    _autoEndpointTimer?.cancel();
    _autoEndpointTimer = _timerFactory.createTimer(
      Duration(milliseconds: waitMs),
      () {
        if (_isStaleSession(sessionId, attemptId, genToken)) return;
        _scheduleAutoEndpointCheckIfNeeded();
      },
    );
  }

  SemanticCompletenessHint? _buildSemanticHint() {
    final text = _transcriptManager.effectiveText.trim();
    if (_semanticHintBuilder != null) {
      return _semanticHintBuilder(text);
    }
    if (text.isEmpty) {
      return const SemanticCompletenessHint(
        hasTranscript: false,
        hasActionableIntent: false,
        hasDanglingConnector: false,
        endsWithBareNumber: false,
      );
    }
    final hasDangling = RegExp(
      r'\b(?:và|với|cùng|rồi|thêm|hoặc|chia|gồm|lúc|vào|hết|mất|giá|khoảng|tầm|từ|sang|cho|ở|tại)$',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
    final endsWithBareNum = RegExp(r'(?:^|\s)\d{1,3}$').hasMatch(text);
    return SemanticCompletenessHint(
      hasTranscript: true,
      hasActionableIntent: !hasDangling && !endsWithBareNum,
      hasDanglingConnector: hasDangling,
      endsWithBareNumber: endsWithBareNum,
    );
  }

  Future<VoiceEnvironmentSnapshot> _resolveEnvironment(String locale) async {
    if (_environmentProvider != null) {
      return _environmentProvider();
    }
    final checks = await _engineRegistry.checkAll(locale: locale);
    final googleCheck = checks[VoiceEngineId.androidSpeech];
    final onDeviceCheck = checks[VoiceEngineId.androidOnDevice];
    final dialogCheck = checks[VoiceEngineId.systemDialog];
    return VoiceEnvironmentSnapshot(
      androidSdkInt: 35,
      osBuildFingerprint: 'default',
      recognitionServiceVersion: googleCheck?.serviceVersion ?? 'unknown',
      locale: locale,
      audioRoute: _snapshot.session.audioRoute,
      isNetworkAvailable: true,
      isGoogleSpeechAvailable: googleCheck?.isAvailable ?? false,
      isAndroidOnDeviceAvailable: onDeviceCheck?.isAvailable ?? false,
      isSystemDialogAvailable: dialogCheck?.isAvailable ?? false,
      nowEpochMs: _clock.wallNow.millisecondsSinceEpoch,
    );
  }

  Future<void> _refreshDiagnosticsData({required String locale}) async {
    final checks = await _engineRegistry.checkAll(locale: locale);
    final caps = await _capabilityRepository.loadEntries();
    final models = await _modelRepository.listModels();
    Map<String, dynamic>? nativeDiag;
    if (_nativeDiagnosticsProvider != null) {
      try {
        nativeDiag = await _nativeDiagnosticsProvider();
      } catch (_) {
        nativeDiag = null;
      }
    }
    if (_disposed) return;

    final nativeEngines =
        (nativeDiag?['availableEngines'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final adapterEngines = checks.entries
        .where((e) => e.value.isAvailable)
        .map((e) => e.key.wireValue);
    final available = <String>{
      ...nativeEngines,
      ...adapterEngines,
    }.toList(growable: false);
    final anyVn =
        checks.values.any((c) => c.isAvailable && c.supportsVietnamese) ||
        nativeDiag?['vietnameseInstalled'] == true ||
        nativeDiag?['vietnameseSupported'] == true;
    final hasMicPerm =
        nativeDiag?['hasRecordPermission'] == true ||
        nativeDiag?['hasMicPermission'] == true;
    final sdkInt =
        (nativeDiag?['sdkInt'] as num?)?.toInt() ??
        _snapshot.diagnostics.androidSdkInt;
    final manufacturer =
        nativeDiag?['manufacturer']?.toString() ??
        _snapshot.diagnostics.manufacturer;
    final model =
        nativeDiag?['model']?.toString() ?? _snapshot.diagnostics.model;
    final micPrivacyBlocked = nativeDiag?['isMicPrivacyBlocked'] is bool
        ? nativeDiag!['isMicPrivacyBlocked'] as bool
        : _snapshot.diagnostics.isMicPrivacyBlocked;
    final audioRoute = nativeDiag?['currentAudioRoute'] != null
        ? VoiceAudioRoute.fromWireValue(
            nativeDiag!['currentAudioRoute']?.toString(),
          )
        : _snapshot.diagnostics.currentAudioRoute;

    final updatedDiag = _snapshot.diagnostics.copyWith(
      androidSdkInt: sdkInt,
      manufacturer: manufacturer,
      model: model,
      hasMicPermission: nativeDiag != null
          ? hasMicPerm
          : _snapshot.diagnostics.hasMicPermission,
      isMicPrivacyBlocked: micPrivacyBlocked,
      currentAudioRoute: audioRoute,
      availableEngines: available,
      vietnameseSupportStatus: anyVn ? 'supported' : 'unavailable',
      capabilityEntries: caps,
      installedModels: models,
      recentTimeline: List<VoiceTimelineEntry>.unmodifiable(_timeline),
    );
    _snapshot = _snapshot.copyWith(
      diagnostics: updatedDiag,
      isCapabilitiesInitialized: true,
    );
    _emitSnapshot();
  }

  bool _transitionPhase(
    VoiceSessionPhase nextPhase, {
    bool? isAwaitingExternalActivity,
    String? engineId,
    VoiceErrorKind? errorKind,
    String? eventNote,
    bool emitNow = true,
  }) {
    final current = _snapshot.session;
    if (!current.phase.canTransitionTo(nextPhase)) {
      return false;
    }
    _recordTimeline(
      eventNote ?? 'phase_${nextPhase.wireValue}',
      nextPhase,
      engineId: engineId ?? current.engineId?.wireValue,
      errorKind: errorKind,
    );
    _updateSession(
      current.copyWith(
        phase: nextPhase,
        isAwaitingExternalActivity: isAwaitingExternalActivity,
      ),
      emitNow: emitNow,
    );
    return true;
  }

  void _updateSession(
    VoiceSession nextSession, {
    VoiceWaveformSample? waveform,
    VoiceRecognitionPreference? activePreference,
    bool? allowOnlineConsent,
    String? actionableHintVi,
    bool clearHint = false,
    bool emitNow = true,
  }) {
    final updatedDiagnostics = _snapshot.diagnostics.copyWith(
      activeSessionId: nextSession.sessionId.isEmpty
          ? null
          : nextSession.sessionId,
      clearActiveSessionId: nextSession.sessionId.isEmpty,
      activeAttemptId: nextSession.attemptId,
      currentPhase: nextSession.phase,
      currentAudioRoute: nextSession.audioRoute,
      lastErrorKind: nextSession.lastErrorKind,
      lastErrorCode: nextSession.lastErrorCode,
      clearLastError: nextSession.lastErrorKind == null,
      timeToReadyMs: nextSession.timeToReadyMs,
      clearTimeToReadyMs: nextSession.timeToReadyMs == null,
      timeToFirstPartialMs: nextSession.timeToFirstPartialMs,
      clearTimeToFirstPartialMs: nextSession.timeToFirstPartialMs == null,
      timeToFinalMs: nextSession.timeToFinalMs,
      clearTimeToFinalMs: nextSession.timeToFinalMs == null,
      retryCount: nextSession.retryCount,
      fallbackCount: nextSession.fallbackCount,
      recentTimeline: List<VoiceTimelineEntry>.unmodifiable(_timeline),
    );

    _snapshot = _snapshot.copyWith(
      session: nextSession,
      transcript: _transcriptManager.state,
      waveform: waveform,
      diagnostics: updatedDiagnostics,
      activePreference: activePreference,
      allowOnlineConsent: allowOnlineConsent,
      actionableHintVi: actionableHintVi,
      clearActionableHint: clearHint,
    );

    if (emitNow) {
      _emitSnapshot();
    }
  }

  void _recordTimeline(
    String eventType,
    VoiceSessionPhase phase, {
    String? engineId,
    VoiceErrorKind? errorKind,
    String? errorCode,
    String? note,
  }) {
    _timeline.add(
      VoiceTimelineEntry(
        monotonicTimestampMs: _clock.elapsedMilliseconds,
        eventType: eventType,
        phase: phase,
        engineId: engineId,
        errorKind: errorKind,
        errorCode: errorCode,
        note: note,
      ),
    );
    if (_timeline.length > _maxTimelineEntries) {
      _timeline.removeRange(0, _timeline.length - _maxTimelineEntries);
    }
  }

  void _emitSnapshot() {
    if (!_disposed && !_snapshotController.isClosed) {
      _snapshotController.add(_snapshot);
    }
  }

  void _cancelAllTimers() {
    _preparingTimer?.cancel();
    _preparingTimer = null;
    _finalizingTimer?.cancel();
    _finalizingTimer = null;
    _maxUtteranceTimer?.cancel();
    _maxUtteranceTimer = null;
    _autoEndpointTimer?.cancel();
    _autoEndpointTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _resetAcousticTrackers() {
    _hasReceivedRms = false;
    _hasSpeechStarted = false;
    _listeningStartedMs = null;
    _speechStartedMs = null;
    _lastAcousticActivityMs = null;
  }

  bool _isStaleSession(String sessionId, int attemptId, int genToken) {
    return _disposed ||
        _snapshot.session.sessionId != sessionId ||
        _snapshot.session.attemptId != attemptId ||
        _snapshot.session.generationToken != genToken ||
        _snapshot.session.terminalOutcome.isTerminal;
  }

  String _nextSessionId() {
    if (_sessionIdGenerator != null) {
      return _sessionIdGenerator();
    }
    _sessionCounter += 1;
    return 'vs_${_clock.elapsedMilliseconds}_$_sessionCounter';
  }
}
