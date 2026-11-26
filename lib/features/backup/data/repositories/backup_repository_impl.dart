import '../../../../core/backup/lifeos_backup_restore_engine.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/backup_entities.dart';
import '../../domain/repositories/backup_repository.dart';
import '../../domain/services/backup_archive_codec.dart';
import '../datasources/firestore_backup_remote_datasource.dart';

class BackupRepositoryImpl implements BackupRepository {
  final FirestoreBackupRemoteDataSource _remoteDataSource;

  const BackupRepositoryImpl({
    required FirestoreBackupRemoteDataSource remoteDataSource,
  }) : _remoteDataSource = remoteDataSource;

  @override
  Future<Result<BackupOwnerDataSummary>> loadOwnerSummary({
    required String ownerId,
  }) async {
    try {
      final summary = await _remoteDataSource.loadOwnerSummary(
        ownerId: ownerId,
      );
      return Success(summary);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<BackupExportBundle>> exportOwnerData({
    required String ownerId,
    String? passphrase,
  }) async {
    try {
      final collections = await _remoteDataSource.fetchAllOwnerCollections(
        ownerId: ownerId,
      );
      final cleanPass = (passphrase ?? '').trim();
      final encrypted = cleanPass.isNotEmpty;
      final archive = BackupArchiveCodec.createArchive(
        ownerId: ownerId,
        collections: collections,
        passphrase: cleanPass,
      );
      final counts = <String, int>{
        for (final entry in collections.entries) entry.key: entry.value.length,
      };
      final summary = BackupOwnerDataSummary(
        ownerId: ownerId,
        countsByCollection: counts,
        loadedAt: DateTime.now().toUtc(),
      );
      return Success(
        BackupExportBundle(
          archiveContent: archive,
          fileName: encrypted
              ? 'LifeOS_Backup_v3.lfbk.json'
              : 'LifeOS_Backup_v3.json',
          mimeType: 'application/json',
          summary: summary,
          encrypted: encrypted,
          schemaVersion: BackupArchiveCodec.currentSchemaVersion,
          archiveSha256: BackupArchiveCodec.computeArchiveSha256(archive),
        ),
      );
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<BackupExportBundle>> exportTransactionsCsv({
    required String ownerId,
  }) async {
    try {
      final collections = await _remoteDataSource.fetchAllOwnerCollections(
        ownerId: ownerId,
      );
      final wallets =
          collections[BackupCollectionCatalog.wallets] ??
          const <Map<String, dynamic>>[];
      final transactions =
          collections[BackupCollectionCatalog.transactions] ??
          const <Map<String, dynamic>>[];
      final walletNamesById = <String, String>{
        for (final w in wallets)
          if ((w['id'] ?? '').toString().isNotEmpty)
            (w['id'] ?? '').toString(): (w['name'] ?? '').toString(),
      };
      final csv = BackupArchiveCodec.exportTransactionsCsv(
        transactions,
        walletNamesById: walletNamesById,
      );
      final counts = <String, int>{
        BackupCollectionCatalog.wallets: wallets.length,
        BackupCollectionCatalog.transactions: transactions.length,
      };
      final summary = BackupOwnerDataSummary(
        ownerId: ownerId,
        countsByCollection: counts,
        loadedAt: DateTime.now().toUtc(),
      );
      return Success(
        BackupExportBundle(
          archiveContent: csv,
          fileName: 'LifeOS_Transactions.csv',
          mimeType: 'text/csv',
          summary: summary,
          encrypted: false,
          schemaVersion: BackupArchiveCodec.currentSchemaVersion,
          archiveSha256: BackupArchiveCodec.computeArchiveSha256(csv),
        ),
      );
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<BackupArchivePreview>> previewAndValidateArchive({
    required String rawArchiveText,
    String? passphrase,
  }) async {
    try {
      final preview = BackupArchiveCodec.previewAndValidateArchive(
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
    try {
      final report = await _remoteDataSource.restoreAllOwnerCollections(
        targetUserId: targetUserId,
        preview: preview,
        mode: mode,
        explicitReplaceConfirmation: explicitReplaceConfirmation,
        onProgress: onProgress,
      );
      return Success(report);
    } on StateError catch (e) {
      return Err(ValidationFailure(message: e.message));
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
