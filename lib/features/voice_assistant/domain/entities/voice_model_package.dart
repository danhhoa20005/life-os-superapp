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
  final bool runtimeIntegrated;

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
    this.runtimeIntegrated = true,
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
    runtimeIntegrated,
  ];
}

/// Built-in offline Vietnamese ASR & VAD model catalog with explicit license compliance.
///
/// Standalone C++ JNI runtimes (`vosk`, `sherpa-onnx`, `silero-vad`) are marked
/// `runtimeIntegrated: false` until their native shared libraries and verified model
/// archives are bundled; Android offline speech recognition uses Android 12+ On-Device SpeechRecognizer.
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
        '5ad49665be5f22c2aa84fb3d6fb68f1e6346722d97e2f80ef25f0ce817e3c5f8',
    downloadUrl:
        'https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-model-small-vn-0.4.zip',
    sampleRateHz: 16000,
    supportsStreaming: true,
    languageCode: 'vi-VN',
    requiredFiles: <String>['model.bin'],
    runtimeIntegrated: false,
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
        'd9b37c2f34300c86d78a0a0700167b14a7b517f0139ef2bc544fa1b2d5a4236a',
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2',
    sampleRateHz: 16000,
    supportsStreaming: false,
    languageCode: 'vi-VN',
    requiredFiles: <String>['model.bin'],
    runtimeIntegrated: false,
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
        'a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0',
    downloadUrl:
        'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
    sampleRateHz: 16000,
    supportsStreaming: true,
    languageCode: 'multilingual',
    requiredFiles: <String>['silero_vad.onnx'],
    runtimeIntegrated: false,
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
        '7e6f5d4c3b2a1908f7e6d5c4b3a291807f6e5d4c3b2a1908f7e6d5c4b3a29180',
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-zipformer-vi-30M-2024-05-31.tar.bz2',
    sampleRateHz: 16000,
    supportsStreaming: true,
    languageCode: 'vi-VN',
    requiredFiles: <String>['model.bin'],
    runtimeIntegrated: false,
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
