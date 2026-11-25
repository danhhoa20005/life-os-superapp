import 'package:equatable/equatable.dart';

import '../entities/voice_engine_capability.dart';
import '../entities/voice_session.dart';

/// Immutable environment snapshot used to match capability cache entries and rank engines.
class VoiceEnvironmentSnapshot extends Equatable {
  final int androidSdkInt;
  final String osBuildFingerprint;
  final String recognitionServiceVersion;
  final String locale;
  final VoiceAudioRoute audioRoute;
  final bool isNetworkAvailable;
  final bool isGoogleSpeechAvailable;
  final bool isAndroidOnDeviceAvailable;
  final bool isSystemDialogAvailable;
  final int nowEpochMs;

  const VoiceEnvironmentSnapshot({
    required this.androidSdkInt,
    required this.osBuildFingerprint,
    required this.recognitionServiceVersion,
    this.locale = 'vi-VN',
    this.audioRoute = VoiceAudioRoute.builtInMic,
    this.isNetworkAvailable = true,
    this.isGoogleSpeechAvailable = true,
    this.isAndroidOnDeviceAvailable = false,
    this.isSystemDialogAvailable = true,
    required this.nowEpochMs,
  });

  @override
  List<Object?> get props => <Object?>[
    androidSdkInt,
    osBuildFingerprint,
    recognitionServiceVersion,
    locale,
    audioRoute,
    isNetworkAvailable,
    isGoogleSpeechAvailable,
    isAndroidOnDeviceAvailable,
    isSystemDialogAvailable,
    nowEpochMs,
  ];
}

/// Ordered candidate selection result or fail-closed block reason.
class EngineSelectionResult extends Equatable {
  final List<VoiceEngineId> orderedEngines;
  final bool isBlocked;
  final VoiceErrorKind? blockedErrorKind;
  final String? blockedMessageVi;
  final List<String> reasons;

  const EngineSelectionResult({
    required this.orderedEngines,
    required this.isBlocked,
    this.blockedErrorKind,
    this.blockedMessageVi,
    this.reasons = const <String>[],
  });

  factory EngineSelectionResult.allowed(
    List<VoiceEngineId> engines, {
    List<String> reasons = const <String>[],
  }) {
    return EngineSelectionResult(
      orderedEngines: List<VoiceEngineId>.unmodifiable(engines),
      isBlocked: false,
      reasons: List<String>.unmodifiable(reasons),
    );
  }

  factory EngineSelectionResult.blocked({
    required VoiceErrorKind errorKind,
    required String messageVi,
    List<String> reasons = const <String>[],
  }) {
    return EngineSelectionResult(
      orderedEngines: const <VoiceEngineId>[],
      isBlocked: true,
      blockedErrorKind: errorKind,
      blockedMessageVi: messageVi,
      reasons: List<String>.unmodifiable(reasons),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    orderedEngines,
    isBlocked,
    blockedErrorKind,
    blockedMessageVi,
    reasons,
  ];
}

/// Pure Dart engine selection policy enforcing `VOICE-007` (strict offline) & `VOICE-008` (TTL capability cache).
class EngineSelectionPolicy {
  const EngineSelectionPolicy();

