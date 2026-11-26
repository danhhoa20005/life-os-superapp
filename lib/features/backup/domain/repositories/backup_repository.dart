import '../../../../core/backup/lifeos_backup_restore_engine.dart';
import '../../../../core/error/app_exception.dart';
import '../entities/backup_entities.dart';

abstract interface class BackupRepository {
  Future<Result<BackupOwnerDataSummary>> loadOwnerSummary({
    required String ownerId,
  });

  Future<Result<BackupExportBundle>> exportOwnerData({
    required String ownerId,
    String? passphrase,
  });

  Future<Result<BackupExportBundle>> exportTransactionsCsv({
    required String ownerId,
  });

  Future<Result<BackupArchivePreview>> previewAndValidateArchive({
    required String rawArchiveText,
    String? passphrase,
  });

  Future<Result<BackupRestoreExecutionReport>> restoreOwnerData({
    required String targetUserId,
    required BackupArchivePreview preview,
    required BackupRestoreMode mode,
    required bool explicitReplaceConfirmation,
    void Function(BackupExecutionProgress progress)? onProgress,
  });
}
