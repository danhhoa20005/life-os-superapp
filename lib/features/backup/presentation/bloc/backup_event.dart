import 'package:equatable/equatable.dart';

import '../../../../core/backup/lifeos_backup_restore_engine.dart';

sealed class BackupEvent extends Equatable {
  const BackupEvent();

  @override
  List<Object?> get props => [];
}

final class BackupSummaryRequested extends BackupEvent {
  final String userId;
  const BackupSummaryRequested(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class BackupExportJsonRequested extends BackupEvent {
  final String userId;
  final String passphrase;

  const BackupExportJsonRequested({
    required this.userId,
    this.passphrase = '',
  });

  @override
  List<Object?> get props => [userId, passphrase];
}

final class BackupExportCsvRequested extends BackupEvent {
  final String userId;
  const BackupExportCsvRequested(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class BackupArchivePreviewRequested extends BackupEvent {
  final String rawArchiveText;
  final String passphrase;

  const BackupArchivePreviewRequested({
    required this.rawArchiveText,
    this.passphrase = '',
  });

  @override
  List<Object?> get props => [rawArchiveText, passphrase];
}

final class BackupRestoreSubmitted extends BackupEvent {
  final String targetUserId;
  final BackupRestoreMode mode;
  final bool explicitReplaceConfirmation;

  const BackupRestoreSubmitted({
    required this.targetUserId,
    required this.mode,
    this.explicitReplaceConfirmation = false,
  });

  @override
  List<Object?> get props => [
    targetUserId,
    mode,
    explicitReplaceConfirmation,
  ];
}

final class BackupFeedbackCleared extends BackupEvent {
  const BackupFeedbackCleared();
}
