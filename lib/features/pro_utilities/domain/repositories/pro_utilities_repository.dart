import '../../../../core/error/app_exception.dart';
import '../entities/pro_utilities_entities.dart';

class ProUtilitiesSnapshot {
  final List<SubscriptionWarrantyEntity> subscriptionsAndWarranties;
  final List<LifeHabitEntity> habits;
  final DailyWellnessEntity todayWellness;
  final List<GiftLedgerEntryEntity> giftEntries;
  final List<PackingChecklistItemEntity> packingItems;

  const ProUtilitiesSnapshot({
    this.subscriptionsAndWarranties = const [],
    this.habits = const [],
    required this.todayWellness,
    this.giftEntries = const [],
    this.packingItems = const [],
  });
}

abstract interface class ProUtilitiesRepository {
  Stream<ProUtilitiesSnapshot> watchAll({required String userId});

  Future<Result<void>> addSubscriptionOrWarranty({
    required String userId,
    required String title,
    required String providerOrStore,
    required SubscriptionCycle cycle,
    required int amountMinor,
    required DateTime nextBillingOrExpiryDate,
    String serialOrNote = '',
  });

  Future<Result<void>> deleteSubscriptionOrWarranty({
    required String userId,
    required String itemId,
  });

  Future<Result<void>> addHabit({
    required String userId,
    required String title,
    required String categoryTag,
  });

  Future<Result<void>> toggleHabitToday({
    required String userId,
    required LifeHabitEntity habit,
    required DateTime date,
  });

  Future<Result<void>> updateDailyWellness({
    required String userId,
    required String dateKey,
    int addWaterMl = 0,
    int addFocusMinutes = 0,
    int addPomodoros = 0,
  });

  Future<Result<void>> addGiftEntry({
    required String userId,
    required String contactName,
    required String relationshipGroup,
    required GiftDirection direction,
    required GiftOccasion occasion,
    required int amountMinor,
    String note = '',
  });

  Future<Result<void>> seedPackingTemplate({
    required String userId,
    required String tripName,
    required List<String> itemTitles,
  });

  Future<Result<void>> togglePackingItem({
    required String userId,
    required PackingChecklistItemEntity item,
  });
}
