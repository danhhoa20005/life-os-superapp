import '../../features/transactions/domain/entities/transaction_entities.dart';

class ParsedSmartEntry {
  final int amountMinor;
  final TransactionKind kind;
  final String categoryId;
  final String categoryName;
  final String merchant;

  const ParsedSmartEntry({
    required this.amountMinor,
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    required this.merchant,
  });
}

/// Parses natural Vietnamese shorthand like:
/// - "ăn phở bò 65k" -> 65,000 VND, Expense, Ăn uống
/// - "nhận lương tháng 11 18tr5" -> 18,500,000 VND, Income, Lương & Thu nhập
/// - "tiền điện 850k" -> 850,000 VND, Expense, Điện/Nước/Internet
/// - "mua nước giặt 145k" -> 145,000 VND, Expense, Việc nhà & Gia dụng
abstract final class SmartQuickEntryParser {
  static final RegExp _shorthandMillion = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:tr|triệu|trieu|củ|cu)(?:\s*(\d{1,3}))?\b',
    caseSensitive: false,
  );

  static final RegExp _shorthandThousand = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:k|nghìn|nghin|ngàn|ngan)(?:\s*(\d{1,2}))?\b',
    caseSensitive: false,
  );

  static final RegExp _rawVndNumber = RegExp(
    r'\b(\d{1,3}(?:[.,]\d{3})+|\d{4,11})\s*(?:đ|d|vnd|vnđ)?\b',
    caseSensitive: false,
  );

  static ParsedSmartEntry? tryParse(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

    int? amountMinor;
    String matchedToken = '';

    final mMatch = _shorthandMillion.firstMatch(trimmed);
    if (mMatch != null) {
      matchedToken = mMatch.group(0) ?? '';
      final base =
          double.tryParse((mMatch.group(1) ?? '0').replaceAll(',', '.')) ?? 0;
      final tail = mMatch.group(2);
      var total = (base * 1000000).round();
      if (tail != null && tail.isNotEmpty) {
        final scale = switch (tail.length) {
          1 => 100000,
          2 => 10000,
          _ => 1000,
        };
        total += (int.tryParse(tail) ?? 0) * scale;
      }
      amountMinor = total;
    } else {
      final kMatch = _shorthandThousand.firstMatch(trimmed);
      if (kMatch != null) {
        matchedToken = kMatch.group(0) ?? '';
        final base =
            double.tryParse((kMatch.group(1) ?? '0').replaceAll(',', '.')) ?? 0;
        final tail = kMatch.group(2);
        var total = (base * 1000).round();
        if (tail != null && tail.isNotEmpty) {
          final scale = tail.length == 1 ? 100 : 10;
          total += (int.tryParse(tail) ?? 0) * scale;
        }
        amountMinor = total;
      } else {
        final rawMatch = _rawVndNumber.firstMatch(trimmed);
        if (rawMatch != null) {
          matchedToken = rawMatch.group(0) ?? '';
          final digits = (rawMatch.group(1) ?? '').replaceAll(
            RegExp(r'[.,]'),
            '',
          );
          amountMinor = int.tryParse(digits);
        }
      }
    }

    if (amountMinor == null || amountMinor <= 0) return null;

    var description = trimmed.replaceFirst(matchedToken, '').trim();
    description = description
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[-:,.\s]+|[-:,.\s]+$'), '');
    if (description.isEmpty) {
      description = 'Giao dịch ghi nhanh';
    } else {
      description =
          '${description[0].toUpperCase()}${description.substring(1)}';
    }

    final lower = trimmed.toLowerCase();

    // Detect Income vs Expense
    final isIncome = _containsAny(lower, const [
      'lương',
      'luong',
      'thưởng',
      'thuong',
      'nhận tiền',
      'nhan tien',
      'thu nhập',
      'thu nhap',
      'hoàn tiền',
      'hoan tien',
      'cổ tức',
      'lãi tiết kiệm',
      'freelance',
    ]);

    if (isIncome) {
      final isSalary = _containsAny(lower, const [
        'lương',
        'luong',
        'thưởng',
        'thuong',
        'freelance',
      ]);
      return ParsedSmartEntry(
        amountMinor: amountMinor,
        kind: TransactionKind.income,
        categoryId: isSalary ? 'cat_salary' : 'cat_other_inc',
        categoryName: isSalary ? 'Lương & Thu nhập' : 'Thu nhập khác',
        merchant: description,
      );
    }

    final (catId, catName) = _classifyExpenseCategory(lower);
    return ParsedSmartEntry(
      amountMinor: amountMinor,
      kind: TransactionKind.expense,
      categoryId: catId,
      categoryName: catName,
      merchant: description,
    );
  }

  static (String, String) _classifyExpenseCategory(String lower) {
    if (_containsAny(lower, const [
      'phở',
      'pho',
      'cơm',
      'com',
      'bún',
      'bun',
      'mì',
      'cafe',
      'cà phê',
      'trà sữa',
      'tra sua',
      'ăn ',
      'an sáng',
      'ăn sáng',
      'ăn trưa',
      'ăn tối',
      'lẩu',
      'nướng',
      'bánh',
      'nhậu',
      'highlands',
      'phúc long',
    ])) {
      return ('cat_food', 'Ăn uống');
    }
    if (_containsAny(lower, const [
      'nước giặt',
      'nước rửa',
      'lau nhà',
      'rác',
      'dọn nhà',
      'giấy vệ sinh',
      'việc nhà',
      'gia dụng',
    ])) {
      return ('cat_housework', 'Việc nhà & Gia dụng');
    }
    if (_containsAny(lower, const [
      'tiền nhà',
      'thuê nhà',
      'tiền phòng',
      'tiền trọ',
      'chung cư',
    ])) {
      return ('cat_housing', 'Nhà cửa & Thuê nhà');
    }
    if (_containsAny(lower, const [
      'điện',
      'nước',
      'wifi',
      'internet',
      '4g',
      '5g',
      'viễn thông',
      'cáp',
    ])) {
      return ('cat_utilities', 'Điện/Nước/Internet');
    }
    if (_containsAny(lower, const [
      'xăng',
      'xang',
      'grab',
      'be ',
      'xanh sm',
      'taxi',
      'gửi xe',
      'gui xe',
      'vé xe',
      'trạm thu phí',
    ])) {
      return ('cat_vehicle', 'Xe cộ & Di chuyển');
    }
    if (_containsAny(lower, const [
      'thay nhớt',
      'sửa xe',
      'bảo dưỡng',
      'rửa xe',
      'lốp xe',
    ])) {
      return ('cat_vehicle_maint', 'Bảo dưỡng & Sửa xe');
    }
    if (_containsAny(lower, const [
      'thuốc',
      'khám',
      'bệnh viện',
      'nha khoa',
      'học phí',
      'sách',
      'khóa học',
      'gym',
    ])) {
      return ('cat_health', 'Sức khỏe & Giáo dục');
    }
    if (_containsAny(lower, const [
      'siêu thị',
      'chợ',
      'shopee',
      'lazada',
      'tiktok',
      'mua sắm',
      'quần áo',
    ])) {
      return ('cat_shopping', 'Chợ & Mua sắm');
    }
    if (_containsAny(lower, const [
      'netflix',
      'spotify',
      'youtube',
      'xem phim',
      'du lịch',
      'game',
    ])) {
      return ('cat_entertainment', 'Giải trí & Đăng ký');
    }
    if (_containsAny(lower, const [
      'mừng cưới',
      'đám cưới',
      'thăm bệnh',
      'biếu',
      'lì xì',
      'quà',
    ])) {
      return ('cat_family_social', 'Hiếu hỉ & Đối ngoại');
    }
    if (_containsAny(lower, const ['trả nợ', 'tra no', 'cho vay', 'trả góp'])) {
      return ('cat_debt', 'Trả nợ & Cho vay');
    }
    return ('cat_other_exp', 'Chi tiêu khác');
  }

  static bool _containsAny(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }
}

