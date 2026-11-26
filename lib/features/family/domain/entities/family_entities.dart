import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/security/bank_notification_parser.dart';

enum HouseholdRole {
  owner,
  admin,
  member;

  String get displayLabel => switch (this) {
    HouseholdRole.owner => 'Trưởng nhóm',
    HouseholdRole.admin => 'Quản trị',
    HouseholdRole.member => 'Thành viên',
  };
}

/// Three real-world collaboration operating modes researched for Life OS:
/// - `family`: Hộ Gia đình / Tổ ấm (vợ chồng, đa thế hệ — quỹ chung + việc nhà + chi phí tổ ấm)
/// - `roommates`: Ở ghép / Nhà trọ (bạn cùng phòng — chia tiền trọ, điện nước, ăn chung, trực nhật)
/// - `group`: Hội nhóm / Chuyến đi (nhóm bạn ăn uống, du lịch, câu lạc bộ — chia hóa đơn & tất toán nhanh)
enum CollaborationSpaceType {
  family,
  roommates,
  group;

  String get displayLabel => switch (this) {
    CollaborationSpaceType.family => 'Hộ Gia đình / Tổ ấm',
    CollaborationSpaceType.roommates => 'Ở ghép / Nhà trọ',
    CollaborationSpaceType.group => 'Hội nhóm / Chuyến đi',
  };

  String get subtitleHint => switch (this) {
    CollaborationSpaceType.family => 'Quỹ chung, việc nhà & lịch gia đình.',
    CollaborationSpaceType.roommates =>
      'Chia tiền phòng, điện nước & ăn chung.',
    CollaborationSpaceType.group => 'Chia hóa đơn ăn uống & chuyến đi.',
  };
}

enum InviteKind {
  oneTime,
  targeted,
  reusableGroup;

  String get displayLabel => switch (this) {
    InviteKind.oneTime => 'Dùng 1 lần',
    InviteKind.targeted => 'Đích danh',
    InviteKind.reusableGroup => 'Mã nhóm nhiều lượt',
  };
}

enum InviteStatus {
  active,
  consumed,
  revoked,
  expired;

  String get displayLabel => switch (this) {
    InviteStatus.active => 'Đang chờ',
    InviteStatus.consumed => 'Đã dùng hết',
    InviteStatus.revoked => 'Đã thu hồi',
    InviteStatus.expired => 'Đã hết hạn',
  };
}

enum SettlementRequestStatus {
  pending,
  confirmed,
  rejected;

  String get displayLabel => switch (this) {
    SettlementRequestStatus.pending => 'Chờ xác nhận',
    SettlementRequestStatus.confirmed => 'Đã xác nhận',
    SettlementRequestStatus.rejected => 'Đã từ chối',
  };
}

enum SplitMethod {
  equal,
  percentage,
  shares,
  exact;

  String get displayLabel => switch (this) {
    SplitMethod.equal => 'Chia đều',
    SplitMethod.percentage => 'Chia theo %',
    SplitMethod.shares => 'Chia theo phần',
    SplitMethod.exact => 'Nhập số tiền từng người',
  };
}

enum SharedExpenseTopic {
  dining,
  housework,
  utilities,
  housing,
  shopping,
  travel,
  other;

  String get displayLabel => switch (this) {
    SharedExpenseTopic.dining => 'Ăn uống & Tụ tập',
    SharedExpenseTopic.housework => 'Việc nhà & Vật tư sinh hoạt',
    SharedExpenseTopic.utilities => 'Điện / Nước / Internet',
    SharedExpenseTopic.housing => 'Tiền nhà / Phí chung cư',
    SharedExpenseTopic.shopping => 'Đi chợ & Mua sắm chung',
    SharedExpenseTopic.travel => 'Du lịch & Hội nhóm',
    SharedExpenseTopic.other => 'Khoản chung khác',
  };
}

class FamilyMemberInfo extends Equatable {
  final String userId;
  final String fullName;
  final HouseholdRole role;

  const FamilyMemberInfo({
    required this.userId,
    required this.fullName,
    required this.role,
  });

  @override
  List<Object?> get props => [userId, fullName, role];
}

/// Represents a pending or previewed invitation to join a Family / Roommates / Group space.
class FamilyPendingInviteEntity extends Equatable {
  final String inviteId;
  final String inviteCode;
  final String familyId;
  final String familyName;
  final CollaborationSpaceType spaceType;
  final InviteKind inviteKind;
  final String? inviteeName;
  final String? inviteeContact;
  final String? inviteeUid;
  final String? inviteeEmail;
  final String? intendedRecipientHash;
  final String invitedByUserId;
  final String invitedByName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int maxUses;
  final int usedCount;
  final String? consumedBy;
  final DateTime? consumedAt;
  final DateTime? revokedAt;
  final bool revoked;
  final InviteStatus status;

