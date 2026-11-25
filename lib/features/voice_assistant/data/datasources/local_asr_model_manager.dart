import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../domain/entities/voice_model_package.dart';
import '../../domain/repositories/local_asr_model_repository.dart';

class LocalAsrModelException implements Exception {
  final String code;
  final String messageVi;

  const LocalAsrModelException(this.code, this.messageVi);

  @override
  String toString() => 'LocalAsrModelException($code): $messageVi';
}

class LocalAsrLicenseBlockedException extends LocalAsrModelException {
  const LocalAsrLicenseBlockedException(String modelId, String license)
    : super(
        'LICENSE_BLOCKED',
        'Mô hình $modelId sử dụng giấy phép $license không cho phép phân phối thương mại.',
      );
}

class LocalAsrInsufficientStorageException extends LocalAsrModelException {
  const LocalAsrInsufficientStorageException(int requiredBytes, int freeBytes)
    : super(
        'INSUFFICIENT_STORAGE',
        'Thiết bị không đủ dung lượng trống (cần ${requiredBytes ~/ (1024 * 1024)} MB, còn ${freeBytes ~/ (1024 * 1024)} MB).',
      );
}

class LocalAsrCorruptedModelException extends LocalAsrModelException {
  const LocalAsrCorruptedModelException(String modelId)
    : super(
        'CHECKSUM_MISMATCH',
        'Gói mô hình $modelId không khớp mã kiểm tra SHA-256 và đã bị từ chối.',
      );
}

class LocalAsrDownloadException extends LocalAsrModelException {
  const LocalAsrDownloadException(String detail)
    : super(
        'DOWNLOAD_FAILED',
        'Không thể tải mô hình giọng nói offline ($detail). Vui lòng thử lại sau.',
      );
}

/// Real filesystem + HTTP Range resume + SHA-256 verified + atomic rollback ASR model manager.
class LocalAsrModelManager implements LocalAsrModelRepository {
  static final RegExp _sha256HexRegex = RegExp(r'^[a-fA-F0-9]{64}$');

  final Future<Directory> Function() _rootDirectoryProvider;
  final http.Client _httpClient;
  final List<LocalAsrModelSpec> _catalog;
  final Future<int> Function(Directory dir)? _freeSpaceBytesProvider;
  final int _minFreeSpaceBufferBytes;

  final Map<String, LocalAsrModelInstallState> _transientStates =
      <String, LocalAsrModelInstallState>{};

  LocalAsrModelManager({
    required Directory rootDirectory,
    http.Client? httpClient,
    List<LocalAsrModelSpec> catalog = LocalAsrModelCatalog.defaults,
    Future<int> Function(Directory dir)? freeSpaceBytesProvider,
    int minFreeSpaceBufferBytes = 1024 * 1024,
  }) : _rootDirectoryProvider = (() async => rootDirectory),
       _httpClient = httpClient ?? http.Client(),
       _catalog = catalog,
       _freeSpaceBytesProvider = freeSpaceBytesProvider,
       _minFreeSpaceBufferBytes = minFreeSpaceBufferBytes;

  LocalAsrModelManager.lazy({
    required Future<Directory> Function() rootDirectoryProvider,
    http.Client? httpClient,
    List<LocalAsrModelSpec> catalog = LocalAsrModelCatalog.defaults,
    Future<int> Function(Directory dir)? freeSpaceBytesProvider,
    int minFreeSpaceBufferBytes = 1024 * 1024,
  }) : _rootDirectoryProvider = rootDirectoryProvider,
       _httpClient = httpClient ?? http.Client(),
       _catalog = catalog,
       _freeSpaceBytesProvider = freeSpaceBytesProvider,
       _minFreeSpaceBufferBytes = minFreeSpaceBufferBytes;

  @override
  Future<List<LocalAsrModelInstallState>> listModels() async {
    final states = <LocalAsrModelInstallState>[];
    for (final spec in _catalog) {
      states.add(await _inspectSpecState(spec));
    }
    return List<LocalAsrModelInstallState>.unmodifiable(states);
  }

