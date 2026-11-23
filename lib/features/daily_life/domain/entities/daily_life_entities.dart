import 'package:equatable/equatable.dart';

// =============================================================================
// 1. HEALTH, MEDICATION CABINET, ASIAN BMI/TDEE & EMERGENCY SOS ENTITIES
// =============================================================================

enum MedicationScheduleSlot {
  morning('Buổi sáng (Sau ăn)'),
  noon('Buổi trưa'),
  evening('Buổi tối'),
  asNeeded('Tủ thuốc dự phòng (Khi cần)');

  final String label;
  const MedicationScheduleSlot(this.label);

  static MedicationScheduleSlot fromName(String? raw) {
    return MedicationScheduleSlot.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MedicationScheduleSlot.morning,
    );
  }
}

class MedicationCabinetItemEntity extends Equatable {
  final String id;
  final String ownerId;
  final String name;
  final String dosage;
  final MedicationScheduleSlot slot;
  final int remainingPills;
  final DateTime expiryDate;
  final String? lastTakenDayKey;
  final String memberName;

  const MedicationCabinetItemEntity({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.dosage,
    required this.slot,
    required this.remainingPills,
    required this.expiryDate,
    this.lastTakenDayKey,
    this.memberName = 'Cả gia đình',
  });

  bool isTakenOn(String dayKey) => lastTakenDayKey == dayKey;

  int daysUntilExpiry(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return exp.difference(today).inDays;
  }

  bool isExpiringSoon(DateTime now) => daysUntilExpiry(now) <= 30;

  @override
  List<Object?> get props => [
        id,
        ownerId,
        name,
        dosage,
        slot,
        remainingPills,
        expiryDate,
        lastTakenDayKey,
        memberName,
      ];
}

class HealthVitalLogEntity extends Equatable {
  final String id;
  final String ownerId;
  final double weightKg;
  final double heightCm;
  final int systolicMmHg;
  final int diastolicMmHg;
  final int heartRateBpm;
  final double sleepHours;
  final DateTime recordedAt;
  final String note;

  const HealthVitalLogEntity({
    required this.id,
    required this.ownerId,
    required this.weightKg,
    required this.heightCm,
    required this.systolicMmHg,
    required this.diastolicMmHg,
    required this.heartRateBpm,
    required this.sleepHours,
    required this.recordedAt,
    this.note = '',
  });

  @override
  List<Object?> get props => [
        id,
        ownerId,
        weightKg,
        heightCm,
        systolicMmHg,
        diastolicMmHg,
        heartRateBpm,
        sleepHours,
        recordedAt,
        note,
      ];
}

class EmergencyMedicalCardEntity extends Equatable {
  final String ownerId;
  final String bloodType;
  final String allergies;
  final String chronicConditions;
  final String insuranceCode;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String preferredHospital;

  /// Never pre-fills unverified medical values (such as fake 'O+' or 'No allergies').
  /// Empty strings represent unprovided fields and render as "Chưa cung cấp" in UI.
  const EmergencyMedicalCardEntity({
    required this.ownerId,
    this.bloodType = '',
    this.allergies = '',
    this.chronicConditions = '',
    this.insuranceCode = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.preferredHospital = '',
  });

  bool get isConfigured =>
      bloodType.trim().isNotEmpty ||
      allergies.trim().isNotEmpty ||
      chronicConditions.trim().isNotEmpty ||
      insuranceCode.trim().isNotEmpty ||
      emergencyContactPhone.trim().isNotEmpty;

  static const empty = EmergencyMedicalCardEntity(ownerId: '');

  @override
  List<Object?> get props => [
        ownerId,
        bloodType,
        allergies,
        chronicConditions,
        insuranceCode,
        emergencyContactName,
        emergencyContactPhone,
        preferredHospital,
      ];
}

class AsianHealthAssessment extends Equatable {
  final double bmi;
  final String bmiCategory;
  final double idealMinWeightKg;
  final double idealMaxWeightKg;
  final int bmrKcal;
  final int tdeeKcal;
  final int recommendedWaterMl;
  final String bloodPressureStatus;

  const AsianHealthAssessment({
    required this.bmi,
    required this.bmiCategory,
    required this.idealMinWeightKg,
    required this.idealMaxWeightKg,
    required this.bmrKcal,
    required this.tdeeKcal,
    required this.recommendedWaterMl,
    required this.bloodPressureStatus,
  });

  @override
  List<Object?> get props => [
        bmi,
        bmiCategory,
        idealMinWeightKg,
        idealMaxWeightKg,
        bmrKcal,
        tdeeKcal,
        recommendedWaterMl,
        bloodPressureStatus,
      ];
}

