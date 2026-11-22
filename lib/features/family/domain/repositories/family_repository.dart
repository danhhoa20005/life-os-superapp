import '../../../../core/error/app_exception.dart';
import '../entities/family_entities.dart';

abstract interface class FamilyRepository {
  Stream<Result<List<FamilyEntity>>> watchMyFamilies(String userId);

  Stream<Result<List<ShoppingItemEntity>>> watchShoppingItems(String familyId);

  Stream<Result<List<SharedBillSplitEntity>>> watchSharedBills(String familyId);

  Stream<Result<List<DebtSettlementEntity>>> watchSettlements(String familyId);

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
  });

  Future<Result<FamilyEntity>> joinFamilyByInvite({
    required String userId,
    required String userName,
    required String inviteCode,
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
    String? note,
  });
}
