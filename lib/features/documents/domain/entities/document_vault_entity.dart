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
  });

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
  ];
}
