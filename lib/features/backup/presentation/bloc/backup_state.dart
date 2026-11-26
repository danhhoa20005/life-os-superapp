import 'package:equatable/equatable.dart';

import '../../domain/entities/backup_entities.dart';

enum BackupOperationKind {
  idle,
  loadingSummary,
  exportingJson,
  exportingCsv,
  previewing,
  restoring,
}

enum BackupToastTone { success, info, warning, error }

final class BackupToastFeedback extends Equatable {
  final int sequence;
  final String messageVi;
  final BackupToastTone tone;

  const BackupToastFeedback({
    required this.sequence,
    required this.messageVi,
    required this.tone,
  });

  @override
  List<Object?> get props => [sequence, messageVi, tone];
}

final class BackupState extends Equatable {
  final BackupOperationKind operation;
  final BackupOwnerDataSummary? summary;
  final String? summaryError;
  final String? lastExportedArchive;
  final BackupExportBundle? lastExportBundle;
  final BackupShareOutcome? lastShareOutcome;
  final BackupArchivePreview? preview;
  final String? previewError;
  final BackupRestoreExecutionReport? lastRestoreReport;
  final String? restoreError;
  final BackupExecutionProgress? progress;
  final BackupToastFeedback? toastFeedback;

  const BackupState({
    this.operation = BackupOperationKind.idle,
    this.summary,
    this.summaryError,
    this.lastExportedArchive,
    this.lastExportBundle,
    this.lastShareOutcome,
    this.preview,
    this.previewError,
    this.lastRestoreReport,
    this.restoreError,
    this.progress,
    this.toastFeedback,
  });

  bool get isBusy => operation != BackupOperationKind.idle;

  BackupState copyWith({
    BackupOperationKind? operation,
    BackupOwnerDataSummary? summary,
    String? summaryError,
    bool clearSummaryError = false,
    String? lastExportedArchive,
    BackupExportBundle? lastExportBundle,
    BackupShareOutcome? lastShareOutcome,
    BackupArchivePreview? preview,
    bool clearPreview = false,
    String? previewError,
    bool clearPreviewError = false,
    BackupRestoreExecutionReport? lastRestoreReport,
    bool clearLastRestoreReport = false,
    String? restoreError,
    bool clearRestoreError = false,
    BackupExecutionProgress? progress,
    bool clearProgress = false,
    BackupToastFeedback? toastFeedback,
    bool clearToastFeedback = false,
  }) {
    return BackupState(
      operation: operation ?? this.operation,
      summary: summary ?? this.summary,
      summaryError: clearSummaryError
          ? null
          : (summaryError ?? this.summaryError),
      lastExportedArchive: lastExportedArchive ?? this.lastExportedArchive,
      lastExportBundle: lastExportBundle ?? this.lastExportBundle,
      lastShareOutcome: lastShareOutcome ?? this.lastShareOutcome,
      preview: clearPreview ? null : (preview ?? this.preview),
      previewError: clearPreviewError
          ? null
          : (previewError ?? this.previewError),
      lastRestoreReport: clearLastRestoreReport
          ? null
          : (lastRestoreReport ?? this.lastRestoreReport),
      restoreError: clearRestoreError
          ? null
          : (restoreError ?? this.restoreError),
      progress: clearProgress ? null : (progress ?? this.progress),
      toastFeedback: clearToastFeedback
          ? null
          : (toastFeedback ?? this.toastFeedback),
    );
  }

  @override
  List<Object?> get props => [
    operation,
    summary,
    summaryError,
    lastExportedArchive,
    lastExportBundle,
    lastShareOutcome,
    preview,
    previewError,
    lastRestoreReport,
    restoreError,
    progress,
    toastFeedback,
  ];
}
