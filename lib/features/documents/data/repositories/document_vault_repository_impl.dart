import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/services/file_storage_service.dart';
import '../../domain/entities/document_vault_entity.dart';
import '../../domain/repositories/document_vault_repository.dart';

class DocumentVaultRepositoryImpl implements DocumentVaultRepository {
  final FirebaseFirestore _firestore;
  final FileStorageService _fileStorage;
  static const Uuid _uuid = Uuid();

  const DocumentVaultRepositoryImpl(
    this._firestore, {
    FileStorageService? fileStorage,
  }) : _fileStorage = fileStorage ?? const SparkSafeFileStorageService();

  DocumentReference<Map<String, dynamic>> _docRef({
    required String userId,
    required DocumentVaultEntity document,
  }) {
    if (document.isFamilyShared &&
        document.familyId != null &&
        document.familyId!.isNotEmpty) {
      return _firestore
          .collection('families')
          .doc(document.familyId)
          .collection('documents')
          .doc(document.id);
    }
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('documents')
        .doc(document.id);
  }

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

    final rawLifecycle = d['storageLifecycle'] as String?;
    final rawAttachmentId = d['attachmentId'] as String?;
    final attachmentId =
        SparkSafeFileStorageService.isValidAttachmentId(rawAttachmentId)
        ? rawAttachmentId
        : null;
    final localPath =
        (d['localAttachmentPath'] ??
                d['localEncryptedPath'] ??
                d['encryptedPath'])
            as String?;
    final localKey = d['localAttachmentStorageKey'] as String?;
    final hasLocalAttachment =
        attachmentId != null ||
        (localPath != null && localPath.isNotEmpty) ||
        (localKey != null && localKey.isNotEmpty);

    final lifecycle = switch (rawLifecycle) {
      'localDeviceOnlyBinary' => DocumentStorageLifecycle.localDeviceOnlyBinary,
      'cloudEncryptedBackup' => DocumentStorageLifecycle.cloudEncryptedBackup,
      _ =>
        hasLocalAttachment
            ? DocumentStorageLifecycle.localDeviceOnlyBinary
            : DocumentStorageLifecycle.metadataCloudSynced,
    };

