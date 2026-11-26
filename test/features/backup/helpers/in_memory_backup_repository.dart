import 'package:life_os/core/backup/lifeos_backup_restore_engine.dart';
import 'package:life_os/core/error/app_exception.dart';
import 'package:life_os/core/error/failure.dart';
import 'package:life_os/features/backup/domain/entities/backup_entities.dart';
import 'package:life_os/features/backup/domain/repositories/backup_repository.dart';
import 'package:life_os/features/backup/domain/services/backup_archive_codec.dart';

/// Test-only in-memory [BackupRepository] for widget tests that inject a
/// [BackupBloc] via `backupBlocOverride` without Firebase/GetIt.
class InMemorySnapshotBackupRepository implements BackupRepository {
  final Map<String, List<Map<String, dynamic>>> _store;
  final BackupArchiveCodec _codec;

  InMemorySnapshotBackupRepository({
    Map<String, List<Map<String, dynamic>>> initialCollections = const {},
    BackupArchiveCodec codec = const BackupArchiveCodec.forTesting(),
  }) : _codec = codec,
       _store = <String, List<Map<String, dynamic>>>{
         for (final key in BackupCollectionCatalog.allKeys)
           key: (initialCollections[key] ?? const <Map<String, dynamic>>[])
               .map((m) => Map<String, dynamic>.from(m))
               .toList(),
       };

  @override
  Future<Result<BackupOwnerDataSummary>> loadOwnerSummary({
    required String ownerId,
  }) async {
    return Success(
      BackupOwnerDataSummary(
        ownerId: ownerId,
        countsByCollection: <String, int>{
          for (final entry in _store.entries) entry.key: entry.value.length,
        },
        loadedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<Result<BackupExportBundle>> exportOwnerData({
    required String ownerId,
    String? passphrase,
  }) async {
    final cleanPass = (passphrase ?? '').trim();
    final encrypted = cleanPass.isNotEmpty;
    final archive = await _codec.createArchiveAsync(
      ownerId: ownerId,
      collections: _store,
      passphrase: cleanPass,
    );
    return Success(
      BackupExportBundle(
        archiveContent: archive,
        fileName: encrypted
            ? 'LifeOS_Backup_v3.lfbk.json'
            : 'LifeOS_Backup_v3.json',
        mimeType: 'application/json',
        summary: BackupOwnerDataSummary(
          ownerId: ownerId,
          countsByCollection: <String, int>{
            for (final entry in _store.entries) entry.key: entry.value.length,
          },
          loadedAt: DateTime.now().toUtc(),
        ),
        encrypted: encrypted,
        schemaVersion: BackupArchiveCodec.currentSchemaVersion,
        archiveSha256: BackupArchiveCodec.computeArchiveSha256(archive),
      ),
    );
  }

  @override
  Future<Result<BackupExportBundle>> exportTransactionsCsv({
    required String ownerId,
  }) async {
    final txs =
        _store[BackupCollectionCatalog.transactions] ??
        const <Map<String, dynamic>>[];
    final wallets =
        _store[BackupCollectionCatalog.wallets] ??
        const <Map<String, dynamic>>[];
    final walletNames = <String, String>{
      for (final w in wallets)
        if ((w['id'] ?? '').toString().isNotEmpty)
          (w['id'] ?? '').toString(): (w['name'] ?? '').toString(),
    };
    final csv = BackupArchiveCodec.exportTransactionsCsv(
      txs,
      walletNamesById: walletNames,
    );
    return Success(
      BackupExportBundle(
        archiveContent: csv,
        fileName: 'LifeOS_Transactions.csv',
        mimeType: 'text/csv',
        summary: BackupOwnerDataSummary(
          ownerId: ownerId,
          countsByCollection: <String, int>{
            BackupCollectionCatalog.wallets: wallets.length,
            BackupCollectionCatalog.transactions: txs.length,
          },
          loadedAt: DateTime.now().toUtc(),
        ),
        encrypted: false,
        schemaVersion: BackupArchiveCodec.currentSchemaVersion,
        archiveSha256: BackupArchiveCodec.computeArchiveSha256(csv),
      ),
    );
  }

  @override
  Future<Result<BackupArchivePreview>> previewAndValidateArchive({
    required String rawArchiveText,
    String? passphrase,
  }) async {
    try {
      final preview = await _codec.previewAndValidateAsync(
        rawArchiveText,
        passphrase: passphrase,
      );
      return Success(preview);
    } on FormatException catch (e) {
      return Err(ValidationFailure(message: e.message));
    } catch (_) {
      return const Err(
        ValidationFailure(
          message:
              'Không thể đọc tệp sao lưu — vui lòng kiểm tra mật khẩu hoặc toàn vẹn dữ liệu.',
        ),
      );
    }
  }

  @override
  Future<Result<BackupRestoreExecutionReport>> restoreOwnerData({
    required String targetUserId,
    required BackupArchivePreview preview,
    required BackupRestoreMode mode,
    required bool explicitReplaceConfirmation,
    void Function(BackupExecutionProgress progress)? onProgress,
  }) async {
    if (mode == BackupRestoreMode.replaceConfirmed &&
        !explicitReplaceConfirmation) {
      return const Err(
        ValidationFailure(
          message: 'Chế độ ghi đè yêu cầu người dùng xác nhận tường minh.',
        ),
      );
    }

    final planned = LifeOsBackupRestoreEngine.applyRestorePlan(
      existingCollections: _store,
      incomingCollections: preview.collections,
      targetUserId: targetUserId,
      mode: mode,
      explicitReplaceConfirmation: explicitReplaceConfirmation,
      sourceSchemaVersion: preview.schemaVersion,
    );
    _store
      ..clear()
      ..addAll(planned.resultingCollections);

    final stats = <BackupCollectionCommitStats>[];
    for (final entry in preview.collections.entries) {
      if (entry.value.isEmpty) continue;
      stats.add(
        BackupCollectionCommitStats(
          collectionKey: entry.key,
          labelVi: BackupCollectionCatalog.labelFor(entry.key),
          plannedCount: entry.value.length,
          committedCount: entry.value.length,
          skippedCount: 0,
          failedCount: 0,
        ),
      );
    }

    return Success(
      BackupRestoreExecutionReport(
        mode: mode,
        plannedCount: preview.totalRecordCount,
        committedCount: planned.report.importedCount,
        skippedCount: planned.report.skippedDuplicateCount,
        failedCount: 0,
        migratedLegacyRecords: planned.report.migratedLegacyRecords,
        perCollectionStats: stats,
        walletBalanceChecks: const <BackupWalletBalanceCheck>[],
        warnings: preview.warnings,
        detailsVi: planned.report.detailsVi,
      ),
    );
  }
}
