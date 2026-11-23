import 'dart:math' as math;

import 'package:equatable/equatable.dart';

// ============================================================================
// 1. SUBSCRIPTION & APPLIANCE WARRANTY RADAR (Replaces Rocket Money / Bobby)
// ============================================================================

enum SubscriptionCycle { monthly, quarterly, yearly, warrantyOnly }

extension SubscriptionCycleX on SubscriptionCycle {
  String get key => name;

  String get labelVi => switch (this) {
    SubscriptionCycle.monthly => 'Hằng tháng',
    SubscriptionCycle.quarterly => 'Mỗi 3 tháng',
    SubscriptionCycle.yearly => 'Hằng năm',
    SubscriptionCycle.warrantyOnly => 'Phiếu bảo hành',
  };

  static SubscriptionCycle fromKey(String? raw) {
    return SubscriptionCycle.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => SubscriptionCycle.monthly,
    );
  }
}

class SubscriptionWarrantyEntity extends Equatable {
  final String id;
  final String ownerId;
  final String title;
  final String providerOrStore;
  final SubscriptionCycle cycle;
  final int amountMinor;
  final DateTime nextBillingOrExpiryDate;
  final int remindDaysBefore;
  final String serialOrNote;
  final bool autoRenew;

  const SubscriptionWarrantyEntity({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.providerOrStore,
    required this.cycle,
    required this.amountMinor,
    required this.nextBillingOrExpiryDate,
    this.remindDaysBefore = 3,
    this.serialOrNote = '',
    this.autoRenew = true,
  });

  bool get isWarranty => cycle == SubscriptionCycle.warrantyOnly;

  int get monthlyEquivalentMinor => switch (cycle) {
    SubscriptionCycle.monthly => amountMinor,
    SubscriptionCycle.quarterly => amountMinor ~/ 3,
    SubscriptionCycle.yearly => amountMinor ~/ 12,
    SubscriptionCycle.warrantyOnly => 0,
  };

  int get annualBurnMinor => switch (cycle) {
    SubscriptionCycle.monthly => amountMinor * 12,
    SubscriptionCycle.quarterly => amountMinor * 4,
    SubscriptionCycle.yearly => amountMinor,
    SubscriptionCycle.warrantyOnly => 0,
  };

  int daysRemainingFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(
      nextBillingOrExpiryDate.year,
      nextBillingOrExpiryDate.month,
      nextBillingOrExpiryDate.day,
    );
    return target.difference(today).inDays;
  }

  bool isDueSoon(DateTime now) {
    final d = daysRemainingFrom(now);
    if (isWarranty) return d >= 0 && d <= 30;
    return d >= 0 && d <= remindDaysBefore;
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    title,
    providerOrStore,
    cycle,
    amountMinor,
    nextBillingOrExpiryDate,
    remindDaysBefore,
    serialOrNote,
    autoRenew,
  ];
}

// ============================================================================
// 2. HABIT STREAKS, HYDRATION & POMODORO FOCUS (Replaces Habitify / Forest)
// ============================================================================

class LifeHabitEntity extends Equatable {
  final String id;
  final String ownerId;
  final String title;
  final String categoryTag; // 'Tài chính' | 'Sức khỏe' | 'Học tập'
  final List<String> completedDateKeys; // 'YYYY-MM-DD'

  const LifeHabitEntity({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.categoryTag,
    required this.completedDateKeys,
  });

  static String formatDayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  bool isCompletedOn(DateTime date) =>
      completedDateKeys.contains(formatDayKey(date));

