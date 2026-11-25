import 'package:equatable/equatable.dart';

import 'voice_engine_capability.dart';

/// Strict 10-state finite state machine for Voice Engine 2.0 sessions.
enum VoiceSessionPhase {
  idle('idle'),
  requestingPermission('requesting_permission'),
  preparing('preparing'),
  listening('listening'),
  finalizing('finalizing'),
  review('review'),
  submitting('submitting'),
  completed('completed'),
  cancelled('cancelled'),
  error('error');

  final String wireValue;

  const VoiceSessionPhase(this.wireValue);

  bool get isActiveCapture =>
      this == requestingPermission ||
      this == preparing ||
      this == listening ||
      this == finalizing;

  bool get isMicrophoneBusy =>
      this == preparing || this == listening || this == finalizing;

  bool get blocksNewStart =>
      this == requestingPermission ||
      this == preparing ||
      this == listening ||
      this == finalizing ||
      this == submitting;

  bool get blocksConfirm =>
      this == requestingPermission ||
      this == preparing ||
      this == listening ||
      this == finalizing ||
      this == submitting;

  bool get isTerminalPhase =>
      this == completed || this == cancelled || this == error;

  static const Map<VoiceSessionPhase, Set<VoiceSessionPhase>>
  _allowedTransitions = <VoiceSessionPhase, Set<VoiceSessionPhase>>{
    VoiceSessionPhase.idle: <VoiceSessionPhase>{
      VoiceSessionPhase.idle,
      VoiceSessionPhase.requestingPermission,
      VoiceSessionPhase.preparing,
      VoiceSessionPhase.review,
      VoiceSessionPhase.cancelled,
      VoiceSessionPhase.error,
    },
    VoiceSessionPhase.requestingPermission: <VoiceSessionPhase>{
      VoiceSessionPhase.requestingPermission,
      VoiceSessionPhase.preparing,
      VoiceSessionPhase.review,
      VoiceSessionPhase.cancelled,
      VoiceSessionPhase.error,
      VoiceSessionPhase.idle,
    },
    VoiceSessionPhase.preparing: <VoiceSessionPhase>{
      VoiceSessionPhase.preparing,
      VoiceSessionPhase.listening,
      VoiceSessionPhase.finalizing,
      VoiceSessionPhase.cancelled,
      VoiceSessionPhase.error,
      VoiceSessionPhase.idle,
    },
    VoiceSessionPhase.listening: <VoiceSessionPhase>{
      VoiceSessionPhase.listening,
      VoiceSessionPhase.finalizing,
      VoiceSessionPhase.cancelled,
      VoiceSessionPhase.error,
    },
    VoiceSessionPhase.finalizing: <VoiceSessionPhase>{
      VoiceSessionPhase.finalizing,
      VoiceSessionPhase.review,
      VoiceSessionPhase.cancelled,
      VoiceSessionPhase.error,
      VoiceSessionPhase.idle,
    },
    VoiceSessionPhase.review: <VoiceSessionPhase>{
      VoiceSessionPhase.review,
      VoiceSessionPhase.requestingPermission,
      VoiceSessionPhase.preparing,
      VoiceSessionPhase.submitting,
      VoiceSessionPhase.cancelled,
      VoiceSessionPhase.error,
      VoiceSessionPhase.idle,
    },
    VoiceSessionPhase.submitting: <VoiceSessionPhase>{
      VoiceSessionPhase.submitting,
      VoiceSessionPhase.completed,
      VoiceSessionPhase.review,
      VoiceSessionPhase.error,
      VoiceSessionPhase.cancelled,
    },
    VoiceSessionPhase.completed: <VoiceSessionPhase>{
      VoiceSessionPhase.completed,
      VoiceSessionPhase.idle,
      VoiceSessionPhase.requestingPermission,
      VoiceSessionPhase.preparing,
      VoiceSessionPhase.review,
    },
    VoiceSessionPhase.cancelled: <VoiceSessionPhase>{
      VoiceSessionPhase.cancelled,
      VoiceSessionPhase.idle,
      VoiceSessionPhase.requestingPermission,
      VoiceSessionPhase.preparing,
      VoiceSessionPhase.review,
    },
    VoiceSessionPhase.error: <VoiceSessionPhase>{
      VoiceSessionPhase.error,
      VoiceSessionPhase.idle,
      VoiceSessionPhase.requestingPermission,
      VoiceSessionPhase.preparing,
      VoiceSessionPhase.review,
      VoiceSessionPhase.cancelled,
    },
  };