  const FamilyPendingInviteEntity({
    String? inviteId,
    required this.inviteCode,
    required this.familyId,
    required this.familyName,
    this.spaceType = CollaborationSpaceType.family,
    InviteKind? inviteKind,
    this.inviteeName,
    this.inviteeContact,
    this.inviteeUid,
    this.inviteeEmail,
    this.intendedRecipientHash,
    required this.invitedByUserId,
    required this.invitedByName,
    required this.createdAt,
    required this.expiresAt,
    this.maxUses = 1,
    this.usedCount = 0,
    this.consumedBy,
    this.consumedAt,
    this.revokedAt,
    this.revoked = false,
    InviteStatus? status,
  }) : inviteId = inviteId ?? inviteCode,
       inviteKind =
           inviteKind ??
           ((intendedRecipientHash != null && intendedRecipientHash != '')
               ? InviteKind.targeted
               : (maxUses > 1 ? InviteKind.reusableGroup : InviteKind.oneTime)),
       status =
           status ??
           (revoked
               ? InviteStatus.revoked
               : (usedCount >= maxUses
                     ? InviteStatus.consumed
                     : InviteStatus.active));

  String get createdBy => invitedByUserId;

  bool get isTargetedInvite =>
      inviteeName != null && inviteeName!.trim().isNotEmpty;

  bool get isTargeted =>
      inviteKind == InviteKind.targeted ||
      (inviteeUid != null && inviteeUid!.trim().isNotEmpty) ||
      (inviteeEmail != null && inviteeEmail!.trim().isNotEmpty) ||
      (intendedRecipientHash != null &&
          intendedRecipientHash!.trim().isNotEmpty) ||
      isTargetedInvite;

  bool get hasRemainingUses => usedCount < maxUses;

  int get remainingUses =>
      (maxUses - usedCount) < 0 ? 0 : (maxUses - usedCount);

  String get displayInviteeTitle {
    if (isTargetedInvite) return inviteeName!.trim();
    if (inviteKind == InviteKind.reusableGroup) {
      return 'Mã mời nhóm ($usedCount/$maxUses lượt)';
    }
    if (inviteKind == InviteKind.targeted) {
      return 'Lời mời đích danh';
    }
    return 'Mã mời chung cho nhóm';
  }

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  InviteStatus effectiveStatusAt(DateTime now) {
    if (revoked || status == InviteStatus.revoked) return InviteStatus.revoked;
    if (usedCount >= maxUses || status == InviteStatus.consumed) {
      return InviteStatus.consumed;
    }
    if (isExpiredAt(now) || status == InviteStatus.expired) {
      return InviteStatus.expired;
    }
    return InviteStatus.active;
  }

  bool isActiveAt(DateTime now) =>
      effectiveStatusAt(now) == InviteStatus.active;

  int remainingDaysFrom(DateTime now) {
    final diff = expiresAt.difference(now);
    if (diff.isNegative) {
      return 0;
    }
    return (diff.inHours / 24.0).ceil().clamp(1, 30);
  }

  @override
  List<Object?> get props => [
    inviteId,
    inviteCode,
    familyId,
    familyName,
    spaceType,
    inviteKind,
    inviteeName,
    inviteeContact,
    inviteeUid,
    inviteeEmail,
    intendedRecipientHash,
    invitedByUserId,
    invitedByName,
    createdAt,
    expiresAt,
    maxUses,
    usedCount,
    consumedBy,
    consumedAt,
    revokedAt,
    revoked,
    status,
  ];
}

/// Pure Domain helper extracting a clean `FAM-XXXXXX` code even if the user pastes
/// a full Zalo / Messenger / SMS invitation paragraph, plus contact normalization & SHA-256 hashing.
abstract final class FamilyInviteCodeExtractor {
  static final RegExp _famPattern = RegExp(r'FAM-[A-Z0-9]{4,12}');

  static String extractCode(String rawInput) {
    final upper = rawInput.trim().toUpperCase();
    final match = _famPattern.firstMatch(upper);
    if (match != null) {
      return match.group(0)!;
    }
    return upper.replaceAll(RegExp(r'\s+'), '');
  }