  int currentStreakAt(DateTime today) {
    final set = completedDateKeys.toSet();
    var cursor = DateTime(today.year, today.month, today.day);
    if (!set.contains(formatDayKey(cursor))) {
      final yesterday = cursor.subtract(const Duration(days: 1));
      if (!set.contains(formatDayKey(yesterday))) return 0;
      cursor = yesterday;
    }
    var streak = 0;
    while (set.contains(formatDayKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    title,
    categoryTag,
    completedDateKeys,
  ];
}

class DailyWellnessEntity extends Equatable {
  final String dateKey;
  final int waterMl;
  final int targetWaterMl;
  final int focusMinutes;
  final int completedPomodoros;

  const DailyWellnessEntity({
    required this.dateKey,
    this.waterMl = 0,
    this.targetWaterMl = 2000,
    this.focusMinutes = 0,
    this.completedPomodoros = 0,
  });

  int get waterProgressPct => targetWaterMl > 0
      ? ((waterMl * 100) / targetWaterMl).clamp(0, 100).round()
      : 0;

  @override
  List<Object?> get props => [
    dateKey,
    waterMl,
    targetWaterMl,
    focusMinutes,
    completedPomodoros,
  ];
}

// ============================================================================
// 3. SỔ HIẾU HỶ "CÓ ĐI CÓ LẠI" & TRAVEL PACKING (Replaces Gift Ledger / Tripsy)
// ============================================================================

enum GiftDirection { gave, received }

enum GiftOccasion { wedding, housewarming, fullMonth, tetHoliday, visitHealth }

extension GiftOccasionX on GiftOccasion {
  String get labelVi => switch (this) {
    GiftOccasion.wedding => 'Đám cưới',
    GiftOccasion.housewarming => 'Tân gia',
    GiftOccasion.fullMonth => 'Đầy tháng / Thôi nôi',
    GiftOccasion.tetHoliday => 'Mừng tuổi / Lễ Tết',
    GiftOccasion.visitHealth => 'Thăm hỏi / Hiếu hỷ',
  };

  static GiftOccasion fromKey(String? raw) {
    return GiftOccasion.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => GiftOccasion.wedding,
    );
  }
}

class GiftLedgerEntryEntity extends Equatable {
  final String id;
  final String ownerId;
  final String contactName;
  final String
  relationshipGroup; // 'Đồng nghiệp' | 'Bạn học' | 'Họ hàng' | 'Đối tác'
  final GiftDirection direction;
  final GiftOccasion occasion;
  final int amountMinor;
  final String note;
  final DateTime eventDate;

  const GiftLedgerEntryEntity({
    required this.id,
    required this.ownerId,
    required this.contactName,
    required this.relationshipGroup,
    required this.direction,
    required this.occasion,
    required this.amountMinor,
    this.note = '',
    required this.eventDate,
  });

  @override
  List<Object?> get props => [
    id,
    ownerId,
    contactName,
    relationshipGroup,
    direction,
    occasion,
    amountMinor,
    note,
    eventDate,
  ];
}

class PackingChecklistItemEntity extends Equatable {
  final String id;
  final String ownerId;
  final String tripName;
  final String title;
  final bool checked;

  const PackingChecklistItemEntity({
    required this.id,
    required this.ownerId,
    required this.tripName,
    required this.title,
    required this.checked,
  });

  @override
  List<Object?> get props => [id, ownerId, tripName, title, checked];
}

// ============================================================================
// 4. PURE-DART PRO FINANCIAL ENGINES (Receipt OCR NLP · Loan · FIRE & 6-Jars)
// ============================================================================

class ParsedReceiptLineItem extends Equatable {
  final String name;
  final int amountMinor;

  const ParsedReceiptLineItem({required this.name, required this.amountMinor});

  @override
  List<Object?> get props => [name, amountMinor];
}

class ParsedReceiptResult extends Equatable {
  final String merchant;
  final String suggestedCategory;
  final List<ParsedReceiptLineItem> items;
  final int totalMinor;

  const ParsedReceiptResult({
    required this.merchant,
    required this.suggestedCategory,
    required this.items,
    required this.totalMinor,
  });

  @override
  List<Object?> get props => [merchant, suggestedCategory, items, totalMinor];
}

/// Pure-Dart Vietnamese Receipt & Invoice Text Parser (replaces paid OCR bill scanners).
abstract final class SmartReceiptParserEngine {
  static final RegExp _totalKeywordRegex = RegExp(
    r'(?:tổng\s*(?:cộng|tiền|thanh\s*toán)?|thành\s*tiền|total|thanh\s*toán)\s*[:=-]?\s*([\d.,]+)\s*(k|nghìn|ngàn|đ|₫|vnd)?',
    caseSensitive: false,
  );

  static final RegExp _linePriceRegex = RegExp(
    r'^(.+?)\s+([\d]{1,3}(?:[.,]\d{3})+|\d+)\s*(k|nghìn|ngàn|đ|₫|vnd)?$',
    caseSensitive: false,
  );

  static int _parseAmountToken(String numPart, String? unitPart) {
    final u = (unitPart ?? '').trim().toLowerCase();
    final digitsOnly = numPart.replaceAll(RegExp(r'[.,]'), '');
    final base = int.tryParse(digitsOnly) ?? 0;
    if (base <= 0) return 0;
    if (u == 'k' || u == 'nghìn' || u == 'ngàn') {
      return base < 100000 ? base * 1000 : base;
    }
    // Without an explicit 'k'/'nghìn' unit, require >= 1,000 VND so street/district numbers ("Quận 7") are never misparsed as prices!
    if (base < 1000) return 0;
    return base;
  }