  EngineSelectionResult selectEngines({
    required VoiceRecognitionPreference preference,
    required VoiceEnvironmentSnapshot environment,
    required List<VoiceEngineCapabilityEntry> capabilityEntries,
    required bool allowOnlineConsent,
    required bool localModelInstalled,
  }) {
    final reasons = <String>[];

    // Index latest valid, non-expired capability entry matching current environment.
    final activeCaps = <VoiceEngineId, VoiceEngineCapabilityEntry>{};
    for (final entry in capabilityEntries) {
      if (entry.isExpired(environment.nowEpochMs)) continue;
      if (!entry.matchesEnvironment(
        androidSdkInt: environment.androidSdkInt,
        osBuildFingerprint: environment.osBuildFingerprint,
        recognitionServiceVersion: environment.recognitionServiceVersion,
        locale: environment.locale,
        audioRoute: environment.audioRoute,
      )) {
        continue;
      }
      final existing = activeCaps[entry.engineId];
      if (existing == null ||
          entry.checkedAtEpochMs >= existing.checkedAtEpochMs) {
        activeCaps[entry.engineId] = entry;
      }
    }

    bool isEngineEligible(VoiceEngineId id) {
      final cap = activeCaps[id];
      if (cap != null && (!cap.isAvailable || !cap.supportsVietnamese)) {
        reasons.add('${id.wireValue}:excluded_by_capability');
        return false;
      }
      return switch (id) {
        VoiceEngineId.androidOnDevice =>
          environment.androidSdkInt >= 31 &&
              environment.isAndroidOnDeviceAvailable,
        VoiceEngineId.localAsr => localModelInstalled,
        VoiceEngineId.androidSpeech =>
          allowOnlineConsent &&
              environment.isNetworkAvailable &&
              environment.isGoogleSpeechAvailable,
        VoiceEngineId.systemDialog =>
          allowOnlineConsent &&
              environment.isNetworkAvailable &&
              environment.isSystemDialogAvailable,
      };
    }

    // VOICE-007: Strict Offline NEVER includes androidSpeech or systemDialog.
    if (preference == VoiceRecognitionPreference.offlineStrict) {
      final offlineCandidates = <VoiceEngineId>[
        if (isEngineEligible(VoiceEngineId.androidOnDevice))
          VoiceEngineId.androidOnDevice,
        if (isEngineEligible(VoiceEngineId.localAsr)) VoiceEngineId.localAsr,
      ];
      if (offlineCandidates.isEmpty) {
        return EngineSelectionResult.blocked(
          errorKind: localModelInstalled
              ? VoiceErrorKind.noEngineAvailable
              : VoiceErrorKind.offlineModelMissing,
          messageVi: localModelInstalled
              ? 'Không có bộ nhận diện Offline khả dụng trên thiết bị cho tiếng Việt.'
              : 'Chế độ Chỉ Offline yêu cầu tải gói tiếng Việt trên máy hoặc thiết bị hỗ trợ Google Offline (Android 12+). Bạn vẫn có thể nhập tay bên dưới.',
          reasons: <String>[...reasons, 'offline_strict_no_offline_engine'],
        );
      }
      final ranked = _rankByCapability(offlineCandidates, activeCaps, reasons);
      return EngineSelectionResult.allowed(ranked, reasons: reasons);
    }

    // Online consent disabled: constrain strictly to offline engines even in auto/online prefs.
    if (!allowOnlineConsent) {
      final offlineCandidates = <VoiceEngineId>[
        if (isEngineEligible(VoiceEngineId.androidOnDevice))
          VoiceEngineId.androidOnDevice,
        if (isEngineEligible(VoiceEngineId.localAsr)) VoiceEngineId.localAsr,
      ];
      if (offlineCandidates.isEmpty) {
        return EngineSelectionResult.blocked(
          errorKind: VoiceErrorKind.offlineModelMissing,
          messageVi:
              'Bạn đang tắt quyền nhận diện giọng nói trực tuyến và chưa cài gói Offline. Hãy tải gói Offline hoặc bật nhận diện trực tuyến.',
          reasons: <String>[...reasons, 'online_consent_disabled'],
        );
      }
      return EngineSelectionResult.allowed(
        _rankByCapability(offlineCandidates, activeCaps, reasons),
        reasons: reasons,
      );
    }

    if (preference == VoiceRecognitionPreference.systemDialog) {
      if (!environment.isNetworkAvailable) {
        return EngineSelectionResult.blocked(
          errorKind: VoiceErrorKind.networkError,
          messageVi: VoiceErrorKind.networkError.friendlyMessageVi,
          reasons: <String>[...reasons, 'system_dialog_no_network'],
        );
      }
      if (isEngineEligible(VoiceEngineId.systemDialog)) {
        return EngineSelectionResult.allowed(const <VoiceEngineId>[
          VoiceEngineId.systemDialog,
        ], reasons: reasons);
      }
      return EngineSelectionResult.blocked(
        errorKind: VoiceErrorKind.noEngineAvailable,
        messageVi:
            'Thiết bị chưa hỗ trợ hộp thoại nhận diện giọng nói hệ thống.',
        reasons: <String>[...reasons, 'system_dialog_unavailable'],
      );
    }

    if (preference == VoiceRecognitionPreference.onlineGoogle) {
      if (!environment.isNetworkAvailable) {
        return EngineSelectionResult.blocked(
          errorKind: VoiceErrorKind.networkError,
          messageVi: VoiceErrorKind.networkError.friendlyMessageVi,
          reasons: <String>[...reasons, 'online_google_no_network'],
        );
      }
      final candidates = <VoiceEngineId>[
        if (isEngineEligible(VoiceEngineId.androidSpeech))
          VoiceEngineId.androidSpeech,
        if (isEngineEligible(VoiceEngineId.systemDialog))
          VoiceEngineId.systemDialog,
      ];
      if (candidates.isEmpty) {
        return EngineSelectionResult.blocked(
          errorKind: VoiceErrorKind.noEngineAvailable,
          messageVi:
              'Thiết bị chưa bật Speech Services by Google để nhận diện trực tuyến.',
          reasons: <String>[...reasons, 'online_google_unavailable'],
        );
      }
      return EngineSelectionResult.allowed(
        _rankByCapability(candidates, activeCaps, reasons),
        reasons: reasons,
      );
    }

    // hybridAuto: prefer Google Speech when online, else offline engines cleanly.
    final hybridCandidates = <VoiceEngineId>[
      if (isEngineEligible(VoiceEngineId.androidSpeech))
        VoiceEngineId.androidSpeech,
      if (isEngineEligible(VoiceEngineId.androidOnDevice))
        VoiceEngineId.androidOnDevice,
      if (isEngineEligible(VoiceEngineId.localAsr)) VoiceEngineId.localAsr,
      if (isEngineEligible(VoiceEngineId.systemDialog))
        VoiceEngineId.systemDialog,
    ];

    if (hybridCandidates.isEmpty) {
      final errKind = !environment.isNetworkAvailable
          ? VoiceErrorKind.networkError
          : VoiceErrorKind.noEngineAvailable;
      return EngineSelectionResult.blocked(
        errorKind: errKind,
        messageVi: errKind.friendlyMessageVi,
        reasons: <String>[...reasons, 'hybrid_auto_none_available'],
      );
    }

    return EngineSelectionResult.allowed(
      _rankByCapability(hybridCandidates, activeCaps, reasons),
      reasons: reasons,
    );
  }

  List<VoiceEngineId> _rankByCapability(
    List<VoiceEngineId> baseOrder,
    Map<VoiceEngineId, VoiceEngineCapabilityEntry> caps,
    List<String> reasons,
  ) {
    final healthy = <VoiceEngineId>[];
    final demoted = <VoiceEngineId>[];

    for (final id in baseOrder) {
      final cap = caps[id];
      final isDegraded =
          cap != null &&
          (cap.consecutiveErrorCount >= 2 ||
              (cap.recentErrorCount >= 2 && cap.reliabilityScore < 0.45));
      if (isDegraded) {
        reasons.add('${id.wireValue}:demoted_recent_failures');
        demoted.add(id);
      } else {
        healthy.add(id);
      }
    }
    return <VoiceEngineId>[...healthy, ...demoted];
  }
}
