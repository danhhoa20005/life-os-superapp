import 'package:equatable/equatable.dart';

/// Concrete speech engine adapters managed by Voice Engine 2.0.
enum VoiceEngineId {
  androidOnDevice('android_on_device', 'Android Offline (On-Device)'),
  localAsr('local_asr', 'Mô hình Offline nội bộ'),
  androidSpeech('android_speech', 'Google Speech (Trực tiếp)'),
  systemDialog('system_dialog', 'Hộp thoại hệ thống');

  final String wireValue;
  final String labelVi;

  const VoiceEngineId(this.wireValue, this.labelVi);

  bool get isStrictlyOffline =>
      this == VoiceEngineId.androidOnDevice || this == VoiceEngineId.localAsr;

  static VoiceEngineId? tryFromWireValue(String? raw) {
    final norm = (raw ?? '').trim().toLowerCase();
    return switch (norm) {
      'android_on_device' || 'on_device' => VoiceEngineId.androidOnDevice,
      'local_asr' => VoiceEngineId.localAsr,
      'android_speech' || 'google_service' => VoiceEngineId.androidSpeech,
      'system_dialog' || 'system_speech_dialog' => VoiceEngineId.systemDialog,
      _ => null,
    };
  }
}

/// User-facing recognition mode preference.
enum VoiceRecognitionPreference {
  offlineStrict('offline_strict', 'Chỉ Offline (Riêng tư)'),
  hybridAuto('hybrid_auto', 'Tự động (Ưu tiên hệ thống)'),
  onlineGoogle('online_google', 'Online (Google Speech)'),
  systemDialog('system_dialog', 'Hộp thoại hệ thống');

  final String wireValue;
  final String labelVi;

  const VoiceRecognitionPreference(this.wireValue, this.labelVi);

  bool get requiresStrictOffline =>
      this == VoiceRecognitionPreference.offlineStrict;

  static VoiceRecognitionPreference fromWireValue(String? raw) {
    final norm = (raw ?? '').trim().toLowerCase();
    return switch (norm) {
      'offline_strict' ||
      'on_device' => VoiceRecognitionPreference.offlineStrict,
      'online_google' ||
      'google_service' => VoiceRecognitionPreference.onlineGoogle,
      'system_dialog' => VoiceRecognitionPreference.systemDialog,
      'hybrid_auto' || 'auto' => VoiceRecognitionPreference.hybridAuto,
      _ => VoiceRecognitionPreference.hybridAuto,
    };
  }
}

/// Active hardware microphone route detected by OS audio manager.
enum VoiceAudioRoute {
  builtInMic('built_in_mic', 'Micro tích hợp'),
  bluetoothSco('bluetooth_sco', 'Bluetooth SCO'),
  bluetoothBle('bluetooth_ble', 'Bluetooth LE Audio'),
  wiredHeadset('wired_headset', 'Tai nghe có dây'),
  usbHeadset('usb_headset', 'Tai nghe USB'),
  speaker('speaker', 'Loa ngoài'),
  unknown('unknown', 'Không xác định');

  final String wireValue;
  final String labelVi;

  const VoiceAudioRoute(this.wireValue, this.labelVi);

  static VoiceAudioRoute fromWireValue(String? raw) {
    final norm = (raw ?? '').trim().toLowerCase();
    return switch (norm) {
      'built_in_mic' || 'builtin' || 'mic' => VoiceAudioRoute.builtInMic,
      'bluetooth_sco' || 'sco' => VoiceAudioRoute.bluetoothSco,
      'bluetooth_ble' || 'ble' => VoiceAudioRoute.bluetoothBle,
      'wired_headset' || 'wired' => VoiceAudioRoute.wiredHeadset,
      'usb_headset' || 'usb' => VoiceAudioRoute.usbHeadset,
      'speaker' => VoiceAudioRoute.speaker,
      _ => VoiceAudioRoute.unknown,
    };
  }
}

/// Environment-scoped capability memory entry with TTL and rolling reliability stats.
class VoiceEngineCapabilityEntry extends Equatable {
  static const int defaultTtlMs = 86400000; // 24 hours