  /// Normalizes emails (lowercase trim) and Vietnamese phone numbers (`+84...` / `84...` -> `0...`).
  static String normalizeRecipientContact(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.contains('@')) {
      return trimmed.toLowerCase();
    }
    final compact = trimmed.replaceAll(RegExp(r'[\s\-\.\(\)]'), '');
    if (RegExp(r'^\+84\d{8,11}$').hasMatch(compact)) {
      return '0${compact.substring(3)}';
    }
    if (RegExp(r'^84\d{8,11}$').hasMatch(compact)) {
      return '0${compact.substring(2)}';
    }
    return compact.toLowerCase();
  }

  /// Computes deterministic SHA-256 hex digest of normalized recipient contact/identifier.
  static String hashRecipientContact(String raw) {
    final normalized = normalizeRecipientContact(raw);
    if (normalized.isEmpty) return '';
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  /// Returns true if raw text appears to contain raw email or phone contact PII.
  static bool looksLikeContactPii(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return false;
    if (clean.contains('@')) return true;
    return RegExp(r'\d').allMatches(clean).length >= 6;
  }

  /// Strips email/phone PII before storing an optional display label on public invite documents.
  static String? sanitizePublicInviteeName(String? rawName) {
    if (rawName == null) return null;
    final clean = rawName.trim();
    if (clean.isEmpty || looksLikeContactPii(clean)) return null;
    return clean;
  }
}

class FamilyEntity extends Equatable {
  final String id;
  final String name;
  final CollaborationSpaceType spaceType;
  final String createdBy;
  final List<String> memberIds;
  final List<FamilyMemberInfo> members;
  final List<FamilyPendingInviteEntity> pendingInvites;
  final DateTime createdAt;

  const FamilyEntity({
    required this.id,
    required this.name,
    this.spaceType = CollaborationSpaceType.family,
    required this.createdBy,
    required this.memberIds,
    required this.members,
    this.pendingInvites = const [],
    required this.createdAt,
  });

  HouseholdRole roleOf(String userId) {
    final m = members.where((e) => e.userId == userId).firstOrNull;
    return m?.role ?? HouseholdRole.member;
  }

  bool isManager(String userId) {
    final r = roleOf(userId);
    return r == HouseholdRole.owner || r == HouseholdRole.admin;
  }

  bool isOwnerUser(String userId) => roleOf(userId) == HouseholdRole.owner;

  List<FamilyPendingInviteEntity> activePendingInvites([DateTime? now]) {
    final refNow = now ?? DateTime.now();
    final active = pendingInvites.where((i) => i.isActiveAt(refNow)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return active;
  }

  @override
  List<Object?> get props => [
    id,
    name,
    spaceType,
    createdBy,
    memberIds,
    members,
    pendingInvites,
    createdAt,
  ];
}

class ShoppingItemEntity extends Equatable {
  final String id;
  final String familyId;
  final String title;
  final String quantityLabel;
  final int estimatedPriceMinor;
  final bool isPurchased;
  final String addedByName;

  const ShoppingItemEntity({
    required this.id,
    required this.familyId,
    required this.title,
    required this.quantityLabel,
    required this.estimatedPriceMinor,
    required this.isPurchased,
    required this.addedByName,
  });

  @override
  List<Object?> get props => [
    id,
    familyId,
    title,
    quantityLabel,
    estimatedPriceMinor,
    isPurchased,
    addedByName,
  ];
}

enum SharedBillReconciliationStatus {
  reconciled,
  needsReconciliation;

  String get displayLabel => switch (this) {
    SharedBillReconciliationStatus.reconciled => 'Đã đối soát',
    SharedBillReconciliationStatus.needsReconciliation => 'Cần đối soát',
  };
}

/// Represents a shared bill paid upfront by one member and split across participants
/// (eating out, housework supplies/cleaning, utilities, rent, trip expenses).
class SharedBillSplitEntity extends Equatable {
  static const int maxSplitParticipants = 20;

  final String id;
  final String familyId;
  final String title;
  final SharedExpenseTopic topic;
  final String paidByUserId;
  final String paidByName;
  final int totalAmountMinor;
  final SplitMethod splitMethod;
  final Map<String, int>
  sharesByUserId; // Exact VND integer owed by each userId
  final Map<String, String> participantNames;
  final String? choreOrTaskNote;
  final DateTime createdAt;

  const SharedBillSplitEntity({
    required this.id,
    required this.familyId,
    required this.title,
    required this.topic,
    required this.paidByUserId,
    required this.paidByName,
    required this.totalAmountMinor,
    required this.splitMethod,
    required this.sharesByUserId,
    required this.participantNames,
    this.choreOrTaskNote,
    required this.createdAt,
  });

  int get sharesSumMinor =>
      sharesByUserId.values.fold<int>(0, (sum, value) => sum + value);

