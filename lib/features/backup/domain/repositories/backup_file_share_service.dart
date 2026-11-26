import '../entities/backup_entities.dart';

/// Pure abstraction for exporting backup files directly to OS share sheets or
/// local files — NEVER copies sensitive backup payloads to the system clipboard.
abstract interface class BackupFileShareService {
  Future<BackupShareOutcome> shareTextFile({
    required String fileName,
    required String content,
    required String mimeType,
    required String title,
  });
}