class AsianHealthBmiTdeeEngine {
  /// Computes Asian-Pacific WHO BMI (IDI & WPRO cutoffs), Mifflin-St Jeor BMR/TDEE,
  /// hydration target, and blood pressure status.
  static AsianHealthAssessment evaluate({
    required double weightKg,
    required double heightCm,
    int ageYears = 29,
    bool isMale = true,
    double activityMultiplier = 1.375,
    int systolicMmHg = 118,
    int diastolicMmHg = 76,
  }) {
    final safeHeightM = (heightCm.clamp(100.0, 230.0)) / 100.0;
    final safeWeight = weightKg.clamp(25.0, 250.0);
    final bmi = safeWeight / (safeHeightM * safeHeightM);

    final String bmiLabel;
    if (bmi < 18.5) {
      bmiLabel = 'Thiếu cân (< 18.5)';
    } else if (bmi < 23.0) {
      bmiLabel = 'Chuẩn Châu Á (18.5 – 22.9)';
    } else if (bmi < 25.0) {
      bmiLabel = 'Thừa cân nhẹ (23.0 – 24.9)';
    } else if (bmi < 30.0) {
      bmiLabel = 'Béo phì độ I (25.0 – 29.9)';
    } else {
      bmiLabel = 'Béo phì độ II (>= 30.0)';
    }

    final minIdeal = 18.5 * safeHeightM * safeHeightM;
    final maxIdeal = 22.9 * safeHeightM * safeHeightM;

    final baseBmr =
        (10 * safeWeight) + (6.25 * (safeHeightM * 100)) - (5 * ageYears.clamp(12, 100));
    final bmr = (isMale ? baseBmr + 5 : baseBmr - 161).round();
    final tdee = (bmr * activityMultiplier.clamp(1.2, 1.9)).round();
    final waterMl = ((safeWeight * 35) / 50).round() * 50;

    final String bpLabel;
    if (systolicMmHg >= 140 || diastolicMmHg >= 90) {
      bpLabel = 'Tăng huyết áp (Cần theo dõi)';
    } else if (systolicMmHg >= 120 || diastolicMmHg >= 80) {
      bpLabel = 'Bình thường cao (Tiền THA)';
    } else if (systolicMmHg < 90 || diastolicMmHg < 60) {
      bpLabel = 'Huyết áp thấp';
    } else {
      bpLabel = 'Huyết áp tối ưu (< 120/80)';
    }

    return AsianHealthAssessment(
      bmi: double.parse(bmi.toStringAsFixed(1)),
      bmiCategory: bmiLabel,
      idealMinWeightKg: double.parse(minIdeal.toStringAsFixed(1)),
      idealMaxWeightKg: double.parse(maxIdeal.toStringAsFixed(1)),
      bmrKcal: bmr,
      tdeeKcal: tdee,
      recommendedWaterMl: waterMl,
      bloodPressureStatus: bpLabel,
    );
  }
}

// =============================================================================
// 2. FAMILY KITCHEN, SMART GROCERY BASKET & FRIDGE ANTI-WASTE ENTITIES
// =============================================================================

enum GroceryAisle {
  produce('Rau củ & Trái cây'),
  meatSeafood('Thịt cá & Trứng sữa'),
  pantry('Gạo, Gia vị & Đồ khô'),
  household('Đồ gia dụng & Vệ sinh');

  final String label;
  const GroceryAisle(this.label);

  static GroceryAisle fromName(String? raw) {
    return GroceryAisle.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => GroceryAisle.produce,
    );
  }
}

class SmartGroceryItemEntity extends Equatable {
  final String id;
  final String ownerId;
  final String name;
  final String quantityLabel;
  final GroceryAisle aisle;
  final int estimatedMinor;
  final bool isBought;
  final bool inFridgeStorage;
  final DateTime? expiryDate;

  const SmartGroceryItemEntity({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.quantityLabel,
    required this.aisle,
    required this.estimatedMinor,
    this.isBought = false,
    this.inFridgeStorage = false,
    this.expiryDate,
  });

  int? daysFreshRemaining(DateTime now) {
    if (expiryDate == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    return exp.difference(today).inDays;
  }

  @override
  List<Object?> get props => [
        id,
        ownerId,
        name,
        quantityLabel,
        aisle,
        estimatedMinor,
        isBought,
        inFridgeStorage,
        expiryDate,
      ];
}

class DailyMealPlanEntity extends Equatable {
  final String dayKey;
  final String ownerId;
  final String breakfast;
  final String lunch;
  final String dinner;
  final int estimatedDailyCostMinor;
  final int estimatedKcal;

  const DailyMealPlanEntity({
    required this.dayKey,
    required this.ownerId,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.estimatedDailyCostMinor,
    required this.estimatedKcal,
  });

  @override
  List<Object?> get props => [
        dayKey,
        ownerId,
        breakfast,
        lunch,
        dinner,
        estimatedDailyCostMinor,
        estimatedKcal,
      ];
}

class MealComboPreset {
  final String title;
  final String regionStyle;
  final String breakfast;
  final String lunch;
  final String dinner;
  final int estimatedCostMinor;
  final int estimatedKcal;
  final List<({String name, String qty, GroceryAisle aisle, int priceMinor})> ingredients;

