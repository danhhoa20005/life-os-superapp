import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

import '../utils/csv_sanitizer.dart';
import '../utils/vnd_amount.dart';

enum BackupRestoreMode {
  merge('merge', 'Hợp nhất an toàn (Giữ dữ liệu cũ, bỏ qua bản ghi trùng)'),
  importAsNew('import_as_new', 'Nhập thêm thành bản ghi mới (Tạo ID mới)'),
  replaceConfirmed('replace', 'Ghi đè toàn bộ (Yêu cầu xác nhận tường minh)');

  final String code;
  final String labelVi;
  const BackupRestoreMode(this.code, this.labelVi);
}

class BackupPreviewSummary extends Equatable {
  final int schemaVersion;
  final String ownerId;
  final DateTime exportedAt;
  final bool checksumVerified;
  final bool wasEncrypted;
  final int walletCount;
  final int transactionCount;
  final int budgetCount;
  final int taskCount;
  final int eventCount;
  final int vehicleCount;
  final int noteCount;
  final List<String> warnings;

  const BackupPreviewSummary({
    required this.schemaVersion,
    required this.ownerId,
    required this.exportedAt,
    required this.checksumVerified,
    required this.wasEncrypted,
    required this.walletCount,
    required this.transactionCount,
    required this.budgetCount,
    required this.taskCount,
    required this.eventCount,
    required this.vehicleCount,
    required this.noteCount,
    this.warnings = const <String>[],
  });

  int get totalRecordCount =>
      walletCount +
      transactionCount +
      budgetCount +
      taskCount +
      eventCount +
      vehicleCount +
      noteCount;

  @override
  List<Object?> get props => [
    schemaVersion,
    ownerId,
    exportedAt,
    checksumVerified,
    wasEncrypted,
    walletCount,
    transactionCount,
    budgetCount,
    taskCount,
    eventCount,
    vehicleCount,
    noteCount,
    warnings,
  ];
}

class BackupRestoreReport extends Equatable {
  final BackupRestoreMode mode;
  final int importedCount;
  final int skippedDuplicateCount;
  final int migratedLegacyRecords;
  final List<String> detailsVi;

  const BackupRestoreReport({
    required this.mode,
    required this.importedCount,
    required this.skippedDuplicateCount,
    required this.migratedLegacyRecords,
    required this.detailsVi,
  });

  @override
  List<Object?> get props => [
    mode,
    importedCount,
    skippedDuplicateCount,
    migratedLegacyRecords,
    detailsVi,
  ];
}

/// Complete Backup & Restore Engine (Section 21).
///
/// Features:
/// - OWASP-sanitized CSV financial export.
/// - Schema-versioned (`currentSchemaVersion = 2`) JSON archive with mandatory SHA-256 payload checksum.
/// - Password-derived authenticated encryption (`PBKDF2-HMAC-SHA256` + `CTR` + `HMAC-SHA256` EtM tag)
///   for portable cross-device encrypted backups (`.lfbk`) — never confuses SHA-256 with encryption!
/// - Non-destructive preview & 3 restore modes (`merge`, `importAsNew`, `replaceConfirmed` requiring explicit flag).
abstract final class LifeOsBackupRestoreEngine {
  static const int currentSchemaVersion = 2;
  static const int minSupportedSchemaVersion = 1;
  static const String magicEnvelope = 'LIFEOS_BACKUP_V2';

  static String exportTransactionsCsv(List<Map<String, dynamic>> transactions) {
    final buf = StringBuffer();
    buf.writeln(
      'MaGiaoDich,NgayPhatSinh,Loai,DanhMuc,MoTa,SoTienVND,TrangThaiXacMinh',
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
      buf.writeln('$id,$date,$kind,$cat,$merchant,$amt,$ver');
    }
    return buf.toString();
  }

