import 'dart:typed_data';

import '../error/app_exception.dart';
import '../error/failure.dart';

/// Metadata descriptor for external binary attachments (receipt scans, vehicle photos, documents).
/// Binary bytes are NEVER stored inside Cloud Firestore documents to preserve Spark quota & latency.
final class StoredFileReference {
  final String storageKey;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String? downloadUrl;

  const StoredFileReference({
    required this.storageKey,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.downloadUrl,
  });
}

/// Pure abstraction for binary object storage (PHẦN 11 — FileStorageService).
/// Decouples domain/application features from Cloud Storage for Firebase (which requires Blaze billing)
/// so an S3/R2/Firebase Storage adapter can be plugged in later without touching any BLoC or Firestore model.
abstract interface class FileStorageService {
  bool get isCloudObjectStorageEnabled;

  Future<Result<StoredFileReference>> uploadUserAttachment({
    required String userId,
    required String folder,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  });

  Future<Result<void>> deleteUserAttachment({
    required String userId,
    required String storageKey,
  });
}

/// Default Spark-safe implementation:
/// - Explicitly prevents storing large binary blobs inside Cloud Firestore.
/// - Does NOT auto-upgrade to Blaze or provision paid Cloud Storage buckets.
class SparkSafeFileStorageService implements FileStorageService {
  static const int maxInlineMetadataPreviewBytes = 0;

  const SparkSafeFileStorageService();

  @override
  bool get isCloudObjectStorageEnabled => false;

  @override
  Future<Result<StoredFileReference>> uploadUserAttachment({
    required String userId,
    required String folder,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    return const Err(
      ValidationFailure(
        code: 'STORAGE_REQUIRES_BLAZE_OR_EXTERNAL_PROVIDER',
        message:
            'Lưu trữ file/ảnh nhị phân trên Cloud Storage yêu cầu gói Blaze trả phí. '
            'Life OS giữ nguyên gói Spark 0đ và không lưu file lớn vào Firestore.',
      ),
    );
  }

  @override
  Future<Result<void>> deleteUserAttachment({
    required String userId,
    required String storageKey,
  }) async {
    return const Success(null);
  }
}
