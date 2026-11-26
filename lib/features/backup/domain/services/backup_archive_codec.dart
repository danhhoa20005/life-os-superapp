import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../../core/backup/lifeos_backup_restore_engine.dart';
import '../../../../core/utils/csv_sanitizer.dart';
import '../entities/backup_entities.dart';
import 'backup_isolate_runner.dart';

/// Pure-Dart versioned (`v3`) backup archive serializer, PBKDF2-HMAC-SHA256
/// authenticated encryptor, and backward-compatible (`v1`/`v2`/`v3`) validator.
class BackupArchiveCodec {
  static const int currentSchemaVersion = 3;
  static const int minSupportedSchemaVersion = 1;
  static const String magicEnvelopeV3 = 'LIFEOS_BACKUP_V3';
  static const String kdfLabel = 'PBKDF2-HMAC-SHA256';
  static const String cipherLabel = 'STREAM-SHA256-ETM';
  static const int defaultKdfIterations = 120000;
  static const int minV3DecodeIterations = 12000;
  static const int maxV3DecodeIterations = 2000000;

  static const List<int> _hkdfEncInfo = <int>[
    108, 105, 102, 101, 111, 115, 45, 98, 97, 99, 107, 117, 112, 45, 118, 51, 45,
    101, 110, 99, // "lifeos-backup-v3-enc"
  ];
  static const List<int> _hkdfMacInfo = <int>[
    108, 105, 102, 101, 111, 115, 45, 98, 97, 99, 107, 117, 112, 45, 118, 51, 45,
    109, 97, 99, // "lifeos-backup-v3-mac"
  ];

  final int encryptIterations;
  final int minDecodeIterations;

  const BackupArchiveCodec()
    : encryptIterations = defaultKdfIterations,
      minDecodeIterations = minV3DecodeIterations;

  /// Test-only constructor allowing lower iteration counts inside fast unit/widget
  /// tests without ever permitting an archive file to weaken production bounds.
  const BackupArchiveCodec.forTesting({
    int kdfIterations = minV3DecodeIterations,
    int minDecodeIterations = minV3DecodeIterations,
  }) : assert(kdfIterations >= 1),
       assert(minDecodeIterations >= 1),
       encryptIterations = kdfIterations,
       minDecodeIterations = minDecodeIterations;

  Future<String> createArchiveAsync({
    required String ownerId,
    required Map<String, List<Map<String, dynamic>>> collections,
    String? passphrase,
    DateTime? exportedAtOverride,
  }) async {
    final cleanPass = (passphrase ?? '').trim();
    if (cleanPass.isEmpty) {
      return createArchiveSync(
        ownerId: ownerId,
        collections: collections,
        passphrase: cleanPass,
        exportedAtOverride: exportedAtOverride,
      );
    }
    final clonedCollections = <String, List<Map<String, dynamic>>>{
      for (final entry in collections.entries)
        entry.key: entry.value.map((m) => Map<String, dynamic>.from(m)).toList(),
    };
    final codec = this;
    return runBackupCryptoTask(
      () => codec.createArchiveSync(
        ownerId: ownerId,
        collections: clonedCollections,
        passphrase: cleanPass,
        exportedAtOverride: exportedAtOverride,
      ),
    );
  }

  Future<BackupArchivePreview> previewAndValidateAsync(
    String rawArchiveText, {
    String? passphrase,
  }) async {
    final dynamic rootDecoded = jsonDecode(rawArchiveText);
    if (rootDecoded is! Map) {
      throw const FormatException('Định dạng tệp sao lưu không hợp lệ.');
    }
    final isEncrypted = rootDecoded['encrypted'] == true;
    if (!isEncrypted) {
      return previewAndValidateSync(rawArchiveText, passphrase: passphrase);
    }
    final codec = this;
    return runBackupCryptoTask(
      () => codec.previewAndValidateSync(
        rawArchiveText,
        passphrase: passphrase,
      ),
    );
  }

