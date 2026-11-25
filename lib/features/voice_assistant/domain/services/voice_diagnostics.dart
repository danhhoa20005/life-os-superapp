import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../entities/voice_engine_capability.dart';
import '../entities/voice_model_package.dart';
import '../entities/voice_session.dart';

/// Sanitized metadata-only timeline record. NEVER contains transcript text, money, or PII.
class VoiceTimelineEntry extends Equatable {
  final int monotonicTimestampMs;
  final String eventType;
  final VoiceSessionPhase phase;
  final String? engineId;
  final VoiceErrorKind? errorKind;
  final String? errorCode;
  final String? note;

  const VoiceTimelineEntry({
    required this.monotonicTimestampMs,
    required this.eventType,
    required this.phase,
    this.engineId,
    this.errorKind,
    this.errorCode,
    this.note,
  });

  Map<String, Object?> toSanitizedMap() => <String, Object?>{
    'tsMs': monotonicTimestampMs,
    'event': eventType,
    'phase': phase.wireValue,
    if (engineId != null) 'engineId': engineId,
    if (errorKind != null) 'errorKind': errorKind!.name,
    if (errorCode != null) 'errorCode': errorCode,
    if (note != null) 'note': _sanitizeTechnicalNote(note!),
  };

  static String _sanitizeTechnicalNote(String raw) {
    // Strip digits >= 4 (potential amounts/phone/account fragments) and keep short ASCII tag.
    final scrubbed = raw.replaceAll(RegExp(r'\d{4,}'), '***');
    return scrubbed.length > 64 ? scrubbed.substring(0, 64) : scrubbed;
  }

  @override
  List<Object?> get props => <Object?>[
    monotonicTimestampMs,
    eventType,
    phase,
    engineId,
    errorKind,
    errorCode,
    note,
  ];
}

/// Strictly sanitized Voice Engine 2.0 diagnostics report (`VOICE-011` / Privacy safe).
/// Guarantees ZERO transcript, ZERO monetary amounts, ZERO account numbers, and ZERO raw audio.
class VoiceDiagnosticsReport extends Equatable {
  final int androidSdkInt;
  final String manufacturer;
  final String model;
  final String osBuild;
  final bool hasMicPermission;
  final bool? isMicPrivacyBlocked;
  final List<String> availableEngines;
  final String vietnameseSupportStatus;
  final VoiceAudioRoute currentAudioRoute;
  final String? activeSessionId;
  final int activeAttemptId;
  final VoiceSessionPhase currentPhase;
  final VoiceErrorKind? lastErrorKind;
  final String? lastErrorCode;
  final int? timeToReadyMs;
  final int? timeToFirstPartialMs;
  final int? timeToFinalMs;
  final int retryCount;
  final int fallbackCount;
  final List<VoiceEngineCapabilityEntry> capabilityEntries;
  final List<LocalAsrModelInstallState> installedModels;
  final List<VoiceTimelineEntry> recentTimeline;

  const VoiceDiagnosticsReport({
    this.androidSdkInt = 0,
    this.manufacturer = 'unknown',
    this.model = 'unknown',
    this.osBuild = 'unknown',
    this.hasMicPermission = false,
    this.isMicPrivacyBlocked,
    this.availableEngines = const <String>[],
    this.vietnameseSupportStatus = 'unknown',
    this.currentAudioRoute = VoiceAudioRoute.builtInMic,
    this.activeSessionId,
    this.activeAttemptId = 0,
    this.currentPhase = VoiceSessionPhase.idle,
    this.lastErrorKind,
    this.lastErrorCode,
    this.timeToReadyMs,
    this.timeToFirstPartialMs,
    this.timeToFinalMs,
    this.retryCount = 0,
    this.fallbackCount = 0,
    this.capabilityEntries = const <VoiceEngineCapabilityEntry>[],
    this.installedModels = const <LocalAsrModelInstallState>[],
    this.recentTimeline = const <VoiceTimelineEntry>[],
  });

  static const VoiceDiagnosticsReport empty = VoiceDiagnosticsReport();

  VoiceDiagnosticsReport copyWith({
    int? androidSdkInt,
    String? manufacturer,
    String? model,
    String? osBuild,
    bool? hasMicPermission,
    bool? isMicPrivacyBlocked,
    bool clearMicPrivacyBlocked = false,
    List<String>? availableEngines,
    String? vietnameseSupportStatus,
    VoiceAudioRoute? currentAudioRoute,
    String? activeSessionId,
    bool clearActiveSessionId = false,
    int? activeAttemptId,
    VoiceSessionPhase? currentPhase,
    VoiceErrorKind? lastErrorKind,
    String? lastErrorCode,
    bool clearLastError = false,
    int? timeToReadyMs,
    bool clearTimeToReadyMs = false,
    int? timeToFirstPartialMs,
    bool clearTimeToFirstPartialMs = false,
    int? timeToFinalMs,
    bool clearTimeToFinalMs = false,
    int? retryCount,
    int? fallbackCount,
    List<VoiceEngineCapabilityEntry>? capabilityEntries,
    List<LocalAsrModelInstallState>? installedModels,
    List<VoiceTimelineEntry>? recentTimeline,
  }) {
    return VoiceDiagnosticsReport(
      androidSdkInt: androidSdkInt ?? this.androidSdkInt,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      osBuild: osBuild ?? this.osBuild,
      hasMicPermission: hasMicPermission ?? this.hasMicPermission,
      isMicPrivacyBlocked: clearMicPrivacyBlocked
          ? null
          : (isMicPrivacyBlocked ?? this.isMicPrivacyBlocked),
      availableEngines: availableEngines ?? this.availableEngines,
      vietnameseSupportStatus:
          vietnameseSupportStatus ?? this.vietnameseSupportStatus,
      currentAudioRoute: currentAudioRoute ?? this.currentAudioRoute,
      activeSessionId: clearActiveSessionId
          ? null
          : (activeSessionId ?? this.activeSessionId),
      activeAttemptId: activeAttemptId ?? this.activeAttemptId,
      currentPhase: currentPhase ?? this.currentPhase,
      lastErrorKind: clearLastError
          ? null
          : (lastErrorKind ?? this.lastErrorKind),
      lastErrorCode: clearLastError
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
      timeToReadyMs: clearTimeToReadyMs
          ? null
          : (timeToReadyMs ?? this.timeToReadyMs),
      timeToFirstPartialMs: clearTimeToFirstPartialMs
          ? null
          : (timeToFirstPartialMs ?? this.timeToFirstPartialMs),
      timeToFinalMs: clearTimeToFinalMs
          ? null
          : (timeToFinalMs ?? this.timeToFinalMs),
      retryCount: retryCount ?? this.retryCount,
      fallbackCount: fallbackCount ?? this.fallbackCount,
      capabilityEntries: capabilityEntries ?? this.capabilityEntries,
      installedModels: installedModels ?? this.installedModels,
      recentTimeline: recentTimeline ?? this.recentTimeline,
    );
  }

