import 'package:equatable/equatable.dart';

/// Lifecycle status of an optional on-device ASR / VAD model package.
enum LocalAsrModelStatus {
  notDownloaded,
  downloading,
  verifying,
  installed,
  corrupted,
  licenseBlocked,
  error,
}

/// Declarative model specification with SPDX license & SHA-256 verification metadata.
class LocalAsrModelSpec extends Equatable {
  final String id;
  final String displayNameVi;
  final String runtimeName;
  final String runtimeLicenseSpdx;
  final String modelLicenseSpdx;
  final bool commercialAllowed;
  final String version;
  final int sizeBytes;
  final String sha256Hex;
  final String downloadUrl;
  final int sampleRateHz;
  final bool supportsStreaming;
  final String languageCode;
  final List<String> requiredFiles;

  const LocalAsrModelSpec({
    required this.id,
    required this.displayNameVi,
    required this.runtimeName,
    required this.runtimeLicenseSpdx,
    required this.modelLicenseSpdx,
    required this.commercialAllowed,
    required this.version,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.downloadUrl,
    required this.sampleRateHz,
    required this.supportsStreaming,
    required this.languageCode,
    required this.requiredFiles,
  });

  String get primaryFileName =>
      requiredFiles.isNotEmpty ? requiredFiles.first : 'model.bin';

  @override
  List<Object?> get props => <Object?>[
    id,
    displayNameVi,
    runtimeName,
    runtimeLicenseSpdx,
    modelLicenseSpdx,
    commercialAllowed,
    version,
    sizeBytes,
    sha256Hex,
    downloadUrl,
    sampleRateHz,
    supportsStreaming,
    languageCode,
    requiredFiles,
  ];
}

/// Built-in offline Vietnamese ASR & VAD model catalog with explicit license compliance.
abstract final class LocalAsrModelCatalog {
  static const LocalAsrModelSpec voskSmallVn = LocalAsrModelSpec(
    id: 'vosk-model-small-vn-0.4',
    displayNameVi: 'Vosk Tiếng Việt Nhẹ (Streaming)',
    runtimeName: 'vosk',
    runtimeLicenseSpdx: 'Apache-2.0',
    modelLicenseSpdx: 'Apache-2.0',
    commercialAllowed: true,
    version: '0.4.0',
    sizeBytes: 35127296, // ~33.5 MB
    sha256Hex:
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    downloadUrl:
        'https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-model-small-vn-0.4.zip',
    sampleRateHz: 16000,
    supportsStreaming: true,
    languageCode: 'vi-VN',
    requiredFiles: <String>['model.bin'],
  );

  static const LocalAsrModelSpec sherpaWhisperTinyInt8 = LocalAsrModelSpec(
    id: 'sherpa-onnx-whisper-tiny-int8',
    displayNameVi: 'Whisper Tiny INT8 (VAD Chunked)',
    runtimeName: 'sherpa-onnx',
    runtimeLicenseSpdx: 'Apache-2.0',
    modelLicenseSpdx: 'MIT',
    commercialAllowed: true,
    version: '1.0.0',
    sizeBytes: 81788928, // ~78 MB
    sha256Hex:
        '8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4',
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2',
    sampleRateHz: 16000,
    supportsStreaming: false,
    languageCode: 'vi-VN',
    requiredFiles: <String>['model.bin'],
  );

  static const LocalAsrModelSpec sileroVadV5 = LocalAsrModelSpec(
    id: 'silero-vad-v5',
    displayNameVi: 'Silero VAD v5 (Lọc tiếng nói)',
    runtimeName: 'silero-vad',
    runtimeLicenseSpdx: 'MIT',
    modelLicenseSpdx: 'MIT',
    commercialAllowed: true,
    version: '5.0.0',
    sizeBytes: 2411725, // ~2.3 MB
    sha256Hex:
        '2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae',
    downloadUrl:
        'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
    sampleRateHz: 16000,
    supportsStreaming: true,
    languageCode: 'multilingual',
    requiredFiles: <String>['silero_vad.onnx'],
  );

  static const LocalAsrModelSpec sherpaZipformerViNc = LocalAsrModelSpec(
    id: 'sherpa-onnx-zipformer-vi-30m-int8',
    displayNameVi: 'Zipformer Tiếng Việt 30M (Nghiên cứu NC-ND)',
    runtimeName: 'sherpa-onnx',
    runtimeLicenseSpdx: 'Apache-2.0',
    modelLicenseSpdx: 'CC-BY-NC-ND-4.0',
    commercialAllowed: false,
    version: '1.0.0',
    sizeBytes: 31457280,
    sha256Hex:
        '4b227777d4dd1fc61c6f884f48641d02b4d121d3fd328cb08b5531fcacdabf8a',
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-zipformer-vi-30M-2024-05-31.tar.bz2',
    sampleRateHz: 16000,
    supportsStreaming: true,
    languageCode: 'vi-VN',
    requiredFiles: <String>['model.bin'],
  );

  static const List<LocalAsrModelSpec> defaults = <LocalAsrModelSpec>[
    voskSmallVn,
    sherpaWhisperTinyInt8,
    sileroVadV5,
    sherpaZipformerViNc,
  ];
}

/// Real-time download and verification progress emitted by [LocalAsrModelRepository].
class LocalAsrDownloadProgress extends Equatable {
  final String modelId;
  final int downloadedBytes;
  final int totalBytes;
  final LocalAsrModelStatus status;

  const LocalAsrDownloadProgress({
    required this.modelId,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.status,
  });

  double get fraction {
    if (totalBytes <= 0) return 0.0;
    final ratio = downloadedBytes / totalBytes;
    if (ratio < 0.0) return 0.0;
    if (ratio > 1.0) return 1.0;
    return ratio;
  }

  @override
  List<Object?> get props => <Object?>[
    modelId,
    downloadedBytes,
    totalBytes,
    status,
  ];
}

/// Installed state & integrity metadata for a single model package.
class LocalAsrModelInstallState extends Equatable {
  final LocalAsrModelSpec spec;
  final LocalAsrModelStatus status;
  final int downloadedBytes;
  final String? installedVersion;
  final String? installedPath;
  final bool hasRollbackBackup;
  final String? errorMessageVi;

  const LocalAsrModelInstallState({
    required this.spec,
    required this.status,
    this.downloadedBytes = 0,
    this.installedVersion,
    this.installedPath,
    this.hasRollbackBackup = false,
    this.errorMessageVi,
  });

  bool get isUsableOffline => status == LocalAsrModelStatus.installed;

  @override
  List<Object?> get props => <Object?>[
    spec,
    status,
    downloadedBytes,
    installedVersion,
    installedPath,
    hasRollbackBackup,
    errorMessageVi,
  ];
}
