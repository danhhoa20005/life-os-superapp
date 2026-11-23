import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/family_entities.dart';
import '../../domain/repositories/family_repository.dart';

class FamilyRemoteDataSource {
  final FirebaseFirestore _firestore;
  static const Uuid _uuid = Uuid();
  static const String _inviteChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  const FamilyRemoteDataSource(this._firestore);

  FamilyEntity _mapFamily(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawMemberIds = (d['memberIds'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => e.toString())
        .toList();
    final rawRoles = Map<String, dynamic>.from(
      (d['memberRoles'] as Map<dynamic, dynamic>?) ??
          const <dynamic, dynamic>{},
    );
    final rawNames = Map<String, dynamic>.from(
      (d['memberNames'] as Map<dynamic, dynamic>?) ??
          const <dynamic, dynamic>{},
    );

    final members = rawMemberIds.map((uid) {
      final roleStr = rawRoles[uid]?.toString() ?? 'member';
      final role = switch (roleStr) {
        'owner' => HouseholdRole.owner,
        'admin' => HouseholdRole.admin,
        _ => HouseholdRole.member,
      };
      return FamilyMemberInfo(
        userId: uid,
        fullName: rawNames[uid]?.toString() ?? 'Thành viên',
        role: role,
      );
    }).toList();

    final spaceType = switch (d['spaceType'] as String?) {
      'roommates' => CollaborationSpaceType.roommates,
      'group' => CollaborationSpaceType.group,
      _ => CollaborationSpaceType.family,
    };

    final famId = (d['id'] as String?) ?? doc.id;
    final famName = (d['name'] as String?) ?? 'Gia đình';
    final rawPendingMap = Map<String, dynamic>.from(
      (d['pendingInvites'] as Map<dynamic, dynamic>?) ??
          const <dynamic, dynamic>{},
    );
    final pendingInvites = <FamilyPendingInviteEntity>[];
    for (final entry in rawPendingMap.entries) {
      if (entry.value is! Map) {
        continue;
      }
      final m = Map<String, dynamic>.from(entry.value as Map);
      final cTs = m['createdAt'];
      final eTs = m['expiresAt'];
      pendingInvites.add(
        FamilyPendingInviteEntity(
          inviteCode: (m['inviteCode'] as String?) ?? entry.key,
          familyId: famId,
          familyName: (m['familyName'] as String?) ?? famName,
          spaceType: spaceType,
          inviteeName: m['inviteeName'] as String?,
          inviteeContact: m['inviteeContact'] as String?,
          invitedByUserId: (m['createdBy'] as String?) ?? '',
          invitedByName: (m['invitedByName'] as String?) ?? 'Quản trị nhóm',
          createdAt: cTs is Timestamp ? cTs.toDate() : DateTime.now(),
          expiresAt: eTs is Timestamp
              ? eTs.toDate()
              : DateTime.now().add(const Duration(days: 7)),
          revoked: (m['revoked'] as bool?) ?? false,
        ),
      );
    }

    final createdTs = d['createdAt'];
    return FamilyEntity(
      id: famId,
      name: famName,
      spaceType: spaceType,
      createdBy: (d['createdBy'] as String?) ?? '',
      memberIds: rawMemberIds,
      members: members,
      pendingInvites: List.unmodifiable(pendingInvites),
      createdAt: createdTs is Timestamp ? createdTs.toDate() : DateTime.now(),
    );
  }

  SharedBillSplitEntity _mapSharedBill(
    String familyId,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final topic = switch (d['topic'] as String?) {
      'housework' => SharedExpenseTopic.housework,
      'utilities' => SharedExpenseTopic.utilities,
      'housing' => SharedExpenseTopic.housing,
      'shopping' => SharedExpenseTopic.shopping,
      'travel' => SharedExpenseTopic.travel,
      'other' => SharedExpenseTopic.other,
      _ => SharedExpenseTopic.dining,
    };
    final splitMethod = switch (d['splitMethod'] as String?) {
      'percentage' => SplitMethod.percentage,
      'shares' => SplitMethod.shares,
      'exact' => SplitMethod.exact,
      _ => SplitMethod.equal,
    };
    final rawShares = Map<String, dynamic>.from(
      (d['sharesByUserId'] as Map<dynamic, dynamic>?) ??
          const <dynamic, dynamic>{},
    );
    final shares = <String, int>{
      for (final e in rawShares.entries) e.key: (e.value as num?)?.toInt() ?? 0,
    };
    final rawNames = Map<String, dynamic>.from(
      (d['participantNames'] as Map<dynamic, dynamic>?) ??
          const <dynamic, dynamic>{},
    );
    final participantNames = <String, String>{
      for (final e in rawNames.entries)
        e.key: e.value?.toString() ?? 'Thành viên',
    };
    final createdTs = d['createdAt'];
    return SharedBillSplitEntity(
      id: (d['id'] as String?) ?? doc.id,
      familyId: familyId,
      title: (d['title'] as String?) ?? '',
      topic: topic,
      paidByUserId: (d['paidByUserId'] as String?) ?? '',
      paidByName: (d['paidByName'] as String?) ?? 'Thành viên',
      totalAmountMinor: (d['totalAmountMinor'] as num?)?.toInt() ?? 0,
      splitMethod: splitMethod,
      sharesByUserId: Map.unmodifiable(shares),
      participantNames: Map.unmodifiable(participantNames),
      choreOrTaskNote: d['choreOrTaskNote'] as String?,
      createdAt: createdTs is Timestamp ? createdTs.toDate() : DateTime.now(),
    );
  }

  DebtSettlementEntity _mapSettlement(
    String familyId,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final createdTs = d['createdAt'];
    return DebtSettlementEntity(
      id: (d['id'] as String?) ?? doc.id,
      familyId: familyId,
      fromUserId: (d['fromUserId'] as String?) ?? '',
      fromUserName: (d['fromUserName'] as String?) ?? 'Thành viên',
      toUserId: (d['toUserId'] as String?) ?? '',
      toUserName: (d['toUserName'] as String?) ?? 'Thành viên',
      amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
      paymentCode: (d['paymentCode'] as String?) ?? 'LIFEOS',
      note: d['note'] as String?,
      createdAt: createdTs is Timestamp ? createdTs.toDate() : DateTime.now(),
    );
  }

  Stream<List<FamilyEntity>> watchMyFamilies(String userId) {
    return _firestore
        .collection('families')
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snap) => snap.docs.map(_mapFamily).toList());
  }

  Stream<List<ShoppingItemEntity>> watchShoppingItems(String familyId) {
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('shopping_items')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final d = doc.data();
            return ShoppingItemEntity(
              id: (d['id'] as String?) ?? doc.id,
              familyId: familyId,
              title: (d['title'] as String?) ?? '',
              quantityLabel: (d['quantityLabel'] as String?) ?? '1',
              estimatedPriceMinor:
                  (d['estimatedPriceMinor'] as num?)?.toInt() ?? 0,
              isPurchased: (d['isPurchased'] as bool?) ?? false,
              addedByName: (d['addedByName'] as String?) ?? 'Thành viên',
            );
          }).toList();
        });
  }

  Stream<List<SharedBillSplitEntity>> watchSharedBills(String familyId) {
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('split_bills')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => _mapSharedBill(familyId, doc)).toList(),
        );
  }

  Stream<List<DebtSettlementEntity>> watchSettlements(String familyId) {
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('settlements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => _mapSettlement(familyId, doc)).toList(),
        );
  }

  Future<FamilyEntity> createFamily({
    required String userId,
    required String userName,
    required String familyName,
    CollaborationSpaceType spaceType = CollaborationSpaceType.family,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final docRef = _firestore.collection('families').doc(id);
    await docRef.set({
      'id': id,
      'name': familyName,
      'spaceType': spaceType.name,
      'createdBy': userId,
      'memberIds': <String>[userId],
      'memberRoles': <String, String>{userId: 'owner'},
      'memberNames': <String, String>{userId: userName},
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });

    await _firestore.collection('users').doc(userId).update({
      'activeFamilyId': id,
      'updatedAt': Timestamp.fromDate(now),
    });

    final snap = await docRef.get();
    return _mapFamily(snap);
  }

  Future<String> createInviteCode({
    required String userId,
    required String familyId,
    required String familyName,
    CollaborationSpaceType spaceType = CollaborationSpaceType.family,
    String? invitedByName,
    String? inviteeName,
    String? inviteeContact,
  }) async {
    final rand = Random.secure();
    final suffix = List.generate(
      6,
      (_) => _inviteChars[rand.nextInt(_inviteChars.length)],
    ).join();
    final code = 'FAM-$suffix';
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 7));
    final cleanInviteeName = inviteeName?.trim();
    final cleanContact = inviteeContact?.trim();
    final cleanInviter =
        (invitedByName != null && invitedByName.trim().isNotEmpty)
        ? invitedByName.trim()
        : 'Trưởng nhóm';

    final invitePayload = <String, dynamic>{
      'inviteCode': code,
      'familyId': familyId,
      'familyName': familyName,
      'spaceType': spaceType.name,
      'createdBy': userId,
      'invitedByName': cleanInviter,
      if (cleanInviteeName != null && cleanInviteeName.isNotEmpty)
        'inviteeName': cleanInviteeName,
      if (cleanContact != null && cleanContact.isNotEmpty)
        'inviteeContact': cleanContact,
      'revoked': false,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': Timestamp.fromDate(now),
    };

    await _firestore.collection('family_invites').doc(code).set(invitePayload);

    final familyRef = _firestore.collection('families').doc(familyId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(familyRef);
      if (!snap.exists) {
        return;
      }
      final d = snap.data()!;
      final pending = Map<String, dynamic>.from(
        (d['pendingInvites'] as Map?) ?? const <String, dynamic>{},
      );
      pending[code] = invitePayload;
      tx.update(familyRef, {
        'pendingInvites': pending,
        'updatedAt': Timestamp.fromDate(now),
      });
    });

    return code;
  }

  Future<FamilyPendingInviteEntity> previewInviteCode({
    required String inviteCode,
  }) async {
    final cleanCode = FamilyInviteCodeExtractor.extractCode(inviteCode);
    if (cleanCode.length < 4) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Vui lòng nhập mã mời hợp lệ (ví dụ: FAM-8K2P9Q).',
      );
    }
    final invSnap = await _firestore
        .collection('family_invites')
        .doc(cleanCode)
        .get();
    if (!invSnap.exists) {
      throw const AppException(
        code: 'NOT_FOUND',
        message: 'Không tìm thấy lời mời nào khớp với mã này.',
      );
    }
    final d = invSnap.data()!;
    if ((d['revoked'] as bool?) == true) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Lời mời này đã bị quản trị viên thu hồi.',
      );
    }
    final expTs = d['expiresAt'];
    final expiresAt = expTs is Timestamp
        ? expTs.toDate()
        : DateTime.now().add(const Duration(days: 7));
    if (expiresAt.isBefore(DateTime.now())) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message:
            'Mã mời này đã hết hạn 7 ngày. Hãy nhờ trưởng nhóm cấp mã mới.',
      );
    }
    final cTs = d['createdAt'];
    final spaceType = switch (d['spaceType'] as String?) {
      'roommates' => CollaborationSpaceType.roommates,
      'group' => CollaborationSpaceType.group,
      _ => CollaborationSpaceType.family,
    };
    return FamilyPendingInviteEntity(
      inviteCode: (d['inviteCode'] as String?) ?? cleanCode,
      familyId: (d['familyId'] as String?) ?? '',
      familyName: (d['familyName'] as String?) ?? 'Không gian chung',
      spaceType: spaceType,
      inviteeName: d['inviteeName'] as String?,
      inviteeContact: d['inviteeContact'] as String?,
      invitedByUserId: (d['createdBy'] as String?) ?? '',
      invitedByName: (d['invitedByName'] as String?) ?? 'Trưởng nhóm',
      createdAt: cTs is Timestamp ? cTs.toDate() : DateTime.now(),
      expiresAt: expiresAt,
      revoked: false,
    );
  }

  Future<void> revokeInviteCode({
    required String actorUserId,
    required String familyId,
    required String inviteCode,
  }) async {
    final now = DateTime.now();
    final invRef = _firestore.collection('family_invites').doc(inviteCode);
    final invSnap = await invRef.get();
    if (invSnap.exists) {
      await invRef.update({
        'revoked': true,
        'revokedBy': actorUserId,
        'revokedAt': Timestamp.fromDate(now),
      });
    }

    final familyRef = _firestore.collection('families').doc(familyId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(familyRef);
      if (!snap.exists) {
        return;
      }
      final d = snap.data()!;
      final roles = Map<String, dynamic>.from((d['memberRoles'] as Map?) ?? {});
      final actorRole = roles[actorUserId]?.toString();
      if (actorRole != 'owner' && actorRole != 'admin') {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message:
              'Chỉ trưởng nhóm hoặc quản trị mới có quyền thu hồi lời mời.',
        );
      }
      tx.update(familyRef, {
        'pendingInvites.$inviteCode': FieldValue.delete(),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<FamilyEntity> joinFamilyByInvite({
    required String userId,
    required String userName,
    required String inviteCode,
  }) async {
    final cleanCode = FamilyInviteCodeExtractor.extractCode(inviteCode);
    final invSnap = await _firestore
        .collection('family_invites')
        .doc(cleanCode)
        .get();
    if (!invSnap.exists) {
      throw const AppException(
        code: 'NOT_FOUND',
        message: 'Mã mời gia đình không tồn tại.',
      );
    }
    final invData = invSnap.data()!;
    if ((invData['revoked'] as bool?) == true) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Lời mời này đã bị thu hồi.',
      );
    }
    final expTs = invData['expiresAt'];
    if (expTs is Timestamp && expTs.toDate().isBefore(DateTime.now())) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Mã mời đã hết hạn.',
      );
    }

    final familyId = invData['familyId'] as String;
    final isTargetedInvite =
        (invData['inviteeName'] as String?)?.trim().isNotEmpty ?? false;
    final familyRef = _firestore.collection('families').doc(familyId);

    await _firestore.runTransaction((tx) async {
      final famSnap = await tx.get(familyRef);
      if (!famSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Nhóm không tồn tại.',
        );
      }
      final d = famSnap.data()!;
      final memberIds = (d['memberIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList();
      if (memberIds.contains(userId)) {
        return;
      }

      final roles = Map<String, dynamic>.from((d['memberRoles'] as Map?) ?? {});
      final names = Map<String, dynamic>.from((d['memberNames'] as Map?) ?? {});
      memberIds.add(userId);
      // Security Rule invariant: joining via invite code ALWAYS assigns 'member' role!
      roles[userId] = 'member';
      names[userId] = userName;

      tx.update(familyRef, {
        'memberIds': memberIds,
        'memberRoles': roles,
        'memberNames': names,
        if (isTargetedInvite) 'pendingInvites.$cleanCode': FieldValue.delete(),
        'lastJoinedInviteCode': cleanCode,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    });

    await _firestore.collection('users').doc(userId).update({
      'activeFamilyId': familyId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    final updated = await familyRef.get();
    return _mapFamily(updated);
  }

  Future<void> updateMemberRole({
    required String actorUserId,
    required String familyId,
    required String targetUserId,
    required HouseholdRole newRole,
  }) async {
    if (newRole == HouseholdRole.owner) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Không thể cấp trùng vai trò Trưởng nhóm.',
      );
    }
    final familyRef = _firestore.collection('families').doc(familyId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(familyRef);
      if (!snap.exists) {
        return;
      }
      final d = snap.data()!;
      final roles = Map<String, dynamic>.from((d['memberRoles'] as Map?) ?? {});
      if (roles[actorUserId]?.toString() != 'owner') {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message: 'Chỉ Trưởng nhóm mới có quyền thay đổi vai trò thành viên.',
        );
      }
      if (roles[targetUserId]?.toString() == 'owner') {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Không thể hạ quyền của Trưởng nhóm.',
        );
      }
      roles[targetUserId] = newRole.name;
      tx.update(familyRef, {
        'memberRoles': roles,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    });
  }

  Future<void> removeMember({
    required String actorUserId,
    required String familyId,
    required String targetUserId,
  }) async {
    if (actorUserId == targetUserId) {
      return leaveFamily(userId: actorUserId, familyId: familyId);
    }
    final familyRef = _firestore.collection('families').doc(familyId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(familyRef);
      if (!snap.exists) {
        return;
      }
      final d = snap.data()!;
      final memberIds = (d['memberIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList();
      final roles = Map<String, dynamic>.from((d['memberRoles'] as Map?) ?? {});
      final names = Map<String, dynamic>.from((d['memberNames'] as Map?) ?? {});

      final actorRole = roles[actorUserId]?.toString();
      final targetRole = roles[targetUserId]?.toString();
      if (actorRole != 'owner' && actorRole != 'admin') {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message: 'Bạn không có quyền xóa thành viên khỏi nhóm.',
        );
      }
      if (targetRole == 'owner' ||
          (actorRole == 'admin' && targetRole == 'admin')) {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Không thể xóa Trưởng nhóm hoặc Quản trị viên đồng cấp.',
        );
      }

      memberIds.remove(targetUserId);
      roles.remove(targetUserId);
      names.remove(targetUserId);

      tx.update(familyRef, {
        'memberIds': memberIds,
        'memberRoles': roles,
        'memberNames': names,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    });
  }

  Future<void> leaveFamily({
    required String userId,
    required String familyId,
  }) async {
    final familyRef = _firestore.collection('families').doc(familyId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(familyRef);
      if (!snap.exists) return;
      final d = snap.data()!;
      final memberIds = (d['memberIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList();
      final roles = Map<String, dynamic>.from((d['memberRoles'] as Map?) ?? {});
      final names = Map<String, dynamic>.from((d['memberNames'] as Map?) ?? {});

      if (roles[userId] == 'owner' && memberIds.length > 1) {
        final otherOwners = memberIds
            .where((id) => id != userId && roles[id] == 'owner')
            .toList();
        if (otherOwners.isEmpty) {
          throw const AppException(
            code: 'CONFLICT_FAILURE',
            message:
                'Chủ nhóm duy nhất không thể rời nhóm khi còn thành viên khác.',
          );
        }
      }

      memberIds.remove(userId);
      roles.remove(userId);
      names.remove(userId);

      tx.update(familyRef, {
        'memberIds': memberIds,
        'memberRoles': roles,
        'memberNames': names,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    });

    await _firestore.collection('users').doc(userId).update({
      'activeFamilyId': null,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> addShoppingItem({
    required String familyId,
    required String userName,
    required String title,
    required String quantityLabel,
    required int estimatedPriceMinor,
  }) async {
    final id = _uuid.v4();
    await _firestore
        .collection('families')
        .doc(familyId)
        .collection('shopping_items')
        .doc(id)
        .set({
          'id': id,
          'title': title,
          'quantityLabel': quantityLabel,
          'estimatedPriceMinor': estimatedPriceMinor,
          'isPurchased': false,
          'addedByName': userName,
          'createdAt': Timestamp.fromDate(DateTime.now()),
        });
  }

  Future<void> toggleShoppingItem({
    required String familyId,
    required String itemId,
    required bool isPurchased,
  }) async {
    await _firestore
        .collection('families')
        .doc(familyId)
        .collection('shopping_items')
        .doc(itemId)
        .update({'isPurchased': isPurchased});
  }

  Future<SharedBillSplitEntity> createSharedBillSplit({
    required String familyId,
    required String title,
    required SharedExpenseTopic topic,
    required String paidByUserId,
    required String paidByName,
    required int totalAmountMinor,
    required SplitMethod splitMethod,
    required Map<String, int> sharesByUserId,
    required Map<String, String> participantNames,
    String? choreOrTaskNote,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final ref = _firestore
        .collection('families')
        .doc(familyId)
        .collection('split_bills')
        .doc(id);

    await ref.set({
      'id': id,
      'familyId': familyId,
      'title': title,
      'topic': topic.name,
      'paidByUserId': paidByUserId,
      'paidByName': paidByName,
      'totalAmountMinor': totalAmountMinor,
      'currencyCode': 'VND',
      'splitMethod': splitMethod.name,
      'sharesByUserId': sharesByUserId,
      'participantNames': participantNames,
      if (choreOrTaskNote != null && choreOrTaskNote.isNotEmpty)
        'choreOrTaskNote': choreOrTaskNote,
      'createdAt': Timestamp.fromDate(now),
    });

    final snap = await ref.get();
    return _mapSharedBill(familyId, snap);
  }

  Future<DebtSettlementEntity> recordDebtSettlement({
    required String familyId,
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String toUserName,
    required int amountMinor,
    required String paymentCode,
    String? note,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final ref = _firestore
        .collection('families')
        .doc(familyId)
        .collection('settlements')
        .doc(id);

    await ref.set({
      'id': id,
      'familyId': familyId,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'amountMinor': amountMinor,
      'currencyCode': 'VND',
      'paymentCode': paymentCode,
      if (note != null && note.isNotEmpty) 'note': note,
      'createdAt': Timestamp.fromDate(now),
    });

    final snap = await ref.get();
    return _mapSettlement(familyId, snap);
  }
}

class FamilyRepositoryImpl implements FamilyRepository {
  final FamilyRemoteDataSource _remoteDataSource;
  const FamilyRepositoryImpl(this._remoteDataSource);

  @override
  Stream<Result<List<FamilyEntity>>> watchMyFamilies(String userId) {
    return _remoteDataSource
        .watchMyFamilies(userId)
        .map<Result<List<FamilyEntity>>>((f) => Success(f))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<FamilyEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Stream<Result<List<ShoppingItemEntity>>> watchShoppingItems(String familyId) {
    return _remoteDataSource
        .watchShoppingItems(familyId)
        .map<Result<List<ShoppingItemEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<ShoppingItemEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Stream<Result<List<SharedBillSplitEntity>>> watchSharedBills(
    String familyId,
  ) {
    return _remoteDataSource
        .watchSharedBills(familyId)
        .map<Result<List<SharedBillSplitEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<SharedBillSplitEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Stream<Result<List<DebtSettlementEntity>>> watchSettlements(String familyId) {
    return _remoteDataSource
        .watchSettlements(familyId)
        .map<Result<List<DebtSettlementEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<DebtSettlementEntity>>> sink,
                ) {
                  sink.add(Err(ErrorMapper.map(e)));
                },
          ),
        );
  }

  @override
  Future<Result<FamilyEntity>> createFamily({
    required String userId,
    required String userName,
    required String familyName,
    CollaborationSpaceType spaceType = CollaborationSpaceType.family,
  }) async {
    try {
      final f = await _remoteDataSource.createFamily(
        userId: userId,
        userName: userName,
        familyName: familyName,
        spaceType: spaceType,
      );
      return Success(f);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<String>> createInviteCode({
    required String userId,
    required String familyId,
    required String familyName,
    CollaborationSpaceType spaceType = CollaborationSpaceType.family,
    String? invitedByName,
    String? inviteeName,
    String? inviteeContact,
  }) async {
    try {
      final code = await _remoteDataSource.createInviteCode(
        userId: userId,
        familyId: familyId,
        familyName: familyName,
        spaceType: spaceType,
        invitedByName: invitedByName,
        inviteeName: inviteeName,
        inviteeContact: inviteeContact,
      );
      return Success(code);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<FamilyPendingInviteEntity>> previewInviteCode({
    required String inviteCode,
  }) async {
    try {
      final preview = await _remoteDataSource.previewInviteCode(
        inviteCode: inviteCode,
      );
      return Success(preview);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> revokeInviteCode({
    required String actorUserId,
    required String familyId,
    required String inviteCode,
  }) async {
    try {
      await _remoteDataSource.revokeInviteCode(
        actorUserId: actorUserId,
        familyId: familyId,
        inviteCode: inviteCode,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<FamilyEntity>> joinFamilyByInvite({
    required String userId,
    required String userName,
    required String inviteCode,
  }) async {
    try {
      final f = await _remoteDataSource.joinFamilyByInvite(
        userId: userId,
        userName: userName,
        inviteCode: inviteCode,
      );
      return Success(f);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateMemberRole({
    required String actorUserId,
    required String familyId,
    required String targetUserId,
    required HouseholdRole newRole,
  }) async {
    try {
      await _remoteDataSource.updateMemberRole(
        actorUserId: actorUserId,
        familyId: familyId,
        targetUserId: targetUserId,
        newRole: newRole,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> removeMember({
    required String actorUserId,
    required String familyId,
    required String targetUserId,
  }) async {
    try {
      await _remoteDataSource.removeMember(
        actorUserId: actorUserId,
        familyId: familyId,
        targetUserId: targetUserId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> leaveFamily({
    required String userId,
    required String familyId,
  }) async {
    try {
      await _remoteDataSource.leaveFamily(userId: userId, familyId: familyId);
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> addShoppingItem({
    required String familyId,
    required String userName,
    required String title,
    required String quantityLabel,
    required int estimatedPriceMinor,
  }) async {
    try {
      await _remoteDataSource.addShoppingItem(
        familyId: familyId,
        userName: userName,
        title: title,
        quantityLabel: quantityLabel,
        estimatedPriceMinor: estimatedPriceMinor,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> toggleShoppingItem({
    required String familyId,
    required String itemId,
    required bool isPurchased,
  }) async {
    try {
      await _remoteDataSource.toggleShoppingItem(
        familyId: familyId,
        itemId: itemId,
        isPurchased: isPurchased,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<SharedBillSplitEntity>> createSharedBillSplit({
    required String familyId,
    required String title,
    required SharedExpenseTopic topic,
    required String paidByUserId,
    required String paidByName,
    required int totalAmountMinor,
    required SplitMethod splitMethod,
    required Map<String, int> sharesByUserId,
    required Map<String, String> participantNames,
    String? choreOrTaskNote,
  }) async {
    try {
      final bill = await _remoteDataSource.createSharedBillSplit(
        familyId: familyId,
        title: title,
        topic: topic,
        paidByUserId: paidByUserId,
        paidByName: paidByName,
        totalAmountMinor: totalAmountMinor,
        splitMethod: splitMethod,
        sharesByUserId: sharesByUserId,
        participantNames: participantNames,
        choreOrTaskNote: choreOrTaskNote,
      );
      return Success(bill);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<DebtSettlementEntity>> recordDebtSettlement({
    required String familyId,
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String toUserName,
    required int amountMinor,
    required String paymentCode,
    String? note,
  }) async {
    try {
      final settlement = await _remoteDataSource.recordDebtSettlement(
        familyId: familyId,
        fromUserId: fromUserId,
        fromUserName: fromUserName,
        toUserId: toUserId,
        toUserName: toUserName,
        amountMinor: amountMinor,
        paymentCode: paymentCode,
        note: note,
      );
      return Success(settlement);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