  static ParsedReceiptResult parse(String rawText) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const ParsedReceiptResult(
        merchant: 'Hóa đơn bán lẻ',
        suggestedCategory: 'Mua sắm',
        items: [],
        totalMinor: 0,
      );
    }

    var merchant = lines.first;
    var explicitTotal = 0;
    final items = <ParsedReceiptLineItem>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final totalMatch = _totalKeywordRegex.firstMatch(line);
      if (totalMatch != null) {
        explicitTotal = _parseAmountToken(
          totalMatch.group(1)!,
          totalMatch.group(2),
        );
        continue;
      }

      final itemMatch = _linePriceRegex.firstMatch(line);
      if (itemMatch != null) {
        final rawName = itemMatch.group(1)!.trim();
        final amt = _parseAmountToken(itemMatch.group(2)!, itemMatch.group(3));
        if (amt >= 1000 && rawName.length >= 2) {
          items.add(ParsedReceiptLineItem(name: rawName, amountMinor: amt));
          if (i == 0) {
            merchant = 'Hóa đơn Mua hàng';
          }
        }
      }
    }

    final sumItems = items.fold<int>(0, (s, it) => s + it.amountMinor);
    final total = explicitTotal > 0 ? explicitTotal : sumItems;

    final lowerAll = rawText.toLowerCase();
    final category =
        (lowerAll.contains('tiền điện') ||
            lowerAll.contains('tiền nước') ||
            lowerAll.contains('hóa đơn điện') ||
            lowerAll.contains('internet') ||
            lowerAll.contains('evn'))
        ? 'Điện/Nước/Internet'
        : (lowerAll.contains('siêu thị') ||
              lowerAll.contains('co.opmart') ||
              lowerAll.contains('winmart') ||
              lowerAll.contains('rửa chén') ||
              lowerAll.contains('bột giặt'))
        ? 'Việc nhà & Gia dụng'
        : (lowerAll.contains('phở') ||
              lowerAll.contains('cà phê') ||
              lowerAll.contains('trà') ||
              lowerAll.contains('cơm') ||
              lowerAll.contains('bún') ||
              lowerAll.contains('lẩu') ||
              lowerAll.contains('grabfood') ||
              lowerAll.contains('highlands'))
        ? 'Ăn uống'
        : (lowerAll.contains('xăng') || lowerAll.contains('grab'))
        ? 'Xe cộ & Di chuyển'
        : 'Việc nhà & Gia dụng';

    return ParsedReceiptResult(
      merchant: merchant,
      suggestedCategory: category,
      items: items,
      totalMinor: total,
    );
  }
}

class LoanSchedulePreview extends Equatable {
  final int firstMonthPaymentMinor;
  final int lastMonthPaymentMinor;
  final int averageMonthlyPaymentMinor;
  final int totalInterestMinor;
  final int totalPayableMinor;

  const LoanSchedulePreview({
    required this.firstMonthPaymentMinor,
    required this.lastMonthPaymentMinor,
    required this.averageMonthlyPaymentMinor,
    required this.totalInterestMinor,
    required this.totalPayableMinor,
  });

  @override
  List<Object?> get props => [
    firstMonthPaymentMinor,
    lastMonthPaymentMinor,
    averageMonthlyPaymentMinor,
    totalInterestMinor,
    totalPayableMinor,
  ];
}

