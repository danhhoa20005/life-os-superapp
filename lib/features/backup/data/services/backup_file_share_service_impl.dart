import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/backup_entities.dart';
import '../../domain/repositories/backup_file_share_service.dart';

/// Exports backup content exclusively as a file and invokes the platform share
/// sheet. Never touches `Clipboard.setData` under any success, cancel, or fallback path.
class MethodChannelBackupFileShareService implements BackupFileShareService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'vn.lifeos.app/app_updater',
  );

  final MethodChannel _channel;
  final Directory? _fallbackDirectoryOverride;
  final bool _invokePlatformShare;

  const MethodChannelBackupFileShareService({
    MethodChannel channel = _defaultChannel,
    Directory? fallbackDirectoryOverride,
    bool invokePlatformShare = true,
  }) : _channel = channel,
       _fallbackDirectoryOverride = fallbackDirectoryOverride,
       _invokePlatformShare = invokePlatformShare;

  @override
  Future<BackupShareOutcome> shareTextFile({
    required String fileName,
    required String content,
    required String mimeType,
    required String title,
  }) async {
    if (_invokePlatformShare &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        final sharedPath = await _channel.invokeMethod<String>(
          'shareTextFile',
          <String, dynamic>{
            'fileName': fileName,
            'content': content,
            'mimeType': mimeType,
            'title': title,
          },
        );
        if (sharedPath != null && sharedPath.trim().isNotEmpty) {
          return BackupShareOutcome(
            status: BackupShareStatus.shared,
            fileName: fileName,
            filePath: sharedPath.trim(),
            messageVi: 'Đã tạo tệp $fileName và mở bảng chia sẻ.',
          );
        }
        return BackupShareOutcome(
          status: BackupShareStatus.cancelled,
          fileName: fileName,
          messageVi:
              'Đã hủy chia sẻ tệp $fileName. Dữ liệu không được sao chép vào bộ nhớ tạm.',
        );
      } on MissingPluginException {
        return _writeLocalExportFileFallback(
          fileName: fileName,
          content: content,
          mimeType: mimeType,
        );
      } on PlatformException catch (e) {
        final code = e.code.toUpperCase();
        if (code.contains('CANCEL')) {
          return BackupShareOutcome(
            status: BackupShareStatus.cancelled,
            fileName: fileName,
            messageVi:
                'Đã hủy chia sẻ tệp $fileName. Dữ liệu không được sao chép vào bộ nhớ tạm.',
          );
        }
        return BackupShareOutcome(
          status: BackupShareStatus.failed,
          fileName: fileName,
          messageVi: 'Không thể mở chia sẻ tệp $fileName.',
        );
      }
    }

    return _writeLocalExportFileFallback(
      fileName: fileName,
      content: content,
      mimeType: mimeType,
    );
  }

  Future<BackupShareOutcome> _writeLocalExportFileFallback({
    required String fileName,
    required String content,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      return BackupShareOutcome(
        status: BackupShareStatus.failed,
        fileName: fileName,
        messageVi:
            'Trình duyệt không hỗ trợ lưu trực tiếp tệp sao lưu ngoài chia sẻ.',
      );
    }
    try {
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '_');
      final dir =
          _fallbackDirectoryOverride ??
          Directory('${Directory.systemTemp.path}/lifeos_backup_exports');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final outFile = File('${dir.path}${Platform.pathSeparator}$safeName');
      final prefix = mimeType.contains('csv') ? '\uFEFF' : '';
      outFile.writeAsStringSync('$prefix$content', flush: true);
      return BackupShareOutcome(
        status: BackupShareStatus.shared,
        fileName: fileName,
        filePath: outFile.path,
        messageVi: 'Đã tạo tệp $fileName tại thư mục xuất cục bộ.',
      );
    } catch (_) {
      return BackupShareOutcome(
        status: BackupShareStatus.failed,
        fileName: fileName,
        messageVi: 'Không thể ghi tệp sao lưu $fileName.',
      );
    }
  }
}
