import 'dart:async';
import 'dart:io';

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
    final localPath = d['localAttachmentPath'] as String?;
    final localKey = d['localAttachmentStorageKey'] as String?;
    final hasLocalAttachment =
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
  /// (`AES-256-GCM` / `"LOSV"` AEAD + SHA-256), storing only metadata + checksum in Firestore.
  Future<Result<DocumentVaultEntity>> attachEncryptedLocalFile({
    required String userId,
    required DocumentVaultEntity document,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final storageOwner = document.ownerId.isNotEmpty
        ? document.ownerId
        : userId;
    final uploadRes = await _fileStorage.uploadUserAttachment(
      userId: storageOwner,
      folder: document.folder.key,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
    );
    if (uploadRes is Err<StoredFileReference>) {
      return Err(uploadRes.failure);
    }
    final stored = (uploadRes as Success<StoredFileReference>).value;

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
        'localAttachmentPath': updated.localAttachmentPath,
        'localAttachmentStorageKey': updated.localAttachmentStorageKey,
        'attachmentSha256': updated.attachmentSha256,
        if (updated.encryptedSizeBytes != null)
          'encryptedSizeBytes': updated.encryptedSizeBytes,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      return Success(updated);
    } catch (_) {
      await _fileStorage.deleteUserAttachment(
        userId: storageOwner,
        storageKey: stored.storageKey,
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
    final storageKey =
        document.localAttachmentStorageKey ??
        _extractFileName(document.localAttachmentPath);
    if (storageKey == null || storageKey.isEmpty) {
      return const Success(null);
    }
    final ownerScope = document.ownerId.isNotEmpty ? document.ownerId : userId;
    return _fileStorage.readLocalAttachmentBytes(
      userId: ownerScope,
      storageKey: storageKey,
      expectedPlaintextSha256: document.attachmentSha256,
    );
  }

  static String? _extractFileName(String? path) {
    if (path == null || path.isEmpty) return null;
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? null : parts.last;
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
      final storageOwner = document.ownerId.isNotEmpty
          ? document.ownerId
          : userId;
      final storageKey =
          document.localAttachmentStorageKey ??
          _extractFileName(document.localAttachmentPath) ??
          '';

      // FIX-008: Delete real encrypted local attachment BEFORE deleting Firestore metadata.
      if (storageKey.isNotEmpty ||
          (document.localAttachmentPath != null &&
              document.localAttachmentPath!.isNotEmpty)) {
        if (_fileStorage is SparkSafeFileStorageService) {
          final deletedPrimary = await _fileStorage.deleteAttachment(
            userId: storageOwner,
            storageKey: storageKey,
            localFilePath: document.localAttachmentPath,
          );
          if (!deletedPrimary) {
            return const Err(
              UnexpectedFailure(
                code: 'LOCAL_VAULT_DELETE_FAILED',
                message:
                    'Không thể xóa tệp đính kèm cục bộ của tài liệu khỏi thiết bị.',
              ),
            );
          }
          if (storageOwner != userId && storageKey.isNotEmpty) {
            final deletedActorCopy = await _fileStorage.deleteAttachment(
              userId: userId,
              storageKey: storageKey,
            );
            if (!deletedActorCopy) {
              return const Err(
                UnexpectedFailure(
                  code: 'LOCAL_VAULT_DELETE_FAILED',
                  message:
                      'Không thể xóa bản sao tệp đính kèm cục bộ của tài liệu.',
                ),
              );
            }
          }
        } else {
          if (storageKey.isNotEmpty) {
            final res = await _fileStorage.deleteUserAttachment(
              userId: storageOwner,
              storageKey: storageKey,
            );
            if (res is Err<void>) return res;
          }
          if (!kIsWeb &&
              document.localAttachmentPath != null &&
              document.localAttachmentPath!.isNotEmpty) {
            final f = File(document.localAttachmentPath!);
            if (f.existsSync()) {
              await f.delete();
              if (f.existsSync()) {
                return const Err(
                  UnexpectedFailure(
                    code: 'LOCAL_VAULT_DELETE_FAILED',
                    message: 'Không thể xóa tệp đính kèm cục bộ trên ổ đĩa.',
                  ),
                );
              }
            }
            final meta = File('${f.path}.meta');
            if (meta.existsSync()) {
              await meta.delete();
            }
          }
        }
      }

      await _docRef(userId: userId, document: document).delete();
      return const Success(null);
    } catch (_) {
      return const Err(
        UnexpectedFailure(
          message:
              'Không thể xóa tài liệu lúc này. Vui lòng kiểm tra kết nối và thử lại.',
        ),
      );
    }
  }
}
