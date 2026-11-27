import '../../../../core/backup/lifeos_backup_restore_engine.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/backup_entities.dart';
import '../repositories/backup_repository.dart';

class LoadBackupOwnerSummaryUseCase
    implements UseCase<BackupOwnerDataSummary, String> {
  final BackupRepository _repository;
  const LoadBackupOwnerSummaryUseCase(this._repository);

  @override
  Future<Result<BackupOwnerDataSummary>> call(String ownerId) {
    if (ownerId.trim().isEmpty) {
      return Future.value(
        const Err(ValidationFailure(message: 'Thiếu mã định danh tài khoản.')),
      );
    }
    return _repository.loadOwnerSummary(ownerId: ownerId.trim());
  }
}

final class ExportFullBackupParams {
  final String ownerId;
  final String? passphrase;
  final bool allowPlaintextExport;

  const ExportFullBackupParams({
    required this.ownerId,
    this.passphrase,
    this.allowPlaintextExport = false,
  });
}

class ExportFullBackupUseCase
    implements UseCase<BackupExportBundle, ExportFullBackupParams> {
  final BackupRepository _repository;
  const ExportFullBackupUseCase(this._repository);

  @override
  Future<Result<BackupExportBundle>> call(ExportFullBackupParams params) {
    if (params.ownerId.trim().isEmpty) {
      return Future.value(
        const Err(ValidationFailure(message: 'Thiếu mã định danh tài khoản.')),
      );
    }
    return _repository.exportOwnerData(
      ownerId: params.ownerId.trim(),
      passphrase: params.passphrase,
      allowPlaintextExport: params.allowPlaintextExport,
    );
  }
}

class ExportTransactionsCsvUseCase
    implements UseCase<BackupExportBundle, String> {
  final BackupRepository _repository;
  const ExportTransactionsCsvUseCase(this._repository);

  @override
  Future<Result<BackupExportBundle>> call(String ownerId) {
    if (ownerId.trim().isEmpty) {
      return Future.value(
        const Err(ValidationFailure(message: 'Thiếu mã định danh tài khoản.')),
      );
    }
    return _repository.exportTransactionsCsv(ownerId: ownerId.trim());
  }
}

final class PreviewBackupArchiveParams {
  final String rawArchiveText;
  final String? passphrase;

  const PreviewBackupArchiveParams({
    required this.rawArchiveText,
    this.passphrase,
  });
}

class PreviewBackupArchiveUseCase
    implements UseCase<BackupArchivePreview, PreviewBackupArchiveParams> {
  final BackupRepository _repository;
  const PreviewBackupArchiveUseCase(this._repository);

  @override
  Future<Result<BackupArchivePreview>> call(PreviewBackupArchiveParams params) {
    if (params.rawArchiveText.trim().isEmpty) {
      return Future.value(
        const Err(
          ValidationFailure(
            message: 'Vui lòng dán nội dung tệp sao lưu để kiểm tra.',
          ),
        ),
      );
    }
    return _repository.previewAndValidateArchive(
      rawArchiveText: params.rawArchiveText,
      passphrase: params.passphrase,
    );
  }
}

final class RestoreBackupArchiveParams {
  final String targetUserId;
  final BackupArchivePreview preview;
  final BackupRestoreMode mode;
  final bool explicitReplaceConfirmation;
  final void Function(BackupExecutionProgress progress)? onProgress;

  const RestoreBackupArchiveParams({
    required this.targetUserId,
    required this.preview,
    required this.mode,
    this.explicitReplaceConfirmation = false,
    this.onProgress,
  });
}

class RestoreBackupArchiveUseCase
    implements
        UseCase<BackupRestoreExecutionReport, RestoreBackupArchiveParams> {
  final BackupRepository _repository;
  const RestoreBackupArchiveUseCase(this._repository);

  @override
  Future<Result<BackupRestoreExecutionReport>> call(
    RestoreBackupArchiveParams params,
  ) {
    if (params.targetUserId.trim().isEmpty) {
      return Future.value(
        const Err(
          ValidationFailure(message: 'Thiếu mã tài khoản đích để khôi phục.'),
        ),
      );
    }
    if (params.mode == BackupRestoreMode.replaceConfirmed &&
        !params.explicitReplaceConfirmation) {
      return Future.value(
        const Err(
          ValidationFailure(
            message:
                'Vui lòng tích chọn xác nhận trước khi dùng chế độ Ghi đè.',
          ),
        ),
      );
    }
    return _repository.restoreOwnerData(
      targetUserId: params.targetUserId.trim(),
      preview: params.preview,
      mode: params.mode,
      explicitReplaceConfirmation: params.explicitReplaceConfirmation,
      onProgress: params.onProgress,
    );
  }
}
