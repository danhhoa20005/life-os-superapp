import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/utils/vietnamese_temporal_and_entity_resolver.dart';
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
    'ts': 'trà sữa',
    'trasua': 'trà sữa',
    'ck': 'chuyển khoản',
    'bhxh': 'bảo hiểm xã hội',
    'bhyt': 'bảo hiểm y tế',
    'tgdd': 'thế giới di động',
    'dmx': 'điện máy xanh',
    'bhx': 'bách hóa xanh',
    'winmart': 'siêu thị winmart',
    'vinmart': 'siêu thị winmart',
    'coopmart': 'siêu thị coopmart',
    'gs25': 'siêu thị gs25',
    'circlek': 'circle k',
    'kfc': 'gà rán kfc',
    'jollibee': 'gà rán jollibee',
    'lotteria': 'gà rán lotteria',
    'cgv': 'rạp phim cgv',
    'bhd': 'rạp phim bhd',
    'lotte': 'siêu thị lotte',
    'aeon': 'siêu thị aeon',
    'evn': 'tiền điện evn',
    'sawaco': 'tiền nước sawaco',
    'capnuoc': 'tiền nước',
    'vnpt': 'viễn thông vnpt',
    'fpt': 'internet fpt',
    'vt': 'viễn thông viettel',
    'spt': 'spotify',
    'ytb': 'youtube',
    'fb': 'facebook',
    'icloud': 'gói icloud',
    'netflix': 'gói netflix',
    'grabbike': 'grab xe ôm',
    'grabcar': 'grab taxi',
    'bebike': 'be xe ôm',
    'becar': 'be taxi',
    'gsm': 'xanh sm taxi',
    'xanhsm': 'xanh sm taxi',
    'epass': 'trạm thu phí epass',
    'vetc': 'trạm thu phí vetc',
    'bsx': 'bảo dưỡng sửa xe',
    'nsd': 'nhông sên dĩa sửa xe',
    'longchau': 'nhà thuốc long châu',
    'pharmacity': 'nhà thuốc pharmacity',
    'ankhang': 'nhà thuốc an khang',
    'vnvc': 'tiêm vắc xin vnvc',
    'fecredit': 'trả góp fe credit',
    'homecredit': 'trả góp home credit',
    'hdsaison': 'trả góp hd saison',
    'vpp': 'văn phòng phẩm',
    'fahasa': 'nhà sách fahasa',
    'concung': 'mẹ bé con cưng',
    'kidsplaza': 'mẹ bé kids plaza',
    'ghtk': 'giao hàng tiết kiệm',
    'ghn': 'giao hàng nhanh',
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
    'à': 'a',
    'á': 'a',
    'ả': 'a',
    'ã': 'a',
    'ạ': 'a',
    'ă': 'a',
    'ằ': 'a',
    'ắ': 'a',
    'ẳ': 'a',
    'ẵ': 'a',
    'ặ': 'a',
    'â': 'a',
    'ầ': 'a',
    'ấ': 'a',
    'ẩ': 'a',
    'ẫ': 'a',
    'ậ': 'a',
    'đ': 'd',
    'è': 'e',
    'é': 'e',
    'ẻ': 'e',
    'ẽ': 'e',
    'ẹ': 'e',
    'ê': 'e',
    'ề': 'e',
    'ế': 'e',
    'ể': 'e',
    'ễ': 'e',
    'ệ': 'e',
    'ì': 'i',
    'í': 'i',
    'ỉ': 'i',
    'ĩ': 'i',
    'ị': 'i',
    'ò': 'o',
    'ó': 'o',
    'ỏ': 'o',
    'õ': 'o',
    'ọ': 'o',
    'ô': 'o',
    'ồ': 'o',
    'ố': 'o',
    'ổ': 'o',
    'ỗ': 'o',
    'ộ': 'o',
    'ơ': 'o',
    'ờ': 'o',
    'ớ': 'o',
    'ở': 'o',
    'ỡ': 'o',
    'ợ': 'o',
    'ù': 'u',
    'ú': 'u',
    'ủ': 'u',
    'ũ': 'u',
    'ụ': 'u',
    'ư': 'u',
    'ừ': 'u',
    'ứ': 'u',
    'ử': 'u',
    'ữ': 'u',
    'ự': 'u',
    'ỳ': 'y',
    'ý': 'y',
    'ỷ': 'y',
    'ỹ': 'y',
    'ỵ': 'y',
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
    s = _normalizeAsrPhoneticsForMoney(s);
    s = _normalizeSpokenNumbers(s);
    s = _normalizeMillionDigitTails(s);

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

  static final RegExp _asrTaiKhoangRegex = RegExp(
    r'(?<![\p{L}\p{N}])(tài)\s+khoảng(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrLuoiRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(triệu|trieu|tr|củ|cu|nghìn|nghin|ngàn|ngan|k|trăm|tram|chục|chuc|xị|xi|lít|lit|tỷ|tỉ|ty|ti)\s+(?:lưỡi|luoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrXiToneRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d{1,2}|nửa|nua|một|mot|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|sáu|sau|xáu|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi)\s+(?:xỉ|xĩ)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrXauLeadRegex = RegExp(
    r'(?<![\p{L}\p{N}])xáu(?=\s+(?:mươi|muoi|trăm|tram|nghìn|nghin|ngàn|ngan|triệu|trieu|củ|cu|chục|chuc|cành|canh|nhành|nhanh|xị|xi|lít|lit|tỷ|tỉ|ty|ti|k)(?![\p{L}\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrLamMuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])lăm\s+(mươi|muoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrLeadingLamRegex = RegExp(
    r'(?<![\p{L}\p{N}])lăm(?=\s+(?:trăm|tram|nghìn|nghin|ngàn|ngan|triệu|trieu|củ|cu|chục|chuc|cành|canh|nhành|nhanh|xị|xi|lít|lit|tỷ|tỉ|ty|ti|k)(?![\p{L}\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _numberBeforeLamGuardRegex = RegExp(
    r'(?:hai|ba|bốn|bon|tư|tu|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi|mươi|linh|lẻ|le|trăm|tram|thứ|thu|\d)\s+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _millionDigitTailRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:triệu|trieu|tr|củ|cu)\s+(một|mot|mốt|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|lam|nhăm|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)(?![\p{L}\p{N}])(?!(?:\s+(?:người|nguoi|tháng|thang|năm|nam|tuần|tuan|ngày|ngay|giờ|gio|cái|cai|chiếc|chiec|lần|lan|đứa|dua|bạn|ban|trăm|tram|nghìn|nghin|ngàn|ngan|k|củ|cu|tỷ|tỉ|ty|ti)))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tuTransferAfterRegex = RegExp(
    r'^\s+(?:ví|vi|tài\s+khoản|tai\s+khoan|thẻ|the|ngân\s+hàng|ngan\s+hang|vcb|tcb|mb|mbbank|acb|bidv|tpb|tpbank|vpb|vpbank|momo|zalopay|vietcombank|techcombank|vietinbank)|\b(?:sang|vào|vao|qua|đến|den)\b',
    caseSensitive: false,
    unicode: true,
  );

  static String _normalizeAsrPhoneticsForMoney(String input) {
    final lower = input.toLowerCase();
    var s = input;
    if (lower.contains('tài khoảng')) {
      s = s.replaceAllMapped(_asrTaiKhoangRegex, (m) => '${m.group(1)} khoản');
    }
    if (lower.contains('lưỡi') || lower.contains('luoi')) {
      s = s.replaceAllMapped(_asrLuoiRuoiRegex, (m) => '${m.group(1)} rưỡi');
    }
    if (lower.contains('xỉ') || lower.contains('xĩ')) {
      s = s.replaceAllMapped(_asrXiToneRegex, (m) => '${m.group(1)} xị');
    }
    if (lower.contains('xáu')) {
      s = s.replaceAll(_asrXauLeadRegex, 'sáu');
    }
    if (lower.contains('lăm')) {
      s = s
          .replaceAllMapped(_asrLamMuoiRegex, (m) => 'năm ${m.group(1)}')
          .replaceAllMapped(_asrLeadingLamRegex, (m) {
            final before = s.substring(0, m.start).toLowerCase();
            return _numberBeforeLamGuardRegex.hasMatch(before)
                ? (m.group(0) ?? '')
                : 'năm';
          });
    }
    return s;
  }

  static String _normalizeMillionDigitTails(String input) {
    final lower = input.toLowerCase();
    if (!lower.contains('triệu') &&
        !lower.contains('trieu') &&
        !lower.contains('củ') &&
        !lower.contains('cu')) {
      return input;
    }
    return input.replaceAllMapped(_millionDigitTailRegex, (m) {
      final rawTail = (m.group(2) ?? '').toLowerCase();
      final after = input.substring(m.end);
      if (rawTail == 'tu' && _tuTransferAfterRegex.hasMatch(after)) {
        return m.group(0) ?? '';
      }
      final whole = m.group(1) ?? '';
      final digit = _vnDigitWords[rawTail];
      if (digit == null || digit <= 0 || digit >= 10) return m.group(0) ?? '';
      return '${whole}tr$digit';
    });
  }

  static const Set<String> kCarrierStopwords = <String>{
    'vcb',
    'tcb',
    'mbbank',
    'bidv',
    'acb',
    'tpb',
    'vpb',
    'tpbank',
    'vpbank',
    'techcombank',
    'vietcombank',
    'vietinbank',
    'sacombank',
    'digibank',
    'smartbanking',
    'zalopay',
    'momo',
    'qr',
    'nd',
    'gd',
  };

  static final RegExp _classifierPreAmountMarkerRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:hết|het|mất|tốn|ton|khoảng|khoang|tầm|tam)\s+(?=(?:\$|\d))',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _classifierUsdNoiseRegex = RegExp(
    r'\$\s*\d+(?:[.,]\d{1,2})?',
    caseSensitive: false,
  );

  static final RegExp _classifierAmountNoiseRegex = RegExp(
    r'(?<![\p{L}\p{N}])\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|tỷ|ty|k|nghìn|nghin|ngàn|ngan|xị|xi|cành|canh|nhành|nhanh|chục|chuc|đ|d|₫|vnd|vnđ|đồng|dong|usd)?(?:\s*\d{1,3}(?:\s*(?:nghìn|nghin|ngàn|ngan|k))?)?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _classifierCarrierPhraseRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:'
    r'(?:hôm|hom)\s+(?:nay|qua|kia)|'
    r'(?:sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem)\s+(?:nay|qua)|'
    r'(?:tuần|tuan)\s+(?:này|nay|trước|truoc)|'
    r'(?:vừa|vua|mới|moi)\s+(?:thanh\s+toán|thanh\s+toan|trả\s+tiền|tra\s+tien)|'
    r'(?:vừa|vua)\s+(?:mới|moi)|'
    r'(?:cho|chi)\s+(?:khoản|khoan)|'
    r'(?:dùng|dung)\s+(?:cho\s+)?(?:việc|viec)|'
    r'(?:số|so)\s+(?:tiền|tien)|'
    r'(?:nội|noi)\s+dung|'
    r'(?:báo|bao)\s+(?:có|co|nợ|no)|'
    r'tinh\s+tinh|'
    r'sd\s+tk|'
    r'gd\s+(?:the|thẻ|qr)'
    r')(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _digitsOnlyRegex = RegExp(r'^\d+$');

  /// Produces the exact classifier token sequence expected by FastText (`feature_spec.py`).
  String toClassifierInput(String text) {
    final cached = _classifierNormCache[text];
    if (cached != null) return cached;

    var s = _normalizeSpokenNumbers(text.trim()).toLowerCase();
    s = s.replaceAll(_classifierPreAmountMarkerRegex, ' ');
    s = s.replaceAll(_classifierUsdNoiseRegex, ' ');
    s = s.replaceAll(_classifierAmountNoiseRegex, ' ');
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    s = s.replaceAll(_classifierCarrierPhraseRegex, ' ');
    final rawTokens = s
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !_digitsOnlyRegex.hasMatch(t));

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

  static final RegExp _liquidNounFollowRegex = RegExp(
    r'^(?:(?:rưỡi|ruoi)\s+)?(?:nước|nuoc|xăng|xang|dầu|dau|sữa|sua|bia|rượu|ruou|cồn|ml|gas)(?![\p{L}\p{N}])',
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

  String _normalizeSpokenNumbers(String input) {
    var s = input;

    // 1. "nửa triệu" / "nửa củ" -> 500 nghìn; "nửa xị" / "nửa lít" -> 50k
    s = s
        .replaceAll(
          RegExp(
            r'(?<![\p{L}\p{N}])(?:nửa|nua)\s+(?:triệu|trieu|củ|cu)(?![\p{L}\p{N}])',
            caseSensitive: false,
            unicode: true,
          ),
          '500 nghìn',
        )
        .replaceAll(
          RegExp(
            r'(?<![\p{L}\p{N}])(?:nửa|nua)\s+xị(?![\p{L}\p{N}])',
            caseSensitive: false,
            unicode: true,
          ),
          '50k',
        )
        .replaceAll(
          RegExp(
            r'(?<![\p{L}\p{N}])(?:nửa|nua)\s+(?:lít|lit)(?![\p{L}\p{N}])(?!(?:\s+(?:xăng|xang|dầu|dau|nước|nuoc|sữa|sua|bia|rượu|ruou|cồn|ml|gas)(?![\p{L}\p{N}])))',
            caseSensitive: false,
            unicode: true,
          ),
          '50k',
        );

    // 2. "<1..9 | một..chín> trăm rưỡi" -> 150k..950k & bare "trăm rưỡi" -> 150k
    s = s.replaceAllMapped(
      RegExp(
        r'(?<![\p{L}\p{N}])(1|2|3|4|5|6|7|8|9|một|mot|hai|ba|bốn|bon|tư|tu|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)\s+(?:trăm|tram)\s+(?:rưỡi|ruoi)(?:\s*(?:nghìn|nghin|ngàn|ngan|cành|canh|nhành|nhanh))?(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
        final tok = (m.group(1) ?? '').trim().toLowerCase();
        final d = int.tryParse(tok) ?? _vnDigitWords[tok];
        if (d == null || d <= 0 || d > 9) return m.group(0)!;
        return '${d * 100 + 50}k';
      },
    );
    s = s.replaceAll(
      RegExp(
        r'(?<![\p{L}\p{N}])(?:trăm|tram)\s+(?:rưỡi|ruoi)(?:\s*(?:nghìn|nghin|ngàn|ngan|cành|canh|nhành|nhanh))?(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      '150k',
    );

    // 3. Spoken Vietnamese numbers before standard or colloquial currency units
    final unitWordPattern = RegExp(
      r'(?<![\p{L}\p{N}])((?:(?:không|khong|một|mot|mốt|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|lam|nhăm|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi|mươi|trăm|tram|linh|lẻ|le)\s+){1,6})(triệu|trieu|tr|củ|cu|nghìn|nghin|ngàn|ngan|xị|xi|cành|canh|nhành|nhanh|chục|chuc|lít|lit)(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    final snapshotSpoken = s;
    s = snapshotSpoken.replaceAllMapped(unitWordPattern, (m) {
      var rawSpoken = m.group(1) ?? '';
      final unit = m.group(2) ?? '';
      final unitLower = unit.toLowerCase();
      final after = snapshotSpoken.substring(m.end).trimLeft();
      final before = snapshotSpoken
          .substring(0, m.start)
          .trimRight()
          .toLowerCase();

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

      var prefix = '';
      final trimmedSpoken = rawSpoken.trimLeft();
      final firstSpace = trimmedSpoken.indexOf(' ');
      if (firstSpace > 0) {
        final firstWord = trimmedSpoken.substring(0, firstSpace).toLowerCase();
        if ((firstWord == 'tam' || firstWord == 'tấm') &&
            (before.endsWith('cơm') ||
                before.endsWith('com') ||
                before.endsWith('bánh') ||
                before.endsWith('banh'))) {
          prefix = '${trimmedSpoken.substring(0, firstSpace)} ';
          rawSpoken = trimmedSpoken.substring(firstSpace + 1);
        }
      }

      final parsed = _parseSmallSpokenInt(rawSpoken);
      if (parsed == null || parsed <= 0) return m.group(0) ?? '';
      return '$prefix$parsed $unit';
    });

    // 4. "<N> triệu/củ rưỡi" -> "<N>tr5" & bare "củ rưỡi" / "triệu rưỡi" -> "1tr5"
    s = s.replaceAllMapped(
      RegExp(
        r'(?<!\d)(\d+)\s*(?:triệu|trieu|tr|củ|cu)\s*(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) => '${m.group(1)}tr5',
    );
    s = s.replaceAll(
      RegExp(
        r'(?<![\p{L}\p{N}])(?:triệu|trieu|củ|cu)\s+(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      '1tr5',
    );

    // 5. Slang "xị" (1 xị = 100.000 ₫, 1 xị rưỡi = 150.000 ₫)
    final snapshotXi = s;
    s = snapshotXi.replaceAllMapped(
      RegExp(
        r'(?<!\d)(\d+)(?:[.,](\d))?\s*(?:xị|xi)(?:\s*(rưỡi|ruoi))?(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
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
      },
    );

    // 6. Slang "cành" / "nhành" (1 cành = 1.000 ₫)
    final snapshotCanh = s;
    s = snapshotCanh.replaceAllMapped(
      RegExp(
        r'(?<!\d)(\d+)\s*(?:cành|canh|nhành|nhanh)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
        final after = snapshotCanh.substring(m.end).trimLeft();
        if (_flowerBranchFollowRegex.hasMatch(after)) {
          return m.group(0)!;
        }
        final n = int.tryParse(m.group(1) ?? '');
        if (n == null || n <= 0) return m.group(0)!;
        return '${n}k';
      },
    );

    // 7. Colloquial "chục" (1 chục = 10.000 ₫; "mấy chục" has no number -> untouched!)
    final snapshotChuc = s;
    s = snapshotChuc.replaceAllMapped(
      RegExp(
        r'(?<!\d)(\d+)\s*(?:chục|chuc)(?:\s*(rưỡi|ruoi))?(?:\s*(?:nghìn|nghin|ngàn|ngan))?(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
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
      },
    );

    // 8. Colloquial "lít" (1 lít = 100.000 ₫, 1 lít rưỡi = 150.000 ₫) ONLY when NOT before liquid/fuel nouns
    final snapshotLit = s;
    s = snapshotLit.replaceAllMapped(
      RegExp(
        r'(?<!\d)(\d+)(?:[.,](\d))?\s*(?:lít|lit)(?:\s*(rưỡi|ruoi))?(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
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
      },
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
      final allowZeroHundred = h == 0 && i + 2 < tokens.length;
      if (h == null || (h <= 0 && !allowZeroHundred) || h > 9) return null;
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
    final nonCurrencyAfterK = RegExp(
      r'^(?:km|ki\s*l[oô]\s*m[eé]t|kilomet|c[aâ]y\s*s[oố]|m[eé]t|ml|l[ií]t|vi[eê]n|mg|gam|kg|k[yý])(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    for (final m in thousandRegex.allMatches(text)) {
      if (!isRangeFree(m.start, m.end)) continue;
      final afterK = text.substring(m.end).trimLeft();
      if (nonCurrencyAfterK.hasMatch(afterK)) continue;
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

      // BUG-010: Never treat ODO ("14.000 km"), volume ("300ml"), dosage ("2000 mg"), or time/percent as VND!
      if (VietnameseTemporalAndEntityResolver.isFollowedByNonCurrencyUnit(
        text,
        m.end,
        hasExplicitCurrencySuffix: hasExplicitUnit,
      )) {
        continue;
      }

      final beforeLower = text.substring(0, m.start).toLowerCase().trimRight();
      if (!hasExplicitUnit &&
          RegExp(
            r'(?:^|\b)(?:odo|km|số\s+km|công\s+tơ\s+mét)\s*[:=]?$',
          ).hasMatch(beforeLower)) {
        continue;
      }

      // Skip negative standalone user amounts ("-500.000", "âm 500.000") when not bank debit
      if (RegExp(r'(?:^|\s)(?:-\s*|âm\s+)$').hasMatch(beforeLower) &&
          !beforeLower.contains('gd') &&
          !beforeLower.contains('vcb') &&
          !beforeLower.contains('tcb')) {
        continue;
      }

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

    // 5. Direct colloquial Vietnamese money extraction (for callers invoking `extractAmounts`
    // directly without calling `normalizeText` first: "nửa triệu/củ", "sáu trăm rưỡi", "trăm rưỡi",
    // "1 củ rưỡi", "xị", "cành/nhành", "chục", and "lít" when NOT preceding liquid/fuel words)
    void addDirectColloquial(
      RegExp pattern,
      int? Function(RegExpMatch m) eval,
    ) {
      for (final m in pattern.allMatches(text)) {
        if (!isRangeFree(m.start, m.end)) continue;
        final minor = eval(m);
        if (minor != null && minor > 0) {
          markRange(m.start, m.end);
          results.add(
            ParsedMonetaryAmount(
              amountMinor: minor,
              matchedToken: m.group(0)!,
              startIndex: m.start,
              endIndex: m.end,
              confidence: 0.96,
            ),
          );
        }
      }
    }

    addDirectColloquial(
      RegExp(
        r'(?<![\p{L}\p{N}])(?:nửa|nua)\s+(?:triệu|trieu|củ|cu)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (_) => 500000,
    );
    addDirectColloquial(
      RegExp(
        r'(?<![\p{L}\p{N}])(1|2|3|4|5|6|7|8|9|một|mot|hai|ba|bốn|bon|tư|tu|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)\s+(?:trăm|tram)\s+(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
        final tok = (m.group(1) ?? '').trim().toLowerCase();
        final d = int.tryParse(tok) ?? _vnDigitWords[tok];
        return (d != null && d >= 1 && d <= 9) ? (d * 100 + 50) * 1000 : null;
      },
    );
    addDirectColloquial(
      RegExp(
        r'(?<![\p{L}\p{N}])(?:trăm|tram)\s+(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (_) => 150000,
    );
    addDirectColloquial(
      RegExp(
        r'(?<![\p{L}\p{N}])(\d+|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi)\s*(?:triệu|trieu|tr|củ|cu)\s+(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
        final tok = (m.group(1) ?? '').trim().toLowerCase();
        final n = int.tryParse(tok) ?? _vnDigitWords[tok];
        return (n != null && n > 0) ? (n * 1000000 + 500000) : null;
      },
    );
    addDirectColloquial(
      RegExp(
        r'(?<![\p{L}\p{N}])(\d+|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)\s*(?:xị|xi)(?:\s+(rưỡi|ruoi))?(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
        final before = text.substring(0, m.start).trimRight().toLowerCase();
        final after = text.substring(m.end).trimLeft();
        if (before.endsWith('lì') ||
            before.endsWith('li') ||
            RegExp(
              r'^(?:măng|mang|giày|giay)(?![\p{L}\p{N}])',
              caseSensitive: false,
              unicode: true,
            ).hasMatch(after)) {
          return null;
        }
        final tok = (m.group(1) ?? '').trim().toLowerCase();
        final n = int.tryParse(tok) ?? _vnDigitWords[tok];
        if (n == null || n <= 0) return null;
        final hasHalf = m.group(2) != null && m.group(2)!.isNotEmpty;
        return (n * 100 + (hasHalf ? 50 : 0)) * 1000;
      },
    );
    addDirectColloquial(
      RegExp(
        r'(?<![\p{L}\p{N}])(\d+|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi)\s*(?:cành|canh|nhành|nhanh)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
        final after = text.substring(m.end).trimLeft();
        if (_flowerBranchFollowRegex.hasMatch(after)) return null;
        final tok = (m.group(1) ?? '').trim().toLowerCase();
        final n = int.tryParse(tok) ?? _vnDigitWords[tok];
        return (n != null && n > 0) ? n * 1000 : null;
      },
    );
    addDirectColloquial(
      RegExp(
        r'(?<![\p{L}\p{N}])(\d+|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)\s*(?:chục|chuc)(?:\s+(rưỡi|ruoi))?(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
        final after = text.substring(m.end).trimLeft();
        if (_itemCountFollowRegex.hasMatch(after) ||
            _millionUnitFollowRegex.hasMatch(after)) {
          return null;
        }
        final tok = (m.group(1) ?? '').trim().toLowerCase();
        final n = int.tryParse(tok) ?? _vnDigitWords[tok];
        if (n == null || n <= 0) return null;
        final hasHalf = m.group(2) != null && m.group(2)!.isNotEmpty;
        return (n * 10 + (hasHalf ? 5 : 0)) * 1000;
      },
    );
    addDirectColloquial(
      RegExp(
        r'(?<![\p{L}\p{N}])(\d+|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)\s*(?:lít|lit)(?:\s+(rưỡi|ruoi))?(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      (m) {
        final after = text.substring(m.end).trimLeft();
        if (_liquidNounFollowRegex.hasMatch(after)) return null;
        final tok = (m.group(1) ?? '').trim().toLowerCase();
        final n = int.tryParse(tok) ?? _vnDigitWords[tok];
        if (n == null || n <= 0) return null;
        final hasHalf = m.group(2) != null && m.group(2)!.isNotEmpty;
        return (n * 100 + (hasHalf ? 50 : 0)) * 1000;
      },
    );

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
      final m = RegExp('\\b${entry.key}\\s+tuan\\s+truoc\\b').firstMatch(ascii);
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

    // 9. Extended Vietnamese future/relative temporal expressions (Section 13)
    final extended = VietnameseTemporalAndEntityResolver.resolveTemporal(
      text,
      referenceNow: ref,
      defaultHour: ref.hour,
    );
    if (extended.hasExplicitDate || extended.hasExplicitTime) {
      return ParsedRelativeDate(
        resolvedDateTime: extended.dateTime,
        matchedPhrase: '',
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
