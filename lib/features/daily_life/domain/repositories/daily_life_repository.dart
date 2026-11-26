import '../../../../core/error/app_exception.dart';
import '../entities/daily_life_entities.dart';

abstract interface class DailyLifeRepository {
  Stream<DailyLifeSnapshot> watchAll({required String userId});

  // 1. Daily Hydration & Water Reminders
  Future<Result<void>> logWaterIntake({
    required String userId,
    required int deltaMl,
    int? targetWaterMl,
    String beverageLabel = 'Nước lọc',
    String? deleteEntryId,
  });

  Future<Result<void>> saveHydrationReminderSettings({
    required String userId,
    required bool reminderEnabled,
    required int intervalMinutes,
    required int startHour,
    int startMinute = 0,
    required int endHour,
    int endMinute = 0,
    required int targetWaterMl,
    HydrationActivityLevel? activityLevel,
    int? preferredCupMl,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  });

  Future<Result<void>> snoozeHydrationReminder({
    required String userId,
    required HydrationReminderStatusEntity status,
    int minutes = 15,
  });

  Future<Result<int>> syncQueuedBackgroundHealthActions({
    required String userId,
  });

  Future<Result<bool>> sendTestHydrationNotification({
    required HydrationReminderStatusEntity status,
    int delaySeconds = 0,
  });

  // 2. Kitchen, Smart Groceries & Fridge Anti-Waste
  Future<Result<void>> addGroceryItem({
    required String userId,
    required String name,
    required String quantityLabel,
    required GroceryAisle aisle,
    required int estimatedMinor,
    bool inFridgeStorage = false,
    DateTime? expiryDate,
  });

  Future<Result<void>> seedMealComboIngredients({
    required String userId,
    required MealComboPreset combo,
    required String dayKey,
  });

  Future<Result<void>> toggleGroceryBought({
    required String userId,
    required SmartGroceryItemEntity item,
  });

  Future<Result<void>> moveGroceryToFridge({
    required String userId,
    required SmartGroceryItemEntity item,
    DateTime? expiryDate,
  });

  Future<Result<void>> clearBoughtGroceries({required String userId});

  Future<Result<void>> deleteGroceryItem({
    required String userId,
    required String itemId,
  });

  // 3. Home Living, EVN Tiered Utilities & Lease/Maintenance
  Future<Result<void>> saveUtilityReading({
    required String userId,
    required String monthKey,
    required int prevElectricKwh,
    required int currElectricKwh,
    required int prevWaterM3,
    required int currWaterM3,
    required bool useEvnTieredTariff,
    required int fixedServicesMinor,
    required int totalAmountMinor,
    bool isPaid = false,
  });

  Future<Result<void>> markUtilityReadingPaid({
    required String userId,
    required String readingId,
  });

  Future<Result<void>> saveHomeContract({
    required String userId,
    required String homeName,
    required int monthlyRentMinor,
    required int depositMinor,
    required int paymentDayOfMonth,
    required DateTime leaseEndDate,
    required String wifiCredentials,
    required String nextApplianceMaintenanceNote,
  });

  // 4. Smart Pinned Notes & Daily Mood Journal
  Future<Result<void>> addOrUpdateNote({
    required String userId,
    String? existingId,
    required String title,
    required String content,
    required String categoryTag,
    LifeMoodLevel? mood,
    bool isPinned = false,
  });

  Future<Result<void>> toggleNotePinned({
    required String userId,
    required SmartLifeNoteEntity note,
  });

  Future<Result<void>> deleteNote({
    required String userId,
    required String noteId,
  });
}
