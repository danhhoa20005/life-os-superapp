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
        CollaborationSpaceType.roommates => 'Chia tiền phòng, điện nước & ăn chung.',
        CollaborationSpaceType.group => 'Chia hóa đơn ăn uống & chuyến đi.',
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

class FamilyEntity extends Equatable {
  final String id;
  final String name;
  final CollaborationSpaceType spaceType;
  final String createdBy;
  final List<String> memberIds;
  final List<FamilyMemberInfo> members;
  final DateTime createdAt;

  const FamilyEntity({
    required this.id,
    required this.name,
    this.spaceType = CollaborationSpaceType.family,
    required this.createdBy,
    required this.memberIds,
    required this.members,
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

  @override
  List<Object?> get props => [
        id,
        name,
        spaceType,
        createdBy,
        memberIds,
        members,
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

/// Represents a shared bill paid upfront by one member and split across participants
/// (eating out, housework supplies/cleaning, utilities, rent, trip expenses).
class SharedBillSplitEntity extends Equatable {
  final String id;
  final String familyId;
  final String title;
  final SharedExpenseTopic topic;
  final String paidByUserId;
  final String paidByName;
  final int totalAmountMinor;
  final SplitMethod splitMethod;
  final Map<String, int> sharesByUserId; // Exact VND integer owed by each userId
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

/// Records an actual debt settlement transfer between two group/family members
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
    required this.createdAt,
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

  const SharedLedgerSummary({
    this.totalSharedSpendMinor = 0,
    this.spendByTopic = const {},
    this.memberBalances = const [],
    this.suggestedTransfers = const [],
  });

  @override
  List<Object?> get props => [
        totalSharedSpendMinor,
        spendByTopic,
        memberBalances,
        suggestedTransfers,
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

/// Pure Domain Minimum-Transfer Graph Debt Simplifier for Roommates, Groups & Families.
abstract final class DebtSimplifier {
  static SharedLedgerSummary summarize({
    required String familyId,
    required List<FamilyMemberInfo> members,
    required List<SharedBillSplitEntity> bills,
    required List<DebtSettlementEntity> settlements,
  }) {
    final namesById = <String, String>{
      for (final m in members) m.userId: m.fullName,
    };
    final paidMap = <String, int>{for (final m in members) m.userId: 0};
    final owedMap = <String, int>{for (final m in members) m.userId: 0};
    final sentMap = <String, int>{for (final m in members) m.userId: 0};
    final receivedMap = <String, int>{for (final m in members) m.userId: 0};
    final topicSpend = <SharedExpenseTopic, int>{};
    var totalSpend = 0;

    for (final bill in bills) {
      totalSpend += bill.totalAmountMinor;
      topicSpend[bill.topic] = (topicSpend[bill.topic] ?? 0) + bill.totalAmountMinor;
      namesById.putIfAbsent(bill.paidByUserId, () => bill.paidByName);
      paidMap[bill.paidByUserId] =
          (paidMap[bill.paidByUserId] ?? 0) + bill.totalAmountMinor;

      for (final entry in bill.sharesByUserId.entries) {
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

    for (final st in settlements) {
      namesById.putIfAbsent(st.fromUserId, () => st.fromUserName);
      namesById.putIfAbsent(st.toUserId, () => st.toUserName);
      sentMap[st.fromUserId] = (sentMap[st.fromUserId] ?? 0) + st.amountMinor;
      receivedMap[st.toUserId] = (receivedMap[st.toUserId] ?? 0) + st.amountMinor;
      paidMap.putIfAbsent(st.fromUserId, () => 0);
      paidMap.putIfAbsent(st.toUserId, () => 0);
      owedMap.putIfAbsent(st.fromUserId, () => 0);
      owedMap.putIfAbsent(st.toUserId, () => 0);
    }

    final allUserIds = namesById.keys.toList()..sort();
    final balances = <MemberNetBalance>[];
    final debtors = <({String userId, int debtMinor})>[];
    final creditors = <({String userId, int creditMinor})>[];

    for (final uid in allUserIds) {
      final paid = paidMap[uid] ?? 0;
      final owed = owedMap[uid] ?? 0;
      final sent = sentMap[uid] ?? 0;
      final received = receivedMap[uid] ?? 0;
      final net = paid - owed + sent - received;

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

      if (net < 0) {
        debtors.add((userId: uid, debtMinor: -net));
      } else if (net > 0) {
        creditors.add((userId: uid, creditMinor: net));
      }
    }

    // Greedy largest-creditor vs largest-debtor matching -> at most (N - 1) transfers!
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

    while (dIdx < debtors.length && cIdx < creditors.length) {
      final dVal = remDebt[dIdx];
      final cVal = remCred[cIdx];
      final settleAmt = dVal < cVal ? dVal : cVal;

      if (settleAmt > 0) {
        final fromId = debtors[dIdx].userId;
        final toId = creditors[cIdx].userId;
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

      remDebt[dIdx] -= settleAmt;
      remCred[cIdx] -= settleAmt;
      if (remDebt[dIdx] == 0) dIdx += 1;
      if (remCred[cIdx] == 0) cIdx += 1;
    }

    return SharedLedgerSummary(
      totalSharedSpendMinor: totalSpend,
      spendByTopic: Map.unmodifiable(topicSpend),
      memberBalances: List.unmodifiable(balances),
      suggestedTransfers: List.unmodifiable(transfers),
    );
  }
}
