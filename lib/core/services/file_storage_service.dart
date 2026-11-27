import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

/// Durable record of a local encrypted attachment whose deletion failed and
/// must be retried safely within `<vaultRoot>/<safeUid>/pending_cleanups.json`.
final class PendingVaultCleanupRecord {
  final String? attachmentId;
  final String? legacyLocalPath;
  final String? legacyStorageKey;
  final DateTime timestamp;

  const PendingVaultCleanupRecord({
    this.attachmentId,
    this.legacyLocalPath,
    this.legacyStorageKey,
    required this.timestamp,
  });

  String get dedupKey =>
      '${attachmentId ?? ''}|${legacyStorageKey ?? ''}|${legacyLocalPath ?? ''}';

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (attachmentId != null && attachmentId!.isNotEmpty)
      'attachmentId': attachmentId,
    if (legacyLocalPath != null && legacyLocalPath!.isNotEmpty)
      'legacyLocalPath': legacyLocalPath,
    if (legacyStorageKey != null && legacyStorageKey!.isNotEmpty)
      'legacyStorageKey': legacyStorageKey,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  factory PendingVaultCleanupRecord.fromJson(Map<String, dynamic> json) {
    final rawTs = json['timestamp']?.toString();
    return PendingVaultCleanupRecord(
      attachmentId: json['attachmentId']?.toString(),
      legacyLocalPath: json['legacyLocalPath']?.toString(),
      legacyStorageKey: json['legacyStorageKey']?.toString(),
      timestamp:
          (rawTs != null ? DateTime.tryParse(rawTs) : null) ??
          DateTime.now().toUtc(),
    );
  }
}

/// Spark-safe Private On-Device Encrypted Document Vault (`SparkSafeFileStorageService`):
/// - Keeps Cloud Firebase strictly on Spark $0/month (NEVER writes binary blobs into Firestore).
/// - Encrypts every attachment with authenticated AES-256-GCM (Android Keystore) / AEAD ("LOSV")
///   before writing to persistent device vault (`noBackupFilesDir/secure_doc_vault`), NEVER temp dirs.
/// - Verifies AEAD tag and SHA-256 checksum fail-closed on every read.
class SparkSafeFileStorageService implements FileStorageService {
  static const int maxAttachmentBytes = 15 * 1024 * 1024; // 15 MB safety cap
  static const String attachmentIndexFileName = 'attachment_index.json';
  static const String attachmentIndexBackupFileName =
      'attachment_index.json.bak';
  static const String pendingCleanupsFileName = 'pending_cleanups.json';
  static final RegExp validAttachmentIdRegex = RegExp(r'^[A-Za-z0-9_-]{8,96}$');
  static const Uuid _uuid = Uuid();

  static final Map<String, Future<void>> _indexLocks = <String, Future<void>>{};
  static int _atomicWriteCounter = 0;
  static final Random _nonceRandom = Random.secure();