  final VoiceEngineId engineId;
  final int androidSdkInt;
  final String osBuildFingerprint;
  final String recognitionServiceVersion;
  final String locale;
  final VoiceAudioRoute audioRoute;
  final bool isAvailable;
  final bool supportsVietnamese;
  final int checkedAtEpochMs;
  final int ttlMs;
  final int recentSuccessCount;
  final int recentErrorCount;
  final int consecutiveErrorCount;
  final String? lastErrorCode;

  const VoiceEngineCapabilityEntry({
    required this.engineId,
    required this.androidSdkInt,
    required this.osBuildFingerprint,
    required this.recognitionServiceVersion,
    required this.locale,
    required this.audioRoute,
    required this.isAvailable,
    required this.supportsVietnamese,
    required this.checkedAtEpochMs,
    this.ttlMs = defaultTtlMs,
    this.recentSuccessCount = 0,
    this.recentErrorCount = 0,
    this.consecutiveErrorCount = 0,
    this.lastErrorCode,
  });

  bool isExpired(int nowEpochMs) {
    if (ttlMs <= 0) return true;
    if (nowEpochMs < checkedAtEpochMs) return true;
    return (nowEpochMs - checkedAtEpochMs) >= ttlMs;
  }

  bool matchesEnvironment({
    required int androidSdkInt,
    required String osBuildFingerprint,
    required String recognitionServiceVersion,
    required String locale,
    required VoiceAudioRoute audioRoute,
  }) {
    return this.androidSdkInt == androidSdkInt &&
        this.osBuildFingerprint == osBuildFingerprint &&
        this.recognitionServiceVersion == recognitionServiceVersion &&
        this.locale.trim().toLowerCase() == locale.trim().toLowerCase() &&
        this.audioRoute == audioRoute;
  }

  /// Rolling reliability score in `0.0..1.0`. Never permanently locks in `1.0` after 1 success.
  double get reliabilityScore {
    if (!isAvailable || !supportsVietnamese) return 0.0;
    final total = recentSuccessCount + recentErrorCount;
    if (total == 0) return 0.5;
    final penalty = consecutiveErrorCount >= 2 ? 0.25 : 0.0;
    final raw =
        (recentSuccessCount + 1.0) /
        (recentSuccessCount + (recentErrorCount * 2.0) + 2.0);
    final adjusted = raw - penalty;
    if (adjusted < 0.0) return 0.0;
    if (adjusted > 1.0) return 1.0;
    return adjusted;
  }

  VoiceEngineCapabilityEntry recordSuccess({required int nowEpochMs}) {
    var nextSucc = recentSuccessCount + 1;
    var nextErr = recentErrorCount;
    // Bound rolling window so historical successes decay over time.
    if (nextSucc + nextErr > 12) {
      nextSucc = (nextSucc + 1) ~/ 2;
      nextErr = nextErr ~/ 2;
    }
    return copyWith(
      isAvailable: true,
      checkedAtEpochMs: nowEpochMs,
      recentSuccessCount: nextSucc,
      recentErrorCount: nextErr,
      consecutiveErrorCount: 0,
      clearLastErrorCode: true,
    );
  }

  VoiceEngineCapabilityEntry recordError({
    required int nowEpochMs,
    String? errorCode,
    bool? stillAvailable,
    bool? stillSupportsVietnamese,
  }) {
    var nextSucc = recentSuccessCount;
    var nextErr = recentErrorCount + 1;
    if (nextSucc + nextErr > 12) {
      nextSucc = nextSucc ~/ 2;
      nextErr = (nextErr + 1) ~/ 2;
    }
    return copyWith(
      isAvailable: stillAvailable ?? isAvailable,
      supportsVietnamese: stillSupportsVietnamese ?? supportsVietnamese,
      checkedAtEpochMs: nowEpochMs,
      recentSuccessCount: nextSucc,
      recentErrorCount: nextErr,
      consecutiveErrorCount: consecutiveErrorCount + 1,
      lastErrorCode: errorCode,
    );
  }

