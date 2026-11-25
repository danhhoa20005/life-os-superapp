import 'dart:convert';
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
  final String plaintextSha256;
  final int? encryptedSizeBytes;
  final String? localFilePath;
  final String? downloadUrl;

  const StoredFileReference({
    required this.storageKey,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.sha256Checksum = '',
    String? plaintextSha256,
    this.encryptedSizeBytes,
    this.localFilePath,
    this.downloadUrl,
  }) : plaintextSha256 = plaintextSha256 ?? sha256Checksum;
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
    String? expectedPlaintextSha256,
  });

  Future<Result<void>> deleteUserAttachment({
    required String userId,
    required String storageKey,
  });
}

/// Spark-safe Private On-Device Encrypted Document Vault (`SparkSafeFileStorageService`):
/// - Keeps Cloud Firebase strictly on Spark $0/month (NEVER writes binary blobs into Firestore).
/// - Encrypts every attachment with authenticated AES-256-GCM (Android Keystore) / AEAD ("LOSV")
///   before writing to persistent device vault (`noBackupFilesDir/secure_doc_vault`), NEVER temp dirs.
/// - Verifies AEAD tag and SHA-256 checksum fail-closed on every read.
class SparkSafeFileStorageService implements FileStorageService {
  static const int maxAttachmentBytes = 15 * 1024 * 1024; // 15 MB safety cap
  static final Map<String, Uint8List> _ephemeralWebVault =
      <String, Uint8List>{};
  static final Map<String, ({String sha256, int encryptedSize})>
  _ephemeralWebMeta = <String, ({String sha256, int encryptedSize})>{};

  final String? customVaultRootPath;
  final NativeSecureVaultBridge? _vaultBridgeOverride;

  const SparkSafeFileStorageService({
    this.customVaultRootPath,
    NativeSecureVaultBridge? vaultBridge,
  }) : _vaultBridgeOverride = vaultBridge;

  NativeSecureVaultBridge get _bridge =>
      _vaultBridgeOverride ?? NativeSecureVaultBridge.instance;

  @override
  bool get isCloudObjectStorageEnabled => false;

  @override
  bool get isLocalDeviceVaultEnabled => true;

  static String _sanitizeUid(String userId) =>
      userId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

  static String _sanitizeStorageKey(String storageKey) =>
      storageKey.replaceAll(RegExp(r'[\\/]'), '_');

  static String _buildAad(String userId, String storageKey) =>
      '${_sanitizeUid(userId)}|${_sanitizeStorageKey(storageKey)}';