  const MealComboPreset({
    required this.title,
    required this.regionStyle,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.estimatedCostMinor,
    required this.estimatedKcal,
    required this.ingredients,
  });
}

class VietnameseMealSuggestionCatalog {
  static const List<MealComboPreset> presets = [
    MealComboPreset(
      title: 'Cơm nhà Miền Nam thanh mát',
      regionStyle: 'Đậm đà · Dễ nấu 30 phút',
      breakfast: 'Bánh mì ốp la + Cà phê sữa tươi',
      lunch: 'Cá hú kho tộ + Canh chua cá lóc + Rau muống xào tỏi',
      dinner: 'Thịt luộc cà pháo + Canh bí đỏ thịt bằm',
      estimatedCostMinor: 165000,
      estimatedKcal: 1850,
      ingredients: [
        (name: 'Cá lóc & cá hú tươi', qty: '600g', aisle: GroceryAisle.meatSeafood, priceMinor: 75000),
        (name: 'Bạc hà, đậu bắp, giá, thơm', qty: '1 set canh chua', aisle: GroceryAisle.produce, priceMinor: 25000),
        (name: 'Thịt ba rọi & thịt bằm', qty: '400g', aisle: GroceryAisle.meatSeafood, priceMinor: 50000),
        (name: 'Rau muống & bí đỏ hồ lô', qty: '1 bó + 1 trái', aisle: GroceryAisle.produce, priceMinor: 15000),
      ],
    ),
    MealComboPreset(
      title: 'Cơm nhà Miền Bắc ấm cúng',
      regionStyle: 'Chuẩn vị gia đình · Đủ chất',
      breakfast: 'Phở gà ta nấu nhanh tại nhà',
      lunch: 'Thịt rang cháy cạnh + Canh cua mồng tơi mướp + Cà muối',
      dinner: 'Đậu phụ nhồi thịt sốt cà chua + Bắp cải luộc dầm trứng',
      estimatedCostMinor: 155000,
      estimatedKcal: 1790,
      ingredients: [
        (name: 'Thịt nạc vai & sườn non', qty: '500g', aisle: GroceryAisle.meatSeafood, priceMinor: 70000),
        (name: 'Cua đồng xay sẵn', qty: '250g', aisle: GroceryAisle.meatSeafood, priceMinor: 40000),
        (name: 'Rau mồng tơi, mướp hương, cà chua', qty: '1 rổ', aisle: GroceryAisle.produce, priceMinor: 25000),
        (name: 'Đậu phụ mơ & trứng gà ta', qty: '4 bìa + 4 quả', aisle: GroceryAisle.meatSeafood, priceMinor: 20000),
      ],
    ),
    MealComboPreset(
      title: 'Thực đơn Eat Clean Giữ dáng',
      regionStyle: 'Ít dầu mỡ · Giàu Protein',
      breakfast: 'Yến mạch sữa chua Hy Lạp + Chuối & Hạt điều',
      lunch: 'Ức gà áp chảo sốt chanh dây + Khoai lang mật + Bông cải hấp',
      dinner: 'Cá hồi áp chảo + Salad bơ trứng luộc',
      estimatedCostMinor: 195000,
      estimatedKcal: 1520,
      ingredients: [
        (name: 'Phi lê cá hồi & ức gà tươi', qty: '450g', aisle: GroceryAisle.meatSeafood, priceMinor: 115000),
        (name: 'Bông cải xanh, xà lách Romaine, bơ sáp', qty: '1 túi', aisle: GroceryAisle.produce, priceMinor: 45000),
        (name: 'Khoai lang mật Đà Lạt', qty: '1kg', aisle: GroceryAisle.produce, priceMinor: 35000),
      ],
    ),
    MealComboPreset(
      title: 'Cuối tuần Sum họp Gia đình / Hội nhóm',
      regionStyle: 'Tiệc nhỏ tại gia · Tiết kiệm 50% so với hàng quán',
      breakfast: 'Bún mọc sườn non dọc mùng',
      lunch: 'Gỏi cuốn tôm thịt sốt tương đậu',
      dinner: 'Lẩu nấm bò Mỹ nhúng rau tổng hợp',
      estimatedCostMinor: 320000,
      estimatedKcal: 2150,
      ingredients: [
        (name: 'Ba chỉ bò Mỹ & tôm sú tươi', qty: '800g', aisle: GroceryAisle.meatSeafood, priceMinor: 195000),
        (name: 'Set nấm kim châm, đùi gà, bào ngư & rau lẩu', qty: '1 khay lớn', aisle: GroceryAisle.produce, priceMinor: 75000),
        (name: 'Bánh tráng, bún tươi & cốt lẩu', qty: '1 phần', aisle: GroceryAisle.pantry, priceMinor: 50000),
      ],
    ),
  ];
}

// =============================================================================
// 3. HOME LIVING, VIETNAM EVN 6-TIER ELECTRICITY & RENT/MAINTENANCE ENTITIES
// =============================================================================

class EvnTierSlice extends Equatable {
  final int tierIndex;
  final String rangeLabel;
  final int kwhUsed;
  final int unitPriceVnd;
  final int subtotalMinor;

