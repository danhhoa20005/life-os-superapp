import '../../../../core/error/app_exception.dart';
import '../entities/family_entities.dart';

abstract interface class FamilyRepository {
  Stream<Result<List<FamilyEntity>>> watchMyFamilies(String userId);

  Stream<Result<List<ShoppingItemEntity>>> watchShoppingItems(String familyId);

  Stream<Result<List<SharedBillSplitEntity>>> watchSharedBills(String familyId);

  Stream<Result<List<DebtSettlementEntity>>> watchSettlements(String familyId);

  Stream<Result<List<SettlementRequestEntity>>> watchSettlementRequests(
    String familyId,
  );

  Future<Result<FamilyEntity>> createFamily({
    required String userId,
    required String userName,
    required String familyName,
    CollaborationSpaceType spaceType = CollaborationSpaceType.family,
  });

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
  });

  Future<Result<FamilyPendingInviteEntity>> previewInviteCode({
    required String inviteCode,
  });

  Future<Result<void>> revokeInviteCode({
    required String actorUserId,
    required String familyId,
    required String inviteCode,
  });

  Future<Result<FamilyEntity>> joinFamilyByInvite({
    required String userId,
    required String userName,
    required String inviteCode,
    String? userEmail,
    String? userPhone,
  });

  Future<Result<void>> updateMemberRole({
    required String actorUserId,
    required String familyId,
    required String targetUserId,
    required HouseholdRole newRole,
  });

  Future<Result<void>> removeMember({
    required String actorUserId,
    required String familyId,
    required String targetUserId,
  });

  Future<Result<void>> leaveFamily({
    required String userId,
    required String familyId,
  });

  Future<Result<void>> addShoppingItem({
    required String familyId,
    required String userName,
    required String title,
    required String quantityLabel,
    required int estimatedPriceMinor,
  });

  Future<Result<void>> toggleShoppingItem({
    required String familyId,
    required String itemId,
    required bool isPurchased,
  });

  Future<Result<void>> deleteShoppingItem({
    required String familyId,
    required String itemId,
  });

  Future<Result<int>> clearPurchasedShoppingItems({
    required String familyId,
  });

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
  });

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
  });

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
  });

  Future<Result<DebtSettlementEntity?>> confirmSettlementRequest({
    required String familyId,
    required String requestId,
    required String actorUserId,
    required bool approve,
    String? disputeReason,
  });

  Future<Result<DebtSettlementEntity>> reverseDebtSettlement({
    required String familyId,
    required String settlementId,
    required String actorUserId,
    String? reason,
  });
}