  @override
  Future<LocalAsrModelInstallState> getModelState(String modelId) async {
    final spec = _findSpec(modelId);
    if (spec != null) {
      return _inspectSpecState(spec);
    }
    final root = await _rootDirectoryProvider();
    final manifest = await _readManifest(_currentDir(root, modelId));
    final fallbackSpec = LocalAsrModelSpec(
      id: modelId,
      displayNameVi: modelId,
      runtimeName: 'local',
      runtimeLicenseSpdx: 'Apache-2.0',
      modelLicenseSpdx: 'MIT',
      commercialAllowed: true,
      version: manifest?['version']?.toString() ?? '0.0.0',
      sizeBytes: (manifest?['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256Hex: manifest?['sha256Hex']?.toString() ?? '',
      downloadUrl: '',
      sampleRateHz: 16000,
      supportsStreaming: true,
      languageCode: 'vi-VN',
      requiredFiles: <String>[
        manifest?['primaryFileName']?.toString() ?? 'model.bin',
      ],
    );
    return _inspectSpecState(fallbackSpec);
  }

  @override
  Future<bool> hasVerifiedInstalledAsrModel() async {
    final models = await listModels();
    for (final item in models) {
      if (item.spec.runtimeName == 'silero-vad') continue;
      if (item.status == LocalAsrModelStatus.installed &&
          item.spec.commercialAllowed) {
        final ok = await verifyModelIntegrity(
          item.spec.id,
          specOverride: item.spec,
        );
        if (ok) return true;
      }
    }
    return false;
  }

  @override
  Future<LocalAsrModelInstallState> downloadModel(
    LocalAsrModelSpec spec, {
    void Function(LocalAsrDownloadProgress progress)? onProgress,
    bool enforceCommercialLicense = true,
  }) async {
    if (enforceCommercialLicense && !spec.commercialAllowed) {
      final blocked = LocalAsrModelInstallState(
        spec: spec,
        status: LocalAsrModelStatus.licenseBlocked,
        errorMessageVi:
            'Mô hình ${spec.id} (${spec.modelLicenseSpdx}) bị chặn ở bản phát hành thương mại.',
      );
      _transientStates[spec.id] = blocked;
      throw LocalAsrLicenseBlockedException(spec.id, spec.modelLicenseSpdx);
    }

    final uri = Uri.tryParse(spec.downloadUrl.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty) {
      throw const LocalAsrDownloadException(
        'URL tải không hợp lệ (chỉ cho phép HTTPS)',
      );
    }

    final expectedHash = spec.sha256Hex.trim().toLowerCase();
    if (!_sha256HexRegex.hasMatch(expectedHash)) {
      throw LocalAsrCorruptedModelException(spec.id);
    }

    final root = await _rootDirectoryProvider();
    final modelRoot = _modelRootDir(root, spec.id);
    final stagingDir = Directory('${modelRoot.path}/staging');
    if (!await stagingDir.exists()) {
      await stagingDir.create(recursive: true);
    }

    final partFile = File('${stagingDir.path}/${spec.id}-${spec.version}.part');
    final existingBytes = await partFile.exists() ? await partFile.length() : 0;

    final remainingNeeded =
        (spec.sizeBytes > existingBytes ? spec.sizeBytes - existingBytes : 0) +
        _minFreeSpaceBufferBytes;
    if (_freeSpaceBytesProvider != null) {
      final freeBytes = await _freeSpaceBytesProvider(root);
      if (freeBytes < remainingNeeded) {
        throw LocalAsrInsufficientStorageException(remainingNeeded, freeBytes);
      }
    }

    var downloadedBytes = existingBytes;
    onProgress?.call(
      LocalAsrDownloadProgress(
        modelId: spec.id,
        downloadedBytes: downloadedBytes,
        totalBytes: spec.sizeBytes,
        status: LocalAsrModelStatus.downloading,
      ),
    );

    final req = http.Request('GET', uri);
    if (existingBytes > 0) {
      req.headers['Range'] = 'bytes=$existingBytes-';
    }

    http.StreamedResponse response;
    try {
      response = await _httpClient.send(req);
    } catch (e) {
      throw LocalAsrDownloadException(e.toString());
    }

    if (response.statusCode == 206) {
      final sink = partFile.openWrite(mode: FileMode.append);
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          onProgress?.call(
            LocalAsrDownloadProgress(
              modelId: spec.id,
              downloadedBytes: downloadedBytes,
              totalBytes: spec.sizeBytes,
              status: LocalAsrModelStatus.downloading,
            ),
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } else if (response.statusCode == 200) {
      downloadedBytes = 0;
      final sink = partFile.openWrite(mode: FileMode.write);
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          onProgress?.call(
            LocalAsrDownloadProgress(
              modelId: spec.id,
              downloadedBytes: downloadedBytes,
              totalBytes: spec.sizeBytes,
              status: LocalAsrModelStatus.downloading,
            ),
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } else if (response.statusCode == 416 && existingBytes > 0) {
      // Partial file may already hold full payload; fall through to SHA-256 check.
    } else {
      throw LocalAsrDownloadException('HTTP ${response.statusCode}');
    }

    onProgress?.call(
      LocalAsrDownloadProgress(
        modelId: spec.id,
        downloadedBytes: await partFile.length(),
        totalBytes: spec.sizeBytes,
        status: LocalAsrModelStatus.verifying,
      ),
    );

    final actualSha256 = await _computeFileSha256(partFile);
    if (actualSha256 != expectedHash) {
      if (await partFile.exists()) {
        await partFile.delete();
      }
      _transientStates[spec.id] = LocalAsrModelInstallState(
        spec: spec,
        status: LocalAsrModelStatus.corrupted,
        errorMessageVi:
            'Tệp mô hình ${spec.id} bị lỗi SHA-256 và đã tự động xóa.',
      );
      throw LocalAsrCorruptedModelException(spec.id);
    }

    // Atomic staged install + rollback backup of prior version.
    final installStageDir = Directory(
      '${stagingDir.path}/install_${spec.version}_${DateTime.now().microsecondsSinceEpoch}',
    );
    await installStageDir.create(recursive: true);

    final stagedPayload = File(
      '${installStageDir.path}/${spec.primaryFileName}',
    );
    await partFile.rename(stagedPayload.path);

    final payloadSize = await stagedPayload.length();
    final manifestFile = File('${installStageDir.path}/manifest.json');
    await manifestFile.writeAsString(
      jsonEncode(<String, Object?>{
        'id': spec.id,
        'version': spec.version,
        'sha256Hex': expectedHash,
        'sizeBytes': payloadSize,
        'primaryFileName': spec.primaryFileName,
        'requiredFiles': spec.requiredFiles,
        'commercialAllowed': spec.commercialAllowed,
        'installedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
      }),
      flush: true,
    );

    final currentDir = _currentDir(root, spec.id);
    final backupDir = _backupDir(root, spec.id);

    if (await currentDir.exists()) {
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
      await currentDir.rename(backupDir.path);
    }

    try {
      await installStageDir.rename(currentDir.path);
    } catch (e) {
      if (await backupDir.exists() && !await currentDir.exists()) {
        await backupDir.rename(currentDir.path);
      }
      rethrow;
    }

    final installedState = LocalAsrModelInstallState(
      spec: spec,
      status: LocalAsrModelStatus.installed,
      downloadedBytes: payloadSize,
      installedVersion: spec.version,
      installedPath: currentDir.path,
      hasRollbackBackup: await backupDir.exists(),
    );
    _transientStates[spec.id] = installedState;
    onProgress?.call(
      LocalAsrDownloadProgress(
        modelId: spec.id,
        downloadedBytes: payloadSize,
        totalBytes: payloadSize,
        status: LocalAsrModelStatus.installed,
      ),
    );
    return installedState;
  }

  @override
  Future<bool> verifyModelIntegrity(
    String modelId, {
    LocalAsrModelSpec? specOverride,
  }) async {
    final root = await _rootDirectoryProvider();
    final currentDir = _currentDir(root, modelId);
    if (!await currentDir.exists()) return false;

    final manifest = await _readManifest(currentDir);
    if (manifest == null) return false;

    final spec = specOverride ?? _findSpec(modelId);
    final requiredFiles =
        spec?.requiredFiles ??
        ((manifest['requiredFiles'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList(growable: false) ??
            <String>[manifest['primaryFileName']?.toString() ?? 'model.bin']);

    for (final fileName in requiredFiles) {
      final f = File('${currentDir.path}/$fileName');
      if (!await f.exists()) {
        return false;
      }
    }

    final primaryName =
        spec?.primaryFileName ??
        manifest['primaryFileName']?.toString() ??
        'model.bin';
    final primaryFile = File('${currentDir.path}/$primaryName');
    if (!await primaryFile.exists()) return false;

    final expectedHash =
        (specOverride?.sha256Hex ?? manifest['sha256Hex']?.toString() ?? '')
            .trim()
            .toLowerCase();
    if (!_sha256HexRegex.hasMatch(expectedHash)) return false;

    final actualHash = await _computeFileSha256(primaryFile);
    final valid = actualHash == expectedHash;
    if (!valid && spec != null) {
      _transientStates[modelId] = LocalAsrModelInstallState(
        spec: spec,
        status: LocalAsrModelStatus.corrupted,
        installedVersion: manifest['version']?.toString(),
        installedPath: currentDir.path,
        hasRollbackBackup: await _backupDir(root, modelId).exists(),
        errorMessageVi: 'Phát hiện tệp mô hình $modelId bị thay đổi hoặc hỏng.',
      );
    }
    return valid;
  }

  @override
  Future<bool> rollbackModel(String modelId) async {
    final root = await _rootDirectoryProvider();
    final backupDir = _backupDir(root, modelId);
    final currentDir = _currentDir(root, modelId);
    if (!await backupDir.exists()) return false;

    final backupManifest = await _readManifest(backupDir);
    if (backupManifest == null) return false;

    final primaryName =
        backupManifest['primaryFileName']?.toString() ?? 'model.bin';
    final primaryFile = File('${backupDir.path}/$primaryName');
    final expectedHash = (backupManifest['sha256Hex']?.toString() ?? '')
        .trim()
        .toLowerCase();
    if (!await primaryFile.exists() ||
        !_sha256HexRegex.hasMatch(expectedHash)) {
      return false;
    }
    final actualHash = await _computeFileSha256(primaryFile);
    if (actualHash != expectedHash) {
      return false;
    }

    Directory? tempOld;
    if (await currentDir.exists()) {
      tempOld = Directory(
        '${_modelRootDir(root, modelId).path}/trash_${DateTime.now().microsecondsSinceEpoch}',
      );
      await currentDir.rename(tempOld.path);
    }

    try {
      await backupDir.rename(currentDir.path);
      if (tempOld != null && await tempOld.exists()) {
        await tempOld.delete(recursive: true);
      }
      _transientStates.remove(modelId);
      return true;
    } catch (_) {
      if (tempOld != null &&
          await tempOld.exists() &&
          !await currentDir.exists()) {
        await tempOld.rename(currentDir.path);
      }
      return false;
    }
  }

  @override
  Future<void> deleteModel(String modelId) async {
    _transientStates.remove(modelId);
    final root = await _rootDirectoryProvider();
    final modelRoot = _modelRootDir(root, modelId);
    if (await modelRoot.exists()) {
      await modelRoot.delete(recursive: true);
    }
  }

  Future<LocalAsrModelInstallState> _inspectSpecState(
    LocalAsrModelSpec spec,
  ) async {
    if (!spec.commercialAllowed) {
      final transient = _transientStates[spec.id];
      if (transient != null &&
          transient.status == LocalAsrModelStatus.licenseBlocked) {
        return transient;
      }
    }

    final root = await _rootDirectoryProvider();
    final currentDir = _currentDir(root, spec.id);
    final backupDir = _backupDir(root, spec.id);
    final hasBackup = await backupDir.exists();

    if (!await currentDir.exists()) {
      final transient = _transientStates[spec.id];
      if (transient != null &&
          (transient.status == LocalAsrModelStatus.corrupted ||
              transient.status == LocalAsrModelStatus.licenseBlocked)) {
        return transient;
      }
      return LocalAsrModelInstallState(
        spec: spec,
        status: spec.commercialAllowed
            ? LocalAsrModelStatus.notDownloaded
            : LocalAsrModelStatus.licenseBlocked,
        hasRollbackBackup: hasBackup,
      );
    }

    final manifest = await _readManifest(currentDir);
    if (manifest == null) {
      return LocalAsrModelInstallState(
        spec: spec,
        status: LocalAsrModelStatus.corrupted,
        installedPath: currentDir.path,
        hasRollbackBackup: hasBackup,
        errorMessageVi: 'Thiếu manifest mô hình offline.',
      );
    }

    final version = manifest['version']?.toString();
    final primaryFile = File('${currentDir.path}/${spec.primaryFileName}');
    final fileBytes = await primaryFile.exists()
        ? await primaryFile.length()
        : 0;

    final intact = await verifyModelIntegrity(
      spec.id,
      specOverride: spec.copyWithVersionAndHashIfNeeded(
        version: version ?? spec.version,
        sha256Hex: manifest['sha256Hex']?.toString() ?? spec.sha256Hex,
      ),
    );
    if (!intact) {
      return LocalAsrModelInstallState(
        spec: spec,
        status: LocalAsrModelStatus.corrupted,
        downloadedBytes: fileBytes,
        installedVersion: version,
        installedPath: currentDir.path,
        hasRollbackBackup: hasBackup,
        errorMessageVi: 'Mô hình ${spec.id} bị hỏng kiểm tra SHA-256.',
      );
    }

    return LocalAsrModelInstallState(
      spec: spec,
      status: LocalAsrModelStatus.installed,
      downloadedBytes: fileBytes,
      installedVersion: version,
      installedPath: currentDir.path,
      hasRollbackBackup: hasBackup,
    );
  }

  LocalAsrModelSpec? _findSpec(String modelId) {
    for (final s in _catalog) {
      if (s.id == modelId) return s;
    }
    return null;
  }

  Directory _modelRootDir(Directory root, String modelId) =>
      Directory('${root.path}/voice_models/$modelId');

  Directory _currentDir(Directory root, String modelId) =>
      Directory('${_modelRootDir(root, modelId).path}/current');

  Directory _backupDir(Directory root, String modelId) =>
      Directory('${_modelRootDir(root, modelId).path}/backup');

  Future<Map<String, dynamic>?> _readManifest(Directory dir) async {
    final file = File('${dir.path}/manifest.json');
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _computeFileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }
}

extension _LocalAsrModelSpecCopy on LocalAsrModelSpec {
  LocalAsrModelSpec copyWithVersionAndHashIfNeeded({
    required String version,
    required String sha256Hex,
  }) {
    return LocalAsrModelSpec(
      id: id,
      displayNameVi: displayNameVi,
      runtimeName: runtimeName,
      runtimeLicenseSpdx: runtimeLicenseSpdx,
      modelLicenseSpdx: modelLicenseSpdx,
      commercialAllowed: commercialAllowed,
      version: version,
      sizeBytes: sizeBytes,
      sha256Hex: sha256Hex,
      downloadUrl: downloadUrl,
      sampleRateHz: sampleRateHz,
      supportsStreaming: supportsStreaming,
      languageCode: languageCode,
      requiredFiles: requiredFiles,
    );
  }
}
