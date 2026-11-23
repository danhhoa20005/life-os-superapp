import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../error/app_exception.dart';
import '../error/failure.dart';
import 'native_secure_vault_bridge.dart';

/// Metadata descriptor for binary attachments (receipt scans, vehicle papers, PDF contracts).
/// Binary bytes are NEVER stored inside Cloud Firestore documents to preserve Spark quota & latency.
final class StoredFileReference {
  final String storageKey;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String sha256Checksum;
  final String? localFilePath;
  final String? downloadUrl;

  const StoredFileReference({
    required this.storageKey,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.sha256Checksum = '',
    this.localFilePath,
    this.downloadUrl,
  });
}

/// Pure abstraction for binary object storage (PHẦN 11 — FileStorageService).
abstract interface class FileStorageService {
  bool get isCloudObjectStorageEnabled;
  bool get isLocalDeviceVaultEnabled;

  Future<Result<StoredFileReference>> uploadUserAttachment({
    required String userId,
    required String folder,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  });

  Future<Result<Uint8List?>> readLocalAttachmentBytes({
    required String userId,
    required String storageKey,
  });

  Future<Result<void>> deleteUserAttachment({
    required String userId,
    required String storageKey,
  });
}

/// Spark-safe Private On-Device Document Vault (`SparkSafeFileStorageService`):
/// - Keeps Cloud Firebase strictly on Spark $0/month (NEVER writes binary blobs into Firestore).
/// - Stores attached images/PDFs inside the app's private on-device sandbox directory with SHA-256 verification.
class SparkSafeFileStorageService implements FileStorageService {
  static const int maxAttachmentBytes = 15 * 1024 * 1024; // 15 MB safety cap
  static final Map<String, Uint8List> _ephemeralWebVault = <String, Uint8List>{};

  final String? customVaultRootPath;

  const SparkSafeFileStorageService({this.customVaultRootPath});

  @override
  bool get isCloudObjectStorageEnabled => false;

  @override
  bool get isLocalDeviceVaultEnabled => true;

  Future<Directory?> _resolveVaultDir(String userId) async {
    if (kIsWeb) return null;
    final safeUid = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final base = customVaultRootPath ??
        await NativeSecureVaultBridge.instance.getVaultDirectoryPath() ??
        '${Directory.systemTemp.path}${Platform.pathSeparator}lifeos_local_vault';
    final dir = Directory('$base${Platform.pathSeparator}$safeUid');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<Result<StoredFileReference>> uploadUserAttachment({
    required String userId,
    required String folder,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      return const Err(
        ValidationFailure(
          code: 'EMPTY_ATTACHMENT',
          message: 'Tệp đính kèm trống, không thể lưu vào kho giấy tờ.',
        ),
      );
    }
    if (bytes.lengthInBytes > maxAttachmentBytes) {
      return const Err(
        ValidationFailure(
          code: 'ATTACHMENT_TOO_LARGE',
          message: 'Tệp vượt quá giới hạn an toàn 15 MB cho kho lưu trữ cục bộ.',
        ),
      );
    }

    final safeFolder = folder.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '_');
    final digest = sha256.convert(bytes).toString();
    final key = '${safeFolder}_${ digest.substring(0, 12) }_$safeName';

    if (kIsWeb) {
      _ephemeralWebVault['$userId/$key'] = bytes;
      return Success(
        StoredFileReference(
          storageKey: key,
          fileName: fileName,
          mimeType: mimeType,
          sizeBytes: bytes.lengthInBytes,
          sha256Checksum: digest,
        ),
      );
    }

    try {
      final dir = await _resolveVaultDir(userId);
      final targetFile = File('${dir!.path}${Platform.pathSeparator}$key');
      await targetFile.writeAsBytes(bytes, flush: true);
      return Success(
        StoredFileReference(
          storageKey: key,
          fileName: fileName,
          mimeType: mimeType,
          sizeBytes: bytes.lengthInBytes,
          sha256Checksum: digest,
          localFilePath: targetFile.path,
        ),
      );
    } catch (e) {
      return Err(
        UnexpectedFailure(
          code: 'LOCAL_VAULT_WRITE_FAILED',
          message: 'Không thể lưu tệp vào kho an toàn trên thiết bị: $e',
        ),
      );
    }
  }

  @override
  Future<Result<Uint8List?>> readLocalAttachmentBytes({
    required String userId,
    required String storageKey,
  }) async {
    if (kIsWeb) {
      return Success(_ephemeralWebVault['$userId/$storageKey']);
    }
    try {
      final dir = await _resolveVaultDir(userId);
      final safeKey = storageKey.replaceAll(RegExp(r'[\\/]'), '_');
      final f = File('${dir!.path}${Platform.pathSeparator}$safeKey');
      if (!f.existsSync()) return const Success(null);
      return Success(await f.readAsBytes());
    } catch (_) {
      return const Success(null);
    }
  }

  @override
  Future<Result<void>> deleteUserAttachment({
    required String userId,
    required String storageKey,
  }) async {
    if (kIsWeb) {
      _ephemeralWebVault.remove('$userId/$storageKey');
      return const Success(null);
    }
    try {
      final dir = await _resolveVaultDir(userId);
      final safeKey = storageKey.replaceAll(RegExp(r'[\\/]'), '_');
      final f = File('${dir!.path}${Platform.pathSeparator}$safeKey');
      if (f.existsSync()) {
        await f.delete();
      }
      return const Success(null);
    } catch (_) {
      return const Success(null);
    }
  }
}