  const EvnTierSlice({
    required this.tierIndex,
    required this.rangeLabel,
    required this.kwhUsed,
    required this.unitPriceVnd,
    required this.subtotalMinor,
  });

  @override
  List<Object?> get props => [tierIndex, rangeLabel, kwhUsed, unitPriceVnd, subtotalMinor];
}

class UtilityBillCalculation extends Equatable {
  final int kwhConsumed;
  final int waterM3Consumed;
  final int electricityPreVatMinor;
  final int electricityVatMinor;
  final int electricityTotalMinor;
  final int waterTotalMinor;
  final int fixedServicesMinor;
  final int grandTotalMinor;
  final int perPersonShareMinor;
  final List<EvnTierSlice> evnTiers;

  const UtilityBillCalculation({
    required this.kwhConsumed,
    required this.waterM3Consumed,
    required this.electricityPreVatMinor,
    required this.electricityVatMinor,
    required this.electricityTotalMinor,
    required this.waterTotalMinor,
    required this.fixedServicesMinor,
    required this.grandTotalMinor,
    required this.perPersonShareMinor,
    required this.evnTiers,
  });

  @override
  List<Object?> get props => [
        kwhConsumed,
        waterM3Consumed,
        electricityPreVatMinor,
        electricityVatMinor,
        electricityTotalMinor,
        waterTotalMinor,
        fixedServicesMinor,
        grandTotalMinor,
        perPersonShareMinor,
        evnTiers,
      ];
}

/// Versioned EVN Retail Residential Electricity Tariff Policy.
enum EvnTariffPolicy {
  /// Quyết định 2892/QĐ-BCT của Bộ Công Thương (hiệu lực từ 01/11/2026) — 5 bậc thang.
  qd2892Nov2026(
    code: 'QD_2892_BCT_2026_11_01',
    title: 'Biểu giá 5 bậc EVN (QĐ 2892/QĐ-BCT · từ 01/11/2026)',
    effectiveFromIso: '2026-11-01',
  ),

  /// Biểu giá 6 bậc trước ngày 01/11/2026 (dùng đối chiếu hóa đơn kỳ cũ).
  legacy6TierPreNov2026(
    code: 'EVN_LEGACY_6_TIER_PRE_2026_11',
    title: 'Biểu giá 6 bậc cũ (Trước 01/11/2026)',
    effectiveFromIso: '2024-10-11',
  );

  final String code;
  final String title;
  final String effectiveFromIso;

  const EvnTariffPolicy({
    required this.code,
    required this.title,
    required this.effectiveFromIso,
  });
}

class VietnamEvnUtilityEngine {
  /// Official 5-tier residential retail electricity tariff from 01/11/2026 (`Quyết định 2892/QĐ-BCT`).
  static const List<({int tier, String label, int capKwh, int priceVnd})>
      evn5TiersQd2892Nov2026 = [
    (tier: 1, label: 'Bậc 1 (0 – 100 kWh)', capKwh: 100, priceVnd: 1901),
    (tier: 2, label: 'Bậc 2 (101 – 200 kWh)', capKwh: 100, priceVnd: 2289),
    (tier: 3, label: 'Bậc 3 (201 – 400 kWh)', capKwh: 200, priceVnd: 2894),
    (tier: 4, label: 'Bậc 4 (401 – 700 kWh)', capKwh: 300, priceVnd: 3456),
    (tier: 5, label: 'Bậc 5 (Trên 700 kWh)', capKwh: 999999, priceVnd: 3844),
  ];

  /// Historical 6-tier residential tariff prior to 01/11/2026 for auditing older bills.
  static const List<({int tier, String label, int capKwh, int priceVnd})>
      evnLegacy6Tiers = [
    (tier: 1, label: 'Bậc 1 (0 – 50 kWh)', capKwh: 50, priceVnd: 1893),
    (tier: 2, label: 'Bậc 2 (51 – 100 kWh)', capKwh: 50, priceVnd: 1956),
    (tier: 3, label: 'Bậc 3 (101 – 200 kWh)', capKwh: 100, priceVnd: 2271),
    (tier: 4, label: 'Bậc 4 (201 – 300 kWh)', capKwh: 100, priceVnd: 2860),
    (tier: 5, label: 'Bậc 5 (301 – 400 kWh)', capKwh: 100, priceVnd: 3197),
    (tier: 6, label: 'Bậc 6 (401+ kWh)', capKwh: 999999, priceVnd: 3302),
  ];

