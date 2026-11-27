import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../error/app_exception.dart';
import '../error/failure.dart';
import 'native_secure_vault_bridge.dart';

/// Metadata descriptor for binary attachments (receipt scans, vehicle papers, PDF contracts).
/// Binary bytes are NEVER stored inside Cloud Firestore documents to preserve Spark quota & latency.
final class StoredFileReference {
  final String storageKey;
  final String? attachmentId;
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
    this.attachmentId,
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
    String? storageKey,
    String? attachmentId,
    String? expectedPlaintextSha256,
  });

  Future<Result<void>> deleteUserAttachment({
    required String userId,
    required String storageKey,
  });

  Future<bool> deleteAttachmentForUser({
    required String userId,
    String? attachmentId,
    String? legacyLocalPath,
    String? legacyStorageKey,
  });
}

/// Spark-safe Private On-Device Encrypted Document Vault (`SparkSafeFileStorageService`):
/// - Keeps Cloud Firebase strictly on Spark $0/month (NEVER writes binary blobs into Firestore).
/// - Encrypts every attachment with authenticated AES-256-GCM (Android Keystore) / AEAD ("LOSV")
///   before writing to persistent device vault (`noBackupFilesDir/secure_doc_vault`), NEVER temp dirs.
/// - Verifies AEAD tag and SHA-256 checksum fail-closed on every read.
class SparkSafeFileStorageService implements FileStorageService {
  static const int maxAttachmentBytes = 15 * 1024 * 1024; // 15 MB safety cap
  static const String attachmentIndexFileName = 'attachment_index.json';
  static final RegExp validAttachmentIdRegex = RegExp(r'^[A-Za-z0-9_-]{8,96}$');
  static const Uuid _uuid = Uuid();

  static final Map<String, Uint8List> _ephemeralWebVault =
      <String, Uint8List>{};
  static final Map<String, ({String sha256, int encryptedSize})>
  _ephemeralWebMeta = <String, ({String sha256, int encryptedSize})>{};
  static final Map<String, String> _ephemeralWebAttachmentIndex =
      <String, String>{};

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