  Future<Directory?> _resolveVaultDir(String userId) async {
    if (kIsWeb) return null;
    final safeUid = _sanitizeUid(userId);
    final String? base;
    if (customVaultRootPath != null && customVaultRootPath!.isNotEmpty) {
      base = customVaultRootPath;
    } else if (Platform.isAndroid || Platform.isIOS) {
      final nativeDir = await _bridge.getVaultDirectoryPath();
      if (nativeDir == null || nativeDir.trim().isEmpty) {
        throw const VaultSecurityException(
          'Persistent native secure vault directory is unavailable.',
        );
      }
      base = nativeDir;
    } else {
      final hostBase =
          Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          Platform.environment['XDG_DATA_HOME'] ??
          Platform.environment['HOME'];
      if (hostBase == null || hostBase.trim().isEmpty) {
        throw const VaultSecurityException(
          'Persistent host vault base directory is unavailable.',
        );
      }
      base =
          '$hostBase${Platform.pathSeparator}LifeOS${Platform.pathSeparator}secure_doc_vault';
    }
    final dir = Directory('$base${Platform.pathSeparator}$safeUid');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory?> _resolveLegacyVaultDir(String userId) async {
    if (kIsWeb || customVaultRootPath != null) return null;
    final legacyBase = await _bridge.getLegacyVaultDirectoryPath();
    if (legacyBase == null || legacyBase.trim().isEmpty) return null;
    final safeUid = _sanitizeUid(userId);
    final dir = Directory('$legacyBase${Platform.pathSeparator}$safeUid');
    return dir.existsSync() ? dir : null;
  }

  static File _metaFileFor(File encFile) => File('${encFile.path}.meta');

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
          message:
              'Tệp vượt quá giới hạn an toàn 15 MB cho kho lưu trữ cục bộ.',
        ),
      );
    }

    final safeFolder = folder.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '_');
    final digest = sha256.convert(bytes).toString();
    final rawKey = '${safeFolder}_${digest.substring(0, 12)}_$safeName';
    final key = rawKey.endsWith('.enc') ? rawKey : '$rawKey.enc';
    final aad = _buildAad(userId, key);

    if (kIsWeb) {
      final cipherPack = await _bridge.encryptBytes(
        plainBytes: bytes,
        aad: aad,
      );
      _ephemeralWebVault['$userId/$key'] = cipherPack;
      _ephemeralWebMeta['$userId/$key'] = (
        sha256: digest,
        encryptedSize: cipherPack.lengthInBytes,
      );
      return Success(
        StoredFileReference(
          storageKey: key,
          fileName: fileName,
          mimeType: mimeType,
          sizeBytes: bytes.lengthInBytes,
          sha256Checksum: digest,
          plaintextSha256: digest,
          encryptedSizeBytes: cipherPack.lengthInBytes,
        ),
      );
    }

    try {
      final dir = await _resolveVaultDir(userId);
      final targetFile = File('${dir!.path}${Platform.pathSeparator}$key');
      final cipherPack = await _bridge.encryptBytes(
        plainBytes: bytes,
        aad: aad,
      );
      await targetFile.writeAsBytes(cipherPack, flush: true);
      final metaFile = _metaFileFor(targetFile);
      await metaFile.writeAsString(
        jsonEncode(<String, dynamic>{
          'plaintextSha256': digest,
          'plaintextSizeBytes': bytes.lengthInBytes,
          'encryptedSizeBytes': cipherPack.lengthInBytes,
        }),
        flush: true,
      );

      return Success(
        StoredFileReference(
          storageKey: key,
          fileName: fileName,
          mimeType: mimeType,
          sizeBytes: bytes.lengthInBytes,
          sha256Checksum: digest,
          plaintextSha256: digest,
          encryptedSizeBytes: cipherPack.lengthInBytes,
          localFilePath: targetFile.path,
        ),
      );
    } catch (e) {
      return Err(
        UnexpectedFailure(
          code: 'LOCAL_VAULT_WRITE_FAILED',
          message:
              'Không thể mã hóa và lưu tệp vào kho an toàn trên thiết bị: $e',
        ),
      );
    }
  }

  @override
  Future<Result<Uint8List?>> readLocalAttachmentBytes({
    required String userId,
    required String storageKey,
    String? expectedPlaintextSha256,
  }) async {
    final safeKey = _sanitizeStorageKey(storageKey);
    final aad = _buildAad(userId, safeKey);

    if (kIsWeb) {
      final cipherPack = _ephemeralWebVault['$userId/$safeKey'];
      if (cipherPack == null) return const Success(null);
      final meta = _ephemeralWebMeta['$userId/$safeKey'];
      if (meta != null && cipherPack.lengthInBytes != meta.encryptedSize) {
        throw const VaultSecurityException(
          'Encrypted web vault attachment size mismatch.',
        );
      }
      final plain = await _bridge.decryptBytes(
        cipherPack: cipherPack,
        aad: aad,
      );
      final actualDigest = sha256.convert(plain).toString();
      final expectedSha = expectedPlaintextSha256 ?? meta?.sha256;
      if (expectedSha != null &&
          expectedSha.isNotEmpty &&
          actualDigest != expectedSha) {
        throw const VaultSecurityException(
          'Decrypted web attachment SHA-256 mismatch.',
        );
      }
      return Success(plain);
    }

    final dir = await _resolveVaultDir(userId);
    var f = File('${dir!.path}${Platform.pathSeparator}$safeKey');
    if (!f.existsSync()) {
      final legacyDir = await _resolveLegacyVaultDir(userId);
      if (legacyDir != null) {
        final legacyFile = File(
          '${legacyDir.path}${Platform.pathSeparator}$safeKey',
        );
        if (legacyFile.existsSync()) {
          f = legacyFile;
        }
      }
    }
    if (!f.existsSync()) return const Success(null);

    final cipherPack = await f.readAsBytes();
    if (cipherPack.length < NativeSecureVaultBridge.magicHeaderBytes.length) {
      throw const VaultSecurityException(
        'Vault attachment is corrupted or unencrypted (missing LOSV header).',
      );
    }
    for (var i = 0; i < NativeSecureVaultBridge.magicHeaderBytes.length; i++) {
      if (cipherPack[i] != NativeSecureVaultBridge.magicHeaderBytes[i]) {
        throw const VaultSecurityException(
          'Vault attachment failed LOSV magic header validation.',
        );
      }
    }

    String? metaPlainSha;
    int? metaEncryptedSize;
    final metaFile = _metaFileFor(f);
    if (metaFile.existsSync()) {
      try {
        final decoded = jsonDecode(await metaFile.readAsString());
        if (decoded is Map) {
          metaPlainSha = decoded['plaintextSha256'] as String?;
          metaEncryptedSize = (decoded['encryptedSizeBytes'] as num?)?.toInt();
        }
      } catch (e) {
        throw VaultSecurityException(
          'Corrupted vault attachment integrity metadata: $e',
        );
      }
    }

    if (metaEncryptedSize != null &&
        cipherPack.lengthInBytes != metaEncryptedSize) {
      throw const VaultSecurityException(
        'Encrypted vault file size does not match recorded encryptedSizeBytes.',
      );
    }

    final plain = await _bridge.decryptBytes(cipherPack: cipherPack, aad: aad);

    final actualDigest = sha256.convert(plain).toString();
    if (metaPlainSha != null &&
        metaPlainSha.isNotEmpty &&
        actualDigest != metaPlainSha) {
      throw const VaultSecurityException(
        'Decrypted attachment SHA-256 mismatch against recorded plaintextSha256.',
      );
    }
    if (expectedPlaintextSha256 != null &&
        expectedPlaintextSha256.isNotEmpty &&
        actualDigest != expectedPlaintextSha256) {
      throw const VaultSecurityException(
        'Decrypted attachment SHA-256 mismatch against expected document checksum.',
      );
    }

    return Success(plain);
  }

  /// Deletes an encrypted local attachment and its `.meta` sidecar, verifying
  /// `!file.existsSync()` afterwards. Returns `false` if deletion fails or the
  /// file remains on disk — NEVER fakes success.
  Future<bool> deleteAttachment({
    required String userId,
    required String storageKey,
    String? localFilePath,
  }) async {
    final safeKey = _sanitizeStorageKey(storageKey);
    if (kIsWeb) {
      _ephemeralWebVault.remove('$userId/$safeKey');
      _ephemeralWebMeta.remove('$userId/$safeKey');
      return !_ephemeralWebVault.containsKey('$userId/$safeKey');
    }

    var allDeleted = true;
    Future<void> unlinkIfExists(File target) async {
      if (!target.existsSync()) return;
      try {
        await target.delete();
      } on FileSystemException {
        allDeleted = false;
      }
      if (target.existsSync()) {
        allDeleted = false;
      }
    }

    try {
      if (safeKey.isNotEmpty) {
        final dir = await _resolveVaultDir(userId);
        if (dir != null) {
          final f = File('${dir.path}${Platform.pathSeparator}$safeKey');
          await unlinkIfExists(f);
          await unlinkIfExists(_metaFileFor(f));
        }
        final legacyDir = await _resolveLegacyVaultDir(userId);
        if (legacyDir != null) {
          final lf = File('${legacyDir.path}${Platform.pathSeparator}$safeKey');
          await unlinkIfExists(lf);
          await unlinkIfExists(_metaFileFor(lf));
        }
      }
      if (localFilePath != null && localFilePath.isNotEmpty) {
        final direct = File(localFilePath);
        await unlinkIfExists(direct);
        await unlinkIfExists(_metaFileFor(direct));
      }
    } catch (_) {
      return false;
    }

    return allDeleted;
  }

  @override
  Future<Result<void>> deleteUserAttachment({
    required String userId,
    required String storageKey,
  }) async {
    final deleted = await deleteAttachment(
      userId: userId,
      storageKey: storageKey,
    );
    if (!deleted) {
      return const Err(
        UnexpectedFailure(
          code: 'LOCAL_VAULT_DELETE_FAILED',
          message:
              'Không thể xóa tệp đính kèm khỏi kho lưu trữ cục bộ trên thiết bị.',
        ),
      );
    }
    return const Success(null);
  }
}
