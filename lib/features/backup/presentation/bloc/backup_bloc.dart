import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';

import '../../../../core/error/app_exception.dart';
import '../../domain/entities/backup_entities.dart';
import '../../domain/repositories/backup_file_share_service.dart';
import '../../domain/usecases/backup_usecases.dart';
import 'backup_event.dart';
import 'backup_state.dart';

class BackupBloc extends Bloc<BackupEvent, BackupState> {
  final LoadBackupOwnerSummaryUseCase _loadSummary;
  final ExportFullBackupUseCase _exportFullBackup;
  final ExportTransactionsCsvUseCase _exportTransactionsCsv;
  final PreviewBackupArchiveUseCase _previewArchive;
  final RestoreBackupArchiveUseCase _restoreArchive;
  final BackupFileShareService _fileShareService;

  int _toastSeq = 0;

  BackupBloc({
    required LoadBackupOwnerSummaryUseCase loadSummary,
    required ExportFullBackupUseCase exportFullBackup,
    required ExportTransactionsCsvUseCase exportTransactionsCsv,
    required PreviewBackupArchiveUseCase previewArchive,
    required RestoreBackupArchiveUseCase restoreArchive,
    required BackupFileShareService fileShareService,
  }) : _loadSummary = loadSummary,
       _exportFullBackup = exportFullBackup,
       _exportTransactionsCsv = exportTransactionsCsv,
       _previewArchive = previewArchive,
       _restoreArchive = restoreArchive,
       _fileShareService = fileShareService,
       super(const BackupState()) {
    on<BackupSummaryRequested>(_onSummaryRequested, transformer: restartable());
    on<BackupExportJsonRequested>(
      _onExportJsonRequested,
      transformer: sequential(),
    );
    on<BackupExportCsvRequested>(
      _onExportCsvRequested,
      transformer: sequential(),
    );
    on<BackupArchivePreviewRequested>(
      _onPreviewRequested,
      transformer: sequential(),
    );
    on<BackupRestoreSubmitted>(_onRestoreSubmitted, transformer: sequential());
    on<BackupFeedbackCleared>(_onFeedbackCleared);
  }

  BackupToastFeedback _toast(String messageVi, BackupToastTone tone) {
    _toastSeq++;
    return BackupToastFeedback(
      sequence: _toastSeq,
      messageVi: messageVi,
      tone: tone,
    );
  }

  Future<void> _onSummaryRequested(
    BackupSummaryRequested event,
    Emitter<BackupState> emit,
  ) async {
    emit(
      state.copyWith(
        operation: BackupOperationKind.loadingSummary,
        clearSummaryError: true,
      ),
    );
    final res = await _loadSummary(event.userId);
    res.fold(
      (failure) => emit(
        state.copyWith(
          operation: BackupOperationKind.idle,
          summaryError: failure.message,
        ),
      ),
      (summary) => emit(
        state.copyWith(
          operation: BackupOperationKind.idle,
          summary: summary,
          clearSummaryError: true,
        ),
      ),
    );
  }

  Future<void> _onExportJsonRequested(
    BackupExportJsonRequested event,
    Emitter<BackupState> emit,
  ) async {
    emit(
      state.copyWith(
        operation: BackupOperationKind.exportingJson,
        clearSummaryError: true,
      ),
    );
    final res = await _exportFullBackup(
      ExportFullBackupParams(
        ownerId: event.userId,
        passphrase: event.passphrase,
        allowPlaintextExport: event.allowPlaintextExport,
      ),
    );
    if (res is Err<BackupExportBundle>) {
      emit(
        state.copyWith(
          operation: BackupOperationKind.idle,
          toastFeedback: _toast(res.failure.message, BackupToastTone.error),
        ),
      );
      return;
    }

    final bundle = (res as Success<BackupExportBundle>).value;
    emit(
      state.copyWith(
        summary: bundle.summary,
        lastExportedArchive: bundle.archiveContent,
        lastExportBundle: bundle,
      ),
    );
    final shareOutcome = await _fileShareService.shareTextFile(
      fileName: bundle.fileName,
      content: bundle.archiveContent,
      mimeType: bundle.mimeType,
      title: 'Bản sao lưu đầy đủ LifeOS',
    );
    final tone = switch (shareOutcome.status) {
      BackupShareStatus.shared => BackupToastTone.success,
      BackupShareStatus.cancelled => BackupToastTone.info,
      BackupShareStatus.failed => BackupToastTone.error,
    };
    emit(
      state.copyWith(
        operation: BackupOperationKind.idle,
        summary: bundle.summary,
        lastExportedArchive: bundle.archiveContent,
        lastExportBundle: bundle,
        lastShareOutcome: shareOutcome,
        toastFeedback: _toast(shareOutcome.messageVi, tone),
      ),
    );
  }