  static UtilityBillCalculation calculate({
    required int prevElectricKwh,
    required int currElectricKwh,
    required int prevWaterM3,
    required int currWaterM3,
    bool useEvnTieredTariff = true,
    EvnTariffPolicy policy = EvnTariffPolicy.qd2892Nov2026,
    int vatRatePercent = 8,
    int customFlatElectricVndPerKwh = 3800,
    int waterVndPerM3 = 15000,
    int internetAndManagementMinor = 220000,
    int splitMemberCount = 1,
  }) {
    final kwh = (currElectricKwh - prevElectricKwh).clamp(0, 100000);
    final m3 = (currWaterM3 - prevWaterM3).clamp(0, 10000);
    final safeMembers = splitMemberCount.clamp(1, 30);
    final safeVatPct = vatRatePercent.clamp(0, 20);

    final slices = <EvnTierSlice>[];
    var elecPreVat = 0;
    var elecVat = 0;

    if (useEvnTieredTariff) {
      final activeTiers = policy == EvnTariffPolicy.qd2892Nov2026
          ? evn5TiersQd2892Nov2026
          : evnLegacy6Tiers;
      var remaining = kwh;
      for (final t in activeTiers) {
        if (remaining <= 0) break;
        final usedInTier = remaining > t.capKwh ? t.capKwh : remaining;
        final sub = usedInTier * t.priceVnd;
        slices.add(
          EvnTierSlice(
            tierIndex: t.tier,
            rangeLabel: t.label,
            kwhUsed: usedInTier,
            unitPriceVnd: t.priceVnd,
            subtotalMinor: sub,
          ),
        );
        elecPreVat += sub;
        remaining -= usedInTier;
      }
      elecVat = ((elecPreVat * safeVatPct) / 100).round();
    } else {
      elecPreVat = kwh * customFlatElectricVndPerKwh.clamp(0, 50000);
      slices.add(
        EvnTierSlice(
          tierIndex: 1,
          rangeLabel: 'Giá điện phòng trọ cố định',
          kwhUsed: kwh,
          unitPriceVnd: customFlatElectricVndPerKwh,
          subtotalMinor: elecPreVat,
        ),
      );
      elecVat = 0;
    }

    final elecTotal = elecPreVat + elecVat;
    final waterTotal = m3 * waterVndPerM3.clamp(0, 200000);
    final fixed = internetAndManagementMinor.clamp(0, 50000000);
    final grand = elecTotal + waterTotal + fixed;
    final share = (grand / safeMembers).ceil();

    return UtilityBillCalculation(
      kwhConsumed: kwh,
      waterM3Consumed: m3,
      electricityPreVatMinor: elecPreVat,
      electricityVatMinor: elecVat,
      electricityTotalMinor: elecTotal,
      waterTotalMinor: waterTotal,
      fixedServicesMinor: fixed,
      grandTotalMinor: grand,
      perPersonShareMinor: share,
      evnTiers: slices,
    );
  }
}

class UtilityMeterReadingEntity extends Equatable {
  final String id;
  final String ownerId;
  final String monthKey;
  final int prevElectricKwh;
  final int currElectricKwh;
  final int prevWaterM3;
  final int currWaterM3;
  final bool useEvnTieredTariff;
  final int fixedServicesMinor;
  final int totalAmountMinor;
  final bool isPaid;
  final DateTime recordedAt;

  const UtilityMeterReadingEntity({
    required this.id,
    required this.ownerId,
    required this.monthKey,
    required this.prevElectricKwh,
    required this.currElectricKwh,
    required this.prevWaterM3,
    required this.currWaterM3,
    required this.useEvnTieredTariff,
    required this.fixedServicesMinor,
    required this.totalAmountMinor,
    this.isPaid = false,
    required this.recordedAt,
  });

  int get kwhUsed => (currElectricKwh - prevElectricKwh).clamp(0, 100000);
  int get waterM3Used => (currWaterM3 - prevWaterM3).clamp(0, 10000);

  @override
  List<Object?> get props => [
        id,
        ownerId,
        monthKey,
        prevElectricKwh,
        currElectricKwh,
        prevWaterM3,
        currWaterM3,
        useEvnTieredTariff,
        fixedServicesMinor,
        totalAmountMinor,
        isPaid,
        recordedAt,
      ];
}

class HomeContractMaintenanceEntity extends Equatable {
  final String id;
  final String ownerId;
  final String homeName;
  final int monthlyRentMinor;
  final int depositMinor;
  final int paymentDayOfMonth;
  final DateTime leaseEndDate;
  final String wifiCredentials;
  final String nextApplianceMaintenanceNote;