  bool canTransitionTo(VoiceSessionPhase next) {
    return _allowedTransitions[this]?.contains(next) ?? false;
  }

  static VoiceSessionPhase fromWireValue(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    return switch (normalized) {
      'requesting_permission' => VoiceSessionPhase.requestingPermission,
      'preparing' || 'initializing' => VoiceSessionPhase.preparing,
      'listening' => VoiceSessionPhase.listening,
      'finalizing' || 'processing' => VoiceSessionPhase.finalizing,
      'review' => VoiceSessionPhase.review,
      'submitting' => VoiceSessionPhase.submitting,
      'completed' => VoiceSessionPhase.completed,
      'cancelled' || 'canceled' => VoiceSessionPhase.cancelled,
      'error' => VoiceSessionPhase.error,
      _ => VoiceSessionPhase.idle,
    };
  }
}

/// Terminal outcome recorded at most once per voice session/attempt.
enum VoiceTerminalOutcome {
  none,
  finalResult,
  cancelled,
  error,
  completed;

  bool get isTerminal => this != VoiceTerminalOutcome.none;
}

/// Surface that initiated the voice session for exclusive mic ownership & diagnostics.
enum VoiceEntryPoint {
  dashboard,
  quickCreate,
  financialAi,
  voiceSheet,
  homeWidget,
  widgetOverlay,
  financePage,
  familyPage,
  menuDirectory,
  diagnosticsSelfTest,
  unknown,
}

/// Normalized voice recognition & audio error taxonomy.
enum VoiceErrorKind {
  permissionDenied,
  permissionPermanentlyDenied,
  microphoneInUse,
  audioError,
  clientError,
  networkError,
  networkTimeout,
  noMatch,
  recognizerBusy,
  speechTimeout,
  serverError,
  tooManyRequests,
  serverDisconnected,
  languageNotSupported,
  languageUnavailable,
  noEngineAvailable,
  offlineModelMissing,
  audioFocusLost,
  interruptedByBackground,
  finalizingTimeout,
  unknown;

  /// Only `recognizerBusy` is retryable once as a transient binder hiccup.
  bool get isRetryableTransient => this == VoiceErrorKind.recognizerBusy;

