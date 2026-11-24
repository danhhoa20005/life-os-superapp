import '../../../../core/security/bank_notification_parser.dart';
import '../../domain/entities/financial_ai_entities.dart';

/// Result of parsing a monetary amount in integer minor units (ZERO floating-point math!).
class ParsedMonetaryAmount {
  final int amountMinor;
  final String currencyCode;
  final int decimalDigits;
  final String matchedToken;
  final int startIndex;
  final int endIndex;
  final double confidence;
  final bool isAmbiguous;

  const ParsedMonetaryAmount({
    required this.amountMinor,
    this.currencyCode = 'VND',
    this.decimalDigits = 0,
    required this.matchedToken,
    required this.startIndex,
    required this.endIndex,
    required this.confidence,
    this.isAmbiguous = false,
  });
}

class ParsedRelativeDate {
  final DateTime resolvedDateTime;
  final String matchedPhrase;
  final bool isAmbiguous;

  const ParsedRelativeDate({
    required this.resolvedDateTime,
    required this.matchedPhrase,
    this.isAmbiguous = false,
  });
}

/// Phase 4 — Comprehensive Vietnamese Financial Text Normalizer:
/// - Handles accented & unaccented Vietnamese (`ăn sáng` / `an sang`).
/// - Expands banking & everyday abbreviations (`cf`, `ck`, `atm`, `tgdd`, `bhx`, `evn`...).
/// - Converts spoken Vietnamese numbers (`mười hai triệu`, `hai triệu ba trăm nghìn`, `rưỡi`).
/// - Parses all currency formats using exact integer arithmetic (zero `double` rounding drift!).
/// - Resolves relative Vietnamese dates via injectable [FinancialClock].
/// - Redacts OTP/PIN/card numbers before any AI processing.
class FinancialTextNormalizer {
  final FinancialClock _clock;

  // Bounded LRU-like normalization cache (Phase 19.9)
  final Map<String, String> _classifierNormCache = <String, String>{};
  static const int _maxCacheEntries = 256;

  FinancialTextNormalizer({FinancialClock clock = const SystemFinancialClock()})
    : _clock = clock;

  DateTime currentReferenceTime() => _clock.now();

  /// Exact same abbreviation map as `tools/financial_ai/feature_spec.py` (train-serve parity).
  static const Map<String, String> kClassifierAbbreviations = <String, String>{
    'cf': 'cà phê',
    'cafe': 'cà phê',
    'caphe': 'cà phê',
    'ck': 'chuyển khoản',
    'bhxh': 'bảo hiểm xã hội',
    'bhyt': 'bảo hiểm y tế',
    'tgdd': 'thế giới di động',
    'dmx': 'điện máy xanh',
    'bhx': 'bách hóa xanh',
    'gs25': 'siêu thị gs25',
    'kfc': 'gà rán kfc',
    'cgv': 'rạp phim cgv',
    'lotte': 'siêu thị lotte',
    'evn': 'tiền điện evn',
    'vnpt': 'viễn thông vnpt',
    'fpt': 'internet fpt',
    'spt': 'spotify',
    'ytb': 'youtube',
    'fb': 'facebook',
    'grabbike': 'grab xe ôm',
    'grabcar': 'grab taxi',
    'gsm': 'xanh sm taxi',
    'xanhsm': 'xanh sm taxi',
    'bsx': 'bảo dưỡng sửa xe',
    'nsd': 'nhông sên dĩa sửa xe',
  };

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

  static const Map<String, String> _diacriticFoldMap = <String, String>{
    'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
    'đ': 'd',
    'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
    'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
    'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
    'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
  };