  bool get hasInvalidShares =>
      totalAmountMinor <= 0 ||
      paidByUserId.trim().isEmpty ||
      sharesByUserId.isEmpty ||
      sharesByUserId.length > maxSplitParticipants ||
      sharesByUserId.entries.any(
        (entry) => entry.key.trim().isEmpty || entry.value < 0,
      ) ||
      sharesByUserId.values.every((value) => value == 0);

  bool get isSharesBalanced =>
      !hasInvalidShares && sharesSumMinor == totalAmountMinor;

  SharedBillReconciliationStatus get reconciliationStatus => isSharesBalanced
      ? SharedBillReconciliationStatus.reconciled
      : SharedBillReconciliationStatus.needsReconciliation;

  bool get needsReconciliation =>
      reconciliationStatus ==
      SharedBillReconciliationStatus.needsReconciliation;

  int get discrepancyMinor => totalAmountMinor - sharesSumMinor;

  @override
  List<Object?> get props => [
    id,
    familyId,
    title,
    topic,
    paidByUserId,
    paidByName,
    totalAmountMinor,
    splitMethod,
    sharesByUserId,
    participantNames,
    choreOrTaskNote,
    createdAt,
  ];
}

/// Two-step debt settlement consent request: Debtor initiates `'pending'`, Creditor confirms/rejects.
class SettlementRequestEntity extends Equatable {
  final String id;
  final String familyId;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final int amountMinor;
  final String paymentCode;
  final String? note;
  final SettlementRequestStatus status;
  final bool isPartial;
  final DateTime createdAt;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final String? disputeReason;
  final String? settlementId;

  const SettlementRequestEntity({
    required this.id,
    required this.familyId,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.amountMinor,
    required this.paymentCode,
    this.note,
    this.status = SettlementRequestStatus.pending,
    this.isPartial = false,
    required this.createdAt,
    this.confirmedBy,
    this.confirmedAt,
    this.disputeReason,
    this.settlementId,
  });

  @override
  List<Object?> get props => [
    id,
    familyId,
    fromUserId,
    fromUserName,
    toUserId,
    toUserName,
    amountMinor,
    paymentCode,
    note,
    status,
    isPartial,
    createdAt,
    confirmedBy,
    confirmedAt,
    disputeReason,
    settlementId,
  ];
}

/// Records an actual debt settlement transfer between two group/family members
/// (or an append-only contra reversal entry when `reversalOfId != null`)
/// with a VietQR/SePay compatible transfer reference code (`SEVQR LIFEOS ...`).
class DebtSettlementEntity extends Equatable {
  final String id;
  final String familyId;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final int amountMinor;
  final String paymentCode;
  final String? note;
  final String status;
  final String? reversalOfId;
  final String? reversedById;
  final String? settlementRequestId;
  final bool isPartial;
  final DateTime createdAt;

  const DebtSettlementEntity({
    required this.id,
    required this.familyId,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.amountMinor,
    required this.paymentCode,
    this.note,
    this.status = 'confirmed',
    this.reversalOfId,
    this.reversedById,
    this.settlementRequestId,
    this.isPartial = false,
    required this.createdAt,
  });

  bool get isReversal => reversalOfId != null && reversalOfId!.isNotEmpty;

  @override
  List<Object?> get props => [
    id,
    familyId,
    fromUserId,
    fromUserName,
    toUserId,
    toUserName,
    amountMinor,
    paymentCode,
    note,
    status,
    reversalOfId,
    reversedById,
    settlementRequestId,
    isPartial,
    createdAt,
  ];
}

class MemberNetBalance extends Equatable {
  final String userId;
  final String fullName;
  final int totalPaidMinor;
  final int totalOwedMinor;
  final int settlementsSentMinor;
  final int settlementsReceivedMinor;

  /// Positive (`> 0`) => Member paid more than owed (receivable / cần nhận lại).
  /// Negative (`< 0`) => Member owes the group/family (payable / cần trả thêm).
  final int netBalanceMinor;

  const MemberNetBalance({
    required this.userId,
    required this.fullName,
    required this.totalPaidMinor,
    required this.totalOwedMinor,
    required this.settlementsSentMinor,
    required this.settlementsReceivedMinor,
    required this.netBalanceMinor,
  });

  @override
  List<Object?> get props => [
    userId,
    fullName,
    totalPaidMinor,
    totalOwedMinor,
    settlementsSentMinor,
    settlementsReceivedMinor,
    netBalanceMinor,
  ];
}

class SimplifiedDebtTransfer extends Equatable {
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final int amountMinor;
  final String sePayTransferCode;

  const SimplifiedDebtTransfer({
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.amountMinor,
    required this.sePayTransferCode,
  });