  const HomeContractMaintenanceEntity({
    required this.id,
    required this.ownerId,
    required this.homeName,
    required this.monthlyRentMinor,
    required this.depositMinor,
    required this.paymentDayOfMonth,
    required this.leaseEndDate,
    this.wifiCredentials = '',
    this.nextApplianceMaintenanceNote = 'Vệ sinh điều hòa & thay lõi lọc nước RO sau 90 ngày',
  });

  int daysUntilLeaseExpiry(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(leaseEndDate.year, leaseEndDate.month, leaseEndDate.day);
    return end.difference(today).inDays;
  }

  @override
  List<Object?> get props => [
        id,
        ownerId,
        homeName,
        monthlyRentMinor,
        depositMinor,
        paymentDayOfMonth,
        leaseEndDate,
        wifiCredentials,
        nextApplianceMaintenanceNote,
      ];
}

// =============================================================================
// 4. SMART PINNED NOTES, DAILY MOOD JOURNAL & VIETNAM GROSS-NET SALARY ENGINE
// =============================================================================

enum LifeMoodLevel {
  great('Tuyệt vời', '🌟'),
  calm('Bình yên', '🌿'),
  focused('Tập trung', '🎯'),
  tired('Hơi mệt', '🌙'),
  stressed('Áp lực', '⚡');

  final String label;
  final String emoji;
  const LifeMoodLevel(this.label, this.emoji);

  static LifeMoodLevel fromName(String? raw) {
    return LifeMoodLevel.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => LifeMoodLevel.calm,
    );
  }
}

class SmartLifeNoteEntity extends Equatable {
  final String id;
  final String ownerId;
  final String title;
  final String content;
  final String categoryTag;
  final LifeMoodLevel? mood;
  final bool isPinned;
  final DateTime updatedAt;

  const SmartLifeNoteEntity({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.content,
    this.categoryTag = 'Ghi chú nhanh',
    this.mood,
    this.isPinned = false,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        id,
        ownerId,
        title,
        content,
        categoryTag,
        mood,
        isPinned,
        updatedAt,
      ];
}

class PitBracketBreakdown extends Equatable {
  final int level;
  final String label;
  final int ratePercent;
  final int taxableSliceMinor;
  final int taxMinor;

  const PitBracketBreakdown({
    required this.level,
    required this.label,
    required this.ratePercent,
    required this.taxableSliceMinor,
    required this.taxMinor,
  });

  @override
  List<Object?> get props => [level, label, ratePercent, taxableSliceMinor, taxMinor];
}

class VietnamSalaryTaxResult extends Equatable {
  final int grossSalaryMinor;
  final int bhxhMinor;
  final int bhytMinor;
  final int bhtnMinor;
  final int totalEmployeeInsuranceMinor;
  final int personalDeductionMinor;
  final int dependentDeductionMinor;
  final int taxableIncomeMinor;
  final int personalIncomeTaxMinor;
  final int netSalaryMinor;
  final int totalEmployerCostMinor;
  final List<PitBracketBreakdown> brackets;

  const VietnamSalaryTaxResult({
    required this.grossSalaryMinor,
    required this.bhxhMinor,
    required this.bhytMinor,
    required this.bhtnMinor,
    required this.totalEmployeeInsuranceMinor,
    required this.personalDeductionMinor,
    required this.dependentDeductionMinor,
    required this.taxableIncomeMinor,
    required this.personalIncomeTaxMinor,
    required this.netSalaryMinor,
    required this.totalEmployerCostMinor,
    required this.brackets,
  });

  @override
  List<Object?> get props => [
        grossSalaryMinor,
        bhxhMinor,
        bhytMinor,
        bhtnMinor,
        totalEmployeeInsuranceMinor,
        personalDeductionMinor,
        dependentDeductionMinor,
        taxableIncomeMinor,
        personalIncomeTaxMinor,
        netSalaryMinor,
        totalEmployerCostMinor,
        brackets,
      ];
}

/// Regional Minimum Wage Zones (`Nghị định 293/2025/NĐ-CP`, hiệu lực từ 01/01/2026).
enum VietnamWageRegion {
  region1(label: 'Vùng I (5,31tr · Trần BHTN 106,2tr)', minWage2026Vnd: 5310000, minWage2025Vnd: 4960000),
  region2(label: 'Vùng II (4,73tr · Trần BHTN 94,6tr)', minWage2026Vnd: 4730000, minWage2025Vnd: 4410000),
  region3(label: 'Vùng III (4,14tr · Trần BHTN 82,8tr)', minWage2026Vnd: 4140000, minWage2025Vnd: 3860000),
  region4(label: 'Vùng IV (3,70tr · Trần BHTN 74,0tr)', minWage2026Vnd: 3700000, minWage2025Vnd: 3450000);

  final String label;
  final int minWage2026Vnd;
  final int minWage2025Vnd;

  const VietnamWageRegion({
    required this.label,
    required this.minWage2026Vnd,
    required this.minWage2025Vnd,
  });