/// Pure-Dart Loan & Mortgage Amortization Calculator (Declining Balance & Annuity EMI).
abstract final class LoanAmortizationEngine {
  static LoanSchedulePreview calculate({
    required int principalMinor,
    required double annualRatePct,
    required int termMonths,
    required bool decliningBalance,
  }) {
    if (principalMinor <= 0 || termMonths <= 0) {
      return const LoanSchedulePreview(
        firstMonthPaymentMinor: 0,
        lastMonthPaymentMinor: 0,
        averageMonthlyPaymentMinor: 0,
        totalInterestMinor: 0,
        totalPayableMinor: 0,
      );
    }

    final monthlyRate = (annualRatePct / 100.0) / 12.0;
    if (monthlyRate <= 0) {
      final monthly = principalMinor ~/ termMonths;
      return LoanSchedulePreview(
        firstMonthPaymentMinor: monthly,
        lastMonthPaymentMinor: monthly,
        averageMonthlyPaymentMinor: monthly,
        totalInterestMinor: 0,
        totalPayableMinor: principalMinor,
      );
    }

    if (decliningBalance) {
      // Dư nợ giảm dần (phổ biến tại ngân hàng Việt Nam khi vay mua nhà / xe)
      final monthlyPrincipal = principalMinor / termMonths;
      final firstInterest = principalMinor * monthlyRate;
      final lastInterest = monthlyPrincipal * monthlyRate;
      final totalInterest =
          (principalMinor * monthlyRate * (termMonths + 1) / 2.0).round();
      final totalPayable = principalMinor + totalInterest;
      return LoanSchedulePreview(
        firstMonthPaymentMinor: (monthlyPrincipal + firstInterest).round(),
        lastMonthPaymentMinor: (monthlyPrincipal + lastInterest).round(),
        averageMonthlyPaymentMinor: (totalPayable / termMonths).round(),
        totalInterestMinor: totalInterest,
        totalPayableMinor: totalPayable,
      );
    } else {
      // Trả góp đều hằng tháng (Annuity / EMI)
      final factor = math.pow(1 + monthlyRate, termMonths);
      final emi = (principalMinor * monthlyRate * factor / (factor - 1))
          .round();
      final totalPayable = emi * termMonths;
      final totalInterest = math.max(0, totalPayable - principalMinor);
      return LoanSchedulePreview(
        firstMonthPaymentMinor: emi,
        lastMonthPaymentMinor: emi,
        averageMonthlyPaymentMinor: emi,
        totalInterestMinor: totalInterest,
        totalPayableMinor: totalPayable,
      );
    }
  }
}

class FireSimulationResult extends Equatable {
  final int fireNumberMinor; // 25x annual expenses (4% rule)
  final double yearsToFire;
  final int projected10YearNetWorthMinor;
  final Map<String, int> sixJarsMonthlyAllocation;

  const FireSimulationResult({
    required this.fireNumberMinor,
    required this.yearsToFire,
    required this.projected10YearNetWorthMinor,
    required this.sixJarsMonthlyAllocation,
  });

  @override
  List<Object?> get props => [
    fireNumberMinor,
    yearsToFire,
    projected10YearNetWorthMinor,
    sixJarsMonthlyAllocation,
  ];
}

/// Pure-Dart Financial Independence (FIRE 4% Rule) & 6-Jars Wealth Allocator.
abstract final class FireWealthSimulatorEngine {
  static FireSimulationResult simulate({
    required int currentNetWorthMinor,
    required int monthlyIncomeMinor,
    required int monthlyExpenseMinor,
    required double expectedAnnualReturnPct,
  }) {
    final safeExpense = math.max(1000000, monthlyExpenseMinor);
    final fireTarget = safeExpense * 12 * 25; // 4% safe withdrawal rule
    final monthlySavings = math.max(
      0,
      monthlyIncomeMinor - monthlyExpenseMinor,
    );
    final rMonthly = (expectedAnnualReturnPct / 100.0) / 12.0;

    var balance = math.max(0, currentNetWorthMinor).toDouble();
    var months = 0;
    while (balance < fireTarget && months < 600) {
      balance = balance * (1 + rMonthly) + monthlySavings;
      months++;
    }

    var tenYr = math.max(0, currentNetWorthMinor).toDouble();
    for (var m = 0; m < 120; m++) {
      tenYr = tenYr * (1 + rMonthly) + monthlySavings;
    }

    final inc = math.max(0, monthlyIncomeMinor);
    final jars = <String, int>{
      'Thiết yếu (55%)': (inc * 55) ~/ 100,
      'Tự do Tài chính (10%)': (inc * 10) ~/ 100,
      'Tiết kiệm Dài hạn (10%)': (inc * 10) ~/ 100,
      'Giáo dục & Phát triển (10%)': (inc * 10) ~/ 100,
      'Hưởng thụ Cân bằng (10%)': (inc * 10) ~/ 100,
      'Cho đi & Hiếu hỷ (5%)': inc - ((inc * 95) ~/ 100),
    };

    return FireSimulationResult(
      fireNumberMinor: fireTarget,
      yearsToFire: months / 12.0,
      projected10YearNetWorthMinor: tenYr.round(),
      sixJarsMonthlyAllocation: jars,
    );
  }
}