    final rawScope = d['storageScope'] as String?;
    final scope = switch (rawScope) {
      'localEncryptedVault' => DocumentStorageScope.localEncryptedVault,
      'cloudMetadataOnly' => DocumentStorageScope.cloudMetadataOnly,
      _ =>
        (hasLocalAttachment ||
                lifecycle == DocumentStorageLifecycle.localDeviceOnlyBinary)
            ? DocumentStorageScope.localEncryptedVault
            : DocumentStorageScope.cloudMetadataOnly,
    };

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
      storageLifecycle: lifecycle,
      storageScope: scope,
      attachmentId: attachmentId,
      localAttachmentPath: localPath,
      localAttachmentStorageKey: localKey,
      attachmentSha256: d['attachmentSha256'] as String?,
      encryptedSizeBytes: (d['encryptedSizeBytes'] as num?)?.toInt(),
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
        'storageLifecycle': entity.storageLifecycle.name,
        'storageScope': entity.storageScope.name,
        'binaryBackedUpToCloud':
            entity.storageLifecycle ==
            DocumentStorageLifecycle.cloudEncryptedBackup,
        'createdAt': now.toIso8601String(),
      };

      await _docRef(userId: params.userId, document: entity).set(payload);
      return Success(entity);
    } catch (_) {
      return const Err(
        UnexpectedFailure(
          message:
              'Không thể lưu tài liệu lúc này. Vui lòng kiểm tra kết nối và thử lại.',
        ),
      );
    }
  }

  /// Encrypts and attaches a local binary file to [document] using [_fileStorage]
  /// (`AES-256-GCM` / `"LOSV"` AEAD + SHA-256).
  /// H6: Syncs ONLY an opaque `attachmentId` (`^[A-Za-z0-9_-]{8,96}$`) + checksum
  /// to Firestore — NEVER writes raw local filesystem paths (`localAttachmentPath`,
  /// `localEncryptedPath`, `encryptedPath`) to Firestore!
  Future<Result<DocumentVaultEntity>> attachEncryptedLocalFile({
    required String userId,
    required DocumentVaultEntity document,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (document.ownerId.isNotEmpty && document.ownerId != userId) {
      return const Err(
        PermissionDeniedFailure(
          message: 'Chỉ chủ sở hữu tài liệu mới có thể đính kèm tệp cục bộ.',
        ),
      );
    }

    final uploadRes = await _fileStorage.uploadUserAttachment(
      userId: userId,
      folder: document.folder.key,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
    );
    if (uploadRes is Err<StoredFileReference>) {
      return Err(uploadRes.failure);
    }
    final stored = (uploadRes as Success<StoredFileReference>).value;
    final opaqueAttachmentId = stored.attachmentId;
    if (!SparkSafeFileStorageService.isValidAttachmentId(opaqueAttachmentId)) {
      await _fileStorage.deleteAttachmentForUser(
        userId: userId,
        legacyLocalPath: stored.localFilePath,
        legacyStorageKey: stored.storageKey,
      );
      return const Err(
        ValidationFailure(
          code: 'INVALID_ATTACHMENT_ID',
          message: 'Mã tệp đính kèm không hợp lệ.',
        ),
      );
    }

    try {
      final updated = DocumentVaultEntity(
        id: document.id,
        ownerId: document.ownerId,
        familyId: document.familyId,
        isFamilyShared: document.isFamilyShared,
        folder: document.folder,
        title: document.title,
        referenceCode: document.referenceCode,
        note: document.note,
        uploadedByName: document.uploadedByName,
        expiryDate: document.expiryDate,
        createdAt: document.createdAt,
        storageLifecycle: DocumentStorageLifecycle.localDeviceOnlyBinary,
        storageScope: DocumentStorageScope.localEncryptedVault,
        attachmentId: opaqueAttachmentId,
        localAttachmentPath: stored.localFilePath,
        localAttachmentStorageKey: stored.storageKey,
        attachmentSha256: stored.plaintextSha256,
        encryptedSizeBytes: stored.encryptedSizeBytes,
      );

      await _docRef(
        userId: userId,
        document: document,
      ).update(<String, dynamic>{
        'storageLifecycle': updated.storageLifecycle.name,
        'storageScope': updated.storageScope.name,
        'attachmentId': opaqueAttachmentId,
        'attachmentSha256': updated.attachmentSha256,
        if (updated.encryptedSizeBytes != null)
          'encryptedSizeBytes': updated.encryptedSizeBytes,
        'localAttachmentPath': FieldValue.delete(),
        'localEncryptedPath': FieldValue.delete(),
        'encryptedPath': FieldValue.delete(),
        'localAttachmentStorageKey': FieldValue.delete(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      return Success(updated);
    } catch (_) {
      await _fileStorage.deleteAttachmentForUser(
        userId: userId,
        attachmentId: opaqueAttachmentId,
        legacyLocalPath: stored.localFilePath,
        legacyStorageKey: stored.storageKey,
      );
      return const Err(
        UnexpectedFailure(
          message:
              'Không thể đính kèm tệp vào tài liệu lúc này. Vui lòng kiểm tra kết nối và thử lại.',
        ),
      );
    }
  }

  /// Reads and decrypts the local attachment for [document], verifying both AEAD
  /// tag and [DocumentVaultEntity.attachmentSha256] (fail-closed).
  Future<Result<Uint8List?>> readEncryptedLocalFile({
    required String userId,
    required DocumentVaultEntity document,
  }) async {
    if (document.ownerId.isNotEmpty && document.ownerId != userId) {
      return const Success(null);
    }
    final validAttachmentId =
        SparkSafeFileStorageService.isValidAttachmentId(document.attachmentId)
        ? document.attachmentId
        : null;
    final legacyKey =
        document.localAttachmentStorageKey ??
        _extractSafeFileName(document.localAttachmentPath);
    if (validAttachmentId == null && (legacyKey == null || legacyKey.isEmpty)) {
      return const Success(null);
    }
    return _fileStorage.readLocalAttachmentBytes(
      userId: userId,
      attachmentId: validAttachmentId,
      storageKey: legacyKey,
      expectedPlaintextSha256: document.attachmentSha256,
    );
  }

  static String? _extractSafeFileName(String? path) {
    if (path == null || path.isEmpty) return null;
    final parts = path.split(RegExp(r'[\\/]'));
    if (parts.isEmpty) return null;
    final candidate = parts.last;
    return SparkSafeFileStorageService.isSingleSafeFileName(candidate)
        ? candidate
        : null;
  }

  @override
  Future<Result<DocumentVaultEntity>> updateDocument(
    UpdateDocumentVaultParams params,
  ) async {
    final title = params.title.trim();
    if (title.isEmpty) {
      return const Err(
        ValidationFailure(message: 'Vui lòng nhập tên tài liệu hoặc hồ sơ.'),
      );
    }
    try {
      final doc = params.existing;
      final updated = DocumentVaultEntity(
        id: doc.id,
        ownerId: doc.ownerId,
        familyId: doc.familyId,
        isFamilyShared: doc.isFamilyShared,
        folder: params.folder,
        title: title,
        referenceCode: params.referenceCode.trim(),
        note: params.note.trim(),
        uploadedByName: doc.uploadedByName,
        expiryDate: params.expiryDate,
        createdAt: doc.createdAt,
        storageLifecycle: doc.storageLifecycle,
        storageScope: doc.storageScope,
        attachmentId: doc.attachmentId,
        localAttachmentPath: doc.localAttachmentPath,
        localAttachmentStorageKey: doc.localAttachmentStorageKey,
        attachmentSha256: doc.attachmentSha256,
        encryptedSizeBytes: doc.encryptedSizeBytes,
      );

      final updates = <String, dynamic>{
        'folder': params.folder.key,
        'title': updated.title,
        'referenceCode': updated.referenceCode,
        'note': updated.note,
        'expiryDate': params.expiryDate?.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await _docRef(userId: params.userId, document: doc).update(updates);
      return Success(updated);
    } catch (_) {
      return const Err(
        UnexpectedFailure(
          message:
              'Không thể cập nhật tài liệu lúc này. Vui lòng kiểm tra kết nối và thử lại.',
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteDocument({
    required String userId,
    required DocumentVaultEntity document,
  }) async {
    try {
      // H6: Execute Firestore document deletion FIRST!
      // If Firestore throws permission-denied or any error, abort immediately
      // and NEVER delete any local file.
      await _docRef(userId: userId, document: document).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        return const Err(PermissionDeniedFailure());
      }
      return const Err(
        UnexpectedFailure(
          message:
              'Không thể xóa tài liệu lúc này. Vui lòng kiểm tra kết nối và thử lại.',
        ),
      );
    } catch (_) {
      return const Err(
        UnexpectedFailure(
          message:
              'Không thể xóa tài liệu lúc này. Vui lòng kiểm tra kết nối và thử lại.',
        ),
      );
    }

    // ONLY AFTER Firestore confirms deletion succeeded, delete local attachment
    // strictly inside the current user's own local vault directory.
    final hasAttachmentRef =
        (document.attachmentId != null && document.attachmentId!.isNotEmpty) ||
        (document.localEncryptedPath != null &&
            document.localEncryptedPath!.isNotEmpty) ||
        (document.localAttachmentStorageKey != null &&
            document.localAttachmentStorageKey!.isNotEmpty);
    if (hasAttachmentRef) {
      await _fileStorage.deleteAttachmentForUser(
        userId: userId,
        attachmentId: document.attachmentId,
        legacyLocalPath: document.localEncryptedPath,
        legacyStorageKey: document.localAttachmentStorageKey,
      );
    }
    return const Success(null);
  }
}