  @override
  List<Object?> get props => [
    fromUserId,
    fromUserName,
    toUserId,
    toUserName,
    amountMinor,
    sePayTransferCode,
  ];
}

class SharedLedgerSummary extends Equatable {
  final int totalSharedSpendMinor;
  final Map<SharedExpenseTopic, int> spendByTopic;
  final List<MemberNetBalance> memberBalances;
  final List<SimplifiedDebtTransfer> suggestedTransfers;
  final bool isExactOptimal;
  final int unverifiedSharedSpendMinor;
  final int inconsistentBillCount;
  final List<String> inconsistentBillIds;

  const SharedLedgerSummary({
    this.totalSharedSpendMinor = 0,
    this.spendByTopic = const {},
    this.memberBalances = const [],
    this.suggestedTransfers = const [],
    this.isExactOptimal = true,
    this.unverifiedSharedSpendMinor = 0,
    this.inconsistentBillCount = 0,
    this.inconsistentBillIds = const [],
  });

  bool get needsReconciliation => inconsistentBillCount > 0;

  @override
  List<Object?> get props => [
    totalSharedSpendMinor,
    spendByTopic,
    memberBalances,
    suggestedTransfers,
    isExactOptimal,
    unverifiedSharedSpendMinor,
    inconsistentBillCount,
    inconsistentBillIds,
  ];
}

/// Pure Domain exact-VND Split Bill Calculator (Equal, Percentage, Shares, Exact).
/// Guarantees `sum(shares.values) == totalAmountMinor` with zero rounding drift.
abstract final class SplitBillCalculator {
  static Map<String, int> computeEqualSplit({
    required int totalAmountMinor,
    required List<String> participantIds,
    required String payerUserId,
  }) {
    final uniqueIds = participantIds.toSet().toList();
    if (totalAmountMinor <= 0 || uniqueIds.isEmpty) {
      return const {};
    }
    // Order deterministically: payer first (absorbs 1 VND remainder transparently), then sorted IDs
    uniqueIds.sort((a, b) {
      if (a == payerUserId && b != payerUserId) return -1;
      if (b == payerUserId && a != payerUserId) return 1;
      return a.compareTo(b);
    });

    final count = uniqueIds.length;
    final baseShare = totalAmountMinor ~/ count;
    final remainder = totalAmountMinor % count;
    final result = <String, int>{};
    for (var i = 0; i < count; i++) {
      result[uniqueIds[i]] = baseShare + (i < remainder ? 1 : 0);
    }
    return Map.unmodifiable(result);
  }

  /// Computes exact integer VND shares from relative weights (e.g. percentages summing to 100
  /// or share units like `{u1: 3, u2: 2, u3: 1}`) via Hamilton's Largest Remainder Method.
  static Map<String, int> computeWeightedSplit({
    required int totalAmountMinor,
    required Map<String, int> weightsByUserId,
  }) {
    final activeEntries =
        weightsByUserId.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    if (totalAmountMinor <= 0 || activeEntries.isEmpty) {
      return const {};
    }

    final totalWeight = activeEntries.fold<int>(0, (sum, e) => sum + e.value);
    if (totalWeight <= 0) return const {};

    final floors = <String, int>{};
    final remainders = <({String userId, int rem})>[];
    var floorSum = 0;

    for (final entry in activeEntries) {
      final numerator = totalAmountMinor * entry.value;
      final q = numerator ~/ totalWeight;
      floors[entry.key] = q;
      floorSum += q;
      remainders.add((userId: entry.key, rem: numerator % totalWeight));
    }

    final leftover = totalAmountMinor - floorSum;
    remainders.sort((a, b) {
      final cmp = b.rem.compareTo(a.rem);
      return cmp != 0 ? cmp : a.userId.compareTo(b.userId);
    });
    for (var i = 0; i < leftover; i++) {
      final uid = remainders[i].userId;
      floors[uid] = (floors[uid] ?? 0) + 1;
    }

    return Map.unmodifiable(floors);
  }
}

/// Pure Domain Hybrid Minimum-Transfer Graph Debt Simplifier (`FIX-006`):
/// - Eliminates ghost `'bank_transfer'` nodes unless uniquely resolved via deterministic payment code.
/// - Enforces zero-sum invariant (`sum(netBalances) == 0`).
/// - For M <= 12 non-zero balances: uses Exact Zero-Sum Subset Decomposition DP (`isExactOptimal: true`).
/// - For M > 12 (or time-budget fallback): uses bounded deterministic Greedy (`isExactOptimal: false`).
/// - Guarantees `amountMinor > 0`, `fromUserId != toUserId`, exact debt conservation & deterministic sort.
abstract final class DebtSimplifier {
  static const int exactDpMaxMembers = 12;
  static const int _exactDpBudgetMs = 50;