  String get friendlyMessageVi => switch (this) {
    VoiceErrorKind.permissionDenied =>
      'Vui lòng cấp quyền Micro để thu âm giọng nói.',
    VoiceErrorKind.permissionPermanentlyDenied =>
      'Quyền Micro đang bị tắt vĩnh viễn. Hãy mở Cài đặt ứng dụng để bật lại.',
    VoiceErrorKind.microphoneInUse =>
      'Micro đang được ứng dụng hoặc cuộc gọi khác sử dụng.',
    VoiceErrorKind.audioError =>
      'Không thể mở luồng thu âm Micro trên thiết bị. Bạn hãy thử lại hoặc nhập tay.',
    VoiceErrorKind.clientError =>
      'Kết nối trình nhận diện giọng nói trên máy gặp sự cố tạm thời.',
    VoiceErrorKind.networkError =>
      'Mạng gián đoạn khi nhận diện giọng nói trực tuyến. Hãy kiểm tra kết nối hoặc dùng Offline.',
    VoiceErrorKind.networkTimeout =>
      'Kết nối máy chủ nhận diện giọng nói quá thời gian chờ.',
    VoiceErrorKind.noMatch =>
      'Chưa nghe rõ câu nói. Bạn hãy bấm Mic để nói lại hoặc chỉnh tay.',
    VoiceErrorKind.recognizerBusy =>
      'Bộ nhận diện giọng nói đang bận, đang giải phóng phiên trước.',
    VoiceErrorKind.speechTimeout =>
      'Chưa phát hiện giọng nói trong thời gian chờ. Bạn hãy bấm Mic để nói lại.',
    VoiceErrorKind.serverError =>
      'Dịch vụ nhận diện giọng nói tạm thời phản hồi lỗi.',
    VoiceErrorKind.tooManyRequests =>
      'Bạn thao tác quá nhanh, vui lòng đợi vài giây rồi thử lại.',
    VoiceErrorKind.serverDisconnected =>
      'Kết nối nhận diện giọng nói bị ngắt giữa chừng.',
    VoiceErrorKind.languageNotSupported =>
      'Trình nhận diện hiện tại chưa hỗ trợ tiếng Việt (vi-VN).',
    VoiceErrorKind.languageUnavailable =>
      'Gói ngôn ngữ tiếng Việt chưa sẵn sàng trên trình nhận diện này.',
    VoiceErrorKind.noEngineAvailable =>
      'Thiết bị chưa có bộ nhận diện giọng nói khả dụng cho chế độ đã chọn.',
    VoiceErrorKind.offlineModelMissing =>
      'Chế độ Chỉ Offline cần tải gói nhận diện tiếng Việt trên máy hoặc bật Google Offline.',
    VoiceErrorKind.audioFocusLost =>
      'Phiên thu âm đã dừng vì thiết bị chuyển quyền âm thanh sang cuộc gọi hoặc ứng dụng khác.',
    VoiceErrorKind.interruptedByBackground =>
      'Đã tạm dừng thu âm an toàn khi ứng dụng chuyển xuống nền.',
    VoiceErrorKind.finalizingTimeout =>
      'Đã kết thúc thu âm nhưng không nhận được phản hồi cuối từ bộ nhận diện.',
    VoiceErrorKind.unknown =>
      'Tạm ngưng thu âm ngoài dự kiến. Bạn có thể nói lại hoặc nhập bên dưới.',
  };

  static VoiceErrorKind fromNativeCode(String? code, {int? androidErrorCode}) {
    if (androidErrorCode != null) {
      return switch (androidErrorCode) {
        1 => VoiceErrorKind.networkTimeout,
        2 => VoiceErrorKind.networkError,
        3 => VoiceErrorKind.audioError,
        4 => VoiceErrorKind.serverError,
        5 => VoiceErrorKind.clientError,
        6 => VoiceErrorKind.speechTimeout,
        7 => VoiceErrorKind.noMatch,
        8 => VoiceErrorKind.recognizerBusy,
        9 => VoiceErrorKind.permissionDenied,
        10 => VoiceErrorKind.tooManyRequests,
        11 => VoiceErrorKind.serverDisconnected,
        12 => VoiceErrorKind.languageNotSupported,
        13 => VoiceErrorKind.languageUnavailable,
        14 => VoiceErrorKind.noEngineAvailable,
        15 => VoiceErrorKind.microphoneInUse,
        _ => VoiceErrorKind.unknown,
      };
    }

    final norm = (code ?? '').trim().toUpperCase();
    return switch (norm) {
      'PERMISSION_DENIED' => VoiceErrorKind.permissionDenied,
      'PERMISSION_PERMANENTLY_DENIED' =>
        VoiceErrorKind.permissionPermanentlyDenied,
      'MICROPHONE_IN_USE' || 'MIC_IN_USE' => VoiceErrorKind.microphoneInUse,
      'AUDIO_ERROR' || 'SPEECH_ERROR_3' => VoiceErrorKind.audioError,
      'CLIENT_ERROR' || 'SPEECH_ERROR_5' => VoiceErrorKind.clientError,
      'NETWORK_ERROR' || 'SPEECH_ERROR_2' => VoiceErrorKind.networkError,
      'NETWORK_TIMEOUT' || 'SPEECH_ERROR_1' => VoiceErrorKind.networkTimeout,
      'NO_MATCH' || 'SPEECH_ERROR_7' => VoiceErrorKind.noMatch,
      'RECOGNIZER_BUSY' || 'SPEECH_ERROR_8' => VoiceErrorKind.recognizerBusy,
      'SPEECH_TIMEOUT' || 'SPEECH_ERROR_6' => VoiceErrorKind.speechTimeout,
      'SERVER_ERROR' || 'SPEECH_ERROR_4' => VoiceErrorKind.serverError,
      'TOO_MANY_REQUESTS' ||
      'SPEECH_ERROR_10' => VoiceErrorKind.tooManyRequests,
      'SERVER_DISCONNECTED' ||
      'SPEECH_ERROR_11' => VoiceErrorKind.serverDisconnected,
      'LANGUAGE_NOT_SUPPORTED' ||
      'SPEECH_ERROR_12' => VoiceErrorKind.languageNotSupported,
      'LANGUAGE_UNAVAILABLE' ||
      'SPEECH_ERROR_13' => VoiceErrorKind.languageUnavailable,
      'NO_SPEECH_ENGINE' ||
      'NO_ENGINE_AVAILABLE' ||
      'UNSUPPORTED' ||
      'SPEECH_ERROR_14' => VoiceErrorKind.noEngineAvailable,
      'OFFLINE_MODEL_MISSING' => VoiceErrorKind.offlineModelMissing,
      'AUDIO_FOCUS_LOST' => VoiceErrorKind.audioFocusLost,
      'INTERRUPTED_BY_BACKGROUND' => VoiceErrorKind.interruptedByBackground,
      'FINALIZING_TIMEOUT' => VoiceErrorKind.finalizingTimeout,
      _ => VoiceErrorKind.unknown,
    };
  }
}