  VoiceEngineCapabilityEntry copyWith({
    VoiceEngineId? engineId,
    int? androidSdkInt,
    String? osBuildFingerprint,
    String? recognitionServiceVersion,
    String? locale,
    VoiceAudioRoute? audioRoute,
    bool? isAvailable,
    bool? supportsVietnamese,
    int? checkedAtEpochMs,
    int? ttlMs,
    int? recentSuccessCount,
    int? recentErrorCount,
    int? consecutiveErrorCount,
    String? lastErrorCode,
    bool clearLastErrorCode = false,
  }) {
    return VoiceEngineCapabilityEntry(
      engineId: engineId ?? this.engineId,
      androidSdkInt: androidSdkInt ?? this.androidSdkInt,
      osBuildFingerprint: osBuildFingerprint ?? this.osBuildFingerprint,
      recognitionServiceVersion:
          recognitionServiceVersion ?? this.recognitionServiceVersion,
      locale: locale ?? this.locale,
      audioRoute: audioRoute ?? this.audioRoute,
      isAvailable: isAvailable ?? this.isAvailable,
      supportsVietnamese: supportsVietnamese ?? this.supportsVietnamese,
      checkedAtEpochMs: checkedAtEpochMs ?? this.checkedAtEpochMs,
      ttlMs: ttlMs ?? this.ttlMs,
      recentSuccessCount: recentSuccessCount ?? this.recentSuccessCount,
      recentErrorCount: recentErrorCount ?? this.recentErrorCount,
      consecutiveErrorCount:
          consecutiveErrorCount ?? this.consecutiveErrorCount,
      lastErrorCode: clearLastErrorCode
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'engineId': engineId.wireValue,
    'androidSdkInt': androidSdkInt,
    'osBuildFingerprint': osBuildFingerprint,
    'recognitionServiceVersion': recognitionServiceVersion,
    'locale': locale,
    'audioRoute': audioRoute.wireValue,
    'isAvailable': isAvailable,
    'supportsVietnamese': supportsVietnamese,
    'checkedAtEpochMs': checkedAtEpochMs,
    'ttlMs': ttlMs,
    'recentSuccessCount': recentSuccessCount,
    'recentErrorCount': recentErrorCount,
    'consecutiveErrorCount': consecutiveErrorCount,
    if (lastErrorCode != null) 'lastErrorCode': lastErrorCode,
  };

  static VoiceEngineCapabilityEntry? fromJson(Map<String, Object?> json) {
    final engineId = VoiceEngineId.tryFromWireValue(
      json['engineId']?.toString(),
    );
    if (engineId == null) return null;
    return VoiceEngineCapabilityEntry(
      engineId: engineId,
      androidSdkInt: (json['androidSdkInt'] as num?)?.toInt() ?? 0,
      osBuildFingerprint: (json['osBuildFingerprint'] ?? '').toString(),
      recognitionServiceVersion: (json['recognitionServiceVersion'] ?? '')
          .toString(),
      locale: (json['locale'] ?? 'vi-VN').toString(),
      audioRoute: VoiceAudioRoute.fromWireValue(json['audioRoute']?.toString()),
      isAvailable: json['isAvailable'] == true,
      supportsVietnamese: json['supportsVietnamese'] == true,
      checkedAtEpochMs: (json['checkedAtEpochMs'] as num?)?.toInt() ?? 0,
      ttlMs: (json['ttlMs'] as num?)?.toInt() ?? defaultTtlMs,
      recentSuccessCount: (json['recentSuccessCount'] as num?)?.toInt() ?? 0,
      recentErrorCount: (json['recentErrorCount'] as num?)?.toInt() ?? 0,
      consecutiveErrorCount:
          (json['consecutiveErrorCount'] as num?)?.toInt() ?? 0,
      lastErrorCode: json['lastErrorCode']?.toString(),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    engineId,
    androidSdkInt,
    osBuildFingerprint,
    recognitionServiceVersion,
    locale,
    audioRoute,
    isAvailable,
    supportsVietnamese,
    checkedAtEpochMs,
    ttlMs,
    recentSuccessCount,
    recentErrorCount,
    consecutiveErrorCount,
    lastErrorCode,
  ];
}