  int bhtnSalaryCapForPolicy(VietnamTaxPolicy policy) {
    final base = policy == VietnamTaxPolicy.law109Year2026 ? minWage2026Vnd : minWage2025Vnd;
    return base * 20;
  }
}

/// Versioned Personal Income Tax Policy (`Luật Thuế TNCN 109/2025/QH15` vs Legacy 2025).
enum VietnamTaxPolicy {
  /// Kỳ tính thuế từ 2026: Giảm trừ bản thân 15,5 triệu/tháng, NPT 6,2 triệu/tháng, Biểu thuế 5 bậc.
  law109Year2026(
    code: 'LAW_109_2025_QH15_YEAR_2026',
    title: 'Kỳ thuế 2026 (Luật 109/2025 · 5 bậc · Giảm trừ 15,5tr)',
    personalDeductionVnd: 15500000,
    dependentDeductionVnd: 6200000,
  ),

  /// Kỳ tính thuế trước 2026: Giảm trừ bản thân 11 triệu/tháng, NPT 4,4 triệu/tháng, Biểu thuế 7 bậc.
  legacy7Bracket2025(
    code: 'PIT_LEGACY_7_BRACKET_PRE_2026',
    title: 'Kỳ thuế 2025 trở về trước (7 bậc · Giảm trừ 11tr)',
    personalDeductionVnd: 11000000,
    dependentDeductionVnd: 4400000,
  );

  final String code;
  final String title;
  final int personalDeductionVnd;
  final int dependentDeductionVnd;

  const VietnamTaxPolicy({
    required this.code,
    required this.title,
    required this.personalDeductionVnd,
    required this.dependentDeductionVnd,
  });
}

class VietnamGrossNetTaxEngine {
  // 20x statutory base salary (2.340.000 * 20 = 46.800.000 VND) cap for BHXH/BHYT
  static const int bhxhBhytSalaryCapVnd = 46800000;

  /// Official 5-bracket progressive PIT schedule from tax year 2026 (`Luật Thuế TNCN 109/2025/QH15`).
  static const List<({int level, String label, int capVnd, int ratePct})>
      pit5Brackets2026 = [
    (level: 1, label: 'Bậc 1 (Đến 10 triệu)', capVnd: 10000000, ratePct: 5),
    (level: 2, label: 'Bậc 2 (Trên 10 – 30 triệu)', capVnd: 20000000, ratePct: 10),
    (level: 3, label: 'Bậc 3 (Trên 30 – 60 triệu)', capVnd: 30000000, ratePct: 20),
    (level: 4, label: 'Bậc 4 (Trên 60 – 100 triệu)', capVnd: 40000000, ratePct: 30),
    (level: 5, label: 'Bậc 5 (Trên 100 triệu)', capVnd: 999999999999, ratePct: 35),
  ];

  /// Legacy 7-bracket progressive PIT schedule (for historical 2025 comparison).
  static const List<({int level, String label, int capVnd, int ratePct})>
      pitLegacy7Brackets2025 = [
    (level: 1, label: 'Bậc 1 (Đến 5 triệu)', capVnd: 5000000, ratePct: 5),
    (level: 2, label: 'Bậc 2 (Trên 5 – 10 triệu)', capVnd: 5000000, ratePct: 10),
    (level: 3, label: 'Bậc 3 (Trên 10 – 18 triệu)', capVnd: 8000000, ratePct: 15),
    (level: 4, label: 'Bậc 4 (Trên 18 – 32 triệu)', capVnd: 14000000, ratePct: 20),
    (level: 5, label: 'Bậc 5 (Trên 32 – 52 triệu)', capVnd: 20000000, ratePct: 25),
    (level: 6, label: 'Bậc 6 (Trên 52 – 80 triệu)', capVnd: 28000000, ratePct: 30),
    (level: 7, label: 'Bậc 7 (Trên 80 triệu)', capVnd: 999999999999, ratePct: 35),
  ];

