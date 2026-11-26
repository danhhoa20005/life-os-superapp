import 'dart:convert';

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
      'encrypts & decrypts v3 archive with passphrase and rejects wrong passphrase',
      () {
        final encrypted = BackupArchiveCodec.createArchive(
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

        expect(encrypted.contains('VCB Lương'), isFalse);
        expect(encrypted.contains('Dữ liệu riêng tư'), isFalse);

        expect(
          () => BackupArchiveCodec.previewAndValidateArchive(encrypted),
          throwsFormatException,
        );
        expect(
          () => BackupArchiveCodec.previewAndValidateArchive(
            encrypted,
            passphrase: 'SaiMatKhau',
          ),
          throwsFormatException,
        );

        final preview = BackupArchiveCodec.previewAndValidateArchive(
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
          v1Preview.collections[BackupCollectionCatalog.transactions]!.first['amountMinor'],
          30000,
        );
        expect(v1Preview.eventCount, 1);
        expect(
          v1Preview.collections[BackupCollectionCatalog.bankAccounts]!.length,
          1,
        );
      },
    );

    test(
      'rejects v3 archive with corrupted plaintextSha256',
      () {
        final raw = BackupArchiveCodec.createArchive(
          ownerId: 'u_tamper',
          collections: const {},
        );
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded['sha256'] = sha256.convert(utf8.encode('other')).toString();

        expect(
          () => BackupArchiveCodec.previewAndValidateArchive(
            jsonEncode(decoded),
          ),
          throwsFormatException,
        );
      },
    );

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