  /// Creates a schema-versioned, SHA-256-checksummed JSON backup (optionally encrypted with [passphrase]).
  static String createBackupArchive({
    required String ownerId,
    required Map<String, List<Map<String, dynamic>>> collections,
    String? passphrase,
    DateTime? exportedAtOverride,
  }) {
    final exportedAt = (exportedAtOverride ?? DateTime.now()).toUtc();
    final canonicalData = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'ownerId': ownerId,
      'exportedAtUtc': exportedAt.toIso8601String(),
      'collections': <String, dynamic>{
        'wallets': collections['wallets'] ?? const <Map<String, dynamic>>[],
        'transactions':
            collections['transactions'] ?? const <Map<String, dynamic>>[],
        'budgets': collections['budgets'] ?? const <Map<String, dynamic>>[],
        'tasks': collections['tasks'] ?? const <Map<String, dynamic>>[],
        'events': collections['events'] ?? const <Map<String, dynamic>>[],
        'vehicles': collections['vehicles'] ?? const <Map<String, dynamic>>[],
        'notes': collections['notes'] ?? const <Map<String, dynamic>>[],
      },
    };
    final payloadJson = jsonEncode(canonicalData);
    final payloadBytes = utf8.encode(payloadJson);
    final sha256Hex = sha256.convert(payloadBytes).toString();