  static SharedLedgerSummary summarize({
    required String familyId,
    required List<FamilyMemberInfo> members,
    required List<SharedBillSplitEntity> bills,
    required List<DebtSettlementEntity> settlements,
  }) {
    final realMemberIds = members.map((m) => m.userId).toSet();
    final namesById = <String, String>{
      for (final m in members) m.userId: m.fullName,
    };
    final paidMap = <String, int>{for (final m in members) m.userId: 0};
    final owedMap = <String, int>{for (final m in members) m.userId: 0};
    final sentMap = <String, int>{for (final m in members) m.userId: 0};
    final receivedMap = <String, int>{for (final m in members) m.userId: 0};
    final topicSpend = <SharedExpenseTopic, int>{};
    var totalSpend = 0;
    var unverifiedSpend = 0;
    final inconsistentIds = <String>[];

    for (final bill in bills) {
      if (!bill.isSharesBalanced) {
        inconsistentIds.add(bill.id);
        if (bill.totalAmountMinor > 0) {
          unverifiedSpend += bill.totalAmountMinor;
        }
        continue;
      }

      final payerId = bill.paidByUserId;
      if (payerId.trim().isEmpty ||
          (payerId == 'bank_transfer' && !realMemberIds.contains(payerId))) {
        inconsistentIds.add(bill.id);
        unverifiedSpend += bill.totalAmountMinor;
        continue;
      }

      final positiveShares = <MapEntry<String, int>>[];
      for (final entry in bill.sharesByUserId.entries) {
        if (entry.value > 0 && entry.key.trim().isNotEmpty) {
          positiveShares.add(entry);
        }
      }

      // Consistent reconciled basis: sum(shares) == totalAmountMinor strictly holds
      totalSpend += bill.totalAmountMinor;
      topicSpend[bill.topic] =
          (topicSpend[bill.topic] ?? 0) + bill.totalAmountMinor;

      namesById.putIfAbsent(payerId, () => bill.paidByName);
      paidMap[payerId] = (paidMap[payerId] ?? 0) + bill.totalAmountMinor;
      owedMap.putIfAbsent(payerId, () => 0);

      for (final entry in positiveShares) {
        final uid = entry.key;
        final share = entry.value;
        namesById.putIfAbsent(
          uid,
          () => bill.participantNames[uid] ?? 'Thành viên',
        );
        owedMap[uid] = (owedMap[uid] ?? 0) + share;
        paidMap.putIfAbsent(uid, () => 0);
      }
    }

    final explicitlyReversedIds = <String>{
      for (final st in settlements)
        if (st.status == 'reversed') st.id,
    };

    for (final st in settlements) {
      if (st.amountMinor <= 0) continue;
      if (st.fromUserId.trim().isEmpty ||
          st.toUserId.trim().isEmpty ||
          st.fromUserId == st.toUserId) {
        continue;
      }
      if (st.status == 'reversed') continue;
      if (st.reversalOfId != null &&
          explicitlyReversedIds.contains(st.reversalOfId)) {
        continue;
      }

      var effectiveFromId = st.fromUserId;
      if (effectiveFromId == 'bank_transfer' &&
          !realMemberIds.contains('bank_transfer')) {
        final resolved = _resolveBankTransferSenderId(
          familyId: familyId,
          toUserId: st.toUserId,
          amountMinor: st.amountMinor,
          paymentCode: st.paymentCode,
          candidateIds: namesById.keys,
        );
        if (resolved == null) {
          // Never create a ghost 'bank_transfer' member or break zero-sum invariant!
          continue;
        }
        effectiveFromId = resolved;
      }

      if (effectiveFromId == st.toUserId) continue;

      if (effectiveFromId == st.fromUserId) {
        namesById.putIfAbsent(effectiveFromId, () => st.fromUserName);
      }
      namesById.putIfAbsent(st.toUserId, () => st.toUserName);
      sentMap[effectiveFromId] =
          (sentMap[effectiveFromId] ?? 0) + st.amountMinor;
      receivedMap[st.toUserId] =
          (receivedMap[st.toUserId] ?? 0) + st.amountMinor;
      paidMap.putIfAbsent(effectiveFromId, () => 0);
      paidMap.putIfAbsent(st.toUserId, () => 0);
      owedMap.putIfAbsent(effectiveFromId, () => 0);
      owedMap.putIfAbsent(st.toUserId, () => 0);
    }

    final allUserIds = namesById.keys.toList()..sort();
    final balances = <MemberNetBalance>[];
    final nonZero = <({String userId, int netMinor})>[];
    var totalNetSum = 0;

    for (final uid in allUserIds) {
      final paid = paidMap[uid] ?? 0;
      final owed = owedMap[uid] ?? 0;
      final sent = sentMap[uid] ?? 0;
      final received = receivedMap[uid] ?? 0;
      final net = paid - owed + sent - received;
      totalNetSum += net;

      balances.add(
        MemberNetBalance(
          userId: uid,
          fullName: namesById[uid] ?? 'Thành viên',
          totalPaidMinor: paid,
          totalOwedMinor: owed,
          settlementsSentMinor: sent,
          settlementsReceivedMinor: received,
          netBalanceMinor: net,
        ),
      );

      if (net != 0) {
        nonZero.add((userId: uid, netMinor: net));
      }
    }

    if (totalNetSum != 0) {
      return SharedLedgerSummary(
        totalSharedSpendMinor: totalSpend,
        spendByTopic: Map.unmodifiable(topicSpend),
        memberBalances: List.unmodifiable(balances),
        suggestedTransfers: const [],
        isExactOptimal: false,
        unverifiedSharedSpendMinor: unverifiedSpend,
        inconsistentBillCount: inconsistentIds.length,
        inconsistentBillIds: List.unmodifiable(inconsistentIds),
      );
    }

    if (nonZero.isEmpty) {
      return SharedLedgerSummary(
        totalSharedSpendMinor: totalSpend,
        spendByTopic: Map.unmodifiable(topicSpend),
        memberBalances: List.unmodifiable(balances),
        suggestedTransfers: const [],
        isExactOptimal: true,
        unverifiedSharedSpendMinor: unverifiedSpend,
        inconsistentBillCount: inconsistentIds.length,
        inconsistentBillIds: List.unmodifiable(inconsistentIds),
      );
    }

    // Deterministic ordering before optimization: magnitude desc, userId asc
    nonZero.sort((a, b) {
      final magCmp = b.netMinor.abs().compareTo(a.netMinor.abs());
      return magCmp != 0 ? magCmp : a.userId.compareTo(b.userId);
    });

    var isExactOptimal = false;
    late List<SimplifiedDebtTransfer> transfers;

    if (nonZero.length <= exactDpMaxMembers) {
      final exact = _solveExactSubsetDp(
        familyId: familyId,
        nonZero: nonZero,
        namesById: namesById,
      );
      if (exact != null) {
        transfers = exact;
        isExactOptimal = true;
      } else {
        transfers = _solveGreedySlice(
          familyId: familyId,
          entries: nonZero,
          namesById: namesById,
        );
        isExactOptimal = false;
      }
    } else {
      transfers = _solveGreedySlice(
        familyId: familyId,
        entries: nonZero,
        namesById: namesById,
      );
      isExactOptimal = false;
    }

    // Enforce deterministic final transfer sort: (amountMinor desc, fromUserId asc, toUserId asc)
    transfers.sort((a, b) {
      final amtCmp = b.amountMinor.compareTo(a.amountMinor);
      if (amtCmp != 0) return amtCmp;
      final fromCmp = a.fromUserId.compareTo(b.fromUserId);
      if (fromCmp != 0) return fromCmp;
      return a.toUserId.compareTo(b.toUserId);
    });

    return SharedLedgerSummary(
      totalSharedSpendMinor: totalSpend,
      spendByTopic: Map.unmodifiable(topicSpend),
      memberBalances: List.unmodifiable(balances),
      suggestedTransfers: List.unmodifiable(transfers),
      isExactOptimal: isExactOptimal,
      unverifiedSharedSpendMinor: unverifiedSpend,
      inconsistentBillCount: inconsistentIds.length,
      inconsistentBillIds: List.unmodifiable(inconsistentIds),
    );
  }

