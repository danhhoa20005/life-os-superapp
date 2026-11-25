import 'package:equatable/equatable.dart';

/// Four canonical document folders matching the LifeOS "Tài liệu gia đình / Tài liệu chung" screen.
enum DocumentFolderCategory {
  billsAndContracts,
  vehiclePapers,
  insuranceAndHealth,
  importantDocs,
}

extension DocumentFolderCategoryX on DocumentFolderCategory {
  String get key => switch (this) {
    DocumentFolderCategory.billsAndContracts => 'bills_contracts',
    DocumentFolderCategory.vehiclePapers => 'vehicle_papers',
    DocumentFolderCategory.insuranceAndHealth => 'insurance_health',
    DocumentFolderCategory.importantDocs => 'important_docs',
  };

  String get displayTitle => switch (this) {
    DocumentFolderCategory.billsAndContracts => 'Hóa đơn & Hợp đồng',
    DocumentFolderCategory.vehiclePapers => 'Giấy tờ xe',
    DocumentFolderCategory.insuranceAndHealth => 'Bảo hiểm & Sức khỏe',
    DocumentFolderCategory.importantDocs => 'Tài liệu quan trọng',
  };

  String get subtitleHint => switch (this) {
    DocumentFolderCategory.billsAndContracts =>
      'Hợp đồng thuê nhà, điện nước, hóa đơn bảo hành',
    DocumentFolderCategory.vehiclePapers =>
      'Đăng ký xe, đăng kiểm, giấy phép lái xe',
    DocumentFolderCategory.insuranceAndHealth =>
      'Bảo hiểm TNDS, BHYT, sổ khám sức khỏe',
    DocumentFolderCategory.importantDocs =>
      'Căn cước, hộ chiếu, giấy khai sinh, học bạ',
  };

  static DocumentFolderCategory fromKey(String? raw) {
    return switch (raw) {
      'vehicle_papers' => DocumentFolderCategory.vehiclePapers,
      'insurance_health' => DocumentFolderCategory.insuranceAndHealth,
      'important_docs' => DocumentFolderCategory.importantDocs,
      _ => DocumentFolderCategory.billsAndContracts,
    };
  }
}

enum DocumentStorageScope {
  /// Encrypted binary stored in device hardware-backed vault + metadata only in cloud.
  localEncryptedVault,

  /// Only metadata stored in cloud (no local binary file).
  cloudMetadataOnly,
}

enum DocumentStorageLifecycle {
  /// Metadata synced to Firestore; no binary file attached.
  metadataCloudSynced,

  /// Metadata synced to Firestore; encrypted binary stored ONLY on the originating device (`F19` / `DOC-01`).
  localDeviceOnlyBinary,

  /// Encrypted binary backed up & restorable across devices.
  cloudEncryptedBackup,
}

class DocumentVaultEntity extends Equatable {
  final String id;
  final String ownerId;
  final String? familyId;
  final bool isFamilyShared;
  final DocumentFolderCategory folder;
  final String title;
  final String referenceCode;
  final String note;
  final String uploadedByName;
  final DateTime? expiryDate;
  final DateTime createdAt;
  final DocumentStorageLifecycle storageLifecycle;
  final DocumentStorageScope storageScope;
  final String? localAttachmentPath;
  final String? localAttachmentStorageKey;
  final String? attachmentSha256;
  final int? encryptedSizeBytes;

  const DocumentVaultEntity({
    required this.id,
    required this.ownerId,
    this.familyId,
    required this.isFamilyShared,
    required this.folder,
    required this.title,
    required this.referenceCode,
    required this.note,
    required this.uploadedByName,
    this.expiryDate,
    required this.createdAt,
    this.storageLifecycle = DocumentStorageLifecycle.metadataCloudSynced,
    DocumentStorageScope? storageScope,
    this.localAttachmentPath,
    this.localAttachmentStorageKey,
    this.attachmentSha256,
    this.encryptedSizeBytes,
  }) : storageScope =
           storageScope ??
           ((localAttachmentPath != null && localAttachmentPath != '') ||
                   storageLifecycle ==
                       DocumentStorageLifecycle.localDeviceOnlyBinary
               ? DocumentStorageScope.localEncryptedVault
               : DocumentStorageScope.cloudMetadataOnly);

  /// Honest multi-device backup status label (`F19` / `DOC-01`).
  String get syncStatusLabelVi => switch (storageLifecycle) {
    DocumentStorageLifecycle.metadataCloudSynced =>
      'Thông tin đã đồng bộ đám mây',
    DocumentStorageLifecycle.localDeviceOnlyBinary =>
      'Tệp đính kèm chỉ lưu trên thiết bị gốc (chưa sao lưu đám mây)',
    DocumentStorageLifecycle.cloudEncryptedBackup =>
      'Đã sao lưu mã hóa đa thiết bị',
  };

  bool get isRestorableOnNewDevice =>
      storageLifecycle != DocumentStorageLifecycle.localDeviceOnlyBinary;

  bool isExpiringSoon(DateTime now) {
    if (expiryDate == null) return false;
    final days = expiryDate!.difference(now).inDays;
    return days >= 0 && days <= 45;
  }

  bool isExpired(DateTime now) {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(now);
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    familyId,
    isFamilyShared,
    folder,
    title,
    referenceCode,
    note,
    uploadedByName,
    expiryDate,
    createdAt,
    storageLifecycle,
    storageScope,
    localAttachmentPath,
    localAttachmentStorageKey,
    attachmentSha256,
    encryptedSizeBytes,
  ];
}