  static final Map<String, Uint8List> _ephemeralWebVault =
      <String, Uint8List>{};
  static final Map<String, ({String sha256, int encryptedSize})>
  _ephemeralWebMeta = <String, ({String sha256, int encryptedSize})>{};
  static final Map<String, String> _ephemeralWebAttachmentIndex =
      <String, String>{};
  static final Map<String, List<PendingVaultCleanupRecord>>
  _ephemeralWebPendingCleanups = <String, List<PendingVaultCleanupRecord>>{};

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
        trimmed == attachmentIndexFileName ||
        trimmed == attachmentIndexBackupFileName ||
        trimmed == pendingCleanupsFileName) {
      return false;
    }
    if (trimmed.contains('/') ||
        trimmed.contains(r'\') ||
        trimmed.contains('\x00') ||
        trimmed.contains('..') ||
        trimmed.contains(':') ||
        trimmed.contains('.tmp.')) {
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

  static File _metaJsonFileFor(File encFile) {
    final p = encFile.path;
    if (p.toLowerCase().endsWith('.enc')) {
      return File('${p.substring(0, p.length - 4)}.meta.json');
    }
    return File('$p.meta.json');
  }

  static File _legacyMetaFileFor(File encFile) => File('${encFile.path}.meta');

  static File _indexFileFor(Directory userVaultDir) => File(
    '${userVaultDir.path}${Platform.pathSeparator}$attachmentIndexFileName',
  );

  static File _indexBackupFileFor(Directory userVaultDir) => File(
    '${userVaultDir.path}${Platform.pathSeparator}$attachmentIndexBackupFileName',
  );

  static File _pendingCleanupsFileFor(Directory userVaultDir) => File(
    '${userVaultDir.path}${Platform.pathSeparator}$pendingCleanupsFileName',
  );

  static String _nextAtomicNonce() {
    _atomicWriteCounter += 1;
    final rand = _nonceRandom.nextInt(0x7FFFFFFF).toRadixString(36);
    return '${DateTime.now().microsecondsSinceEpoch}_${_atomicWriteCounter}_$rand';
  }

  /// Per-UID async FIFO mutex serializing all `attachment_index.json` and
  /// `pending_cleanups.json` reads/writes for [safeUid].
  static Future<T> _withIndexLock<T>(
    String safeUid,
    Future<T> Function() action,
  ) async {
    final prev = _indexLocks[safeUid] ?? Future<void>.value();
    final completer = Completer<void>();
    final tail = prev.catchError((_) {}).then((_) => completer.future);
    _indexLocks[safeUid] = tail;
    try {
      await prev.catchError((_) {});
      return await action();
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (identical(_indexLocks[safeUid], tail)) {
        unawaited(
          tail.whenComplete(() {
            if (identical(_indexLocks[safeUid], tail)) {
              _indexLocks.remove(safeUid);
            }
          }),
        );
      }
    }
  }

  static Map<String, String>? _tryParseValidIndexMap(
    File candidate,
    Directory userVaultDir,
  ) {
    if (!candidate.existsSync()) return null;
    if (FileSystemEntity.isLinkSync(candidate.path)) return null;
    if (!isCanonicalPathStrictlyInsideDirectory(
      userVaultDir: userVaultDir,
      candidateFile: candidate,
    )) {
      return null;
    }
    try {
      final raw = candidate.readAsStringSync();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
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
      return null;
    }
  }

  static bool _hasLosvMagicHeader(File encFile) {
    RandomAccessFile? raf;
    try {
      if (!encFile.existsSync() || FileSystemEntity.isLinkSync(encFile.path)) {
        return false;
      }
      final len = encFile.lengthSync();
      if (len < NativeSecureVaultBridge.magicHeaderBytes.length) return false;
      raf = encFile.openSync(mode: FileMode.read);
      final header = raf.readSync(
        NativeSecureVaultBridge.magicHeaderBytes.length,
      );
      if (header.length < NativeSecureVaultBridge.magicHeaderBytes.length) {
        return false;
      }
      for (
        var i = 0;
        i < NativeSecureVaultBridge.magicHeaderBytes.length;
        i++
      ) {
        if (header[i] != NativeSecureVaultBridge.magicHeaderBytes[i]) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  static Map<String, String> _recoverIndexFromBackupAndMetaUnlocked(
    Directory userVaultDir, {
    required String safeUid,
  }) {
    final recovered = <String, String>{};

    // 1. Attempt recovery from `attachment_index.json.bak` first (filtering to
    //    files that genuinely exist inside `userVaultDir`).
    final bakFile = _indexBackupFileFor(userVaultDir);
    final bakMap = _tryParseValidIndexMap(bakFile, userVaultDir);
    if (bakMap != null) {
      bakMap.forEach((attId, fileName) {
        final candidate = File(
          '${userVaultDir.path}${Platform.pathSeparator}$fileName',
        );
        if (candidate.existsSync() &&
            !FileSystemEntity.isLinkSync(candidate.path) &&
            isCanonicalPathStrictlyInsideDirectory(
              userVaultDir: userVaultDir,
              candidateFile: candidate,
            )) {
          recovered[attId] = fileName;
        }
      });
    }

    // 2. Scan verified `*.meta.json` (and legacy `*.enc.meta`) sidecars inside
    //    `<vaultRoot>/<safeUid>/` so attachments added after the last `.bak`
    //    rotation are ALSO recovered without silent loss!
    try {
      for (final entity in userVaultDir.listSync(followLinks: false)) {
        if (entity is! File || FileSystemEntity.isLinkSync(entity.path)) {
          continue;
        }
        if (!isCanonicalPathStrictlyInsideDirectory(
          userVaultDir: userVaultDir,
          candidateFile: entity,
        )) {
          continue;
        }
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : entity.path.split(Platform.pathSeparator).last;
        if (name == attachmentIndexFileName ||
            name == attachmentIndexBackupFileName ||
            name == pendingCleanupsFileName ||
            name.contains('.tmp.')) {
          continue;
        }
        final isMetaJson = name.endsWith('.meta.json');
        final isLegacyMeta = name.endsWith('.enc.meta');
        if (!isMetaJson && !isLegacyMeta) continue;

        try {
          final decoded = jsonDecode(entity.readAsStringSync());
          if (decoded is! Map) continue;
          final metaOwner = decoded['ownerId']?.toString();
          if (metaOwner != null &&
              metaOwner.trim().isNotEmpty &&
              _sanitizeUidOrNull(metaOwner) != safeUid) {
            continue;
          }
          final attId = decoded['attachmentId']?.toString();
          if (!isValidAttachmentId(attId)) continue;

          String? storageKey = decoded['storageKey']?.toString();
          if (!isSingleSafeFileName(storageKey)) {
            if (isMetaJson) {
              storageKey = '${name.substring(0, name.length - 10)}.enc';
            } else {
              storageKey = name.substring(0, name.length - 5);
            }
          }
          if (!isSingleSafeFileName(storageKey)) continue;

          final encFile = File(
            '${userVaultDir.path}${Platform.pathSeparator}$storageKey',
          );
          if (!isCanonicalPathStrictlyInsideDirectory(
            userVaultDir: userVaultDir,
            candidateFile: encFile,
          )) {
            continue;
          }
          if (!_hasLosvMagicHeader(encFile)) continue;

          final expectedEncSize = (decoded['encryptedSizeBytes'] as num?)
              ?.toInt();
          if (expectedEncSize != null &&
              encFile.lengthSync() != expectedEncSize) {
            continue;
          }

          recovered[attId!] = storageKey!;
        } catch (_) {
          // Ignore malformed individual meta sidecar and keep scanning others.
        }
      }
    } catch (_) {}

    return recovered;
  }

  static Future<Map<String, String>> _loadAttachmentIndexUnlocked(
    Directory userVaultDir, {
    required String safeUid,
  }) async {
    final indexFile = _indexFileFor(userVaultDir);
    if (indexFile.existsSync()) {
      final parsed = _tryParseValidIndexMap(indexFile, userVaultDir);
      if (parsed != null) {
        return parsed;
      }
      // Corrupted or truncated `attachment_index.json` -> recover from `.bak` / `*.meta.json`!
      final recovered = _recoverIndexFromBackupAndMetaUnlocked(
        userVaultDir,
        safeUid: safeUid,
      );
      if (recovered.isNotEmpty) {
        try {
          await _saveAttachmentIndexAtomicUnlocked(
            userVaultDir,
            recovered,
            backupCurrent: false,
          );
        } catch (_) {}
      }
      return recovered;
    }

    // Index missing completely: check if `.bak` or `*.meta.json` exist to rebuild.
    final recovered = _recoverIndexFromBackupAndMetaUnlocked(
      userVaultDir,
      safeUid: safeUid,
    );
    if (recovered.isNotEmpty) {
      try {
        await _saveAttachmentIndexAtomicUnlocked(
          userVaultDir,
          recovered,
          backupCurrent: false,
        );
      } catch (_) {}
    }
    return recovered;
  }

  static Future<void> _saveAttachmentIndexAtomicUnlocked(
    Directory userVaultDir,
    Map<String, String> index, {
    bool backupCurrent = true,
  }) async {
    final indexFile = _indexFileFor(userVaultDir);
    final bakFile = _indexBackupFileFor(userVaultDir);
    if (!isCanonicalPathStrictlyInsideDirectory(
      userVaultDir: userVaultDir,
      candidateFile: indexFile,
    )) {
      throw const VaultSecurityException(
        'Attachment index path escapes user vault directory.',
      );
    }

    final clean = <String, String>{};
    index.forEach((key, value) {
      if (isValidAttachmentId(key) && isSingleSafeFileName(value)) {
        clean[key] = value;
      }
    });

    final nonce = _nextAtomicNonce();
    final tmpFile = File(
      '${userVaultDir.path}${Platform.pathSeparator}$attachmentIndexFileName.tmp.$nonce',
    );
    final bakTmpFile = File(
      '${userVaultDir.path}${Platform.pathSeparator}$attachmentIndexBackupFileName.tmp.$nonce',
    );

    try {
      tmpFile.writeAsStringSync(jsonEncode(clean), flush: true);

      if (backupCurrent &&
          indexFile.existsSync() &&
          !FileSystemEntity.isLinkSync(indexFile.path) &&
          isCanonicalPathStrictlyInsideDirectory(
            userVaultDir: userVaultDir,
            candidateFile: indexFile,
          )) {
        final currentParsed = _tryParseValidIndexMap(indexFile, userVaultDir);
        if (currentParsed != null) {
          bakTmpFile.writeAsStringSync(jsonEncode(currentParsed), flush: true);
          bakTmpFile.renameSync(bakFile.path);
        }
      }

      tmpFile.renameSync(indexFile.path);
    } finally {
      if (tmpFile.existsSync()) {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
      if (bakTmpFile.existsSync()) {
        try {
          bakTmpFile.deleteSync();
        } catch (_) {}
      }
    }
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
    final safeName = fileName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '_')
        .replaceAll('..', '_');
    final digest = sha256.convert(bytes).toString();
    final attachmentId =
        'att_${digest.substring(0, 12)}_${_uuid.v4().replaceAll('-', '').substring(0, 12)}';
    // VAULT-01: Each attachment receives a unique physical filename `<attachmentId>.enc`
    // and `<attachmentId>.meta.json` so duplicate uploads never share a physical path.
    final key = '$attachmentId.enc';
    if (!isSingleSafeFileName(key)) {
      return const Err(
        ValidationFailure(
          code: 'INVALID_ATTACHMENT_NAME',
          message: 'Tên tệp đính kèm không hợp lệ.',
        ),
      );
    }
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
      final metaFile = _metaJsonFileFor(targetFile);
      await metaFile.writeAsString(
        jsonEncode(<String, dynamic>{
          'ownerId': userId,
          'attachmentId': attachmentId,
          'storageKey': key,
          'folder': folder,
          'originalFileName': safeName,
          'mimeType': mimeType,
          'plaintextSha256': digest,
          'plaintextSizeBytes': bytes.lengthInBytes,
          'encryptedSizeBytes': cipherPack.lengthInBytes,
        }),
        flush: true,
      );

      await _withIndexLock(safeUid, () async {
        final index = await _loadAttachmentIndexUnlocked(dir, safeUid: safeUid);
        index[attachmentId] = key;
        await _saveAttachmentIndexAtomicUnlocked(dir, index);
      });

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
      resolvedFileName = await _withIndexLock(safeUid, () async {
        if (dir != null && dir.existsSync()) {
          final idx = await _loadAttachmentIndexUnlocked(dir, safeUid: safeUid);
          final found = idx[trimmedAttId];
          if (found != null) return found;
        }
        if (legacyDir != null && legacyDir.existsSync()) {
          final legacyIdx = await _loadAttachmentIndexUnlocked(
            legacyDir,
            safeUid: safeUid,
          );
          return legacyIdx[trimmedAttId];
        }
        return null;
      });
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
    final jsonMetaFile = _metaJsonFileFor(f);
    final legacyMetaFile = _legacyMetaFileFor(f);
    final metaFile = jsonMetaFile.existsSync() ? jsonMetaFile : legacyMetaFile;
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
        final prefix = '$safeUid/';
        final stillReferenced = _ephemeralWebAttachmentIndex.entries.any(
          (e) => e.key.startsWith(prefix) && e.value == targetKey,
        );
        if (!stillReferenced) {
          _ephemeralWebVault.remove('$safeUid/$targetKey');
          _ephemeralWebMeta.remove('$safeUid/$targetKey');
          _ephemeralWebVault.remove('$userId/$targetKey');
          _ephemeralWebMeta.remove('$userId/$targetKey');
        }
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
      return await _withIndexLock(safeUid, () async {
        final dir = await _resolveVaultDir(userId, createIfMissing: false);
        final legacyDir = await _resolveLegacyVaultDir(userId);
        final allowedDirs = <Directory>[
          if (dir != null && dir.existsSync()) dir,
          if (legacyDir != null && legacyDir.existsSync()) legacyDir,
        ];

        var deletedByIndex = false;
        if (trimmedAttId != null && trimmedAttId.isNotEmpty) {
          for (final vaultDir in allowedDirs) {
            final index = await _loadAttachmentIndexUnlocked(
              vaultDir,
              safeUid: safeUid,
            );
            final indexedFileName = index.remove(trimmedAttId);
            if (indexedFileName != null &&
                isSingleSafeFileName(indexedFileName)) {
              await _saveAttachmentIndexAtomicUnlocked(vaultDir, index);
              final stillReferenced = index.values.any(
                (name) => name == indexedFileName,
              );
              if (!stillReferenced) {
                final target = File(
                  '${vaultDir.path}${Platform.pathSeparator}$indexedFileName',
                );
                await unlinkIfExists(target, vaultDir);
                await unlinkIfExists(_metaJsonFileFor(target), vaultDir);
                await unlinkIfExists(_legacyMetaFileFor(target), vaultDir);
              }
              deletedByIndex = true;
            }
          }
        }

        if (!deletedByIndex) {
          if (trimmedLegacyKey != null && trimmedLegacyKey.isNotEmpty) {
            for (final vaultDir in allowedDirs) {
              final index = await _loadAttachmentIndexUnlocked(
                vaultDir,
                safeUid: safeUid,
              );
              final matchingKeys = index.entries
                  .where((e) => e.value == trimmedLegacyKey)
                  .map((e) => e.key)
                  .toList(growable: false);
              if ((trimmedAttId == null || trimmedAttId.isEmpty) &&
                  matchingKeys.length == 1) {
                index.remove(matchingKeys.single);
                await _saveAttachmentIndexAtomicUnlocked(vaultDir, index);
              }
              final stillReferenced = index.values.any(
                (name) => name == trimmedLegacyKey,
              );
              if (!stillReferenced) {
                final target = File(
                  '${vaultDir.path}${Platform.pathSeparator}$trimmedLegacyKey',
                );
                await unlinkIfExists(target, vaultDir);
                await unlinkIfExists(_metaJsonFileFor(target), vaultDir);
                await unlinkIfExists(_legacyMetaFileFor(target), vaultDir);
              }
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
            if (fileName == null ||
                fileName == attachmentIndexFileName ||
                fileName == attachmentIndexBackupFileName ||
                fileName == pendingCleanupsFileName ||
                fileName.contains('.tmp.')) {
              return false;
            }
            final index = await _loadAttachmentIndexUnlocked(
              matchingBase,
              safeUid: safeUid,
            );
            final matchingKeys = index.entries
                .where((e) => e.value == fileName)
                .map((e) => e.key)
                .toList(growable: false);
            if ((trimmedAttId == null || trimmedAttId.isEmpty) &&
                matchingKeys.length == 1) {
              index.remove(matchingKeys.single);
              await _saveAttachmentIndexAtomicUnlocked(matchingBase, index);
            }
            final stillReferenced = index.values.any(
              (name) => name == fileName,
            );
            if (!stillReferenced) {
              await unlinkIfExists(candidate, matchingBase);
              await unlinkIfExists(_metaJsonFileFor(candidate), matchingBase);
              await unlinkIfExists(_legacyMetaFileFor(candidate), matchingBase);
            }
          }
        }
        return allDeleted;
      });
    } catch (_) {
      return false;
    }
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

  static List<PendingVaultCleanupRecord> _loadPendingCleanupsUnlocked(
    Directory userVaultDir,
  ) {
    final file = _pendingCleanupsFileFor(userVaultDir);
    if (!file.existsSync() || FileSystemEntity.isLinkSync(file.path)) {
      return const <PendingVaultCleanupRecord>[];
    }
    if (!isCanonicalPathStrictlyInsideDirectory(
      userVaultDir: userVaultDir,
      candidateFile: file,
    )) {
      return const <PendingVaultCleanupRecord>[];
    }
    try {
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return const <PendingVaultCleanupRecord>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <PendingVaultCleanupRecord>[];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (e) => PendingVaultCleanupRecord.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList();
    } catch (_) {
      return const <PendingVaultCleanupRecord>[];
    }
  }

  static void _savePendingCleanupsAtomicUnlocked(
    Directory userVaultDir,
    List<PendingVaultCleanupRecord> records,
  ) {
    final file = _pendingCleanupsFileFor(userVaultDir);
    if (!isCanonicalPathStrictlyInsideDirectory(
      userVaultDir: userVaultDir,
      candidateFile: file,
    )) {
      throw const VaultSecurityException(
        'Pending cleanups path escapes user vault directory.',
      );
    }
    if (records.isEmpty) {
      if (file.existsSync() && !FileSystemEntity.isLinkSync(file.path)) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      return;
    }
    final nonce = _nextAtomicNonce();
    final tmpFile = File(
      '${userVaultDir.path}${Platform.pathSeparator}$pendingCleanupsFileName.tmp.$nonce',
    );
    try {
      tmpFile.writeAsStringSync(
        jsonEncode(records.map((r) => r.toJson()).toList()),
        flush: true,
      );
      tmpFile.renameSync(file.path);
    } finally {
      if (tmpFile.existsSync()) {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Persists a durable pending local attachment cleanup entry in
  /// `<vaultRoot>/<safeUid>/pending_cleanups.json` when immediate deletion fails.
  Future<void> recordPendingCleanup({
    required String userId,
    String? attachmentId,
    String? legacyLocalPath,
    String? legacyStorageKey,
    DateTime? timestamp,
  }) async {
    final safeUid = _sanitizeUidOrNull(userId);
    if (safeUid == null) return;
    final record = PendingVaultCleanupRecord(
      attachmentId: attachmentId?.trim().isNotEmpty == true
          ? attachmentId!.trim()
          : null,
      legacyLocalPath: legacyLocalPath?.trim().isNotEmpty == true
          ? legacyLocalPath!.trim()
          : null,
      legacyStorageKey: legacyStorageKey?.trim().isNotEmpty == true
          ? legacyStorageKey!.trim()
          : null,
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
    );
    if (record.attachmentId == null &&
        record.legacyLocalPath == null &&
        record.legacyStorageKey == null) {
      return;
    }

    if (kIsWeb) {
      final list = _ephemeralWebPendingCleanups.putIfAbsent(
        safeUid,
        () => <PendingVaultCleanupRecord>[],
      );
      list.removeWhere((e) => e.dedupKey == record.dedupKey);
      list.add(record);
      return;
    }

    await _withIndexLock(safeUid, () async {
      final dir = await _resolveVaultDir(userId, createIfMissing: true);
      if (dir == null) return;
      final existing = List<PendingVaultCleanupRecord>.from(
        _loadPendingCleanupsUnlocked(dir),
      );
      existing.removeWhere((e) => e.dedupKey == record.dedupKey);
      existing.add(record);
      _savePendingCleanupsAtomicUnlocked(dir, existing);
    });
  }

  Future<List<PendingVaultCleanupRecord>> loadPendingCleanups(
    String userId,
  ) async {
    final safeUid = _sanitizeUidOrNull(userId);
    if (safeUid == null) return const <PendingVaultCleanupRecord>[];
    if (kIsWeb) {
      return List<PendingVaultCleanupRecord>.unmodifiable(
        _ephemeralWebPendingCleanups[safeUid] ??
            const <PendingVaultCleanupRecord>[],
      );
    }
    return _withIndexLock(safeUid, () async {
      final dir = await _resolveVaultDir(userId, createIfMissing: false);
      if (dir == null || !dir.existsSync()) {
        return const <PendingVaultCleanupRecord>[];
      }
      return List<PendingVaultCleanupRecord>.unmodifiable(
        _loadPendingCleanupsUnlocked(dir),
      );
    });
  }

  /// Retries all durable pending cleanups using [deleteAttachmentForUser] (or
  /// a custom [deleteDelegate] when called from repository tests).
  /// Returns the count of items still pending after the retry pass (`0` = all clear).
  Future<int> retryPendingCleanups(
    String userId, {
    Future<bool> Function({
      required String userId,
      String? attachmentId,
      String? legacyLocalPath,
      String? legacyStorageKey,
    })?
    deleteDelegate,
  }) async {
    final safeUid = _sanitizeUidOrNull(userId);
    if (safeUid == null) return 0;

    final pending = await loadPendingCleanups(userId);
    if (pending.isEmpty) return 0;

    final deleter = deleteDelegate ?? deleteAttachmentForUser;
    final succeededKeys = <String>{};
    for (final rec in pending) {
      var ok = false;
      try {
        ok = await deleter(
          userId: userId,
          attachmentId: rec.attachmentId,
          legacyLocalPath: rec.legacyLocalPath,
          legacyStorageKey: rec.legacyStorageKey,
        );
      } catch (_) {
        ok = false;
      }
      if (ok) {
        succeededKeys.add(rec.dedupKey);
      }
    }

    if (kIsWeb) {
      final list = _ephemeralWebPendingCleanups[safeUid];
      if (list == null) return 0;
      list.removeWhere((e) => succeededKeys.contains(e.dedupKey));
      if (list.isEmpty) {
        _ephemeralWebPendingCleanups.remove(safeUid);
        return 0;
      }
      return list.length;
    }

    return _withIndexLock(safeUid, () async {
      final dir = await _resolveVaultDir(userId, createIfMissing: false);
      if (dir == null || !dir.existsSync()) return 0;
      final latest = List<PendingVaultCleanupRecord>.from(
        _loadPendingCleanupsUnlocked(dir),
      );
      latest.removeWhere((e) => succeededKeys.contains(e.dedupKey));
      _savePendingCleanupsAtomicUnlocked(dir, latest);
      return latest.length;
    });
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
      _ephemeralWebPendingCleanups.remove(safeUid);
      return;
    }

    await _withIndexLock(safeUid, () async {
      final bridge = vaultBridge ?? NativeSecureVaultBridge.instance;
      final basePaths = <String>{};
      final primaryBase = await _resolveVaultBasePath(
        customVaultRootPath: customVaultRootPath,
        vaultBridge: bridge,
      );
      if (primaryBase != null && primaryBase.trim().isNotEmpty) {
        basePaths.add(primaryBase);
      }
      if (customVaultRootPath == null &&
          (Platform.isAndroid || Platform.isIOS)) {
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
    });
  }
}