  static String sanitizeUserIdSegment(String userId) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') {
      throw const VaultSecurityException(
        'User ID segment cannot be empty or relative traversal.',
      );
    }
    final sanitized = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      throw const VaultSecurityException(
        'Sanitized user ID segment cannot be empty or relative traversal.',
      );
    }
    return sanitized;
  }

  static String? _sanitizeUidOrNull(String? userId) {
    if (userId == null) return null;
    try {
      return sanitizeUserIdSegment(userId);
    } on VaultSecurityException {
      return null;
    }
  }

  static String _sanitizeUid(String userId) => sanitizeUserIdSegment(userId);

  static bool isValidAttachmentId(String? value) {
    if (value == null || value.isEmpty || value.contains('..')) return false;
    return validAttachmentIdRegex.hasMatch(value);
  }

  static bool isSingleSafeFileName(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed != value ||
        trimmed == '.' ||
        trimmed == '..' ||
        trimmed == attachmentIndexFileName) {
      return false;
    }
    if (trimmed.contains('/') ||
        trimmed.contains(r'\') ||
        trimmed.contains('\x00') ||
        trimmed.contains('..') ||
        trimmed.contains(':')) {
      return false;
    }
    return true;
  }

  static String _buildAad(String userId, String storageKey) =>
      '${_sanitizeUid(userId)}|$storageKey';

  static String _normalizeForComparison(String path) {
    var normalized = Platform.isWindows ? path.replaceAll('/', r'\') : path;
    while (normalized.length > 1 &&
        normalized.endsWith(Platform.pathSeparator) &&
        !(Platform.isWindows &&
            normalized.length == 3 &&
            normalized[1] == ':')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static ({String root, List<String> segments}) _splitAbsolutePath(
    String absPath,
  ) {
    final osPath = Platform.isWindows ? absPath.replaceAll('/', r'\') : absPath;
    if (Platform.isWindows) {
      if (osPath.startsWith(r'\\')) {
        // UNC path: \\server\share\...
        final parts = osPath
            .substring(2)
            .split(r'\')
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.length >= 2) {
          final root = '\\\\${parts[0]}\\${parts[1]}';
          return (root: root, segments: parts.sublist(2));
        }
      }
      if (osPath.length >= 2 && osPath[1] == ':') {
        final root = '${osPath.substring(0, 2)}\\';
        final rest = osPath
            .substring(2)
            .split(r'\')
            .where((s) => s.isNotEmpty)
            .toList();
        return (root: root, segments: rest);
      }
    }
    final segments = osPath.split('/').where((s) => s.isNotEmpty).toList();
    return (root: '/', segments: segments);
  }

  static String _joinPath(String root, List<String> segments) {
    if (segments.isEmpty) return root;
    final sep = Platform.pathSeparator;
    final base = root.endsWith(sep) ? root.substring(0, root.length - 1) : root;
    return '$base$sep${segments.join(sep)}';
  }

  /// Resolves [rawPath] left-to-right collapsing `.` / `..` AND resolving real
  /// symlinks along the path. Returns `null` if a dangling/cyclic symlink or
  /// invalid path is encountered.
  static String? _resolveCanonicalPath(String rawPath) {
    if (rawPath.trim().isEmpty || rawPath.contains('\x00')) return null;
    try {
      final osRaw = Platform.isWindows
          ? rawPath.replaceAll('/', r'\')
          : rawPath;
      final split = _splitAbsolutePath(File(osRaw).absolute.path);
      var currentRoot = split.root;
      var resolvedSegments = <String>[];
      var linkHops = 0;

      final queue = List<String>.from(split.segments);
      for (var i = 0; i < queue.length; i++) {
        final seg = queue[i];
        if (seg.isEmpty || seg == '.') continue;
        if (seg == '..') {
          if (resolvedSegments.isNotEmpty) {
            resolvedSegments.removeLast();
          }
          continue;
        }
        resolvedSegments.add(seg);
        final probe = _joinPath(currentRoot, resolvedSegments);
        final entityType = FileSystemEntity.typeSync(probe, followLinks: false);
        if (entityType == FileSystemEntityType.link) {
          linkHops += 1;
          if (linkHops > 32) return null;
          final targetResolved = File(probe).resolveSymbolicLinksSync();
          final targetSplit = _splitAbsolutePath(targetResolved);
          currentRoot = targetSplit.root;
          resolvedSegments = List<String>.from(targetSplit.segments);
        }
      }

      final candidate = _joinPath(currentRoot, resolvedSegments);
      final finalType = FileSystemEntity.typeSync(
        candidate,
        followLinks: false,
      );
      if (finalType == FileSystemEntityType.link) {
        return File(candidate).resolveSymbolicLinksSync();
      }
      if (finalType != FileSystemEntityType.notFound) {
        return File(candidate).resolveSymbolicLinksSync();
      }
      return candidate;
    } catch (_) {
      return null;
    }
  }

  /// Strict canonical path containment verifier (H6):
  /// Returns `true` iff [candidateFile] resolves strictly inside [userVaultDir]
  /// (rejecting `..`, symlink escapes, dangling symlinks, and directory self-match).
  static bool isCanonicalPathStrictlyInsideDirectory({
    required Directory userVaultDir,
    required File candidateFile,
  }) {
    final baseCanonical = _resolveCanonicalPath(userVaultDir.path);
    final targetCanonical = _resolveCanonicalPath(candidateFile.path);
    if (baseCanonical == null || targetCanonical == null) return false;

    final baseNorm = _normalizeForComparison(baseCanonical);
    final targetNorm = _normalizeForComparison(targetCanonical);
    final sep = Platform.pathSeparator;
    final basePrefix = baseNorm.endsWith(sep) ? baseNorm : '$baseNorm$sep';
    return targetNorm.length > basePrefix.length &&
        targetNorm.startsWith(basePrefix);
  }

  static Future<String?> _resolveVaultBasePath({
    String? customVaultRootPath,
    NativeSecureVaultBridge? vaultBridge,
  }) async {
    if (customVaultRootPath != null && customVaultRootPath.isNotEmpty) {
      return customVaultRootPath;
    }
    final bridge = vaultBridge ?? NativeSecureVaultBridge.instance;
    if (Platform.isAndroid || Platform.isIOS) {
      final nativeDir = await bridge.getVaultDirectoryPath();
      if (nativeDir == null || nativeDir.trim().isEmpty) {
        return null;
      }
      return nativeDir;
    }
    final hostBase =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Platform.environment['XDG_DATA_HOME'] ??
        Platform.environment['HOME'];
    if (hostBase == null || hostBase.trim().isEmpty) {
      return null;
    }
    return '$hostBase${Platform.pathSeparator}LifeOS${Platform.pathSeparator}secure_doc_vault';
  }

  Future<Directory?> _resolveVaultDir(
    String userId, {
    bool createIfMissing = true,
  }) async {
    if (kIsWeb) return null;
    final safeUid = _sanitizeUid(userId);
    final base = await _resolveVaultBasePath(
      customVaultRootPath: customVaultRootPath,
      vaultBridge: _bridge,
    );
    if (base == null || base.trim().isEmpty) {
      if (Platform.isAndroid || Platform.isIOS) {
        throw const VaultSecurityException(
          'Persistent native secure vault directory is unavailable.',
        );
      }
      throw const VaultSecurityException(
        'Persistent host vault base directory is unavailable.',
      );
    }
    final dir = Directory('$base${Platform.pathSeparator}$safeUid');
    if (createIfMissing && !dir.existsSync()) {
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

  static File _indexFileFor(Directory userVaultDir) => File(
    '${userVaultDir.path}${Platform.pathSeparator}$attachmentIndexFileName',
  );

  static Future<Map<String, String>> _loadAttachmentIndex(
    Directory userVaultDir,
  ) async {
    final indexFile = _indexFileFor(userVaultDir);
    if (!indexFile.existsSync()) return <String, String>{};
    if (!isCanonicalPathStrictlyInsideDirectory(
      userVaultDir: userVaultDir,
      candidateFile: indexFile,
    )) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(await indexFile.readAsString());
      if (decoded is! Map) return <String, String>{};
      final out = <String, String>{};
      decoded.forEach((key, value) {
        final attId = key?.toString();
        final fileName = value?.toString();
        if (isValidAttachmentId(attId) && isSingleSafeFileName(fileName)) {
          out[attId!] = fileName!;
        }
      });
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<void> _saveAttachmentIndex(
    Directory userVaultDir,
    Map<String, String> index,
  ) async {
    final indexFile = _indexFileFor(userVaultDir);
    final clean = <String, String>{};
    index.forEach((key, value) {
      if (isValidAttachmentId(key) && isSingleSafeFileName(value)) {
        clean[key] = value;
      }
    });
    await indexFile.writeAsString(jsonEncode(clean), flush: true);
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
          message:
              'Tệp vượt quá giới hạn an toàn 15 MB cho kho lưu trữ cục bộ.',
        ),
      );
    }

    final safeUid = _sanitizeUid(userId);
    final safeFolder = folder.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final safeName = fileName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '_')
        .replaceAll('..', '_');
    final digest = sha256.convert(bytes).toString();
    final rawKey = '${safeFolder}_${digest.substring(0, 12)}_$safeName';
    final key = rawKey.endsWith('.enc') ? rawKey : '$rawKey.enc';
    if (!isSingleSafeFileName(key)) {
      return const Err(
        ValidationFailure(
          code: 'INVALID_ATTACHMENT_NAME',
          message: 'Tên tệp đính kèm không hợp lệ.',
        ),
      );
    }
    final attachmentId =
        'att_${digest.substring(0, 12)}_${_uuid.v4().replaceAll('-', '').substring(0, 12)}';
    final aad = _buildAad(userId, key);

    if (kIsWeb) {
      final cipherPack = await _bridge.encryptBytes(
        plainBytes: bytes,
        aad: aad,
      );
      _ephemeralWebVault['$safeUid/$key'] = cipherPack;
      _ephemeralWebMeta['$safeUid/$key'] = (
        sha256: digest,
        encryptedSize: cipherPack.lengthInBytes,
      );
      _ephemeralWebAttachmentIndex['$safeUid/$attachmentId'] = key;
      return Success(
        StoredFileReference(
          storageKey: key,
          attachmentId: attachmentId,
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
      if (!isCanonicalPathStrictlyInsideDirectory(
        userVaultDir: dir,
        candidateFile: targetFile,
      )) {
        return const Err(
          ValidationFailure(
            code: 'INVALID_ATTACHMENT_PATH',
            message: 'Đường dẫn lưu tệp vượt khỏi phạm vi kho an toàn.',
          ),
        );
      }
      final cipherPack = await _bridge.encryptBytes(
        plainBytes: bytes,
        aad: aad,
      );
      await targetFile.writeAsBytes(cipherPack, flush: true);
      final metaFile = _metaFileFor(targetFile);
      await metaFile.writeAsString(
        jsonEncode(<String, dynamic>{
          'ownerId': userId,
          'attachmentId': attachmentId,
          'plaintextSha256': digest,
          'plaintextSizeBytes': bytes.lengthInBytes,
          'encryptedSizeBytes': cipherPack.lengthInBytes,
        }),
        flush: true,
      );

      final index = await _loadAttachmentIndex(dir);
      index[attachmentId] = key;
      await _saveAttachmentIndex(dir, index);

      return Success(
        StoredFileReference(
          storageKey: key,
          attachmentId: attachmentId,
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
    String? storageKey,
    String? attachmentId,
    String? expectedPlaintextSha256,
  }) async {
    final safeUid = _sanitizeUid(userId);
    final trimmedAttId = attachmentId?.trim();
    if (trimmedAttId != null &&
        trimmedAttId.isNotEmpty &&
        !isValidAttachmentId(trimmedAttId)) {
      throw const VaultSecurityException(
        'Invalid opaque attachmentId (rejected path traversal).',
      );
    }

    final trimmedStorageKey = storageKey?.trim();
    if (trimmedStorageKey != null &&
        trimmedStorageKey.isNotEmpty &&
        !isSingleSafeFileName(trimmedStorageKey)) {
      throw const VaultSecurityException(
        'Invalid storageKey (rejected path traversal).',
      );
    }

    if (kIsWeb) {
      String? resolvedKey;
      if (trimmedAttId != null && trimmedAttId.isNotEmpty) {
        resolvedKey = _ephemeralWebAttachmentIndex['$safeUid/$trimmedAttId'];
      }
      resolvedKey ??= trimmedStorageKey;
      if (resolvedKey == null || resolvedKey.isEmpty) {
        return const Success(null);
      }
      final cipherPack =
          _ephemeralWebVault['$safeUid/$resolvedKey'] ??
          _ephemeralWebVault['$userId/$resolvedKey'];
      if (cipherPack == null) return const Success(null);
      final meta =
          _ephemeralWebMeta['$safeUid/$resolvedKey'] ??
          _ephemeralWebMeta['$userId/$resolvedKey'];
      if (meta != null && cipherPack.lengthInBytes != meta.encryptedSize) {
        throw const VaultSecurityException(
          'Encrypted web vault attachment size mismatch.',
        );
      }
      final aad = _buildAad(userId, resolvedKey);
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

    final dir = await _resolveVaultDir(userId, createIfMissing: false);
    final legacyDir = await _resolveLegacyVaultDir(userId);

    String? resolvedFileName;
    if (trimmedAttId != null && trimmedAttId.isNotEmpty) {
      if (dir != null && dir.existsSync()) {
        final idx = await _loadAttachmentIndex(dir);
        resolvedFileName = idx[trimmedAttId];
      }
      if (resolvedFileName == null &&
          legacyDir != null &&
          legacyDir.existsSync()) {
        final legacyIdx = await _loadAttachmentIndex(legacyDir);
        resolvedFileName = legacyIdx[trimmedAttId];
      }
    }
    resolvedFileName ??= trimmedStorageKey;

    if (resolvedFileName == null || resolvedFileName.isEmpty) {
      return const Success(null);
    }
    if (!isSingleSafeFileName(resolvedFileName)) {
      throw const VaultSecurityException(
        'Resolved attachment filename failed single-filename safety check.',
      );
    }

    File? f;
    if (dir != null && dir.existsSync()) {
      final candidate = File(
        '${dir.path}${Platform.pathSeparator}$resolvedFileName',
      );
      if (!isCanonicalPathStrictlyInsideDirectory(
        userVaultDir: dir,
        candidateFile: candidate,
      )) {
        throw const VaultSecurityException(
          'Attachment path escapes user vault directory.',
        );
      }
      if (candidate.existsSync()) {
        f = candidate;
      }
    }
    if (f == null && legacyDir != null && legacyDir.existsSync()) {
      final legacyCandidate = File(
        '${legacyDir.path}${Platform.pathSeparator}$resolvedFileName',
      );
      if (!isCanonicalPathStrictlyInsideDirectory(
        userVaultDir: legacyDir,
        candidateFile: legacyCandidate,
      )) {
        throw const VaultSecurityException(
          'Legacy attachment path escapes user vault directory.',
        );
      }
      if (legacyCandidate.existsSync()) {
        f = legacyCandidate;
      }
    }
    if (f == null || !f.existsSync()) return const Success(null);

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

    final aad = _buildAad(userId, resolvedFileName);
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

  /// Path-contained per-user attachment deletion (H6):
  /// 1. Looks up opaque [attachmentId] in `<vaultRoot>/<sanitizedUserId>/attachment_index.json` first.
  /// 2. Falls back to [legacyStorageKey] or [legacyLocalPath] ONLY when the resolved file
  ///    is strictly contained inside `<vaultRoot>/<sanitizedUserId>` (or legacy user vault dir).
  /// 3. Rejects any `..`, symlink escape, or path outside the user's vault directory!
  @override
  Future<bool> deleteAttachmentForUser({
    required String userId,
    String? attachmentId,
    String? legacyLocalPath,
    String? legacyStorageKey,
  }) async {
    final safeUid = _sanitizeUidOrNull(userId);
    if (safeUid == null) return false;

    final trimmedAttId = attachmentId?.trim();
    if (trimmedAttId != null &&
        trimmedAttId.isNotEmpty &&
        !isValidAttachmentId(trimmedAttId)) {
      return false;
    }

    final trimmedLegacyKey = legacyStorageKey?.trim();
    if (trimmedLegacyKey != null &&
        trimmedLegacyKey.isNotEmpty &&
        !isSingleSafeFileName(trimmedLegacyKey)) {
      return false;
    }

    if (kIsWeb) {
      var targetKey = trimmedLegacyKey;
      if (trimmedAttId != null && trimmedAttId.isNotEmpty) {
        final indexed = _ephemeralWebAttachmentIndex.remove(
          '$safeUid/$trimmedAttId',
        );
        targetKey ??= indexed;
      }
      if (targetKey != null && targetKey.isNotEmpty) {
        _ephemeralWebVault.remove('$safeUid/$targetKey');
        _ephemeralWebMeta.remove('$safeUid/$targetKey');
        _ephemeralWebVault.remove('$userId/$targetKey');
        _ephemeralWebMeta.remove('$userId/$targetKey');
      }
      return true;
    }

    var allDeleted = true;
    Future<void> unlinkIfExists(File target, Directory allowedDir) async {
      if (!isCanonicalPathStrictlyInsideDirectory(
        userVaultDir: allowedDir,
        candidateFile: target,
      )) {
        allDeleted = false;
        return;
      }
      if (FileSystemEntity.isLinkSync(target.path)) {
        // Unlink only if inside dir, never touch target outside.
        try {
          await Link(target.path).delete();
        } on FileSystemException {
          allDeleted = false;
        }
        return;
      }
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
      final dir = await _resolveVaultDir(userId, createIfMissing: false);
      final legacyDir = await _resolveLegacyVaultDir(userId);
      final allowedDirs = <Directory>[
        if (dir != null && dir.existsSync()) dir,
        if (legacyDir != null && legacyDir.existsSync()) legacyDir,
      ];

      var deletedByIndex = false;
      if (trimmedAttId != null && trimmedAttId.isNotEmpty) {
        for (final vaultDir in allowedDirs) {
          final index = await _loadAttachmentIndex(vaultDir);
          final indexedFileName = index.remove(trimmedAttId);
          if (indexedFileName != null &&
              isSingleSafeFileName(indexedFileName)) {
            final target = File(
              '${vaultDir.path}${Platform.pathSeparator}$indexedFileName',
            );
            await unlinkIfExists(target, vaultDir);
            await unlinkIfExists(_metaFileFor(target), vaultDir);
            await _saveAttachmentIndex(vaultDir, index);
            deletedByIndex = true;
          }
        }
      }

      if (!deletedByIndex) {
        if (trimmedLegacyKey != null && trimmedLegacyKey.isNotEmpty) {
          for (final vaultDir in allowedDirs) {
            final target = File(
              '${vaultDir.path}${Platform.pathSeparator}$trimmedLegacyKey',
            );
            await unlinkIfExists(target, vaultDir);
            await unlinkIfExists(_metaFileFor(target), vaultDir);
          }
        }

        final trimmedLegacyPath = legacyLocalPath?.trim();
        if (trimmedLegacyPath != null && trimmedLegacyPath.isNotEmpty) {
          final candidate = File(trimmedLegacyPath);
          Directory? matchingBase;
          for (final vaultDir in allowedDirs) {
            if (isCanonicalPathStrictlyInsideDirectory(
              userVaultDir: vaultDir,
              candidateFile: candidate,
            )) {
              matchingBase = vaultDir;
              break;
            }
          }
          if (matchingBase == null) {
            // Strictly reject any path outside the user's vault directory!
            return false;
          }
          final fileName = _resolveCanonicalPath(
            candidate.path,
          )?.split(Platform.pathSeparator).last;
          if (fileName == attachmentIndexFileName) {
            return false;
          }
          await unlinkIfExists(candidate, matchingBase);
          await unlinkIfExists(_metaFileFor(candidate), matchingBase);
        }
      }
    } catch (_) {
      return false;
    }

    return allDeleted;
  }

  /// Deletes an encrypted local attachment and its `.meta` sidecar, verifying
  /// `!file.existsSync()` afterwards. Enforces strict canonical path containment.
  Future<bool> deleteAttachment({
    required String userId,
    required String storageKey,
    String? localFilePath,
  }) {
    return deleteAttachmentForUser(
      userId: userId,
      legacyStorageKey: storageKey,
      legacyLocalPath: localFilePath,
    );
  }

  @override
  Future<Result<void>> deleteUserAttachment({
    required String userId,
    required String storageKey,
  }) async {
    final deleted = await deleteAttachmentForUser(
      userId: userId,
      legacyStorageKey: storageKey,
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

  static Future<void> _deleteDirectorySafely(
    Directory dir,
    Directory allowedBase,
  ) async {
    if (!isCanonicalPathStrictlyInsideDirectory(
      userVaultDir: allowedBase,
      candidateFile: File(dir.path),
    )) {
      return;
    }
    if (FileSystemEntity.isLinkSync(dir.path)) {
      await Link(dir.path).delete();
      return;
    }
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is Link || FileSystemEntity.isLinkSync(entity.path)) {
        await Link(entity.path).delete();
      } else if (entity is Directory) {
        await _deleteDirectorySafely(entity, dir);
      } else if (entity is File) {
        await entity.delete();
      }
    }
    if (dir.existsSync()) {
      await dir.delete();
    }
  }

  /// Account-scoped document vault cleanup (H4):
  /// Safely deletes ONLY `<vaultRoot>/<sanitizedUserId>` (verified via canonical
  /// path containment), leaving all other users' vault directories untouched.
  static Future<void> clearVaultForUser(
    String userId, {
    String? customVaultRootPath,
    NativeSecureVaultBridge? vaultBridge,
  }) async {
    final safeUid = _sanitizeUidOrNull(userId);
    if (safeUid == null) return;

    if (kIsWeb) {
      final prefixes = <String>['$safeUid/', '${userId.trim()}/'];
      _ephemeralWebVault.removeWhere(
        (k, _) => prefixes.any((p) => k.startsWith(p)),
      );
      _ephemeralWebMeta.removeWhere(
        (k, _) => prefixes.any((p) => k.startsWith(p)),
      );
      _ephemeralWebAttachmentIndex.removeWhere(
        (k, _) => prefixes.any((p) => k.startsWith(p)),
      );
      return;
    }

    final bridge = vaultBridge ?? NativeSecureVaultBridge.instance;
    final basePaths = <String>{};
    final primaryBase = await _resolveVaultBasePath(
      customVaultRootPath: customVaultRootPath,
      vaultBridge: bridge,
    );
    if (primaryBase != null && primaryBase.trim().isNotEmpty) {
      basePaths.add(primaryBase);
    }
    if (customVaultRootPath == null && (Platform.isAndroid || Platform.isIOS)) {
      final legacyBase = await bridge.getLegacyVaultDirectoryPath();
      if (legacyBase != null && legacyBase.trim().isNotEmpty) {
        basePaths.add(legacyBase);
      }
    }

    for (final basePath in basePaths) {
      final baseDir = Directory(basePath);
      if (!baseDir.existsSync()) continue;
      final userDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}$safeUid',
      );
      if (FileSystemEntity.isLinkSync(userDir.path)) {
        // Never follow a symlink out of vaultRoot into another user's dir.
        continue;
      }
      if (!userDir.existsSync()) continue;
      if (!isCanonicalPathStrictlyInsideDirectory(
        userVaultDir: baseDir,
        candidateFile: File(userDir.path),
      )) {
        continue;
      }
      await _deleteDirectorySafely(userDir, baseDir);
    }
  }
}