/// Immutable state entity representing a single Voice Engine 2.0 session lifecycle.
class VoiceSession extends Equatable {
  final String sessionId;
  final int attemptId;
  final String ownerId;
  final VoiceEntryPoint entryPoint;
  final VoiceEngineId? engineId;
  final VoiceRecognitionPreference mode;
  final VoiceSessionPhase phase;
  final VoiceTerminalOutcome terminalOutcome;
  final int? startedAtMonotonicMs;
  final int? readyAtMonotonicMs;
  final int? firstPartialAtMonotonicMs;
  final int? finalAtMonotonicMs;
  final int retryCount;
  final int fallbackCount;
  final VoiceErrorKind? lastErrorKind;
  final String? lastErrorCode;
  final String? lastErrorMessageVi;
  final int lastProcessedSequence;
  final bool isAwaitingExternalActivity;
  final VoiceAudioRoute audioRoute;
  final String locale;
  final int generationToken;

  const VoiceSession({
    required this.sessionId,
    required this.attemptId,
    required this.ownerId,
    required this.entryPoint,
    this.engineId,
    this.mode = VoiceRecognitionPreference.hybridAuto,
    this.phase = VoiceSessionPhase.idle,
    this.terminalOutcome = VoiceTerminalOutcome.none,
    this.startedAtMonotonicMs,
    this.readyAtMonotonicMs,
    this.firstPartialAtMonotonicMs,
    this.finalAtMonotonicMs,
    this.retryCount = 0,
    this.fallbackCount = 0,
    this.lastErrorKind,
    this.lastErrorCode,
    this.lastErrorMessageVi,
    this.lastProcessedSequence = 0,
    this.isAwaitingExternalActivity = false,
    this.audioRoute = VoiceAudioRoute.builtInMic,
    this.locale = 'vi-VN',
    this.generationToken = 0,
  });

  const VoiceSession.idle({
    this.mode = VoiceRecognitionPreference.hybridAuto,
    this.locale = 'vi-VN',
    this.audioRoute = VoiceAudioRoute.builtInMic,
    this.generationToken = 0,
  }) : sessionId = '',
       attemptId = 0,
       ownerId = '',
       entryPoint = VoiceEntryPoint.unknown,
       engineId = null,
       phase = VoiceSessionPhase.idle,
       terminalOutcome = VoiceTerminalOutcome.none,
       startedAtMonotonicMs = null,
       readyAtMonotonicMs = null,
       firstPartialAtMonotonicMs = null,
       finalAtMonotonicMs = null,
       retryCount = 0,
       fallbackCount = 0,
       lastErrorKind = null,
       lastErrorCode = null,
       lastErrorMessageVi = null,
       lastProcessedSequence = 0,
       isAwaitingExternalActivity = false;

