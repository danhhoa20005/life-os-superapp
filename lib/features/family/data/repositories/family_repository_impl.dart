import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/family_entities.dart';
import '../../domain/repositories/family_repository.dart';

typedef FamilyCloudFunctionsInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> payload,
    );

class FamilyRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseAuth? _firebaseAuth;
  final FamilyCloudFunctionsInvoker? _functionsInvoker;
  static const Uuid _uuid = Uuid();
  static const String _inviteChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  const FamilyRemoteDataSource(
    this._firestore, {
    FirebaseAuth? firebaseAuth,
    FamilyCloudFunctionsInvoker? functionsInvoker,
  }) : _firebaseAuth = firebaseAuth,
       _functionsInvoker = functionsInvoker;

  CollaborationSpaceType _parseSpaceType(String? raw) => switch (raw) {
    'roommates' => CollaborationSpaceType.roommates,
    'group' => CollaborationSpaceType.group,
    _ => CollaborationSpaceType.family,
  };

  InviteKind _parseInviteKind(
    String? raw, {
    String? intendedRecipientHash,
    int maxUses = 1,
  }) {
    return switch (raw) {
      'targeted' => InviteKind.targeted,
      'reusableGroup' => InviteKind.reusableGroup,
      'oneTime' => InviteKind.oneTime,
      _ =>
        (intendedRecipientHash != null && intendedRecipientHash.isNotEmpty)
            ? InviteKind.targeted
            : (maxUses > 1 ? InviteKind.reusableGroup : InviteKind.oneTime),
    };
  }

  InviteStatus _parseInviteStatus(
    String? raw, {
    required bool revoked,
    required int usedCount,
    required int maxUses,
  }) {
    if (raw == 'revoked' || revoked) return InviteStatus.revoked;
    if (raw == 'consumed' || usedCount >= maxUses) return InviteStatus.consumed;
    if (raw == 'expired') return InviteStatus.expired;
    if (raw == 'active') return InviteStatus.active;
    return InviteStatus.active;
  }

  DateTime _readDateTime(dynamic value, DateTime fallback) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return fallback;
  }

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

    final spaceType = _parseSpaceType(d['spaceType'] as String?);
    final famId = (d['id'] as String?) ?? doc.id;
    final famName = (d['name'] as String?) ?? 'Gia đình';
    final rawPendingMap = Map<String, dynamic>.from(
      (d['pendingInvites'] as Map<dynamic, dynamic>?) ??
          const <dynamic, dynamic>{},
    );
    final pendingInvites = <FamilyPendingInviteEntity>[];
    final now = DateTime.now();

    for (final entry in rawPendingMap.entries) {
      if (entry.value is! Map) {
        continue;
      }
      final m = Map<String, dynamic>.from(entry.value as Map);
      final code = (m['inviteCode'] as String?) ?? entry.key;
      final maxUses = ((m['maxUses'] as num?)?.toInt() ?? 1).clamp(1, 100);
      final usedCount = ((m['usedCount'] as num?)?.toInt() ?? 0).clamp(0, 1000);
      final revoked = (m['revoked'] as bool?) ?? false;
      final recipientHash = m['intendedRecipientHash'] as String?;

      pendingInvites.add(
        FamilyPendingInviteEntity(
          inviteId: (m['inviteId'] as String?) ?? code,
          inviteCode: code,
          familyId: famId,
          familyName: (m['familyName'] as String?) ?? famName,
          spaceType: spaceType,
          inviteKind: _parseInviteKind(
            m['inviteKind'] as String?,
            intendedRecipientHash: recipientHash,
            maxUses: maxUses,
          ),
          inviteeName: m['inviteeName'] as String?,
          inviteeContact: m['inviteeContact'] as String?,
          intendedRecipientHash: recipientHash,
          invitedByUserId:
              (m['invitedByUserId'] as String?) ??
              (m['createdBy'] as String?) ??
              '',
          invitedByName: (m['invitedByName'] as String?) ?? 'Quản trị nhóm',
          createdAt: _readDateTime(m['createdAt'], now),
          expiresAt: _readDateTime(
            m['expiresAt'],
            now.add(const Duration(days: 7)),
          ),
          maxUses: maxUses,
          usedCount: usedCount,
          consumedBy: m['consumedBy'] as String?,
          consumedAt: m['consumedAt'] != null
              ? _readDateTime(m['consumedAt'], now)
              : null,
          revokedAt: m['revokedAt'] != null
              ? _readDateTime(m['revokedAt'], now)
              : null,
          revoked: revoked,
          status: _parseInviteStatus(
            m['status'] as String?,
            revoked: revoked,
            usedCount: usedCount,
            maxUses: maxUses,
          ),
        ),
      );
    }

    return FamilyEntity(
      id: famId,
      name: famName,
      spaceType: spaceType,
      createdBy: (d['createdBy'] as String?) ?? '',
      memberIds: rawMemberIds,
      members: members,
      pendingInvites: List.unmodifiable(pendingInvites),
      createdAt: _readDateTime(d['createdAt'], now),
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
      createdAt: _readDateTime(d['createdAt'], DateTime.now()),
    );
  }

  DebtSettlementEntity _mapSettlement(
    String familyId,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
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
      status: (d['status'] as String?) ?? 'confirmed',
      reversalOfId: d['reversalOfId'] as String?,
      reversedById: d['reversedById'] as String?,
      settlementRequestId: d['settlementRequestId'] as String?,
      isPartial: (d['isPartial'] as bool?) ?? false,
      createdAt: _readDateTime(d['createdAt'], DateTime.now()),
    );
  }

  SettlementRequestEntity _mapSettlementRequest(
    String familyId,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawStatus = d['status'] as String?;
    final status = switch (rawStatus) {
      'confirmed' => SettlementRequestStatus.confirmed,
      'rejected' => SettlementRequestStatus.rejected,
      _ => SettlementRequestStatus.pending,
    };
    return SettlementRequestEntity(
      id: (d['id'] as String?) ?? doc.id,
      familyId: familyId,
      fromUserId: (d['fromUserId'] as String?) ?? '',
      fromUserName: (d['fromUserName'] as String?) ?? 'Thành viên',
      toUserId: (d['toUserId'] as String?) ?? '',
      toUserName: (d['toUserName'] as String?) ?? 'Thành viên',
      amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
      paymentCode: (d['paymentCode'] as String?) ?? 'LIFEOS',
      note: d['note'] as String?,
      status: status,
      isPartial: (d['isPartial'] as bool?) ?? false,
      createdAt: _readDateTime(d['createdAt'], DateTime.now()),
      confirmedBy: d['confirmedBy'] as String?,
      confirmedAt: d['confirmedAt'] != null
          ? _readDateTime(d['confirmedAt'], DateTime.now())
          : null,
      disputeReason: d['disputeReason'] as String?,
      settlementId: d['settlementId'] as String?,
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

  Stream<List<SettlementRequestEntity>> watchSettlementRequests(
    String familyId,
  ) {
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('settlement_requests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => _mapSettlementRequest(familyId, doc))
              .toList(),
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

    await _firestore.collection('users').doc(userId).set({
      'id': userId,
      'familyId': id,
      'activeFamilyId': id,
      'familyIds': FieldValue.arrayUnion([id]),
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));

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
    InviteKind? inviteKind,
    int maxUses = 1,
    int ttlDays = 7,
  }) async {
    final cleanInviteeName = inviteeName?.trim();
    final cleanContact = inviteeContact?.trim();
    final hasContact = cleanContact != null && cleanContact.isNotEmpty;

    final effectiveKind =
        inviteKind ??
        (hasContact
            ? InviteKind.targeted
            : (maxUses > 1 ? InviteKind.reusableGroup : InviteKind.oneTime));

    var effectiveMaxUses = maxUses;
    if (effectiveKind == InviteKind.oneTime ||
        effectiveKind == InviteKind.targeted) {
      if (maxUses != 1) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Mã mời 1 lần hoặc đích danh chỉ cho phép maxUses = 1.',
        );
      }
      effectiveMaxUses = 1;
    } else {
      if (effectiveMaxUses < 2 || effectiveMaxUses > 100) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Mã mời nhóm nhiều lượt phải có số lượt từ 2 đến 100.',
        );
      }
    }

    if (effectiveKind == InviteKind.targeted && !hasContact) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Mã mời đích danh bắt buộc nhập Email hoặc SĐT người nhận.',
      );
    }

    final cleanTtlDays = ttlDays.clamp(1, 30);
    final cleanInviter =
        (invitedByName != null && invitedByName.trim().isNotEmpty)
        ? invitedByName.trim()
        : 'Trưởng nhóm';

    if (_functionsInvoker != null) {
      final res = await _functionsInvoker('createFamilyInvite', {
        'familyId': familyId,
        'familyName': familyName,
        'spaceType': spaceType.name,
        'invitedByName': cleanInviter,
        'inviteKind': effectiveKind.name,
        'maxUses': effectiveMaxUses,
        'ttlDays': cleanTtlDays,
        if (cleanInviteeName != null && cleanInviteeName.isNotEmpty)
          'inviteeName': cleanInviteeName,
        if (hasContact) 'inviteeContact': cleanContact,
      });
      final code = (res['inviteCode'] as String?)?.trim() ?? '';
      if (code.isEmpty) {
        throw const AppException(
          code: 'UNEXPECTED',
          message: 'Máy chủ không trả về mã mời hợp lệ.',
        );
      }
      return code;
    }

    final rand = Random.secure();
    final suffix = List.generate(
      6,
      (_) => _inviteChars[rand.nextInt(_inviteChars.length)],
    ).join();
    final code = 'FAM-$suffix';
    final now = DateTime.now();
    final expiresAt = now.add(Duration(days: cleanTtlDays));
    final recipientHash = hasContact
        ? FamilyInviteCodeExtractor.hashRecipientContact(cleanContact)
        : null;
    final publicInviteeName =
        FamilyInviteCodeExtractor.sanitizePublicInviteeName(cleanInviteeName);

    // STRICT FIX-003: NEVER write raw email/phone PII (`inviteeContact`) to public `family_invites/{code}`!
    final publicInvitePayload = <String, dynamic>{
      'inviteId': code,
      'inviteCode': code,
      'familyId': familyId,
      'familyName': familyName,
      'spaceType': spaceType.name,
      'inviteKind': effectiveKind.name,
      'isTargeted': effectiveKind == InviteKind.targeted,
      'createdBy': userId,
      'invitedByUserId': userId,
      'invitedByName': cleanInviter,
      if (publicInviteeName != null && publicInviteeName.isNotEmpty)
        'inviteeName': publicInviteeName,
      if (recipientHash != null && recipientHash.isNotEmpty)
        'intendedRecipientHash': recipientHash,
      'maxUses': effectiveMaxUses,
      'usedCount': 0,
      'consumedBy': null,
      'consumedAt': null,
      'revoked': false,
      'revokedAt': null,
      'status': InviteStatus.active.name,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    };

    // Internal family-only pendingInvites map retains invitee display contact for managers
    final internalPendingPayload = <String, dynamic>{
      ...publicInvitePayload,
      if (cleanInviteeName != null && cleanInviteeName.isNotEmpty)
        'inviteeName': cleanInviteeName,
      if (hasContact) 'inviteeContact': cleanContact,
    };

    final batch = _firestore.batch();
    batch.set(
      _firestore.collection('family_invites').doc(code),
      publicInvitePayload,
    );
    batch.update(_firestore.collection('families').doc(familyId), {
      'pendingInvites.$code': internalPendingPayload,
      'updatedAt': Timestamp.fromDate(now),
    });
    await batch.commit();

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

    if (_functionsInvoker != null) {
      final res = await _functionsInvoker('previewFamilyInvite', {
        'inviteCode': cleanCode,
      });
      final now = DateTime.now();
      final maxUses = ((res['maxUses'] as num?)?.toInt() ?? 1).clamp(1, 100);
      final usedCount = ((res['usedCount'] as num?)?.toInt() ?? 0).clamp(
        0,
        1000,
      );
      return FamilyPendingInviteEntity(
        inviteId: (res['inviteId'] as String?) ?? cleanCode,
        inviteCode: (res['inviteCode'] as String?) ?? cleanCode,
        familyId: (res['familyId'] as String?) ?? '',
        familyName: (res['familyName'] as String?) ?? 'Không gian chung',
        spaceType: _parseSpaceType(res['spaceType'] as String?),
        inviteKind: _parseInviteKind(
          res['inviteKind'] as String?,
          maxUses: maxUses,
        ),
        inviteeName: res['inviteeName'] as String?,
        invitedByUserId: (res['invitedByUserId'] as String?) ?? '',
        invitedByName: (res['invitedByName'] as String?) ?? 'Trưởng nhóm',
        createdAt: _readDateTime(res['createdAtMs'], now),
        expiresAt: _readDateTime(
          res['expiresAtMs'],
          now.add(const Duration(days: 7)),
        ),
        maxUses: maxUses,
        usedCount: usedCount,
        revoked: false,
        status: _parseInviteStatus(
          res['status'] as String?,
          revoked: false,
          usedCount: usedCount,
          maxUses: maxUses,
        ),
      );
    }

    // FIX-002: NEVER read `families/{familyId}` during invite preview (non-member lacks read access)!
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
    final revoked = (d['revoked'] as bool?) == true;
    final rawStatus = d['status'] as String?;
    if (revoked || rawStatus == 'revoked') {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Lời mời này đã bị quản trị viên thu hồi.',
      );
    }
    final now = DateTime.now();
    final expiresAt = _readDateTime(
      d['expiresAt'],
      now.add(const Duration(days: 7)),
    );
    if (!expiresAt.isAfter(now) || rawStatus == 'expired') {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message:
            'Mã mời này đã hết hạn sử dụng. Hãy nhờ trưởng nhóm cấp mã mới.',
      );
    }
    final maxUses = ((d['maxUses'] as num?)?.toInt() ?? 1).clamp(1, 100);
    final usedCount = ((d['usedCount'] as num?)?.toInt() ?? 0).clamp(0, 1000);
    if (usedCount >= maxUses || rawStatus == 'consumed') {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Mã mời này đã được sử dụng hết lượt.',
      );
    }

    final recipientHash = d['intendedRecipientHash'] as String?;
    return FamilyPendingInviteEntity(
      inviteId: (d['inviteId'] as String?) ?? cleanCode,
      inviteCode: (d['inviteCode'] as String?) ?? cleanCode,
      familyId: (d['familyId'] as String?) ?? '',
      familyName: (d['familyName'] as String?) ?? 'Không gian chung',
      spaceType: _parseSpaceType(d['spaceType'] as String?),
      inviteKind: _parseInviteKind(
        d['inviteKind'] as String?,
        intendedRecipientHash: recipientHash,
        maxUses: maxUses,
      ),
      inviteeName: d['inviteeName'] as String?,
      intendedRecipientHash: recipientHash,
      invitedByUserId:
          (d['invitedByUserId'] as String?) ?? (d['createdBy'] as String?) ?? '',
      invitedByName: (d['invitedByName'] as String?) ?? 'Trưởng nhóm',
      createdAt: _readDateTime(d['createdAt'], now),
      expiresAt: expiresAt,
      maxUses: maxUses,
      usedCount: usedCount,
      consumedBy: d['consumedBy'] as String?,
      consumedAt: d['consumedAt'] != null
          ? _readDateTime(d['consumedAt'], now)
          : null,
      revokedAt: d['revokedAt'] != null
          ? _readDateTime(d['revokedAt'], now)
          : null,
      revoked: false,
      status: InviteStatus.active,
    );
  }

  Future<void> revokeInviteCode({
    required String actorUserId,
    required String familyId,
    required String inviteCode,
  }) async {
    final cleanCode = FamilyInviteCodeExtractor.extractCode(inviteCode);
    if (_functionsInvoker != null) {
      await _functionsInvoker('revokeFamilyInvite', {
        'familyId': familyId,
        'inviteCode': cleanCode,
      });
      return;
    }

    final now = DateTime.now();
    final familyRef = _firestore.collection('families').doc(familyId);
    final famSnap = await familyRef.get();
    if (!famSnap.exists) {
      return;
    }
    final d = famSnap.data()!;
    final roles = Map<String, dynamic>.from((d['memberRoles'] as Map?) ?? {});
    final actorRole = roles[actorUserId]?.toString();
    if (actorRole != 'owner' && actorRole != 'admin') {
      throw const AppException(
        code: 'PERMISSION_DENIED',
        message: 'Chỉ trưởng nhóm hoặc quản trị mới có quyền thu hồi lời mời.',
      );
    }

    final invRef = _firestore.collection('family_invites').doc(cleanCode);
    final invSnap = await invRef.get();

    final batch = _firestore.batch();
    if (invSnap.exists) {
      batch.update(invRef, {
        'revoked': true,
        'revokedBy': actorUserId,
        'revokedAt': Timestamp.fromDate(now),
        'status': InviteStatus.revoked.name,
        'updatedAt': Timestamp.fromDate(now),
      });
    }
    batch.update(familyRef, {
      'pendingInvites.$cleanCode': FieldValue.delete(),
      'updatedAt': Timestamp.fromDate(now),
    });
    await batch.commit();
  }

  Future<List<String>> _resolveTargetedCandidateHashes({
    required String userId,
    String? userEmail,
    String? userPhone,
  }) async {
    final candidates = <String>[];
    if (_firebaseAuth != null) {
      final current = _firebaseAuth.currentUser;
      if (current == null || current.uid != userId) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message:
              'Phiên đăng nhập hiện tại không khớp để xác thực mã mời đích danh.',
        );
      }
      if (current.email != null && current.email!.trim().isNotEmpty) {
        candidates.add(current.email!);
      }
      if (current.phoneNumber != null &&
          current.phoneNumber!.trim().isNotEmpty) {
        candidates.add(current.phoneNumber!);
      }
      candidates.add(current.uid);
    } else if ((userEmail != null && userEmail.trim().isNotEmpty) ||
        (userPhone != null && userPhone.trim().isNotEmpty)) {
      if (userEmail != null && userEmail.trim().isNotEmpty) {
        candidates.add(userEmail);
      }
      if (userPhone != null && userPhone.trim().isNotEmpty) {
        candidates.add(userPhone);
      }
      candidates.add(userId);
    } else {
      // Fallback for DI setups without FirebaseAuth override: read caller's own user profile doc (never families!)
      final userSnap = await _firestore.collection('users').doc(userId).get();
      final u = userSnap.data() ?? const <String, dynamic>{};
      final email = u['email']?.toString();
      final phone = (u['phone'] ?? u['phoneNumber'])?.toString();
      if (email != null && email.trim().isNotEmpty) candidates.add(email);
      if (phone != null && phone.trim().isNotEmpty) candidates.add(phone);
      candidates.add(userId);
    }

    return candidates
        .map(FamilyInviteCodeExtractor.hashRecipientContact)
        .where((h) => h.isNotEmpty)
        .toList();
  }

  Future<FamilyEntity> joinFamilyByInvite({
    required String userId,
    required String userName,
    required String inviteCode,
    String? userEmail,
    String? userPhone,
  }) async {
    final cleanCode = FamilyInviteCodeExtractor.extractCode(inviteCode);
    if (cleanCode.length < 4) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Vui lòng nhập mã mời hợp lệ (ví dụ: FAM-8K2P9Q).',
      );
    }

    if (_functionsInvoker != null) {
      final res = await _functionsInvoker('joinFamilyByInvite', {
        'inviteCode': cleanCode,
        'userName': userName,
      });
      final famId = (res['familyId'] as String?)?.trim() ?? '';
      if (famId.isNotEmpty) {
        final famSnap = await _firestore
            .collection('families')
            .doc(famId)
            .get();
        if (famSnap.exists) {
          return _mapFamily(famSnap);
        }
      }
      return FamilyEntity(
        id: famId.isNotEmpty ? famId : 'fam_joined',
        name: (res['familyName'] as String?) ?? 'Không gian chung',
        spaceType: _parseSpaceType(res['spaceType'] as String?),
        createdBy: '',
        memberIds: [userId],
        members: [
          FamilyMemberInfo(
            userId: userId,
            fullName: userName,
            role: HouseholdRole.member,
          ),
        ],
        createdAt: DateTime.now(),
      );
    }

    // FIX-002: Spark / Direct Firestore mode NEVER calls `get(familyRef)` before join!
    final invRef = _firestore.collection('family_invites').doc(cleanCode);
    final invSnap = await invRef.get();
    if (!invSnap.exists) {
      throw const AppException(
        code: 'NOT_FOUND',
        message: 'Mã mời gia đình không tồn tại.',
      );
    }
    final invData = invSnap.data()!;
    final rawStatus = invData['status'] as String?;
    if ((invData['revoked'] as bool?) == true || rawStatus == 'revoked') {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Lời mời này đã bị thu hồi.',
      );
    }
    final now = DateTime.now();
    final expiresAt = _readDateTime(
      invData['expiresAt'],
      now.add(const Duration(days: 7)),
    );
    if (!expiresAt.isAfter(now) || rawStatus == 'expired') {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Mã mời đã hết hạn.',
      );
    }

    final maxUses = ((invData['maxUses'] as num?)?.toInt() ?? 1).clamp(1, 100);
    final usedCount = ((invData['usedCount'] as num?)?.toInt() ?? 0).clamp(
      0,
      1000,
    );
    if (usedCount >= maxUses || rawStatus == 'consumed') {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Mã mời này đã được sử dụng hết lượt.',
      );
    }

    final recipientHash = (invData['intendedRecipientHash'] as String?)?.trim();
    if (recipientHash != null && recipientHash.isNotEmpty) {
      final candidateHashes = await _resolveTargetedCandidateHashes(
        userId: userId,
        userEmail: userEmail,
        userPhone: userPhone,
      );
      if (!candidateHashes.contains(recipientHash)) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message:
              'Mã mời đích danh này chỉ dành cho đúng Email/SĐT được mời.',
        );
      }
    }

    final familyId = invData['familyId'] as String;
    final familyRef = _firestore.collection('families').doc(familyId);
    final userRef = _firestore.collection('users').doc(userId);
    final nextUsed = usedCount + 1;
    final exhausted = nextUsed >= maxUses;

    final batch = _firestore.batch();
    batch.update(invRef, {
      'usedCount': FieldValue.increment(1),
      'consumedBy': userId,
      'consumedAt': FieldValue.serverTimestamp(),
      'status': exhausted
          ? InviteStatus.consumed.name
          : InviteStatus.active.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(familyRef, {
      'memberIds': FieldValue.arrayUnion([userId]),
      'memberRoles.$userId': 'member',
      'memberNames.$userId': userName,
      'lastJoinedInviteCode': cleanCode,
      'updatedAt': FieldValue.serverTimestamp(),
      if (exhausted) 'pendingInvites.$cleanCode': FieldValue.delete(),
    });
    batch.set(userRef, {
      'id': userId,
      'familyId': familyId,
      'activeFamilyId': familyId,
      'familyIds': FieldValue.arrayUnion([familyId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // Idempotent guard: if caller is already a member, reading familyRef now succeeds without burning an invite slot
        try {
          final existingSnap = await familyRef.get();
          final existingMembers =
              (existingSnap.data()?['memberIds'] as List<dynamic>? ??
                      const <dynamic>[])
                  .map((m) => m.toString());
          if (existingSnap.exists && existingMembers.contains(userId)) {
            return _mapFamily(existingSnap);
          }
        } catch (_) {}
      }
      rethrow;
    }

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
        'lastRemovedMemberId': targetUserId,
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

  Future<void> deleteShoppingItem({
    required String familyId,
    required String itemId,
  }) async {
    await _firestore
        .collection('families')
        .doc(familyId)
        .collection('shopping_items')
        .doc(itemId)
        .delete();
  }

  Future<int> clearPurchasedShoppingItems({required String familyId}) async {
    final snap = await _firestore
        .collection('families')
        .doc(familyId)
        .collection('shopping_items')
        .where('isPurchased', isEqualTo: true)
        .get();
    if (snap.docs.isEmpty) return 0;
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return snap.docs.length;
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
      'status': 'open',
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
    bool isPartial = false,
    String? settlementRequestId,
    String? note,
  }) async {
    if (fromUserId == toUserId) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Người trả nợ và người nhận không được trùng nhau.',
      );
    }
    if (amountMinor <= 0) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Số tiền tất toán phải lớn hơn 0.',
      );
    }
    final now = DateTime.now();
    // F04 / SEC-04: Deterministic idempotency key per (family, payer, payee, amount, paymentCode, partial suffix)
    final safeCode = paymentCode
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9_-]'), '');
    final id = settlementRequestId != null && settlementRequestId.isNotEmpty
        ? 'stl_req_$settlementRequestId'
        : (safeCode.isNotEmpty && safeCode != 'LIFEOS'
              ? 'stl_${fromUserId}_${toUserId}_${amountMinor}_$safeCode'
              : _uuid.v4());
    final ref = _firestore
        .collection('families')
        .doc(familyId)
        .collection('settlements')
        .doc(id);

    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) {
        return;
      }
      tx.set(ref, {
        'id': id,
        'familyId': familyId,
        'fromUserId': fromUserId,
        'fromUserName': fromUserName,
        'toUserId': toUserId,
        'toUserName': toUserName,
        'amountMinor': amountMinor,
        'currencyCode': 'VND',
        'paymentCode': paymentCode,
        'status': 'confirmed',
        'isPartial': isPartial,
        if (settlementRequestId != null && settlementRequestId.isNotEmpty)
          'settlementRequestId': settlementRequestId,
        if (note != null && note.isNotEmpty) 'note': note,
        'createdAt': Timestamp.fromDate(now),
      });
    });

    final snap = await ref.get();
    return _mapSettlement(familyId, snap);
  }

  Future<SettlementRequestEntity> requestDebtSettlement({
    required String familyId,
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String toUserName,
    required int amountMinor,
    required String paymentCode,
    bool isPartial = false,
    String? note,
  }) async {
    if (fromUserId == toUserId) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Người trả nợ và người nhận không được trùng nhau.',
      );
    }
    if (amountMinor <= 0) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Số tiền yêu cầu tất toán phải lớn hơn 0.',
      );
    }
    final id = 'sreq_${_uuid.v4()}';
    final now = DateTime.now();
    final ref = _firestore
        .collection('families')
        .doc(familyId)
        .collection('settlement_requests')
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
      'status': 'pending',
      'isPartial': isPartial,
      if (note != null && note.isNotEmpty) 'note': note,
      'createdAt': Timestamp.fromDate(now),
    });

    final snap = await ref.get();
    return _mapSettlementRequest(familyId, snap);
  }

  Future<DebtSettlementEntity?> confirmSettlementRequest({
    required String familyId,
    required String requestId,
    required String actorUserId,
    required bool approve,
    String? disputeReason,
  }) async {
    final reqRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('settlement_requests')
        .doc(requestId);
    final reqSnap = await reqRef.get();
    if (!reqSnap.exists) {
      throw const AppException(
        code: 'NOT_FOUND',
        message: 'Không tìm thấy yêu cầu tất toán.',
      );
    }
    final req = _mapSettlementRequest(familyId, reqSnap);
    if (req.status != SettlementRequestStatus.pending) {
      throw const AppException(
        code: 'CONFLICT_FAILURE',
        message: 'Yêu cầu tất toán này đã được xử lý trước đó.',
      );
    }
    if (actorUserId != req.toUserId) {
      throw const AppException(
        code: 'PERMISSION_DENIED',
        message: 'Chỉ người nhận tiền mới có quyền xác nhận hoặc từ chối.',
      );
    }

    final now = DateTime.now();
    if (!approve) {
      await reqRef.update({
        'status': 'rejected',
        'confirmedBy': actorUserId,
        'confirmedAt': Timestamp.fromDate(now),
        if (disputeReason != null && disputeReason.isNotEmpty)
          'disputeReason': disputeReason,
      });
      return null;
    }

    final stlId = 'stl_req_$requestId';
    final stlRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('settlements')
        .doc(stlId);

    final batch = _firestore.batch();
    batch.update(reqRef, {
      'status': 'confirmed',
      'confirmedBy': actorUserId,
      'confirmedAt': Timestamp.fromDate(now),
    });
    batch.set(stlRef, {
      'id': stlId,
      'familyId': familyId,
      'fromUserId': req.fromUserId,
      'fromUserName': req.fromUserName,
      'toUserId': req.toUserId,
      'toUserName': req.toUserName,
      'amountMinor': req.amountMinor,
      'currencyCode': 'VND',
      'paymentCode': req.paymentCode,
      'status': 'confirmed',
      'isPartial': req.isPartial,
      'settlementRequestId': requestId,
      if (req.note != null && req.note!.isNotEmpty) 'note': req.note,
      'createdAt': Timestamp.fromDate(now),
    });
    await batch.commit();

    final stlSnap = await stlRef.get();
    return _mapSettlement(familyId, stlSnap);
  }

  Future<DebtSettlementEntity> reverseDebtSettlement({
    required String familyId,
    required String settlementId,
    required String actorUserId,
    String? reason,
  }) async {
    final stlCol = _firestore
        .collection('families')
        .doc(familyId)
        .collection('settlements');
    final origRef = stlCol.doc(settlementId);
    final revId = 'rev_$settlementId';
    final revRef = stlCol.doc(revId);

    await _firestore.runTransaction((tx) async {
      final origSnap = await tx.get(origRef);
      if (!origSnap.exists) {
        throw const AppException(
          code: 'NOT_FOUND',
          message: 'Không tìm thấy khoản tất toán gốc để hoàn tác.',
        );
      }
      final orig = _mapSettlement(familyId, origSnap);
      if (orig.isReversal) {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message: 'Không thể hoàn tác trên chính bút toán đối ứng.',
        );
      }
      if (orig.fromUserId == 'bank_transfer') {
        throw const AppException(
          code: 'VALIDATION_FAILURE',
          message:
              'Không thể hoàn tác tự động giao dịch ngân hàng không gắn thành viên.',
        );
      }
      if (actorUserId != orig.fromUserId && actorUserId != orig.toUserId) {
        throw const AppException(
          code: 'PERMISSION_DENIED',
          message:
              'Chỉ người trả hoặc người nhận của khoản tất toán mới được hoàn tác.',
        );
      }

      final revSnap = await tx.get(revRef);
      if (revSnap.exists) {
        throw const AppException(
          code: 'CONFLICT_FAILURE',
          message: 'Khoản tất toán này đã được hoàn tác trước đó.',
        );
      }

      final now = DateTime.now();
      final cleanReason = reason?.trim();
      // Append-only contra entry (preserves `allow update, delete: if false;` on `settlements`)
      tx.set(revRef, {
        'id': revId,
        'familyId': familyId,
        'fromUserId': orig.toUserId,
        'fromUserName': orig.toUserName,
        'toUserId': orig.fromUserId,
        'toUserName': orig.fromUserName,
        'amountMinor': orig.amountMinor,
        'currencyCode': 'VND',
        'paymentCode': 'REV_${orig.paymentCode}',
        'status': 'confirmed',
        'reversalOfId': settlementId,
        'isPartial': orig.isPartial,
        'note': (cleanReason != null && cleanReason.isNotEmpty)
            ? cleanReason
            : 'Hoàn tác tất toán (${orig.paymentCode})',
        'createdAt': Timestamp.fromDate(now),
      });
    });

    final revSnap = await revRef.get();
    return _mapSettlement(familyId, revSnap);
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
  Stream<Result<List<SettlementRequestEntity>>> watchSettlementRequests(
    String familyId,
  ) {
    return _remoteDataSource
        .watchSettlementRequests(familyId)
        .map<Result<List<SettlementRequestEntity>>>((items) => Success(items))
        .transform(
          StreamTransformer.fromHandlers(
            handleError:
                (
                  Object e,
                  StackTrace _,
                  EventSink<Result<List<SettlementRequestEntity>>> sink,
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
    InviteKind? inviteKind,
    int maxUses = 1,
    int ttlDays = 7,
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
        inviteKind: inviteKind,
        maxUses: maxUses,
        ttlDays: ttlDays,
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
    String? userEmail,
    String? userPhone,
  }) async {
    try {
      final f = await _remoteDataSource.joinFamilyByInvite(
        userId: userId,
        userName: userName,
        inviteCode: inviteCode,
        userEmail: userEmail,
        userPhone: userPhone,
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
  Future<Result<void>> deleteShoppingItem({
    required String familyId,
    required String itemId,
  }) async {
    try {
      await _remoteDataSource.deleteShoppingItem(
        familyId: familyId,
        itemId: itemId,
      );
      return const Success(null);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<int>> clearPurchasedShoppingItems({
    required String familyId,
  }) async {
    try {
      final count = await _remoteDataSource.clearPurchasedShoppingItems(
        familyId: familyId,
      );
      return Success(count);
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
    bool isPartial = false,
    String? settlementRequestId,
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
        isPartial: isPartial,
        settlementRequestId: settlementRequestId,
        note: note,
      );
      return Success(settlement);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<SettlementRequestEntity>> requestDebtSettlement({
    required String familyId,
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String toUserName,
    required int amountMinor,
    required String paymentCode,
    bool isPartial = false,
    String? note,
  }) async {
    try {
      final req = await _remoteDataSource.requestDebtSettlement(
        familyId: familyId,
        fromUserId: fromUserId,
        fromUserName: fromUserName,
        toUserId: toUserId,
        toUserName: toUserName,
        amountMinor: amountMinor,
        paymentCode: paymentCode,
        isPartial: isPartial,
        note: note,
      );
      return Success(req);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<DebtSettlementEntity?>> confirmSettlementRequest({
    required String familyId,
    required String requestId,
    required String actorUserId,
    required bool approve,
    String? disputeReason,
  }) async {
    try {
      final settlement = await _remoteDataSource.confirmSettlementRequest(
        familyId: familyId,
        requestId: requestId,
        actorUserId: actorUserId,
        approve: approve,
        disputeReason: disputeReason,
      );
      return Success(settlement);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<DebtSettlementEntity>> reverseDebtSettlement({
    required String familyId,
    required String settlementId,
    required String actorUserId,
    String? reason,
  }) async {
    try {
      final reversal = await _remoteDataSource.reverseDebtSettlement(
        familyId: familyId,
        settlementId: settlementId,
        actorUserId: actorUserId,
        reason: reason,
      );
      return Success(reversal);
    } catch (e) {
      return Err(ErrorMapper.map(e));
    }
  }
}