  Map<String, Object?> toSanitizedMap() {
    return <String, Object?>{
      'schemaVersion': 'voice_diag_v2',
      'device': <String, Object?>{
        'androidSdkInt': androidSdkInt,
        'manufacturer': manufacturer,
        'model': model,
        'osBuild': osBuild,
      },
      'permissions': <String, Object?>{
        'hasMicPermission': hasMicPermission,
        'isMicPrivacyBlocked': isMicPrivacyBlocked,
      },
      'engines': <String, Object?>{
        'available': availableEngines,
        'vietnameseSupportStatus': vietnameseSupportStatus,
        'currentAudioRoute': currentAudioRoute.wireValue,
      },
      'session': <String, Object?>{
        'activeSessionId': activeSessionId,
        'activeAttemptId': activeAttemptId,
        'currentPhase': currentPhase.wireValue,
        'lastErrorKind': lastErrorKind?.name,
        'lastErrorCode': lastErrorCode,
        'timeToReadyMs': timeToReadyMs,
        'timeToFirstPartialMs': timeToFirstPartialMs,
        'timeToFinalMs': timeToFinalMs,
        'retryCount': retryCount,
        'fallbackCount': fallbackCount,
      },
      'capabilities': capabilityEntries
          .map((e) => e.toJson())
          .toList(growable: false),
      'installedModels': installedModels
          .map(
            (m) => <String, Object?>{
              'id': m.spec.id,
              'status': m.status.name,
              'installedVersion': m.installedVersion,
              'commercialAllowed': m.spec.commercialAllowed,
            },
          )
          .toList(growable: false),
      'recentTimeline': recentTimeline
          .map((t) => t.toSanitizedMap())
          .toList(growable: false),
    };
  }

  String toSanitizedJson() {
    return const JsonEncoder.withIndent('  ').convert(toSanitizedMap());
  }

  String toSanitizedTextReport() {
    final buf = StringBuffer()
      ..writeln('LifeOS Voice Diagnostics v2 (Sanitized)')
      ..writeln('Device: $manufacturer $model (SDK $androidSdkInt, $osBuild)')
      ..writeln(
        'Mic Permission: ${hasMicPermission ? "GRANTED" : "DENIED"} '
        '(PrivacySwitchBlocked: ${isMicPrivacyBlocked ?? "unknown"})',
      )
      ..writeln('Audio Route: ${currentAudioRoute.wireValue}')
      ..writeln('Vietnamese Support: $vietnameseSupportStatus')
      ..writeln(
        'Available Engines: ${availableEngines.isEmpty ? "none" : availableEngines.join(", ")}',
      )
      ..writeln(
        'Session: id=${activeSessionId ?? "-"} attempt=$activeAttemptId '
        'phase=${currentPhase.wireValue}',
      )
      ..writeln(
        'Latencies(ms): ready=${timeToReadyMs ?? "-"} '
        'firstPartial=${timeToFirstPartialMs ?? "-"} '
        'final=${timeToFinalMs ?? "-"}',
      )
      ..writeln('Retries/Fallbacks: $retryCount / $fallbackCount')
      ..writeln(
        'Last Error: ${lastErrorKind?.name ?? "none"} (${lastErrorCode ?? "-"})',
      )
      ..writeln('Timeline (${recentTimeline.length} events):');
    for (final item in recentTimeline) {
      buf.writeln(
        '  [${item.monotonicTimestampMs}ms] ${item.eventType} '
        'phase=${item.phase.wireValue}'
        '${item.engineId != null ? " engine=${item.engineId}" : ""}'
        '${item.errorCode != null ? " err=${item.errorCode}" : ""}',
      );
    }
    return buf.toString().trimRight();
  }

  @override
  List<Object?> get props => <Object?>[
    androidSdkInt,
    manufacturer,
    model,
    osBuild,
    hasMicPermission,
    isMicPrivacyBlocked,
    availableEngines,
    vietnameseSupportStatus,
    currentAudioRoute,
    activeSessionId,
    activeAttemptId,
    currentPhase,
    lastErrorKind,
    lastErrorCode,
    timeToReadyMs,
    timeToFirstPartialMs,
    timeToFinalMs,
    retryCount,
    fallbackCount,
    capabilityEntries,
    installedModels,
    recentTimeline,
  ];
}