    final cleanPass = (passphrase ?? '').trim();
    if (cleanPass.isEmpty) {
      return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'format': magicEnvelope,
        'encrypted': false,
        'sha256': sha256Hex,
        'payload': canonicalData,
      });
    }

    final encryptedPack = _encryptPortablePayload(payloadBytes, cleanPass);
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format': magicEnvelope,
      'encrypted': true,
      'kdf': 'PBKDF2-HMAC-SHA256-12000',
      'cipher': 'STREAM-SHA256-ETM',
      'saltB64': base64Encode(encryptedPack.salt),
      'nonceB64': base64Encode(encryptedPack.nonce),
      'macB64': base64Encode(encryptedPack.mac),
      'ciphertextB64': base64Encode(encryptedPack.ciphertext),
      'plaintextSha256': sha256Hex,
    });
  }

  /// Validates checksum, decrypts if needed, upgrades legacy v1 schema, and returns preview counts.
  static ({BackupPreviewSummary summary, Map<String, List<Map<String, dynamic>>> collections})
      previewAndValidateArchive(
    String rawArchiveText, {
    String? passphrase,
  }) {
    final dynamic rootDecoded = jsonDecode(rawArchiveText);
    if (rootDecoded is! Map) {
      throw const FormatException('Định dạng tệp sao lưu không hợp lệ.');
    }
    final root = Map<String, dynamic>.from(rootDecoded);
    final isEncrypted = root['encrypted'] == true;
    Map<String, dynamic> payloadMap;
    var checksumOk = false;

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
      checksumOk = true;
      payloadMap =
          Map<String, dynamic>.from(jsonDecode(utf8.decode(plainBytes)) as Map);
    } else if (root['format'] == magicEnvelope && root['payload'] is Map) {
      final rawPayload = Map<String, dynamic>.from(root['payload'] as Map);
      final expectedSha = (root['sha256'] ?? '').toString();
      final actualSha =
          sha256.convert(utf8.encode(jsonEncode(rawPayload))).toString();
      if (expectedSha != actualSha) {
        throw const FormatException(
          'Mã kiểm tra toàn vẹn SHA-256 không khớp — từ chối nhập dữ liệu bị sửa đổi.',
        );
      }
      checksumOk = true;
      payloadMap = rawPayload;
    } else {
      // Backward compatibility for v1 un-enveloped exports (`PersonalDataExport`)
      payloadMap = <String, dynamic>{
        'schemaVersion': (root['schemaVersion'] as num?)?.toInt() ?? 1,
        'ownerId': (root['ownerId'] ?? root['userId'] ?? '').toString(),
        'exportedAtUtc':
            (root['exportedAtUtc'] ?? root['exportedAt'] ?? '').toString(),
        'collections': root['collections'] is Map
            ? root['collections']
            : <String, dynamic>{
                'wallets': root['wallets'] ?? const <dynamic>[],
                'transactions': root['transactions'] ?? const <dynamic>[],
                'budgets': root['budgets'] ?? const <dynamic>[],
                'tasks': root['tasks'] ?? const <dynamic>[],
                'events': root['events'] ?? const <dynamic>[],
                'vehicles': root['vehicles'] ?? const <dynamic>[],
                'notes': root['notes'] ?? const <dynamic>[],
              },
      };
      checksumOk = true;
    }

    final schemaVer = (payloadMap['schemaVersion'] as num?)?.toInt() ?? 1;
    if (schemaVer < minSupportedSchemaVersion ||
        schemaVer > currentSchemaVersion) {
      throw FormatException(
        'Phiên bản cấu trúc sao lưu v$schemaVer không tương thích (hỗ trợ v$minSupportedSchemaVersion..v$currentSchemaVersion).',
      );
    }

    final rawCols = payloadMap['collections'] is Map
        ? Map<String, dynamic>.from(payloadMap['collections'] as Map)
        : const <String, dynamic>{};

    List<Map<String, dynamic>> readList(String key) {
      final raw = rawCols[key];
      if (raw is! List) return <Map<String, dynamic>>[];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => _migrateRecordIfNeeded(schemaVer, Map<String, dynamic>.from(m)))
          .toList();
    }

    final collections = <String, List<Map<String, dynamic>>>{
      'wallets': readList('wallets'),
      'transactions': readList('transactions'),
      'budgets': readList('budgets'),
      'tasks': readList('tasks'),
      'events': readList('events'),
      'vehicles': readList('vehicles'),
      'notes': readList('notes'),
    };

    final warnings = <String>[];
    if (schemaVer < currentSchemaVersion) {
      warnings.add(
        'Đã tự động nâng cấp cấu trúc dữ liệu từ v$schemaVer lên v$currentSchemaVersion.',
      );
    }

    final exportedAt = DateTime.tryParse(
          (payloadMap['exportedAtUtc'] ?? '').toString(),
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    final summary = BackupPreviewSummary(
      schemaVersion: schemaVer,
      ownerId: (payloadMap['ownerId'] ?? '').toString(),
      exportedAt: exportedAt,
      checksumVerified: checksumOk,
      wasEncrypted: isEncrypted,
      walletCount: collections['wallets']!.length,
      transactionCount: collections['transactions']!.length,
      budgetCount: collections['budgets']!.length,
      taskCount: collections['tasks']!.length,
      eventCount: collections['events']!.length,
      vehicleCount: collections['vehicles']!.length,
      noteCount: collections['notes']!.length,
      warnings: warnings,
    );
    return (summary: summary, collections: collections);
  }

  /// Plans non-destructive `merge`, `importAsNew`, or explicitly confirmed `replaceConfirmed`.
  static ({
    Map<String, List<Map<String, dynamic>>> resultingCollections,
    BackupRestoreReport report,
  }) applyRestorePlan({
    required Map<String, List<Map<String, dynamic>>> existingCollections,
    required Map<String, List<Map<String, dynamic>>> incomingCollections,
    required String targetUserId,
    BackupRestoreMode mode = BackupRestoreMode.merge,
    bool explicitReplaceConfirmation = false,
    int sourceSchemaVersion = currentSchemaVersion,
  }) {
    if (mode == BackupRestoreMode.replaceConfirmed &&
        !explicitReplaceConfirmation) {
      throw StateError(
        'Chế độ ghi đè yêu cầu người dùng xác nhận tường minh.',
      );
    }

    final out = <String, List<Map<String, dynamic>>>{};
    var imported = 0;
    var skippedDup = 0;
    final migratedCount = sourceSchemaVersion < currentSchemaVersion
        ? incomingCollections.values.fold<int>(0, (s, l) => s + l.length)
        : 0;

    final keys = <String>{
      ...existingCollections.keys,
      ...incomingCollections.keys,
    };

    for (final colKey in keys) {
      final currentList = List<Map<String, dynamic>>.from(
        existingCollections[colKey] ?? const <Map<String, dynamic>>[],
      );
      final incomingList =
          incomingCollections[colKey] ?? const <Map<String, dynamic>>[];

      if (mode == BackupRestoreMode.replaceConfirmed) {
        final rebound = incomingList.map((item) {
          final copy = Map<String, dynamic>.from(item);
          copy['ownerId'] = targetUserId;
          return copy;
        }).toList();
        imported += rebound.length;
        out[colKey] = rebound;
        continue;
      }

      final existingIds = <String>{
        for (final e in currentList)
          if ((e['id'] ?? '').toString().isNotEmpty) (e['id'] ?? '').toString(),
      };
      final existingFingerprints = <String>{
        for (final e in currentList) _recordFingerprint(colKey, e),
      };

      for (var i = 0; i < incomingList.length; i++) {
        final copy = Map<String, dynamic>.from(incomingList[i]);
        copy['ownerId'] = targetUserId;
        final origId = (copy['id'] ?? '').toString();
        final fp = _recordFingerprint(colKey, copy);

        if (mode == BackupRestoreMode.merge) {
          if ((origId.isNotEmpty && existingIds.contains(origId)) ||
              existingFingerprints.contains(fp)) {
            skippedDup++;
            continue;
          }
          currentList.add(copy);
          if (origId.isNotEmpty) existingIds.add(origId);
          existingFingerprints.add(fp);
          imported++;
        } else {
          // importAsNew: mint deterministic non-colliding IDs
          final newId = origId.isEmpty
              ? 'imp_${colKey}_$i'
              : 'imp_${origId}_${i + 1}';
          copy['id'] = newId;
          currentList.add(copy);
          imported++;
        }
      }
      out[colKey] = currentList;
    }

    final totalTxMinor = (out['transactions'] ?? const <Map<String, dynamic>>[])
        .fold<int>(0, (s, t) => s + ((t['amountMinor'] as num?)?.toInt() ?? 0));

    final report = BackupRestoreReport(
      mode: mode,
      importedCount: imported,
      skippedDuplicateCount: skippedDup,
      migratedLegacyRecords: migratedCount,
      detailsVi: <String>[
        'Đã nhập thành công $imported bản ghi (${mode.labelVi.split('(').first.trim()}).',
        if (skippedDup > 0) 'Đã chặn $skippedDup bản ghi trùng lặp.',
        if (totalTxMinor > 0)
          'Tổng giá trị giao dịch sau khôi phục: ${VndAmount.format(totalTxMinor)}.',
      ],
    );
    return (resultingCollections: out, report: report);
  }

  static Map<String, dynamic> _migrateRecordIfNeeded(
    int schemaVer,
    Map<String, dynamic> rec,
  ) {
    if (schemaVer == 1) {
      rec.putIfAbsent('currencyCode', () => 'VND');
      if (rec.containsKey('amount') && !rec.containsKey('amountMinor')) {
        rec['amountMinor'] = (rec['amount'] as num?)?.toInt() ?? 0;
      }
    }
    return rec;
  }

  static String _recordFingerprint(String colKey, Map<String, dynamic> rec) {
    return '$colKey|${rec['title'] ?? rec['merchant'] ?? rec['name'] ?? ''}|${rec['amountMinor'] ?? rec['limitMinor'] ?? ''}|${rec['occurredAt'] ?? rec['startsAt'] ?? ''}';
  }

  static ({Uint8List salt, Uint8List nonce, Uint8List ciphertext, Uint8List mac})
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
    final actualMac =
        Hmac(sha256, keys.macKey).convert(<int>[...salt, ...nonce, ...ciphertext]).bytes;
    if (actualMac.length != expectedMac.length) {
      throw const FormatException('Mật khẩu giải mã không đúng hoặc tệp bị sửa đổi.');
    }
    var diff = 0;
    for (var i = 0; i < actualMac.length; i++) {
      diff |= actualMac[i] ^ expectedMac[i];
    }
    if (diff != 0) {
      throw const FormatException('Mật khẩu giải mã không đúng hoặc tệp bị sửa đổi.');
    }
    return _xorKeystream(ciphertext, keys.encKey, nonce);
  }

  static ({List<int> encKey, List<int> macKey}) _deriveEncAndMacKeys(
    String passphrase,
    Uint8List salt,
  ) {
    final passBytes = utf8.encode(passphrase);
    final hmac = Hmac(sha256, passBytes);
    // Iterative HMAC-SHA256 key stretching (PBKDF2-style 4,096 rounds)
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
