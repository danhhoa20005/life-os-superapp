import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../../core/backup/lifeos_backup_restore_engine.dart';
import '../../../../core/utils/csv_sanitizer.dart';
import '../entities/backup_entities.dart';

/// Pure-Dart versioned (`v3`) backup archive serializer, authenticated encryptor,
/// and backward-compatible (`v1`/`v2`/`v3`) validator.
abstract final class BackupArchiveCodec {
  static const int currentSchemaVersion = 3;
  static const int minSupportedSchemaVersion = 1;
  static const String magicEnvelopeV3 = 'LIFEOS_BACKUP_V3';
  static const String kdfLabel = 'HMAC-SHA256-4096';
  static const String cipherLabel = 'STREAM-SHA256-ETM';

  static String createArchive({
    required String ownerId,
    required Map<String, List<Map<String, dynamic>>> collections,
    String? passphrase,
    DateTime? exportedAtOverride,
  }) {
    final exportedAt = (exportedAtOverride ?? DateTime.now()).toUtc();
    final canonicalCollections = <String, dynamic>{};

    for (final key in BackupCollectionCatalog.allKeys) {
      final list = collections[key];
      canonicalCollections[key] = list != null
          ? list.map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[];
    }
    for (final entry in collections.entries) {
      if (!canonicalCollections.containsKey(entry.key)) {
        canonicalCollections[entry.key] = entry.value
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    }

    final canonicalData = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'ownerId': ownerId,
      'exportedAtUtc': exportedAt.toIso8601String(),
      'archiveKind': 'full_owner_backup',
      'limitations': BackupCollectionCatalog.defaultLimitationsVi,
      'collections': canonicalCollections,
    };
    final payloadJson = jsonEncode(canonicalData);
    final payloadBytes = utf8.encode(payloadJson);
    final sha256Hex = sha256.convert(payloadBytes).toString();

    final cleanPass = (passphrase ?? '').trim();
    if (cleanPass.isEmpty) {
      return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'format': magicEnvelopeV3,
        'encrypted': false,
        'sha256': sha256Hex,
        'payload': canonicalData,
      });
    }

    final encryptedPack = _encryptPortablePayload(payloadBytes, cleanPass);
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format': magicEnvelopeV3,
      'encrypted': true,
      'kdf': kdfLabel,
      'cipher': cipherLabel,
      'saltB64': base64Encode(encryptedPack.salt),
      'nonceB64': base64Encode(encryptedPack.nonce),
      'macB64': base64Encode(encryptedPack.mac),
      'ciphertextB64': base64Encode(encryptedPack.ciphertext),
      'plaintextSha256': sha256Hex,
    });
  }

  static BackupArchivePreview previewAndValidateArchive(
    String rawArchiveText, {
    String? passphrase,
  }) {
    final dynamic rootDecoded = jsonDecode(rawArchiveText);
    if (rootDecoded is! Map) {
      throw const FormatException('Định dạng tệp sao lưu không hợp lệ.');
    }
    final root = Map<String, dynamic>.from(rootDecoded);
    final format = root['format']?.toString() ?? '';

    if (format == magicEnvelopeV3) {
      return _decodeV3Archive(root, passphrase: passphrase);
    }

    // Backward compatibility with v2 (`LIFEOS_BACKUP_V2`) and v1 (`PersonalDataExport`).
    final legacy = LifeOsBackupRestoreEngine.previewAndValidateArchive(
      rawArchiveText,
      passphrase: passphrase,
    );
    final normalizedCols = <String, List<Map<String, dynamic>>>{
      for (final key in BackupCollectionCatalog.allKeys)
        key: List<Map<String, dynamic>>.from(
          legacy.collections[key] ?? const <Map<String, dynamic>>[],
        ),
    };

    // Preserve any extra v1 PersonalDataExport collections (`privateEvents`, `bankAccounts`, etc.)
    if (root['encrypted'] != true && format != LifeOsBackupRestoreEngine.magicEnvelope) {
      if ((normalizedCols[BackupCollectionCatalog.events] ?? const []).isEmpty &&
          root['privateEvents'] is List) {
        normalizedCols[BackupCollectionCatalog.events] =
            (root['privateEvents'] as List)
                .whereType<Map<dynamic, dynamic>>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
      }
      if ((normalizedCols[BackupCollectionCatalog.bankAccounts] ?? const [])
              .isEmpty &&
          root['bankAccounts'] is List) {
        normalizedCols[BackupCollectionCatalog.bankAccounts] =
            (root['bankAccounts'] as List)
                .whereType<Map<dynamic, dynamic>>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
      }
    }

    final legacyPayloadSha = sha256
        .convert(utf8.encode(jsonEncode(normalizedCols)))
        .toString();

    final warnings = <String>[
      ...legacy.summary.warnings.where(
        (w) => !w.contains('v2'),
      ),
      if (legacy.summary.schemaVersion < currentSchemaVersion)
        'Đã tự động nâng cấp cấu trúc dữ liệu từ v${legacy.summary.schemaVersion} lên v$currentSchemaVersion.',
    ];

    return BackupArchivePreview(
      schemaVersion: legacy.summary.schemaVersion,
      ownerId: legacy.summary.ownerId,
      exportedAt: legacy.summary.exportedAt,
      checksumVerified: legacy.summary.checksumVerified,
      wasEncrypted: legacy.summary.wasEncrypted,
      archiveSha256: legacyPayloadSha,
      collections: normalizedCols,
      warnings: warnings,
    );
  }

  static BackupArchivePreview _decodeV3Archive(
    Map<String, dynamic> root, {
    String? passphrase,
  }) {
    final isEncrypted = root['encrypted'] == true;
    late final Map<String, dynamic> payloadMap;
    late final String sha256Hex;

    if (isEncrypted) {
      final cleanPass = (passphrase ?? '').trim();
      if (cleanPass.isEmpty) {
        throw const FormatException(
          'Bản sao lưu được mã hóa — vui lòng nhập mật khẩu giải mã.',
        );
      }
      final salt = base64Decode((root['saltB64'] ?? '').toString());
      final nonce = base64Decode((root['nonceB64'] ?? '').toString());
      final mac = base64Decode((root['macB64'] ?? '').toString());
      final ciphertext = base64Decode((root['ciphertextB64'] ?? '').toString());
      final plainBytes = _decryptPortablePayload(
        ciphertext: ciphertext,
        salt: salt,
        nonce: nonce,
        expectedMac: mac,
        passphrase: cleanPass,
      );
      final expectedSha = (root['plaintextSha256'] ?? '').toString();
      final actualSha = sha256.convert(plainBytes).toString();
      if (expectedSha.isEmpty || expectedSha != actualSha) {
        throw const FormatException(
          'Checksum SHA-256 sau giải mã không khớp — tệp bị hỏng.',
        );
      }
      sha256Hex = actualSha;
      final decoded = jsonDecode(utf8.decode(plainBytes));
      if (decoded is! Map) {
        throw const FormatException('Dữ liệu sao lưu sau giải mã không hợp lệ.');
      }
      payloadMap = Map<String, dynamic>.from(decoded);
    } else {
      final rawPayload = root['payload'];
      if (rawPayload is! Map) {
        throw const FormatException('Thiếu payload trong tệp sao lưu v3.');
      }
      final mapPayload = Map<String, dynamic>.from(rawPayload);
      final expectedSha = (root['sha256'] ?? '').toString();
      final actualSha = sha256
          .convert(utf8.encode(jsonEncode(mapPayload)))
          .toString();
      if (expectedSha.isEmpty || expectedSha != actualSha) {
        throw const FormatException(
          'Mã kiểm tra toàn vẹn SHA-256 không khớp — từ chối nhập dữ liệu bị sửa đổi.',
        );
      }
      sha256Hex = actualSha;
      payloadMap = mapPayload;
    }

    final schemaVer =
        (payloadMap['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion;
    if (schemaVer < minSupportedSchemaVersion ||
        schemaVer > currentSchemaVersion) {
      throw FormatException(
        'Phiên bản cấu trúc sao lưu v$schemaVer không tương thích (hỗ trợ v$minSupportedSchemaVersion..v$currentSchemaVersion).',
      );
    }

    final rawCols = payloadMap['collections'] is Map
        ? Map<String, dynamic>.from(payloadMap['collections'] as Map)
        : const <String, dynamic>{};

    final collections = <String, List<Map<String, dynamic>>>{};
    for (final key in BackupCollectionCatalog.allKeys) {
      collections[key] = _readMapList(rawCols[key]);
    }
    for (final entry in rawCols.entries) {
      if (!collections.containsKey(entry.key)) {
        collections[entry.key] = _readMapList(entry.value);
      }
    }

    final limitations = payloadMap['limitations'] is List
        ? (payloadMap['limitations'] as List)
              .map((e) => e.toString())
              .where((s) => s.trim().isNotEmpty)
              .toList()
        : BackupCollectionCatalog.defaultLimitationsVi;

    final exportedAt =
        DateTime.tryParse((payloadMap['exportedAtUtc'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return BackupArchivePreview(
      schemaVersion: schemaVer,
      ownerId: (payloadMap['ownerId'] ?? '').toString(),
      exportedAt: exportedAt,
      checksumVerified: true,
      wasEncrypted: isEncrypted,
      archiveSha256: sha256Hex,
      collections: collections,
      warnings: schemaVer < currentSchemaVersion
          ? <String>[
              'Đã tự động nâng cấp cấu trúc dữ liệu từ v$schemaVer lên v$currentSchemaVersion.',
            ]
          : const <String>[],
      limitationsVi: limitations.isEmpty
          ? BackupCollectionCatalog.defaultLimitationsVi
          : limitations,
    );
  }

  static List<Map<String, dynamic>> _readMapList(Object? raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  static String exportTransactionsCsv(
    List<Map<String, dynamic>> transactions, {
    Map<String, String> walletNamesById = const <String, String>{},
  }) {
    final buf = StringBuffer();
    buf.writeln(
      'MaGiaoDich,NgayPhatSinh,Loai,DanhMuc,MoTa,SoTienVND,TrangThaiXacMinh,ViNguon,ViDich,GhiChu',
    );
    for (final tx in transactions) {
      final id = CsvSanitizer.escapeQuotedCell((tx['id'] ?? '').toString());
      final date = CsvSanitizer.escapeQuotedCell(
        (tx['occurredAt'] ?? '').toString(),
      );
      final kind = CsvSanitizer.escapeQuotedCell(
        (tx['kind'] ?? 'expense').toString(),
      );
      final cat = CsvSanitizer.escapeQuotedCell(
        (tx['categoryName'] ?? 'Khác').toString(),
      );
      final merchant = CsvSanitizer.escapeQuotedCell(
        (tx['merchant'] ?? '').toString(),
      );
      final amt = ((tx['amountMinor'] as num?)?.toInt() ?? 0).toString();
      final ver = CsvSanitizer.escapeQuotedCell(
        (tx['verification'] ?? 'userConfirmed').toString(),
      );
      final walletId = (tx['walletId'] ?? '').toString();
      final walletLabel = walletNamesById[walletId] ?? walletId;
      final targetWalletId = (tx['targetWalletId'] ?? '').toString();
      final targetWalletLabel = targetWalletId.isEmpty
          ? ''
          : (walletNamesById[targetWalletId] ?? targetWalletId);
      final note = (tx['note'] ?? '').toString();

      buf.writeln(
        '$id,$date,$kind,$cat,$merchant,$amt,$ver,'
        '${CsvSanitizer.escapeQuotedCell(walletLabel)},'
        '${CsvSanitizer.escapeQuotedCell(targetWalletLabel)},'
        '${CsvSanitizer.escapeQuotedCell(note)}',
      );
    }
    return buf.toString();
  }

  static String computeArchiveSha256(String archiveContent) =>
      sha256.convert(utf8.encode(archiveContent)).toString();

  static ({
    Uint8List salt,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List mac,
  })
  _encryptPortablePayload(List<int> plainBytes, String passphrase) {
    final rng = math.Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    final keys = _deriveEncAndMacKeys(passphrase, salt);
    final ciphertext = _xorKeystream(plainBytes, keys.encKey, nonce);
    final macInput = <int>[...salt, ...nonce, ...ciphertext];
    final mac = Uint8List.fromList(
      Hmac(sha256, keys.macKey).convert(macInput).bytes,
    );
    return (salt: salt, nonce: nonce, ciphertext: ciphertext, mac: mac);
  }

  static Uint8List _decryptPortablePayload({
    required Uint8List ciphertext,
    required Uint8List salt,
    required Uint8List nonce,
    required Uint8List expectedMac,
    required String passphrase,
  }) {
    final keys = _deriveEncAndMacKeys(passphrase, salt);
    final actualMac = Hmac(
      sha256,
      keys.macKey,
    ).convert(<int>[...salt, ...nonce, ...ciphertext]).bytes;
    if (actualMac.length != expectedMac.length) {
      throw const FormatException(
        'Mật khẩu giải mã không đúng hoặc tệp bị sửa đổi.',
      );
    }
    var diff = 0;
    for (var i = 0; i < actualMac.length; i++) {
      diff |= actualMac[i] ^ expectedMac[i];
    }
    if (diff != 0) {
      throw const FormatException(
        'Mật khẩu giải mã không đúng hoặc tệp bị sửa đổi.',
      );
    }
    return _xorKeystream(ciphertext, keys.encKey, nonce);
  }

  static ({List<int> encKey, List<int> macKey}) _deriveEncAndMacKeys(
    String passphrase,
    Uint8List salt,
  ) {
    final passBytes = utf8.encode(passphrase);
    final hmac = Hmac(sha256, passBytes);
    var block1 = hmac.convert(<int>[...salt, 0, 0, 0, 1]).bytes;
    final acc1 = List<int>.from(block1);
    for (var i = 1; i < 4096; i++) {
      block1 = hmac.convert(block1).bytes;
      for (var j = 0; j < acc1.length; j++) {
        acc1[j] ^= block1[j];
      }
    }
    var block2 = hmac.convert(<int>[...salt, 0, 0, 0, 2]).bytes;
    final acc2 = List<int>.from(block2);
    for (var i = 1; i < 4096; i++) {
      block2 = hmac.convert(block2).bytes;
      for (var j = 0; j < acc2.length; j++) {
        acc2[j] ^= block2[j];
      }
    }
    return (encKey: acc1, macKey: acc2);
  }

  static Uint8List _xorKeystream(
    List<int> input,
    List<int> encKey,
    Uint8List nonce,
  ) {
    final out = Uint8List(input.length);
    final hmac = Hmac(sha256, encKey);
    var counter = 0;
    var offset = 0;
    while (offset < input.length) {
      final ctrBytes = <int>[
        ...nonce,
        (counter >> 24) & 0xFF,
        (counter >> 16) & 0xFF,
        (counter >> 8) & 0xFF,
        counter & 0xFF,
      ];
      final keyBlock = hmac.convert(ctrBytes).bytes;
      final chunk = math.min(32, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        out[offset + i] = input[offset + i] ^ keyBlock[i];
      }
      offset += chunk;
      counter++;
    }
    return out;
  }
}
