import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../entities/document_vault_entity.dart';

/// Shared failure code and factory for non-silent pending local attachment cleanup.
abstract final class DocumentCleanupFailureCodes {
  static const String pendingLocalCleanup = 'PENDING_LOCAL_CLEANUP';

  static Failure createPendingLocalCleanupFailure() => const UnexpectedFailure(
    code: pendingLocalCleanup,
    message:
        'Đã xóa hồ sơ trên đám mây, nhưng tệp mã hóa cục bộ chưa thể xóa ngay và đã được xếp hàng dọn lại.',
  );

  static bool isPendingLocalCleanup(Failure? failure) =>
      failure != null && failure.code == pendingLocalCleanup;
}

class CreateDocumentVaultParams {
  final String userId;
  final String userName;
  final String? familyId;
  final bool shareWithFamily;
  final DocumentFolderCategory folder;
  final String title;
  final String referenceCode;
  final String note;
  final DateTime? expiryDate;

  const CreateDocumentVaultParams({
    required this.userId,
    required this.userName,
    this.familyId,
    required this.shareWithFamily,
    required this.folder,
    required this.title,
    this.referenceCode = '',
    this.note = '',
    this.expiryDate,
  });
}

class UpdateDocumentVaultParams {
  final String userId;
  final DocumentVaultEntity existing;
  final DocumentFolderCategory folder;
  final String title;
  final String referenceCode;
  final String note;
  final DateTime? expiryDate;

  const UpdateDocumentVaultParams({
    required this.userId,
    required this.existing,
    required this.folder,
    required this.title,
    this.referenceCode = '',
    this.note = '',
    this.expiryDate,
  });
}

abstract interface class DocumentVaultRepository {
  Stream<List<DocumentVaultEntity>> watchDocuments({
    required String userId,
    String? familyId,
  });

  Future<Result<DocumentVaultEntity>> createDocument(
    CreateDocumentVaultParams params,
  );

  Future<Result<DocumentVaultEntity>> updateDocument(
    UpdateDocumentVaultParams params,
  );

  Future<Result<void>> deleteDocument({
    required String userId,
    required DocumentVaultEntity document,
  });
}