/// Computes Emergency Fund Runway & actionable personal financial health insights.
class EmergencyRunwaySnapshot {
  final double monthsOfRunway;
  final int recommendedSixMonthMinor;
  final int shortfallMinor;
  final String statusBadge;
  final String headline;

  const EmergencyRunwaySnapshot({
    required this.monthsOfRunway,
    required this.recommendedSixMonthMinor,
    required this.shortfallMinor,
    required this.statusBadge,
    required this.headline,
  });

  factory EmergencyRunwaySnapshot.compute({
    required int netLiquidMinor,
    required int monthlyExpenseMinor,
  }) {
    final baselineExpense = monthlyExpenseMinor > 0
        ? monthlyExpenseMinor
        : 8000000;
    final safeLiquid = netLiquidMinor > 0 ? netLiquidMinor : 0;
    final months = safeLiquid / baselineExpense;
    final target6M = baselineExpense * 6;
    final shortfall = (target6M - safeLiquid) > 0 ? (target6M - safeLiquid) : 0;

    final (badge, headline) = switch (months) {
      >= 6.0 => (
        'An toàn Vững vàng (≥ 6 tháng)',
        'Quỹ dự phòng đủ trang trải ${months.toStringAsFixed(1)} tháng chi phí sinh hoạt.',
      ),
      >= 3.0 => (
        'Khá an toàn (3–6 tháng)',
        'Đủ dự phòng ${months.toStringAsFixed(1)} tháng. Nên tích lũy thêm lên mốc 6 tháng.',
      ),
      >= 1.0 => (
        'Mỏng (< 3 tháng)',
        'Quỹ dự phòng hiện đạt ${months.toStringAsFixed(1)} tháng chi tiêu.',
      ),
      _ => (
        'Cần ưu tiên tích lũy',
        'Hãy trích tối thiểu 10–20% thu nhập vào Quỹ dự phòng khẩn cấp.',
      ),
    };

    return EmergencyRunwaySnapshot(
      monthsOfRunway: months,
      recommendedSixMonthMinor: target6M,
      shortfallMinor: shortfall,
      statusBadge: badge,
      headline: headline,
    );
  }
}
