import '../../../../core/error/app_exception.dart';
import '../entities/daily_life_entities.dart';

abstract interface class DailyLifeRepository {
  Stream<DailyLifeSnapshot> watchAll({required String userId});

  // 1. Health, Hydration & Medication Cabinet
  Future<Result<void>> addMedication({
    required String userId,
    required String name,
    required String dosage,
    required MedicationScheduleSlot slot,
    required int remainingPills,
    required DateTime expiryDate,
    bool inventoryConfirmed = true,
    String memberName = 'Cả gia đình',
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
  });

  Future<Result<void>> updateMedicationReminder({
    required String userId,
    required MedicationCabinetItemEntity item,
    required bool reminderEnabled,
    required int reminderHour,
    required int reminderMinute,
  });

  Future<Result<void>> updateMedicationInventory({
    required String userId,
    required MedicationCabinetItemEntity item,
    required int remainingPills,
    required DateTime expiryDate,
    String? dosage,
  });

  Future<Result<void>> snoozeMedication15Min({
    required MedicationCabinetItemEntity item,
  });

  Future<Result<void>> toggleMedicationToday({
    required String userId,
    required MedicationCabinetItemEntity item,
    required String dayKey,
  });

  Future<Result<void>> deleteMedication({
    required String userId,
    required String medId,
  });

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
    double? weightKg,
    double? heightCm,
    HydrationActivityLevel? activityLevel,
    bool? autoSyncTargetByBody,
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

  Future<Result<void>> addHealthVitalLog({
    required String userId,
    required double weightKg,
    required double heightCm,
    required int systolicMmHg,
    required int diastolicMmHg,
    required int heartRateBpm,
    required double sleepHours,
    String note = '',
  });

  Future<Result<void>> deleteHealthVitalLog({
    required String userId,
    required String logId,
  });

  Future<Result<void>> saveEmergencyMedicalCard({
    required EmergencyMedicalCardEntity card,
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