  int? get timeToReadyMs {
    final start = startedAtMonotonicMs;
    final ready = readyAtMonotonicMs;
    if (start == null || ready == null || ready < start) return null;
    return ready - start;
  }

  int? get timeToFirstPartialMs {
    final start = startedAtMonotonicMs;
    final partial = firstPartialAtMonotonicMs;
    if (start == null || partial == null || partial < start) return null;
    return partial - start;
  }

  int? get timeToFinalMs {
    final start = startedAtMonotonicMs;
    final fin = finalAtMonotonicMs;
    if (start == null || fin == null || fin < start) return null;
    return fin - start;
  }

  VoiceSession copyWith({
    String? sessionId,
    int? attemptId,
    String? ownerId,
    VoiceEntryPoint? entryPoint,
    VoiceEngineId? engineId,
    bool clearEngineId = false,
    VoiceRecognitionPreference? mode,
    VoiceSessionPhase? phase,
    VoiceTerminalOutcome? terminalOutcome,
    int? startedAtMonotonicMs,
    int? readyAtMonotonicMs,
    bool clearReadyAt = false,
    int? firstPartialAtMonotonicMs,
    bool clearFirstPartialAt = false,
    int? finalAtMonotonicMs,
    bool clearFinalAt = false,
    int? retryCount,
    int? fallbackCount,
    VoiceErrorKind? lastErrorKind,
    String? lastErrorCode,
    String? lastErrorMessageVi,
    bool clearLastError = false,
    int? lastProcessedSequence,
    bool? isAwaitingExternalActivity,
    VoiceAudioRoute? audioRoute,
    String? locale,
    int? generationToken,
  }) {
    return VoiceSession(
      sessionId: sessionId ?? this.sessionId,
      attemptId: attemptId ?? this.attemptId,
      ownerId: ownerId ?? this.ownerId,
      entryPoint: entryPoint ?? this.entryPoint,
      engineId: clearEngineId ? null : (engineId ?? this.engineId),
      mode: mode ?? this.mode,
      phase: phase ?? this.phase,
      terminalOutcome: terminalOutcome ?? this.terminalOutcome,
      startedAtMonotonicMs: startedAtMonotonicMs ?? this.startedAtMonotonicMs,
      readyAtMonotonicMs: clearReadyAt
          ? null
          : (readyAtMonotonicMs ?? this.readyAtMonotonicMs),
      firstPartialAtMonotonicMs: clearFirstPartialAt
          ? null
          : (firstPartialAtMonotonicMs ?? this.firstPartialAtMonotonicMs),
      finalAtMonotonicMs: clearFinalAt
          ? null
          : (finalAtMonotonicMs ?? this.finalAtMonotonicMs),
      retryCount: retryCount ?? this.retryCount,
      fallbackCount: fallbackCount ?? this.fallbackCount,
      lastErrorKind: clearLastError
          ? null
          : (lastErrorKind ?? this.lastErrorKind),
      lastErrorCode: clearLastError
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
      lastErrorMessageVi: clearLastError
          ? null
          : (lastErrorMessageVi ?? this.lastErrorMessageVi),
      lastProcessedSequence:
          lastProcessedSequence ?? this.lastProcessedSequence,
      isAwaitingExternalActivity:
          isAwaitingExternalActivity ?? this.isAwaitingExternalActivity,
      audioRoute: audioRoute ?? this.audioRoute,
      locale: locale ?? this.locale,
      generationToken: generationToken ?? this.generationToken,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    sessionId,
    attemptId,
    ownerId,
    entryPoint,
    engineId,
    mode,
    phase,
    terminalOutcome,
    startedAtMonotonicMs,
    readyAtMonotonicMs,
    firstPartialAtMonotonicMs,
    finalAtMonotonicMs,
    retryCount,
    fallbackCount,
    lastErrorKind,
    lastErrorCode,
    lastErrorMessageVi,
    lastProcessedSequence,
    isAwaitingExternalActivity,
    audioRoute,
    locale,
    generationToken,
  ];
}
