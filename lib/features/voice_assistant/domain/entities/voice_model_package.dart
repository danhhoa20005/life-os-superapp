import 'package:equatable/equatable.dart';

/// Lifecycle status of an optional on-device ASR / VAD model package.
enum LocalAsrModelStatus {
  notDownloaded,
  downloading,
  verifying,
  installed,
  corrupted,
  licenseBlocked,
  runtimeUnavailable,
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
  final bool verifiedInferenceCapable;
  final String? bundledAssetPath;

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
    this.runtimeIntegrated = false,
    this.verifiedInferenceCapable = false,
    this.bundledAssetPath,
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
    verifiedInferenceCapable,
    bundledAssetPath,
  ];
}

/// Optional offline Vietnamese ASR & VAD model catalog with explicit license
/// and runtime-integration truthfulness flags.
///
/// Native Vosk / Sherpa-ONNX / Silero inference runtimes are NOT integrated in
/// this build yet (`runtimeIntegrated: false, verifiedInferenceCapable: false`),
/// so strict offline voice capture relies solely on Android 13+ On-Device
/// SpeechRecognizer (when available on the device) or manual text entry.
abstract final class LocalAsrModelCatalog {
  static const LocalAsrModelSpec voskSmallVn = LocalAsrModelSpec(
    id: 'vosk-model-small-vn-0.4',
    displayNameVi: 'Vosk Tiếng Việt Nhẹ (Streaming)',
    runtimeName: 'vosk',
    runtimeLicenseSpdx: 'Apache-2.0',
    modelLicenseSpdx: 'Apache-2.0',
    commercialAllowed: true,
    version: '0.4.0',
    sizeBytes: 16590,
    sha256Hex:
        '174bb1767b429d113fa1145a39d6b4c7e072a5844e4cbe54ef7005ec50b94c44',
    downloadUrl:
        'https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-model-small-vn-0.4.zip',
    sampleRateHz: 16000,
    supportsStreaming: true,
    languageCode: 'vi-VN',
    requiredFiles: <String>['model.bin'],
    runtimeIntegrated: false,
    verifiedInferenceCapable: false,
    bundledAssetPath: 'assets/models/vosk_model_small_vn_0_4.bin',
  );

  static const LocalAsrModelSpec sherpaWhisperTinyInt8 = LocalAsrModelSpec(
    id: 'sherpa-onnx-whisper-tiny-int8',
    displayNameVi: 'Whisper Tiny INT8 (VAD Chunked)',
    runtimeName: 'sherpa-onnx',
    runtimeLicenseSpdx: 'Apache-2.0',
    modelLicenseSpdx: 'MIT',
    commercialAllowed: true,
    version: '1.0.0',
    sizeBytes: 16596,
    sha256Hex:
        '000b145cde8e611b7c066a853e72ea0352a31ed3d44bdb7fcbe7acc8d158b148',
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2',
    sampleRateHz: 16000,
    supportsStreaming: false,
    languageCode: 'vi-VN',
    requiredFiles: <String>['model.bin'],
    runtimeIntegrated: false,
    verifiedInferenceCapable: false,
    bundledAssetPath: 'assets/models/sherpa_onnx_whisper_tiny_int8.bin',
  );

  static const LocalAsrModelSpec sileroVadV5 = LocalAsrModelSpec(
    id: 'silero-vad-v5',
    displayNameVi: 'Silero VAD v5 (Lọc tiếng nói)',
    runtimeName: 'silero-vad',
    runtimeLicenseSpdx: 'MIT',
    modelLicenseSpdx: 'MIT',
    commercialAllowed: true,
    version: '5.0.0',
    sizeBytes: 16469,
    sha256Hex:
        'da1d6a6de7a2c8dd806ccdbfa964ce7e9566373f1e05440d8b02979bdf253c66',
    downloadUrl:
        'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
    sampleRateHz: 16000,
    supportsStreaming: true,
    languageCode: 'multilingual',
    requiredFiles: <String>['silero_vad.onnx'],
    runtimeIntegrated: false,
    verifiedInferenceCapable: false,
    bundledAssetPath: 'assets/models/silero_vad_v5.onnx',
  );

  static const LocalAsrModelSpec sherpaZipformerViInt8 = LocalAsrModelSpec(
    id: 'sherpa-onnx-zipformer-vi-30m-int8',
    displayNameVi: 'Zipformer Tiếng Việt 30M INT8 (Streaming)',
    runtimeName: 'sherpa-onnx',
    runtimeLicenseSpdx: 'Apache-2.0',
    modelLicenseSpdx: 'Apache-2.0',
    commercialAllowed: true,
    version: '1.0.0',
    sizeBytes: 16600,
    sha256Hex:
        'c07d3406821b42370e4b9a9943bb02c926023e70ef68d80ce28f81fc2ff8129b',
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-zipformer-vi-30M-2024-05-31.tar.bz2',
    sampleRateHz: 16000,
    supportsStreaming: true,
    languageCode: 'vi-VN',
    requiredFiles: <String>['model.bin'],
    runtimeIntegrated: false,
    verifiedInferenceCapable: false,
    bundledAssetPath: 'assets/models/sherpa_onnx_zipformer_vi_30m_int8.bin',
  );

  /// Retained strictly for license-compliance unit tests verifying CC-BY-NC-ND-4.0 rejection.
  static const LocalAsrModelSpec sherpaZipformerViNc = LocalAsrModelSpec(
    id: 'sherpa-onnx-zipformer-vi-30m-nc-nd',
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
    verifiedInferenceCapable: false,
  );

  static const List<LocalAsrModelSpec> defaults = <LocalAsrModelSpec>[
    voskSmallVn,
    sherpaWhisperTinyInt8,
    sileroVadV5,
    sherpaZipformerViInt8,
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

  bool get isUsableOffline =>
      status == LocalAsrModelStatus.installed &&
      spec.runtimeIntegrated &&
      spec.verifiedInferenceCapable;

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
