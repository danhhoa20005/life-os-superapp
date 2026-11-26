import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:life_os/core/backup/lifeos_backup_restore_engine.dart';
import 'package:life_os/features/backup/domain/entities/backup_entities.dart';
import 'package:life_os/features/backup/domain/services/backup_archive_codec.dart';

void main() {
  group('BackupArchiveCodec', () {
    test(
      'creates & verifies v3 plaintext archive with SHA-256 and blocks tampering',
      () {
        final raw = BackupArchiveCodec.createArchive(
          ownerId: 'u_codec_1',
          exportedAtOverride: DateTime.utc(2026, 11, 25, 10, 0),
          collections: {
            BackupCollectionCatalog.wallets: [
              {'id': 'w1', 'name': 'Ví chính', 'balanceMinor': 1500000},
            ],
            BackupCollectionCatalog.transactions: [
              {
                'id': 'tx1',
                'walletId': 'w1',
                'kind': 'expense',
                'amountMinor': 50000,
                'merchant': 'Cà phê',
                'occurredAt': '2026-11-25T03:00:00Z',
              },
            ],
            BackupCollectionCatalog.notes: [
              {'id': 'n1', 'title': 'Nhắc', 'content': 'Đóng tiền điện'},
            ],
          },
        );

        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        expect(decoded['format'], BackupArchiveCodec.magicEnvelopeV3);
        expect(decoded['encrypted'], isFalse);

        final preview = BackupArchiveCodec.previewAndValidateArchive(raw);
        expect(preview.schemaVersion, BackupArchiveCodec.currentSchemaVersion);
        expect(preview.checksumVerified, isTrue);
        expect(preview.wasEncrypted, isFalse);
        expect(preview.walletCount, 1);
        expect(preview.transactionCount, 1);
        expect(preview.noteCount, 1);

        // Tamper amountMinor -> SHA-256 check MUST fail
        final tampered = raw.replaceFirst('50000', '999999');
        expect(
          () => BackupArchiveCodec.previewAndValidateArchive(tampered),
          throwsFormatException,
        );
      },
    );

    test(
      'encrypts & decrypts v3 archive with PBKDF2-HMAC-SHA256 >= 120000 off UI isolate and rejects wrong passphrase',
      () async {
        const codec = BackupArchiveCodec();
        final encrypted = await codec.createArchiveAsync(
          ownerId: 'u_codec_2',
          passphrase: 'MatKhauManh#2026',
          collections: {
            BackupCollectionCatalog.wallets: [
              {'id': 'w1', 'name': 'VCB Lương', 'balanceMinor': 25000000},
            ],
            BackupCollectionCatalog.notes: [
              {'id': 'n1', 'title': 'Mật', 'content': 'Dữ liệu riêng tư'},
            ],
          },
        );

        final envelope = jsonDecode(encrypted) as Map<String, dynamic>;
        expect(envelope['format'], BackupArchiveCodec.magicEnvelopeV3);
        expect(envelope['encrypted'], isTrue);
        expect(envelope['kdf'], 'PBKDF2-HMAC-SHA256');
        expect(envelope['iterations'], greaterThanOrEqualTo(120000));
        expect(envelope['cipher'], 'STREAM-SHA256-ETM');
        expect(encrypted.contains('VCB Lương'), isFalse);
        expect(encrypted.contains('Dữ liệu riêng tư'), isFalse);

        await expectLater(
          codec.previewAndValidateAsync(encrypted),
          throwsFormatException,
        );
        await expectLater(
          codec.previewAndValidateAsync(encrypted, passphrase: 'SaiMatKhau'),
          throwsFormatException,
        );

        final preview = await codec.previewAndValidateAsync(
          encrypted,
          passphrase: 'MatKhauManh#2026',
        );
        expect(preview.wasEncrypted, isTrue);
        expect(preview.checksumVerified, isTrue);
        expect(preview.walletCount, 1);
        expect(preview.noteCount, 1);
      },
    );

    test(
      'pbkdf2HmacSha256 matches official PBKDF2-HMAC-SHA256 test vectors',
      () {
        String hexOf(Uint8List bytes) =>
            bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

        final v1 = BackupArchiveCodec.pbkdf2HmacSha256(
          passwordBytes: utf8.encode('password'),
          salt: utf8.encode('salt'),
          iterations: 1,
          dkLen: 32,
        );
        expect(
          hexOf(v1),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
        );

        final v2 = BackupArchiveCodec.pbkdf2HmacSha256(
          passwordBytes: utf8.encode('password'),
          salt: utf8.encode('salt'),
          iterations: 2,
          dkLen: 32,
        );
        expect(
          hexOf(v2),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
        );

        final v4096 = BackupArchiveCodec.pbkdf2HmacSha256(
          passwordBytes: utf8.encode('password'),
          salt: utf8.encode('salt'),
          iterations: 4096,
          dkLen: 32,
        );
        expect(
          hexOf(v4096),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
        );
      },
    );

    test(
      'rejects v3 archive claiming 4096 iterations or missing/weak KDF metadata',
      () async {
        const weakTestCodec = BackupArchiveCodec.forTesting(
          kdfIterations: 4096,
          minDecodeIterations: 4096,
        );
        final weakArchive = await weakTestCodec.createArchiveAsync(
          ownerId: 'u_weak',
          passphrase: 'Pass#Weak4096',
          collections: {
            BackupCollectionCatalog.notes: [
              {'id': 'n1', 'title': 'Nhạy cảm', 'content': 'Secret'},
            ],
          },
        );
        final weakEnvelope = jsonDecode(weakArchive) as Map<String, dynamic>;
        expect(weakEnvelope['iterations'], 4096);

        // Production codec MUST reject any v3 file claiming < 12000 iterations.
        const prodCodec = BackupArchiveCodec();
        await expectLater(
          prodCodec.previewAndValidateAsync(
            weakArchive,
            passphrase: 'Pass#Weak4096',
          ),
          throwsFormatException,
        );

        // Forging missing iterations or old 'HMAC-SHA256-4096' label MUST fail.
        final missingIter = Map<String, dynamic>.from(weakEnvelope)
          ..remove('iterations');
        await expectLater(
          prodCodec.previewAndValidateAsync(
            jsonEncode(missingIter),
            passphrase: 'Pass#Weak4096',
          ),
          throwsFormatException,
        );

        final legacyKdfLabel = Map<String, dynamic>.from(weakEnvelope)
          ..['kdf'] = 'HMAC-SHA256-4096'
          ..['iterations'] = 120000;
        await expectLater(
          prodCodec.previewAndValidateAsync(
            jsonEncode(legacyKdfLabel),
            passphrase: 'Pass#Weak4096',
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'tampered v3 ciphertext or MAC fails closed (both fail authentication)',
      () async {
        const fastCodec = BackupArchiveCodec.forTesting(kdfIterations: 12000);
        final encrypted = await fastCodec.createArchiveAsync(
          ownerId: 'u_mac_tamper',
          passphrase: 'StrongPass#2026',
          collections: {
            BackupCollectionCatalog.wallets: [
              {'id': 'w1', 'name': 'Ví chính', 'balanceMinor': 9000000},
            ],
          },
        );
        final root = jsonDecode(encrypted) as Map<String, dynamic>;

        // 1. Flip 1 byte in ciphertextB64 -> MAC failure before decrypt
        final ct = base64Decode(root['ciphertextB64'] as String);
        ct[0] ^= 0xFF;
        final badCt = Map<String, dynamic>.from(root)
          ..['ciphertextB64'] = base64Encode(ct);
        await expectLater(
          fastCodec.previewAndValidateAsync(
            jsonEncode(badCt),
            passphrase: 'StrongPass#2026',
          ),
          throwsFormatException,
        );

        // 2. Flip 1 byte in macB64 -> fails closed
        final mac = base64Decode(root['macB64'] as String);
        mac[mac.length - 1] ^= 0x01;
        final badMac = Map<String, dynamic>.from(root)
          ..['macB64'] = base64Encode(mac);
        await expectLater(
          fastCodec.previewAndValidateAsync(
            jsonEncode(badMac),
            passphrase: 'StrongPass#2026',
          ),
          throwsFormatException,
        );

        // 3. Downgrade iterations field on legitimate envelope -> MAC context mismatch
        final downgradedIter = Map<String, dynamic>.from(root)
          ..['iterations'] = 12001;
        await expectLater(
          fastCodec.previewAndValidateAsync(
            jsonEncode(downgradedIter),
            passphrase: 'StrongPass#2026',
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'backward-compatible with v2 (LIFEOS_BACKUP_V2) and v1 PersonalDataExport archives',
      () {
        final v2Archive = LifeOsBackupRestoreEngine.createBackupArchive(
          ownerId: 'u_v2',
          passphrase: 'PassV2#123',
          collections: {
            'wallets': [
              {'id': 'w1', 'name': 'Ví tiền mặt', 'balanceMinor': 500000},
            ],
            'transactions': [
              {
                'id': 'tx1',
                'walletId': 'w1',
                'kind': 'expense',
                'amountMinor': 45000,
                'merchant': 'Phở',
                'occurredAt': '2026-10-10T02:00:00Z',
              },
            ],
          },
        );

        final v2Preview = BackupArchiveCodec.previewAndValidateArchive(
          v2Archive,
          passphrase: 'PassV2#123',
        );
        expect(v2Preview.schemaVersion, 2);
        expect(v2Preview.wasEncrypted, isTrue);
        expect(v2Preview.walletCount, 1);
        expect(v2Preview.transactionCount, 1);
        expect(
          v2Preview.warnings.any((w) => w.contains('v2') && w.contains('v3')),
          isTrue,
        );

        final v1Raw = jsonEncode(<String, dynamic>{
          'exportedAt': '2026-09-01T00:00:00Z',
          'wallets': [
            {'id': 'w_v1', 'name': 'Ví cũ', 'balanceMinor': 1200000},
          ],
          'transactions': [
            {
              'id': 'tx_v1',
              'walletId': 'w_v1',
              'amount': 30000,
              'merchant': 'Bún bò',
              'occurredAt': '2026-09-01T01:00:00Z',
            },
          ],
          'privateEvents': [
            {
              'id': 'ev_v1',
              'title': 'Khám sức khỏe',
              'startsAt': '2026-09-05T02:00:00Z',
              'endsAt': '2026-09-05T03:00:00Z',
            },
          ],
          'bankAccounts': [
            {'id': 'ba_1', 'bankCode': 'VCB', 'accountMasked': '•••• 8899'},
          ],
        });

        final v1Preview = BackupArchiveCodec.previewAndValidateArchive(v1Raw);
        expect(v1Preview.schemaVersion, 1);
        expect(v1Preview.walletCount, 1);
        expect(v1Preview.transactionCount, 1);
        expect(
          v1Preview
              .collections[BackupCollectionCatalog.transactions]!
              .first['amountMinor'],
          30000,
        );
        expect(v1Preview.eventCount, 1);
        expect(
          v1Preview.collections[BackupCollectionCatalog.bankAccounts]!.length,
          1,
        );
      },
    );

    test('rejects v3 archive with corrupted plaintextSha256', () {
      final raw = BackupArchiveCodec.createArchive(
        ownerId: 'u_tamper',
        collections: const {},
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded['sha256'] = sha256.convert(utf8.encode('other')).toString();

      expect(
        () => BackupArchiveCodec.previewAndValidateArchive(jsonEncode(decoded)),
        throwsFormatException,
      );
    });

    test(
      'exportTransactionsCsv sanitizes formula-injection cells and includes wallet/note columns',
      () {
        final csv = BackupArchiveCodec.exportTransactionsCsv(
          [
            {
              'id': 'tx1',
              'occurredAt': '2026-11-25T10:00:00Z',
              'kind': 'transfer',
              'categoryName': 'Chuyển nội bộ',
              'merchant': '=CMD("calc")',
              'amountMinor': 250000,
              'verification': 'userConfirmed',
              'walletId': 'w1',
              'targetWalletId': 'w2',
              'note': '+1+1',
            },
          ],
          walletNamesById: const {'w1': 'VCB', 'w2': 'Ví tiền mặt'},
        );

        expect(csv, contains('ViNguon,ViDich,GhiChu'));
        expect(csv, contains('"\'=CMD(""calc"")"'));
        expect(csv, contains('"\'+1+1"'));
        expect(csv, contains('"VCB"'));
        expect(csv, contains('"Ví tiền mặt"'));
      },
    );
  });
}