  static String? _resolveBankTransferSenderId({
    required String familyId,
    required String toUserId,
    required int amountMinor,
    required String paymentCode,
    required Iterable<String> candidateIds,
  }) {
    final cleanCode = paymentCode.trim().toUpperCase().replaceFirst(
      RegExp(r'^SEVQR\s+'),
      '',
    );
    if (cleanCode.isEmpty) return null;
    for (final cid in candidateIds) {
      if (cid == toUserId || cid == 'bank_transfer') continue;
      final expected = BankNotificationParser.buildSePayTransferCode(
        scopePrefix: 'SPLIT',
        seed: '$familyId:$cid:$toUserId:$amountMinor',
      ).trim().toUpperCase();
      if (cleanCode == expected) {
        return cid;
      }
    }
    return null;
  }

  static List<SimplifiedDebtTransfer>? _solveExactSubsetDp({
    required String familyId,
    required List<({String userId, int netMinor})> nonZero,
    required Map<String, String> namesById,
  }) {
    final n = nonZero.length;
    final totalMasks = 1 << n;
    final subsetSum = List<int>.filled(totalMasks, 0);
    for (var mask = 1; mask < totalMasks; mask++) {
      final lsb = mask & -mask;
      final bitIdx = lsb.bitLength - 1;
      subsetSum[mask] = subsetSum[mask ^ lsb] + nonZero[bitIdx].netMinor;
    }

    final stopwatch = Stopwatch()..start();
    final dp = List<int>.filled(totalMasks, 0);
    final firstSub = List<int>.filled(totalMasks, 0);

    for (var mask = 1; mask < totalMasks; mask++) {
      if (subsetSum[mask] != 0) continue;
      if (stopwatch.elapsedMilliseconds > _exactDpBudgetMs) {
        return null;
      }

      var bestCount = 1;
      var bestSub = mask;
      final lsb = mask & -mask;
      for (var sub = (mask - 1) & mask; sub > 0; sub = (sub - 1) & mask) {
        if ((sub & lsb) == 0) continue;
        if (subsetSum[sub] != 0) continue;
        final candidate = dp[sub] + dp[mask ^ sub];
        if (candidate > bestCount) {
          bestCount = candidate;
          bestSub = sub;
        }
      }
      dp[mask] = bestCount;
      firstSub[mask] = bestSub;
    }

    final components = <int>[];
    void collect(int mask) {
      if (mask == 0) return;
      final sub = firstSub[mask];
      if (sub == 0 || sub == mask) {
        components.add(mask);
      } else {
        collect(sub);
        collect(mask ^ sub);
      }
    }

    collect(totalMasks - 1);

    final transfers = <SimplifiedDebtTransfer>[];
    for (final compMask in components) {
      final compEntries = <({String userId, int netMinor})>[];
      for (var i = 0; i < n; i++) {
        if ((compMask & (1 << i)) != 0) {
          compEntries.add(nonZero[i]);
        }
      }
      transfers.addAll(
        _solveGreedySlice(
          familyId: familyId,
          entries: compEntries,
          namesById: namesById,
        ),
      );
    }
    return transfers;
  }

