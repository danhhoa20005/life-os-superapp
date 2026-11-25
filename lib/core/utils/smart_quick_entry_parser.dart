import '../../features/transactions/domain/entities/transaction_entities.dart';
import 'vietnamese_temporal_and_entity_resolver.dart';

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
  static const Map<String, int> _vnDigitWords = <String, int>{
    'không': 0,
    'khong': 0,
    'linh': 0,
    'lẻ': 0,
    'le': 0,
    'một': 1,
    'mot': 1,
    'mốt': 1,
    'hai': 2,
    'ba': 3,
    'bốn': 4,
    'bon': 4,
    'tư': 4,
    'tu': 4,
    'năm': 5,
    'nam': 5,
    'lăm': 5,
    'lam': 5,
    'nhăm': 5,
    'sáu': 6,
    'sau': 6,
    'bảy': 7,
    'bay': 7,
    'bẩy': 7,
    'tám': 8,
    'tam': 8,
    'chín': 9,
    'chin': 9,
    'mười': 10,
    'muoi': 10,
  };

  static const Set<String> _nonStandaloneDigitTokens = <String>{
    'không',
    'khong',
    'linh',
    'lẻ',
    'le',
    'mốt',
    'tư',
    'tu',
    'lăm',
    'lam',
    'nhăm',
  };

  static final RegExp _halfMillionRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:nửa|nua)\s+(?:triệu|trieu|củ|cu)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _halfXiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:nửa|nua)\s+xị(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _hundredHalfWithLeadRegex = RegExp(
    r'(?<![\p{L}\p{N}])(1|2|3|4|5|6|7|8|9|một|mot|hai|ba|bốn|bon|tư|tu|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)\s+(?:trăm|tram)\s+(?:rưỡi|ruoi)(?:\s*(?:nghìn|nghin|ngàn|ngan))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _bareHundredHalfRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:trăm|tram)\s+(?:rưỡi|ruoi)(?:\s*(?:nghìn|nghin|ngàn|ngan))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _spokenBeforeUnitRegex = RegExp(
    r'(?<![\p{L}\p{N}])((?:(?:không|khong|một|mot|mốt|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|lam|nhăm|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi|mươi|trăm|tram|linh|lẻ|le)\s+){1,6})(triệu|trieu|tr|củ|cu|nghìn|nghin|ngàn|ngan|xị|xi|cành|canh|nhành|nhanh|chục|chuc|lít|lit)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _millionHalfRegex = RegExp(
    r'(?<!\d)(\d+)\s*(?:triệu|trieu|tr|củ|cu)\s*(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _bareMillionHalfRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:triệu|trieu|củ|cu)\s+(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _xiSlangRegex = RegExp(
    r'(?<!\d)(\d+)(?:[.,](\d))?\s*(?:xị|xi)(?:\s*(rưỡi|ruoi))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _canhSlangRegex = RegExp(
    r'(?<!\d)(\d+)\s*(?:cành|canh|nhành|nhanh)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _chucSlangRegex = RegExp(
    r'(?<!\d)(\d+)\s*(?:chục|chuc)(?:\s*(rưỡi|ruoi))?(?:\s*(?:nghìn|nghin|ngàn|ngan))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _litSlangRegex = RegExp(
    r'(?<!\d)(\d+)(?:[.,](\d))?\s*(?:lít|lit)(?:\s*(rưỡi|ruoi))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _liquidNounFollowRegex = RegExp(
    r'^(?:nước|nuoc|xăng|xang|dầu|dau|sữa|sua|bia|rượu|ruou|cồn|ml)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _flowerBranchFollowRegex = RegExp(
    r'^(?:hoa|đào|dao|mai|cây|cay|lá|la)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _itemCountFollowRegex = RegExp(
    r'^(?:trứng|trung|quả|qua|trái|trai|cái|cai|chiếc|chiec|lon|chai|gói|goi|hộp|hop|viên|vien|bó|bo|con)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _millionUnitFollowRegex = RegExp(
    r'^(?:triệu|trieu|tr|củ|cu|tỷ|ty)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _shorthandMillion = RegExp(
    r'(?<!\d)(\d+)(?:[.,](\d{1,6}))?\s*(?:tr|triệu|trieu|củ|cu)(?:\s*(\d{1,3})\s*(?:nghìn|nghin|ngàn|ngan|k)?)?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _shorthandThousand = RegExp(
    r'(?<!\d)(\d+)(?:[.,](\d{1,3}))?\s*(?:k|nghìn|nghin|ngàn|ngan)(?:\s*(\d{1,2}))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _rawVndNumber = RegExp(
    r'(?<![\p{L}\p{N}])(\d{1,3}(?:[.,]\d{3})+|\d{4,11})(\s*(?:đ|d|₫|vnd|vnđ|đồng|dong))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _negativeMoneyRegex = RegExp(
    r'(?:^|[\s,(])(?:-\s*\d|âm\s+\d|am\s+\d)',
    caseSensitive: false,
    unicode: true,
  );

  /// Pre-normalizes colloquial Vietnamese money expressions & slang (`củ`, `xị`, `cành`/`nhành`,
  /// `chục`, `lít` when not preceding liquid/fuel nouns, `nửa triệu`/`nửa củ`, `trăm rưỡi`, `rưỡi`)
  /// using 100% exact `int` arithmetic (zero floating-point drift).
  static String normalizeColloquialMoney(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return trimmed;

    var s = trimmed;

    // 1. "nửa triệu" / "nửa củ" -> 500k; "nửa xị" -> 50k
    s = s.replaceAll(_halfMillionRegex, '500k');
    s = s.replaceAll(_halfXiRegex, '50k');

    // 2. "<1..9 | một..chín> trăm rưỡi" -> 150k..950k; bare "trăm rưỡi" -> 150k
    s = s.replaceAllMapped(_hundredHalfWithLeadRegex, (m) {
      final tok = (m.group(1) ?? '').trim().toLowerCase();
      final d = int.tryParse(tok) ?? _vnDigitWords[tok];
      if (d == null || d <= 0 || d > 9) return m.group(0)!;
      return '${d * 100 + 50}k';
    });
    s = s.replaceAll(_bareHundredHalfRegex, '150k');

    // 3. Spoken Vietnamese numbers before currency or colloquial units
    final snapshotSpoken = s;
    s = snapshotSpoken.replaceAllMapped(_spokenBeforeUnitRegex, (m) {
      final rawSpoken = m.group(1) ?? '';
      final unit = m.group(2) ?? '';
      final unitLower = unit.toLowerCase();
      final after = snapshotSpoken.substring(m.end).trimLeft();
      final before = snapshotSpoken
          .substring(0, m.start)
          .trimRight()
          .toLowerCase();

      // Guard "ngân hàng" (unaccented "ngan hang") and "máy bay" (unaccented "may bay") and "lì xì" ("li xi")
      if (unitLower == 'ngan' &&
          RegExp(
            r'^(?:hàng|hang)(?![\p{L}\p{N}])',
            caseSensitive: false,
            unicode: true,
          ).hasMatch(after)) {
        return m.group(0)!;
      }
      if (rawSpoken.trim().toLowerCase() == 'bay' &&
          (before.endsWith('máy') || before.endsWith('may'))) {
        return m.group(0)!;
      }
      if (unitLower == 'xi' &&
          (before.endsWith('lì') || before.endsWith('li'))) {
        return m.group(0)!;
      }

      final parsed = _parseSmallSpokenInt(rawSpoken);
      if (parsed == null || parsed <= 0) return m.group(0)!;
      return '$parsed $unit';
    });

    // 4. "<N> triệu/củ rưỡi" -> "<N>tr5" & bare "củ rưỡi" / "triệu rưỡi" -> "1tr5"
    s = s.replaceAllMapped(_millionHalfRegex, (m) => '${m.group(1)}tr5');
    s = s.replaceAll(_bareMillionHalfRegex, '1tr5');

    // 5. Slang "xị" (1 xị = 100k, 1 xị rưỡi = 150k)
    final snapshotXi = s;
    s = snapshotXi.replaceAllMapped(_xiSlangRegex, (m) {
      final after = snapshotXi.substring(m.end).trimLeft();
      if (RegExp(
        r'^(?:măng|mang|giày|giay)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ).hasMatch(after)) {
        return m.group(0)!;
      }
      final n = int.tryParse(m.group(1) ?? '');
      if (n == null || n <= 0) return m.group(0)!;
      final dec = m.group(2);
      final hasHalf =
          (m.group(3) != null && m.group(3)!.isNotEmpty) || dec == '5';
      final extraTens = (!hasHalf && dec != null && dec.isNotEmpty)
          ? (int.tryParse(dec) ?? 0) * 10
          : 0;
      final kVal = n * 100 + (hasHalf ? 50 : extraTens);
      return '${kVal}k';
    });

    // 6. Slang "cành" / "nhành" (1 cành = 1k)
    final snapshotCanh = s;
    s = snapshotCanh.replaceAllMapped(_canhSlangRegex, (m) {
      final after = snapshotCanh.substring(m.end).trimLeft();
      if (_flowerBranchFollowRegex.hasMatch(after)) {
        return m.group(0)!;
      }
      final n = int.tryParse(m.group(1) ?? '');
      if (n == null || n <= 0) return m.group(0)!;
      return '${n}k';
    });

    // 7. Colloquial "chục" (1 chục = 10k; "mấy chục" has no integer prefix -> untouched!)
    final snapshotChuc = s;
    s = snapshotChuc.replaceAllMapped(_chucSlangRegex, (m) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n == null || n <= 0) return m.group(0)!;
      final hasHalf = m.group(2) != null && m.group(2)!.isNotEmpty;
      final after = snapshotChuc.substring(m.end).trimLeft();
      if (!hasHalf && _millionUnitFollowRegex.hasMatch(after)) {
        return '${n * 10}';
      }
      if (_itemCountFollowRegex.hasMatch(after)) {
        return m.group(0)!;
      }
      final kVal = n * 10 + (hasHalf ? 5 : 0);
      return '${kVal}k';
    });

    // 8. Colloquial "lít" (1 lít = 100k, 1 lít rưỡi = 150k) ONLY when NOT preceding liquid/fuel nouns
    final snapshotLit = s;
    s = snapshotLit.replaceAllMapped(_litSlangRegex, (m) {
      final after = snapshotLit.substring(m.end).trimLeft();
      if (_liquidNounFollowRegex.hasMatch(after)) {
        return m.group(0)!;
      }
      final n = int.tryParse(m.group(1) ?? '');
      if (n == null || n <= 0) return m.group(0)!;
      final dec = m.group(2);
      final hasHalf =
          (m.group(3) != null && m.group(3)!.isNotEmpty) || dec == '5';
      final extraTens = (!hasHalf && dec != null && dec.isNotEmpty)
          ? (int.tryParse(dec) ?? 0) * 10
          : 0;
      final kVal = n * 100 + (hasHalf ? 50 : extraTens);
      return '${kVal}k';
    });

    return s;
  }

  static int? _parseSmallSpokenInt(String phrase) {
    final tokens = phrase
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;
    if (tokens.length == 1 &&
        _nonStandaloneDigitTokens.contains(tokens.first)) {
      return null;
    }

    var hundreds = 0;
    var tens = 0;
    var ones = 0;
    var i = 0;

    if (i + 1 < tokens.length &&
        (tokens[i + 1] == 'trăm' || tokens[i + 1] == 'tram')) {
      final h = _vnDigitWords[tokens[i]];
      if (h == null || h <= 0 || h > 9) return null;
      hundreds = h * 100;
      i += 2;
      if (i < tokens.length &&
          (tokens[i] == 'linh' || tokens[i] == 'lẻ' || tokens[i] == 'le')) {
        i++;
      }
    }

    if (i < tokens.length) {
      if (tokens[i] == 'mười' || tokens[i] == 'muoi') {
        tens = 10;
        i++;
        if (i < tokens.length && _vnDigitWords.containsKey(tokens[i])) {
          ones = _vnDigitWords[tokens[i]]!;
          i++;
        }
      } else if (i + 1 < tokens.length &&
          (tokens[i + 1] == 'mươi' || tokens[i + 1] == 'muoi')) {
        final t = _vnDigitWords[tokens[i]];
        if (t == null || t <= 0 || t > 9) return null;
        tens = t * 10;
        i += 2;
        if (i < tokens.length && _vnDigitWords.containsKey(tokens[i])) {
          ones = _vnDigitWords[tokens[i]]!;
          i++;
        }
      } else if (i + 1 == tokens.length - 1 &&
          hundreds == 0 &&
          _vnDigitWords.containsKey(tokens[i]) &&
          (_vnDigitWords[tokens[i]] ?? 0) >= 2 &&
          (_vnDigitWords[tokens[i]] ?? 0) <= 9 &&
          const {
            'mốt',
            'tư',
            'tu',
            'lăm',
            'lam',
            'nhăm',
          }.contains(tokens[i + 1])) {
        // Shorthand spoken two-digit ("ba lăm" -> 35, "hai mốt" -> 21, "bốn tư" -> 44)
        tens = _vnDigitWords[tokens[i]]! * 10;
        ones = _vnDigitWords[tokens[i + 1]]!;
        i += 2;
      } else if (_vnDigitWords.containsKey(tokens[i])) {
        ones = _vnDigitWords[tokens[i]]!;
        i++;
      }
    }

    if (i != tokens.length) return null;
    final total = hundreds + tens + ones;
    return total > 0 ? total : null;
  }

  static ParsedSmartEntry? tryParse(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

    // Section 13: Chặn mệnh đề phủ định, giả định, hỏi ý kiến hoặc hỏi số dư.
    if (ClauseSafetyScreener.screenClause(trimmed).isBlocked) {
      return null;
    }

    // FIX-004: Không tự ép số âm ("-500k", "âm 500k") thành giao dịch dương.
    if (_negativeMoneyRegex.hasMatch(trimmed)) {
      return null;
    }

    final normalized = normalizeColloquialMoney(trimmed);
    if (normalized.isEmpty) return null;

    int? amountMinor;
    String matchedToken = '';

    final mMatch = _shorthandMillion.firstMatch(normalized);
    if (mMatch != null) {
      matchedToken = mMatch.group(0) ?? '';
      final wholeMil = int.tryParse(mMatch.group(1) ?? '') ?? 0;
      final decDigits = mMatch.group(2);
      final tail = mMatch.group(3);
      var total = wholeMil * 1000000;
      if (decDigits != null && decDigits.isNotEmpty) {
        final padded = decDigits.padRight(6, '0').substring(0, 6);
        total += int.parse(padded);
      } else if (tail != null && tail.isNotEmpty) {
        final tailVal = int.tryParse(tail) ?? 0;
        final lowerToken = matchedToken.toLowerCase();
        final hasExplicitThousandWord =
            lowerToken.contains('nghìn') ||
            lowerToken.contains('nghin') ||
            lowerToken.contains('ngàn') ||
            lowerToken.contains('ngan') ||
            lowerToken.endsWith('k');
        if (hasExplicitThousandWord) {
          total += tailVal * 1000;
        } else {
          final scale = switch (tail.length) {
            1 => 100000,
            2 => 10000,
            _ => 1000,
          };
          total += tailVal * scale;
        }
      }
      amountMinor = total;
    } else {
      final kMatch = _shorthandThousand.firstMatch(normalized);
      if (kMatch != null) {
        matchedToken = kMatch.group(0) ?? '';
        final wholeK = int.tryParse(kMatch.group(1) ?? '') ?? 0;
        final decDigits = kMatch.group(2);
        final tail = kMatch.group(3);
        var total = wholeK * 1000;
        if (decDigits != null && decDigits.isNotEmpty) {
          final padded = decDigits.padRight(3, '0').substring(0, 3);
          total += int.parse(padded);
        } else if (tail != null && tail.isNotEmpty) {
          final scale = tail.length == 1 ? 100 : 10;
          total += (int.tryParse(tail) ?? 0) * scale;
        }
        amountMinor = total;
      } else {
        for (final rawMatch in _rawVndNumber.allMatches(normalized)) {
          final hasCurrencySuffix = (rawMatch.group(2) ?? '').trim().isNotEmpty;
          if (VietnameseTemporalAndEntityResolver.isFollowedByNonCurrencyUnit(
            normalized,
            rawMatch.end,
            hasExplicitCurrencySuffix: hasCurrencySuffix,
          )) {
            continue;
          }
          matchedToken = rawMatch.group(0) ?? '';
          final digits = (rawMatch.group(1) ?? '').replaceAll(
            RegExp(r'[.,]'),
            '',
          );
          amountMinor = int.tryParse(digits);
          break;
        }
      }
    }

    if (amountMinor == null || amountMinor <= 0) return null;

    var description = normalized.replaceFirst(matchedToken, '').trim();
    description = description
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[-:,.\s]+|[-:,.\s]+$'), '');
    if (description.isEmpty) {
      description = 'Giao dịch ghi nhanh';
    } else {
      description =
          '${description[0].toUpperCase()}${description.substring(1)}';
    }

    final lower = normalized.toLowerCase();

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
    if (RegExp(
          r'(?<![\p{L}\p{N}])cf(?![\p{L}\p{N}])',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(lower) ||
        _containsAny(lower, const [
          'phở',
          'pho',
          'cơm',
          'com',
          'bún',
          'bun',
          'mì',
          'cafe',
          'cà phê',
          'ca phe',
          'caphe',
          'trà sữa',
          'tra sua',
          'trà đá',
          'tra da',
          'ăn ',
          'an sáng',
          'ăn sáng',
          'ăn trưa',
          'ăn tối',
          'lẩu',
          'nướng',
          'bánh',
          'nhậu',
          'nhau',
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