  String createArchiveSync({
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

    final encryptedPack = _encryptPortablePayload(
      payloadBytes,
      cleanPass,
      encryptIterations,
    );
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format': magicEnvelopeV3,
      'encrypted': true,
      'kdf': kdfLabel,
      'iterations': encryptIterations,
      'cipher': cipherLabel,
      'saltB64': base64Encode(encryptedPack.salt),
      'nonceB64': base64Encode(encryptedPack.nonce),
      'macB64': base64Encode(encryptedPack.mac),
      'ciphertextB64': base64Encode(encryptedPack.ciphertext),
      'plaintextSha256': sha256Hex,
    });
  }

  BackupArchivePreview previewAndValidateSync(
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

    // Backward compatibility with v2 (`LIFEOS_BACKUP_V2`, PBKDF2-HMAC-SHA256-12000)
    // and v1 (`PersonalDataExport`).
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

    if (root['encrypted'] != true &&
        format != LifeOsBackupRestoreEngine.magicEnvelope) {
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
      ...legacy.summary.warnings.where((w) => !w.contains('v2')),
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

  static String createArchive({
    required String ownerId,
    required Map<String, List<Map<String, dynamic>>> collections,
    String? passphrase,
    DateTime? exportedAtOverride,
  }) => const BackupArchiveCodec().createArchiveSync(
    ownerId: ownerId,
    collections: collections,
    passphrase: passphrase,
    exportedAtOverride: exportedAtOverride,
  );

  static BackupArchivePreview previewAndValidateArchive(
    String rawArchiveText, {
    String? passphrase,
  }) => const BackupArchiveCodec().previewAndValidateSync(
    rawArchiveText,
    passphrase: passphrase,
  );

  BackupArchivePreview _decodeV3Archive(
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
      final kdf = (root['kdf'] ?? '').toString();
      if (kdf != kdfLabel) {
        throw FormatException(
          'Thuật toán KDF không được hỗ trợ cho bản sao lưu v3: $kdf.',
        );
      }
      final cipher = (root['cipher'] ?? '').toString();
      if (cipher != cipherLabel) {
        throw FormatException(
          'Thuật toán mã hóa không được hỗ trợ cho bản sao lưu v3: $cipher.',
        );
      }
      final rawIter = root['iterations'];
      if (rawIter is! num || !rawIter.isFinite || rawIter != rawIter.toInt()) {
        throw const FormatException(
          'Thiếu hoặc sai số vòng lặp KDF trong tệp sao lưu v3.',
        );
      }
      final iterations = rawIter.toInt();
      if (iterations < minDecodeIterations ||
          iterations > maxV3DecodeIterations) {
        throw FormatException(
          'Số vòng lặp KDF ($iterations) không đạt ngưỡng an toàn tối thiểu ($minDecodeIterations).',
        );
      }

      late final Uint8List salt;
      late final Uint8List nonce;
      late final Uint8List mac;
      late final Uint8List ciphertext;
      try {
        salt = base64Decode((root['saltB64'] ?? '').toString());
        nonce = base64Decode((root['nonceB64'] ?? '').toString());
        mac = base64Decode((root['macB64'] ?? '').toString());
        ciphertext = base64Decode((root['ciphertextB64'] ?? '').toString());
      } on FormatException {
        throw const FormatException(
          'Cấu trúc mã hóa Base64 không hợp lệ hoặc tệp bị hỏng.',
        );
      }
      if (salt.isEmpty || nonce.isEmpty || mac.length != 32) {
        throw const FormatException(
          'Tham số mã hóa không hợp lệ hoặc tệp bị cắt xén.',
        );
      }

      final plainBytes = _decryptPortablePayload(
        ciphertext: ciphertext,
        salt: salt,
        nonce: nonce,
        expectedMac: mac,
        passphrase: cleanPass,
        iterations: iterations,
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

  /// RFC 2898 / NIST SP 800-132 PBKDF2-HMAC-SHA256 key derivation.
  static Uint8List pbkdf2HmacSha256({
    required List<int> passwordBytes,
    required List<int> salt,
    required int iterations,
    int dkLen = 32,
  }) {
    final hmac = Hmac(sha256, passwordBytes);
    final numBlocks = (dkLen + 31) ~/ 32;
    final out = Uint8List(dkLen);
    final blockInput = Uint8List(salt.length + 4);
    blockInput.setAll(0, salt);

    for (var blockIdx = 1; blockIdx <= numBlocks; blockIdx++) {
      blockInput[salt.length] = (blockIdx >> 24) & 0xFF;
      blockInput[salt.length + 1] = (blockIdx >> 16) & 0xFF;
      blockInput[salt.length + 2] = (blockIdx >> 8) & 0xFF;
      blockInput[salt.length + 3] = blockIdx & 0xFF;

      var u = hmac.convert(blockInput).bytes;
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < 32; j++) {
          t[j] ^= u[j];
        }
      }
      final offset = (blockIdx - 1) * 32;
      final toCopy = math.min(32, dkLen - offset);
      out.setRange(offset, offset + toCopy, t);
    }
    return out;
  }

  static List<int> _buildMacContextPrefix(int iterations) =>
      utf8.encode('$kdfLabel|$iterations|$cipherLabel|');

  static ({
    Uint8List salt,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List mac,
  })
  _encryptPortablePayload(
    List<int> plainBytes,
    String passphrase,
    int iterations,
  ) {
    final rng = math.Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    final keys = _deriveEncAndMacKeys(passphrase, salt, iterations);
    final ciphertext = _xorKeystream(plainBytes, keys.encKey, nonce);
    final macInput = <int>[
      ..._buildMacContextPrefix(iterations),
      ...salt,
      ...nonce,
      ...ciphertext,
    ];
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
    required int iterations,
  }) {
    final keys = _deriveEncAndMacKeys(passphrase, salt, iterations);
    final actualMac = Hmac(sha256, keys.macKey).convert(<int>[
      ..._buildMacContextPrefix(iterations),
      ...salt,
      ...nonce,
      ...ciphertext,
    ]).bytes;
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
    int iterations,
  ) {
    final masterKey = pbkdf2HmacSha256(
      passwordBytes: utf8.encode(passphrase),
      salt: salt,
      iterations: iterations,
      dkLen: 32,
    );
    final expand = Hmac(sha256, masterKey);
    final encKey = expand.convert(const <int>[..._hkdfEncInfo, 0x01]).bytes;
    final macKey = expand.convert(const <int>[..._hkdfMacInfo, 0x01]).bytes;
    return (encKey: encKey, macKey: macKey);
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