  static List<SimplifiedDebtTransfer> _solveGreedySlice({
    required String familyId,
    required List<({String userId, int netMinor})> entries,
    required Map<String, String> namesById,
  }) {
    final debtors = <({String userId, int debtMinor})>[];
    final creditors = <({String userId, int creditMinor})>[];
    for (final e in entries) {
      if (e.netMinor < 0) {
        debtors.add((userId: e.userId, debtMinor: -e.netMinor));
      } else if (e.netMinor > 0) {
        creditors.add((userId: e.userId, creditMinor: e.netMinor));
      }
    }

    debtors.sort((a, b) {
      final cmp = b.debtMinor.compareTo(a.debtMinor);
      return cmp != 0 ? cmp : a.userId.compareTo(b.userId);
    });
    creditors.sort((a, b) {
      final cmp = b.creditMinor.compareTo(a.creditMinor);
      return cmp != 0 ? cmp : a.userId.compareTo(b.userId);
    });

    final transfers = <SimplifiedDebtTransfer>[];
    var dIdx = 0;
    var cIdx = 0;
    final remDebt = debtors.map((d) => d.debtMinor).toList();
    final remCred = creditors.map((c) => c.creditMinor).toList();
    final maxOps = (debtors.length + creditors.length) * 2 + 4;
    var ops = 0;

    while (dIdx < debtors.length && cIdx < creditors.length && ops < maxOps) {
      ops += 1;
      final dVal = remDebt[dIdx];
      final cVal = remCred[cIdx];
      final settleAmt = dVal < cVal ? dVal : cVal;

      if (settleAmt > 0) {
        final fromId = debtors[dIdx].userId;
        final toId = creditors[cIdx].userId;
        if (fromId != toId) {
          transfers.add(
            SimplifiedDebtTransfer(
              fromUserId: fromId,
              fromUserName: namesById[fromId] ?? 'Thành viên',
              toUserId: toId,
              toUserName: namesById[toId] ?? 'Thành viên',
              amountMinor: settleAmt,
              sePayTransferCode: BankNotificationParser.buildSePayTransferCode(
                scopePrefix: 'SPLIT',
                seed: '$familyId:$fromId:$toId:$settleAmt',
              ),
            ),
          );
        }
      }

      remDebt[dIdx] -= settleAmt;
      remCred[cIdx] -= settleAmt;
      if (remDebt[dIdx] == 0) dIdx += 1;
      if (remCred[cIdx] == 0) cIdx += 1;
    }

    return transfers;
  }
}