  /// Strips all Vietnamese diacritics to lowercase ASCII (identical to `strip_vn_accents` in Python).
  static String stripVnAccents(String input) {
    final lower = input.toLowerCase();
    final sb = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      sb.write(_diacriticFoldMap[ch] ?? ch);
    }
    return sb.toString();
  }

  /// Normalizes user/bank/ASR text while preserving semantic tokens for extraction.
  String normalizeText(String rawText) {
    if (rawText.trim().isEmpty) return '';
    var s = OtpRedactor.redact(rawText.trim());
    s = _normalizeSpokenNumbers(s);

    // Expand standalone banking shorthand while keeping amounts intact
    s = s.replaceAllMapped(
      RegExp(
        r'(?<![\p{L}\p{N}])(ck|cf|cafe|caphe|xang|tgdd|dmx|bhx)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
        final tok = m.group(1)!.toLowerCase();
        if (tok == 'xang') return 'xăng';
        return kClassifierAbbreviations[tok] ?? tok;
      },
    );

    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static const Set<String> kCarrierStopwords = <String>{
    'hom', 'nay', 'qua', 'kia', 'sang', 'trua', 'chieu', 'toi', 'tuan', 'truoc',
    'vua', 'moi', 'da', 'minh', 'em', 'anh', 'het', 'mat', 'ton', 'khoang',
    'gd', 'the', 'qr', 'nd', 'vcb', 'tcb', 'mbbank', 'bidv', 'acb', 'tpb', 'vpb',
    'digibank', 'tinh', 'so',
  };

  /// Produces the exact classifier token sequence expected by FastText (`feature_spec.py`).
  String toClassifierInput(String text) {
    final cached = _classifierNormCache[text];
    if (cached != null) return cached;

    var s = text.trim().toLowerCase();
    s = s.replaceAll(
      RegExp(
        r'\b\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|k|nghìn|nghin|ngàn|ngan|đ|d|₫|vnd|vnđ|usd)?(?:\s*\d{1,3})?\b',
        caseSensitive: false,
        unicode: true,
      ),
      ' ',
    );
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    final rawTokens = s
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && int.tryParse(t) == null);

    final expanded = <String>[];
    for (final tok in rawTokens) {
      final mapped = kClassifierAbbreviations[tok];
      if (mapped != null) {
        expanded.addAll(mapped.split(' '));
      } else {
        expanded.add(tok);
      }
    }
    final filtered = expanded
        .where((w) => !kCarrierStopwords.contains(stripVnAccents(w)))
        .toList();
    final result = (filtered.isNotEmpty ? filtered : expanded).join(' ').trim();
    if (_classifierNormCache.length >= _maxCacheEntries) {
      _classifierNormCache.clear();
    }
    _classifierNormCache[text] = result;
    return result;
  }

  String _normalizeSpokenNumbers(String input) {
    var s = input;
    s = s
        .replaceAll(
          RegExp(r'\bnửa\s+(?:triệu|trieu|củ|cu)\b', caseSensitive: false),
          '500 nghìn',
        )
        .replaceAll(
          RegExp(
            r'\bmột\s+(?:triệu|trieu|củ|cu)\s+rưỡi\b',
            caseSensitive: false,
          ),
          '1tr5',
        )
        .replaceAll(
          RegExp(r'\bhai\s+trăm\s+rưỡi\b', caseSensitive: false),
          '250k',
        )
        .replaceAll(
          RegExp(r'\bba\s+trăm\s+rưỡi\b', caseSensitive: false),
          '350k',
        )
        .replaceAll(
          RegExp(r'\bbốn\s+trăm\s+rưỡi\b', caseSensitive: false),
          '450k',
        )
        .replaceAll(
          RegExp(r'\bnăm\s+trăm\s+rưỡi\b', caseSensitive: false),
          '550k',
        );

    final unitWordPattern = RegExp(
      r'((?:(?:không|khong|một|mot|mốt|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|lam|sáu|sau|bảy|bay|tám|tam|chín|chin|mười|muoi|mươi|trăm|tram|linh|lẻ|le)\s+){1,6})(triệu|trieu|nghìn|nghin|ngàn|ngan|củ|cu)\b',
      caseSensitive: false,
      unicode: true,
    );
    s = s.replaceAllMapped(unitWordPattern, (m) {
      final parsed = _parseSmallSpokenInt(m.group(1) ?? '');
      if (parsed == null || parsed <= 0) return m.group(0) ?? '';
      return '$parsed ${m.group(2)}';
    });

    s = s.replaceAllMapped(
      RegExp(
        r'(\d+)\s*(?:triệu|trieu|tr|củ|cu)\s*(?:rưỡi|ruoi)\b',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}tr5',
    );
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
    var hundreds = 0;
    var tens = 0;
    var ones = 0;
    var i = 0;
    if (i + 1 < tokens.length &&
        (tokens[i + 1] == 'trăm' || tokens[i + 1] == 'tram')) {
      final h = _vnDigitWords[tokens[i]];
      if (h == null) return null;
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
        }
      } else if (i + 1 < tokens.length &&
          (tokens[i + 1] == 'mươi' || tokens[i + 1] == 'muoi')) {
        final t = _vnDigitWords[tokens[i]];
        if (t == null) return null;
        tens = t * 10;
        i += 2;
        if (i < tokens.length && _vnDigitWords.containsKey(tokens[i])) {
          ones = _vnDigitWords[tokens[i]]!;
        }
      } else if (_vnDigitWords.containsKey(tokens[i])) {
        ones = _vnDigitWords[tokens[i]]!;
      }
    }
    final total = hundreds + tens + ones;
    return total > 0 ? total : null;
  }

  /// Extracts all monetary amounts in `text` using pure integer arithmetic (`int`, zero `double`!).
  /// Handles:
  /// - `2 triệu 300 nghìn`, `1tr5`, `1.5 triệu`, `1,5 triệu`, `12tr`
  /// - `50k`, `50K`, `50 nghìn`, `50 ngàn`
  /// - `50.000`, `50,000đ`, `125000 VND`
  /// - Foreign currency (`$12.50`, `4.99 USD`)
  /// - Marks bare `1.500` (without unit and `< 10,000`) as `isAmbiguous: true`!
  List<ParsedMonetaryAmount> extractAmounts(String text) {
    final results = <ParsedMonetaryAmount>[];
    final occupied = List<bool>.filled(text.length, false);

    bool isRangeFree(int s, int e) {
      for (var i = s; i < e; i++) {
        if (occupied[i]) return false;
      }
      return true;
    }

    void markRange(int s, int e) {
      for (var i = s; i < e; i++) {
        occupied[i] = true;
      }
    }

    // 1. Compound Million + Thousand: "2 triệu 300 nghìn", "1tr500k", "1tr5", "1.5 triệu", "1,5 triệu"
    final millionRegex = RegExp(
      r'(?<!\d)(\d+)(?:([.,])(\d{1,3}))?\s*(?:triệu|trieu|tr|củ|cu)(?:\s*(\d{1,3})\s*(?:nghìn|nghin|ngàn|ngan|k)?)?(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    for (final m in millionRegex.allMatches(text)) {
      if (!isRangeFree(m.start, m.end)) continue;
      final wholeMil = int.tryParse(m.group(1) ?? '');
      if (wholeMil == null) continue;
      var minor = wholeMil * 1000000;
      final decDigits = m.group(3);
      if (decDigits != null && decDigits.isNotEmpty) {
        final padded = decDigits.padRight(6, '0').substring(0, 6);
        minor += int.parse(padded);
      } else {
        final tail = m.group(4);
        if (tail != null && tail.isNotEmpty) {
          final tailVal = int.parse(tail);
          final rawMatched = m.group(0)!.toLowerCase();
          final hasExplicitThousandWord =
              rawMatched.contains('nghìn') ||
              rawMatched.contains('nghin') ||
              rawMatched.contains('ngàn') ||
              rawMatched.contains('ngan') ||
              rawMatched.endsWith('k');
          if (hasExplicitThousandWord) {
            // e.g. "2 triệu 300 nghìn" -> +300 * 1,000 = +300,000
            minor += tailVal * 1000;
          } else {
            // Shorthand "1tr5" -> +500,000; "1tr25" -> +250,000; "1tr250" -> +250,000
            final scale = switch (tail.length) {
              1 => 100000,
              2 => 10000,
              _ => 1000,
            };
            minor += tailVal * scale;
          }
        }
      }
      if (minor > 0) {
        markRange(m.start, m.end);
        results.add(
          ParsedMonetaryAmount(
            amountMinor: minor,
            matchedToken: m.group(0)!,
            startIndex: m.start,
            endIndex: m.end,
            confidence: 0.99,
          ),
        );
      }
    }

    // 2. Thousand shorthand: "50k", "50K", "35 nghìn", "70 ngàn", "12.5k"
    final thousandRegex = RegExp(
      r'(?<!\d)(\d+)(?:([.,])(\d{1,3}))?\s*(?:nghìn|nghin|ngàn|ngan|k)(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    for (final m in thousandRegex.allMatches(text)) {
      if (!isRangeFree(m.start, m.end)) continue;
      final wholeK = int.tryParse(m.group(1) ?? '');
      if (wholeK == null) continue;
      final dec = m.group(3);
      var minor = wholeK * 1000;
      if (dec != null && dec.isNotEmpty) {
        if (dec.length == 3 && wholeK < 1000) {
          // e.g. "1.500k" -> ambiguous whether 1,500,000 or 1,500!
          markRange(m.start, m.end);
          results.add(
            ParsedMonetaryAmount(
              amountMinor: wholeK * 1000000 + int.parse(dec) * 1000,
              matchedToken: m.group(0)!,
              startIndex: m.start,
              endIndex: m.end,
              confidence: 0.50,
              isAmbiguous: true,
            ),
          );
          continue;
        }
        final padded = dec.padRight(3, '0').substring(0, 3);
        minor += int.parse(padded);
      }
      if (minor > 0) {
        markRange(m.start, m.end);
        results.add(
          ParsedMonetaryAmount(
            amountMinor: minor,
            matchedToken: m.group(0)!,
            startIndex: m.start,
            endIndex: m.end,
            confidence: 0.98,
          ),
        );
      }
    }

    // 3. Foreign currency USD/EUR ("$12.50", "15.99 USD")
    final usdRegex = RegExp(
      r'(?:\$\s*(\d+)(?:\.(\d{1,2}))?|(\d+)(?:\.(\d{1,2}))?\s*USD)\b',
      caseSensitive: false,
    );
    for (final m in usdRegex.allMatches(text)) {
      if (!isRangeFree(m.start, m.end)) continue;
      final dollars = int.tryParse(m.group(1) ?? m.group(3) ?? '');
      if (dollars == null) continue;
      final centsStr = (m.group(2) ?? m.group(4) ?? '')
          .padRight(2, '0')
          .substring(0, 2);
      final cents = int.parse(centsStr);
      final minor = dollars * 100 + cents;
      if (minor > 0) {
        markRange(m.start, m.end);
        results.add(
          ParsedMonetaryAmount(
            amountMinor: minor,
            currencyCode: 'USD',
            decimalDigits: 2,
            matchedToken: m.group(0)!,
            startIndex: m.start,
            endIndex: m.end,
            confidence: 0.95,
          ),
        );
      }
    }

    // 4. Grouped thousands or explicit VND integer: "50.000", "50,000đ", "125000 VND"
    // Guard against dates like "15/11/2026" or account numbers > 12 digits!
    final groupedOrExplicitVnd = RegExp(
      r'(?<![\d/-])(\d{1,3}(?:([.,])\d{3})+|\d{4,12})(?:\s*(đ|₫|vnd|vnđ|đồng|dong))?(?![\d/-])',
      caseSensitive: false,
      unicode: true,
    );
    for (final m in groupedOrExplicitVnd.allMatches(text)) {
      if (!isRangeFree(m.start, m.end)) continue;
      final numPart = m.group(1)!;
      final unitPart = m.group(3);
      final hasExplicitUnit = unitPart != null && unitPart.trim().isNotEmpty;

      // Skip long bare account/reference numbers (e.g. 1017588888 without currency suffix)
      final digitsOnly = numPart.replaceAll(RegExp(r'[.,]'), '');
      if (!hasExplicitUnit &&
          !numPart.contains('.') &&
          !numPart.contains(',') &&
          digitsOnly.length >= 9) {
        continue;
      }

      // Skip years like 2024..2035 if preceded by "năm" or "/"
      final parsedInt = int.tryParse(digitsOnly);
      if (parsedInt == null || parsedInt <= 0) continue;
      if (!hasExplicitUnit && parsedInt >= 1990 && parsedInt <= 2035) {
        final before = text.substring(0, m.start).toLowerCase();
        if (before.endsWith('năm ') ||
            before.endsWith('nam ') ||
            before.endsWith('đời ')) {
          continue;
        }
      }

      // Ambiguity check (Phase 4.4): bare "1.500" or "2,500" (< 10,000 without explicit currency unit)
      final isSingleThreeDigitGroupUnder10k =
          !hasExplicitUnit &&
          RegExp(r'^\d[.,]\d{3}$').hasMatch(numPart) &&
          parsedInt < 10000;

      markRange(m.start, m.end);
      results.add(
        ParsedMonetaryAmount(
          amountMinor: parsedInt,
          matchedToken: m.group(0)!,
          startIndex: m.start,
          endIndex: m.end,
          confidence: hasExplicitUnit
              ? 0.99
              : (isSingleThreeDigitGroupUnder10k ? 0.48 : 0.92),
          isAmbiguous: isSingleThreeDigitGroupUnder10k,
        ),
      );
    }

    results.sort((a, b) => a.startIndex.compareTo(b.startIndex));
    return results;
  }

  /// Resolves Vietnamese relative date/time expressions relative to `referenceTime` (or `_clock.now()`).
  ParsedRelativeDate? extractRelativeDate(
    String text, {
    DateTime? referenceTime,
  }) {
    final ref = referenceTime ?? _clock.now();
    final ascii = stripVnAccents(text);

    int hourForPartOfDay(String s, int fallbackHour) {
      if (s.contains('sang')) return 8;
      if (s.contains('trua')) return 12;
      if (s.contains('chieu')) return 16;
      if (s.contains('toi') || s.contains('dem')) return 20;
      return fallbackHour;
    }

    // 1. Explicit dd/MM/yyyy or dd/MM
    final dmMatch = RegExp(
      r'\b(\d{1,2})/(\d{1,2})(?:/(\d{4}))?\b',
    ).firstMatch(text);
    if (dmMatch != null) {
      final d = int.tryParse(dmMatch.group(1)!) ?? ref.day;
      final mo = int.tryParse(dmMatch.group(2)!) ?? ref.month;
      final y = int.tryParse(dmMatch.group(3) ?? '') ?? ref.year;
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        return ParsedRelativeDate(
          resolvedDateTime: DateTime(
            y,
            mo,
            d,
            hourForPartOfDay(ascii, ref.hour),
            ref.minute,
          ),
          matchedPhrase: dmMatch.group(0)!,
        );
      }
    }

    // 2. "hôm kia" (2 days ago)
    final homKia = RegExp(r'\bhom\s+kia\b').firstMatch(ascii);
    if (homKia != null) {
      final base = ref.subtract(const Duration(days: 2));
      return ParsedRelativeDate(
        resolvedDateTime: DateTime(
          base.year,
          base.month,
          base.day,
          hourForPartOfDay(ascii, 12),
          0,
        ),
        matchedPhrase: text.substring(homKia.start, homKia.end),
      );
    }

    // 3. "hôm qua", "sáng qua", "trưa qua", "chiều qua", "tối qua", "đêm qua"
    final quaMatch = RegExp(
      r'\b(hom|sang|trua|chieu|toi|dem)\s+qua\b',
    ).firstMatch(ascii);
    if (quaMatch != null) {
      final base = ref.subtract(const Duration(days: 1));
      return ParsedRelativeDate(
        resolvedDateTime: DateTime(
          base.year,
          base.month,
          base.day,
          hourForPartOfDay(quaMatch.group(1)!, 12),
          0,
        ),
        matchedPhrase: text.substring(quaMatch.start, quaMatch.end),
      );
    }

    // 4. Weekday last week: "thứ hai tuần trước" .. "chủ nhật tuần trước"
    final weekdayMap = <String, int>{
      'thu hai': DateTime.monday,
      'thu 2': DateTime.monday,
      'thu ba': DateTime.tuesday,
      'thu 3': DateTime.tuesday,
      'thu tu': DateTime.wednesday,
      'thu 4': DateTime.wednesday,
      'thu nam': DateTime.thursday,
      'thu 5': DateTime.thursday,
      'thu sau': DateTime.friday,
      'thu 6': DateTime.friday,
      'thu bay': DateTime.saturday,
      'thu 7': DateTime.saturday,
      'chu nhat': DateTime.sunday,
    };
    for (final entry in weekdayMap.entries) {
      final m = RegExp(
        '\\b${entry.key}\\s+tuan\\s+truoc\\b',
      ).firstMatch(ascii);
      if (m != null) {
        final currentMonday = DateTime(
          ref.year,
          ref.month,
          ref.day,
        ).subtract(Duration(days: ref.weekday - DateTime.monday));
        final lastWeekMonday = currentMonday.subtract(const Duration(days: 7));
        final target = lastWeekMonday.add(
          Duration(days: entry.value - DateTime.monday),
        );
        return ParsedRelativeDate(
          resolvedDateTime: DateTime(
            target.year,
            target.month,
            target.day,
            hourForPartOfDay(ascii, 12),
            0,
          ),
          matchedPhrase: text.substring(m.start, m.end),
        );
      }
    }

    // 5. "tuần trước" (without specific weekday -> 7 days ago, marked slightly ambiguous)
    final tuanTruoc = RegExp(r'\btuan\s+truoc\b').firstMatch(ascii);
    if (tuanTruoc != null) {
      final base = ref.subtract(const Duration(days: 7));
      return ParsedRelativeDate(
        resolvedDateTime: DateTime(base.year, base.month, base.day, 12, 0),
        matchedPhrase: text.substring(tuanTruoc.start, tuanTruoc.end),
        isAmbiguous: true,
      );
    }

    // 6. "tháng trước"
    final thangTruoc = RegExp(r'\bthang\s+truoc\b').firstMatch(ascii);
    if (thangTruoc != null) {
      final prevMonth = ref.month == 1 ? 12 : ref.month - 1;
      final prevYear = ref.month == 1 ? ref.year - 1 : ref.year;
      final maxDay = DateTime(prevYear, prevMonth + 1, 0).day;
      final clampedDay = ref.day > maxDay ? maxDay : ref.day;
      return ParsedRelativeDate(
        resolvedDateTime: DateTime(prevYear, prevMonth, clampedDay, 12, 0),
        matchedPhrase: text.substring(thangTruoc.start, thangTruoc.end),
        isAmbiguous: true,
      );
    }

    // 7. "ngày 15"
    final ngayMatch = RegExp(r'\bngay\s+(\d{1,2})\b').firstMatch(ascii);
    if (ngayMatch != null) {
      final dayNum = int.tryParse(ngayMatch.group(1)!) ?? 0;
      if (dayNum >= 1 && dayNum <= 31) {
        var targetMonth = ref.month;
        var targetYear = ref.year;
        if (dayNum > ref.day) {
          targetMonth = ref.month == 1 ? 12 : ref.month - 1;
          targetYear = ref.month == 1 ? ref.year - 1 : ref.year;
        }
        final maxDay = DateTime(targetYear, targetMonth + 1, 0).day;
        final safeDay = dayNum > maxDay ? maxDay : dayNum;
        return ParsedRelativeDate(
          resolvedDateTime: DateTime(
            targetYear,
            targetMonth,
            safeDay,
            hourForPartOfDay(ascii, 12),
            0,
          ),
          matchedPhrase: text.substring(ngayMatch.start, ngayMatch.end),
        );
      }
    }

    // 8. "hôm nay", "sáng nay", "trưa nay", "chiều nay", "tối nay"
    final nayMatch = RegExp(
      r'\b(hom|sang|trua|chieu|toi)\s+nay\b',
    ).firstMatch(ascii);
    if (nayMatch != null) {
      return ParsedRelativeDate(
        resolvedDateTime: DateTime(
          ref.year,
          ref.month,
          ref.day,
          hourForPartOfDay(nayMatch.group(1)!, ref.hour),
          ref.minute,
        ),
        matchedPhrase: text.substring(nayMatch.start, nayMatch.end),
      );
    }

    return null;
  }

  /// Canonicalizes a merchant string into a stable lookup key for Personalization (Phase 10).
  static String? canonicalizeMerchant(String? merchantOrDesc) {
    if (merchantOrDesc == null || merchantOrDesc.trim().isEmpty) return null;
    var ascii = stripVnAccents(merchantOrDesc.trim());
    // Strip leading bank prefix ("vcb:", "tcb:", "gd the", "thanh toan") & trailing reference digits
    ascii = ascii
        .replaceAll(
          RegExp(
            r'^(?:vcb|tcb|mb|mbbank|acb|bidv|ctg|tpb|vpb|stb|momo|zalopay)\s*[:\-]\s*',
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(mua|chi|tra|thanh\s+toan|ung|nhan|di|uong|an|tai|o|cho|het|mat|ton)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\b\d{3,}\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (ascii.length < 2) return null;
    final words = ascii.split(' ').take(4).join('_');
    return words.isEmpty ? null : words;
  }
}