  Future<void> _onExportCsvRequested(
    BackupExportCsvRequested event,
    Emitter<BackupState> emit,
  ) async {
    emit(
      state.copyWith(
        operation: BackupOperationKind.exportingCsv,
        clearSummaryError: true,
      ),
    );
    final res = await _exportTransactionsCsv(event.userId);
    if (res is Err<BackupExportBundle>) {
      emit(
        state.copyWith(
          operation: BackupOperationKind.idle,
          toastFeedback: _toast(res.failure.message, BackupToastTone.error),
        ),
      );
      return;
    }

    final bundle = (res as Success<BackupExportBundle>).value;
    final shareOutcome = await _fileShareService.shareTextFile(
      fileName: bundle.fileName,
      content: bundle.archiveContent,
      mimeType: bundle.mimeType,
      title: 'Sao kê giao dịch CSV LifeOS',
    );
    final tone = switch (shareOutcome.status) {
      BackupShareStatus.shared => BackupToastTone.success,
      BackupShareStatus.cancelled => BackupToastTone.info,
      BackupShareStatus.failed => BackupToastTone.error,
    };
    emit(
      state.copyWith(
        operation: BackupOperationKind.idle,
        lastExportBundle: bundle,
        lastShareOutcome: shareOutcome,
        toastFeedback: _toast(shareOutcome.messageVi, tone),
      ),
    );
  }

  Future<void> _onPreviewRequested(
    BackupArchivePreviewRequested event,
    Emitter<BackupState> emit,
  ) async {
    emit(
      state.copyWith(
        operation: BackupOperationKind.previewing,
        clearPreviewError: true,
        clearRestoreError: true,
      ),
    );
    final res = await _previewArchive(
      PreviewBackupArchiveParams(
        rawArchiveText: event.rawArchiveText,
        passphrase: event.passphrase,
      ),
    );
    res.fold(
      (failure) => emit(
        state.copyWith(
          operation: BackupOperationKind.idle,
          clearPreview: true,
          clearLastRestoreReport: true,
          previewError: failure.message,
        ),
      ),
      (preview) => emit(
        state.copyWith(
          operation: BackupOperationKind.idle,
          preview: preview,
          clearPreviewError: true,
          clearLastRestoreReport: true,
        ),
      ),
    );
  }

  Future<void> _onRestoreSubmitted(
    BackupRestoreSubmitted event,
    Emitter<BackupState> emit,
  ) async {
    final currentPreview = state.preview;
    if (currentPreview == null) {
      emit(
        state.copyWith(
          toastFeedback: _toast(
            'Vui lòng kiểm tra toàn vẹn tệp sao lưu trước khi khôi phục.',
            BackupToastTone.warning,
          ),
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        operation: BackupOperationKind.restoring,
        clearLastRestoreReport: true,
        clearRestoreError: true,
        progress: const BackupExecutionProgress(
          stageLabelVi: 'Đang chuẩn bị khôi phục dữ liệu...',
          completedUnits: 0,
          totalUnits: 0,
        ),
      ),
    );

    final res = await _restoreArchive(
      RestoreBackupArchiveParams(
        targetUserId: event.targetUserId,
        preview: currentPreview,
        mode: event.mode,
        explicitReplaceConfirmation: event.explicitReplaceConfirmation,
        onProgress: (p) {
          if (!emit.isDone) {
            emit(state.copyWith(progress: p));
          }
        },
      ),
    );

    if (res is Err<BackupRestoreExecutionReport>) {
      emit(
        state.copyWith(
          operation: BackupOperationKind.idle,
          clearProgress: true,
          restoreError: res.failure.message,
          toastFeedback: _toast(res.failure.message, BackupToastTone.error),
        ),
      );
      return;
    }

    final report = (res as Success<BackupRestoreExecutionReport>).value;
    // Refresh live owner summary after commit so counts reflect actual persisted state.
    final refreshedSummaryRes = await _loadSummary(event.targetUserId);
    final refreshedSummary =
        refreshedSummaryRes is Success<BackupOwnerDataSummary>
        ? refreshedSummaryRes.value
        : state.summary;

    final tone = report.isCleanSuccess
        ? BackupToastTone.success
        : (report.isPartialFailure
              ? BackupToastTone.error
              : BackupToastTone.warning);

    emit(
      state.copyWith(
        operation: BackupOperationKind.idle,
        clearProgress: true,
        summary: refreshedSummary,
        lastRestoreReport: report,
        clearRestoreError: true,
        toastFeedback: _toast(
          report.detailsVi.isNotEmpty
              ? report.detailsVi.first
              : 'Đã hoàn tất xử lý khôi phục.',
          tone,
        ),
      ),
    );
  }

  void _onFeedbackCleared(
    BackupFeedbackCleared event,
    Emitter<BackupState> emit,
  ) {
    emit(state.copyWith(clearToastFeedback: true));
  }
}