  static VietnamSalaryTaxResult fromGross({
    required int grossMinor,
    int dependentsCount = 0,
    VietnamTaxPolicy policy = VietnamTaxPolicy.law109Year2026,
    VietnamWageRegion region = VietnamWageRegion.region1,
  }) {
    final gross = grossMinor.clamp(0, 5000000000);
    final deps = dependentsCount.clamp(0, 20);
    final bhtnCap = region.bhtnSalaryCapForPolicy(policy);

    final bhxhBase = gross > bhxhBhytSalaryCapVnd ? bhxhBhytSalaryCapVnd : gross;
    final bhtnBase = gross > bhtnCap ? bhtnCap : gross;

    final bhxh = (bhxhBase * 0.08).round();
    final bhyt = (bhxhBase * 0.015).round();
    final bhtn = (bhtnBase * 0.01).round();
    final totalEmpIns = bhxh + bhyt + bhtn;

    final incomeBeforeTax = gross - totalEmpIns;
    final personalDeduct = policy.personalDeductionVnd;
    final depDeduct = deps * policy.dependentDeductionVnd;
    final taxable =
        (incomeBeforeTax - personalDeduct - depDeduct).clamp(0, 5000000000);

    final activeBrackets = policy == VietnamTaxPolicy.law109Year2026
        ? pit5Brackets2026
        : pitLegacy7Brackets2025;

    final breakdown = <PitBracketBreakdown>[];
    var remainingTaxable = taxable;
    var totalPit = 0;

    for (final b in activeBrackets) {
      if (remainingTaxable <= 0) break;
      final slice = remainingTaxable > b.capVnd ? b.capVnd : remainingTaxable;
      final tax = ((slice * b.ratePct) / 100).round();
      breakdown.add(
        PitBracketBreakdown(
          level: b.level,
          label: b.label,
          ratePercent: b.ratePct,
          taxableSliceMinor: slice,
          taxMinor: tax,
        ),
      );
      totalPit += tax;
      remainingTaxable -= slice;
    }

    final net = (gross - totalEmpIns - totalPit).clamp(0, 5000000000);
    final employerIns =
        (bhxhBase * 0.175).round() + (bhxhBase * 0.03).round() + (bhtnBase * 0.01).round();

    return VietnamSalaryTaxResult(
      grossSalaryMinor: gross,
      bhxhMinor: bhxh,
      bhytMinor: bhyt,
      bhtnMinor: bhtn,
      totalEmployeeInsuranceMinor: totalEmpIns,
      personalDeductionMinor: personalDeduct,
      dependentDeductionMinor: depDeduct,
      taxableIncomeMinor: taxable,
      personalIncomeTaxMinor: totalPit,
      netSalaryMinor: net,
      totalEmployerCostMinor: gross + employerIns,
      brackets: breakdown,
    );
  }

  /// Binary searches exact Gross salary needed to achieve target Net take-home salary.
  static VietnamSalaryTaxResult fromNet({
    required int targetNetMinor,
    int dependentsCount = 0,
    VietnamTaxPolicy policy = VietnamTaxPolicy.law109Year2026,
    VietnamWageRegion region = VietnamWageRegion.region1,
  }) {
    final target = targetNetMinor.clamp(0, 2000000000);
    if (target == 0) {
      return fromGross(
        grossMinor: 0,
        dependentsCount: dependentsCount,
        policy: policy,
        region: region,
      );
    }

    var low = target;
    var high = (target * 2) + 50000000;
    for (var i = 0; i < 42; i++) {
      final mid = (low + high) ~/ 2;
      final attempt = fromGross(
        grossMinor: mid,
        dependentsCount: dependentsCount,
        policy: policy,
        region: region,
      );
      if (attempt.netSalaryMinor < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return fromGross(
      grossMinor: low,
      dependentsCount: dependentsCount,
      policy: policy,
      region: region,
    );
  }
}

// =============================================================================
// 5. UNIFIED DAILY LIFE SNAPSHOT FOR REACTIVE STREAMING
// =============================================================================

class DailyLifeSnapshot extends Equatable {
  final List<MedicationCabinetItemEntity> medications;
  final List<HealthVitalLogEntity> healthLogs;
  final EmergencyMedicalCardEntity emergencyCard;
  final List<SmartGroceryItemEntity> groceryItems;
  final List<DailyMealPlanEntity> mealPlans;
  final List<UtilityMeterReadingEntity> utilityReadings;
  final List<HomeContractMaintenanceEntity> homeContracts;
  final List<SmartLifeNoteEntity> notes;

  const DailyLifeSnapshot({
    this.medications = const [],
    this.healthLogs = const [],
    this.emergencyCard = EmergencyMedicalCardEntity.empty,
    this.groceryItems = const [],
    this.mealPlans = const [],
    this.utilityReadings = const [],
    this.homeContracts = const [],
    this.notes = const [],
  });

  static const empty = DailyLifeSnapshot();

  int get pendingGroceriesCount =>
      groceryItems.where((g) => !g.inFridgeStorage && !g.isBought).length;

  int get pendingGroceriesMinor => groceryItems
      .where((g) => !g.inFridgeStorage && !g.isBought)
      .fold<int>(0, (sum, g) => sum + g.estimatedMinor);

  int get boughtGroceriesMinor => groceryItems
      .where((g) => !g.inFridgeStorage && g.isBought)
      .fold<int>(0, (sum, g) => sum + g.estimatedMinor);

  int get fridgeItemsCount => groceryItems.where((g) => g.inFridgeStorage).length;

  int medicationsTakenCount(String dayKey) =>
      medications.where((m) => m.isTakenOn(dayKey)).length;

  @override
  List<Object?> get props => [
        medications,
        healthLogs,
        emergencyCard,
        groceryItems,
        mealPlans,
        utilityReadings,
        homeContracts,
        notes,
      ];
}
