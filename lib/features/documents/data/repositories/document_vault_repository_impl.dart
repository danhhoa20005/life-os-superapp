import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/document_vault_entity.dart';
import '../../domain/repositories/document_vault_repository.dart';

class DocumentVaultRepositoryImpl implements DocumentVaultRepository {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();

  const DocumentVaultRepositoryImpl(this._firestore);

  DocumentVaultEntity _fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required bool shared,
  }) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime parseDt(dynamic raw, DateTime fallback) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) return DateTime.tryParse(raw) ?? fallback;
      return fallback;
    }

    DateTime? parseNullableDt(dynamic raw) {
      if (raw == null) return null;
      if (raw is Timestamp) return raw.toDate();
      if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
      return null;
    }

    return DocumentVaultEntity(
      id: doc.id,
      ownerId: (d['ownerId'] ?? d['uploadedBy'] ?? '') as String,
      familyId: d['familyId'] as String?,
      isFamilyShared: shared || (d['isFamilyShared'] == true),
      folder: DocumentFolderCategoryX.fromKey(d['folder'] as String?),
      title: (d['title'] ?? 'Tài liệu') as String,
      referenceCode: (d['referenceCode'] ?? '') as String,
      note: (d['note'] ?? '') as String,
      uploadedByName: (d['uploadedByName'] ?? 'Thành viên') as String,
      expiryDate: parseNullableDt(d['expiryDate']),
      createdAt: parseDt(d['createdAt'], DateTime.now()),
    );
  }

  @override
  Stream<List<DocumentVaultEntity>> watchDocuments({
    required String userId,
    String? familyId,
  }) {
    return Stream<List<DocumentVaultEntity>>.multi((controller) {
      var personalDocs = <DocumentVaultEntity>[];
      var familyDocs = <DocumentVaultEntity>[];

      void emitMerged() {
        if (controller.isClosed) return;
        final merged = <String, DocumentVaultEntity>{
          for (final doc in personalDocs) doc.id: doc,
          for (final doc in familyDocs) doc.id: doc,
        }.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(merged);
      }

      final subPersonal = _firestore
          .collection('users')
          .doc(userId)
          .collection('documents')
          .snapshots()
          .listen((snap) {
            personalDocs = snap.docs
                .map((d) => _fromDoc(d, shared: false))
                .toList();
            emitMerged();
          }, onError: (_) => emitMerged());

      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subFamily;
      if (familyId != null && familyId.isNotEmpty) {
        subFamily = _firestore
            .collection('families')
            .doc(familyId)
            .collection('documents')
            .snapshots()
            .listen((snap) {
              familyDocs = snap.docs
                  .map((d) => _fromDoc(d, shared: true))
                  .toList();
              emitMerged();
            }, onError: (_) => emitMerged());
      }

      controller.onCancel = () async {
        await subPersonal.cancel();
        await subFamily?.cancel();
      };
    });
  }

  @override
  Future<Result<DocumentVaultEntity>> createDocument(
    CreateDocumentVaultParams params,
  ) async {
    final title = params.title.trim();
    if (title.isEmpty) {
      return const Err(
        ValidationFailure(message: 'Vui lòng nhập tên tài liệu hoặc hồ sơ.'),
      );
    }

    try {
      final id = 'doc_${_uuid.v4().substring(0, 8)}';
      final now = DateTime.now();
      final isShared =
          params.shareWithFamily &&
          params.familyId != null &&
          params.familyId!.isNotEmpty;

      final entity = DocumentVaultEntity(
        id: id,
        ownerId: params.userId,
        familyId: isShared ? params.familyId : null,
        isFamilyShared: isShared,
        folder: params.folder,
        title: title,
        referenceCode: params.referenceCode.trim(),
        note: params.note.trim(),
        uploadedByName: params.userName,
        expiryDate: params.expiryDate,
        createdAt: now,
      );

      final payload = <String, dynamic>{
        'id': id,
        'ownerId': params.userId,
        'uploadedBy': params.userId,
        'uploadedByName': params.userName,
        'familyId': isShared ? params.familyId : null,
        'isFamilyShared': isShared,
        'folder': params.folder.key,
        'title': entity.title,
        'referenceCode': entity.referenceCode,
        'note': entity.note,
        'expiryDate': params.expiryDate?.toIso8601String(),
        'createdAt': now.toIso8601String(),
      };

      if (isShared) {
        await _firestore
            .collection('families')
            .doc(params.familyId)
            .collection('documents')
            .doc(id)
            .set(payload);
      } else {
        await _firestore
            .collection('users')
            .doc(params.userId)
            .collection('documents')
            .doc(id)
            .set(payload);
      }

      return Success(entity);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể lưu tài liệu: $e'));
    }
  }

  @override
  Future<Result<void>> deleteDocument({
    required String userId,
    required DocumentVaultEntity document,
  }) async {
    try {
      if (document.isFamilyShared &&
          document.familyId != null &&
          document.familyId!.isNotEmpty) {
        await _firestore
            .collection('families')
            .doc(document.familyId)
            .collection('documents')
            .doc(document.id)
            .delete();
      } else {
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('documents')
            .doc(document.id)
            .delete();
      }
      return const Success(null);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Không thể xóa tài liệu: $e'));
    }
  }
}
