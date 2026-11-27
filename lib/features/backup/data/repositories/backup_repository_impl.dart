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
  final BackupArchiveCodec _codec;

  const BackupRepositoryImpl({
    required FirestoreBackupRemoteDataSource remoteDataSource,
    BackupArchiveCodec codec = const BackupArchiveCodec(),
  }) : _remoteDataSource = remoteDataSource,
       _codec = codec;

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
    bool allowPlaintextExport = false,
  }) async {
    try {
      final collections = await _remoteDataSource.fetchAllOwnerCollections(
        ownerId: ownerId,
      );
      final cleanPass = (passphrase ?? '').trim();
      final encrypted = cleanPass.isNotEmpty;
      final archive = await _codec.createArchiveAsync(
        ownerId: ownerId,
        collections: collections,
        passphrase: cleanPass,
        allowPlaintextExport: allowPlaintextExport,
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
              ? 'LifeOS_Backup_v4.lfbk.json'
              : 'LifeOS_Backup_v4.json',
          mimeType: 'application/json',
          summary: summary,
          encrypted: encrypted,
          schemaVersion: BackupArchiveCodec.currentSchemaVersion,
          archiveSha256: BackupArchiveCodec.computeArchiveSha256(archive),
          limitationsVi: encrypted
              ? BackupCollectionCatalog.defaultLimitationsVi
              : <String>[
                  BackupArchiveCodec.plaintextExportWarningVi,
                  ...BackupCollectionCatalog.defaultLimitationsVi,
                ],
        ),
      );
    } on FormatException catch (e) {
      return Err(ValidationFailure(message: e.message));
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
