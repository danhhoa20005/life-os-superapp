import '../../features/financial_ai/data/normalization/financial_text_normalizer.dart';

enum ClauseSafetyStatus {
  allowed,
  blockedHypothetical,
  blockedNegated,
  blockedQuestion,
  blockedBalanceInquiry,
  financialQuery,
}

class ClauseSafetyResult {
  final ClauseSafetyStatus status;
  final String? reasonVi;

  const ClauseSafetyResult.allowed()
    : status = ClauseSafetyStatus.allowed,
      reasonVi = null;

  const ClauseSafetyResult.blocked({
    required this.status,
    required this.reasonVi,
  });

  bool get isAllowed => status == ClauseSafetyStatus.allowed;
  bool get isBlocked => !isAllowed;
}

class VietnameseTemporalResolution {
  final DateTime dateTime;
  final bool hasExplicitDate;
  final bool hasExplicitTime;
  final int? durationMinutes;
  final String cleanedText;

  const VietnameseTemporalResolution({
    required this.dateTime,
    required this.hasExplicitDate,
    required this.hasExplicitTime,
    this.durationMinutes,
    required this.cleanedText,
  });
}

class VietnameseEntitySnapshot {
  final String? walletHint;
  final String? destinationWalletHint;
  final String? vehicleHint;
  final int? odometerKm;
  final String? locationHint;

  const VietnameseEntitySnapshot({
    this.walletHint,
    this.destinationWalletHint,
    this.vehicleHint,
    this.odometerKm,
    this.locationHint,
  });
}

/// Clause-level Safety Screener: blocks hypothetical plans ("Tôi định mua xe 30 triệu"),
/// negations ("Đừng ghi khoản ăn trưa 50k"), questions without execution command
/// ("Có nên mua điện thoại 15tr không?"), and balance inquiries ("Còn 2 triệu trong tài khoản"),
/// while allowing valid sibling clauses in compound utterances ("Ăn sáng 45k, đừng ghi khoản cà phê 30k").
abstract final class ClauseSafetyScreener {
  static final RegExp _explicitActionCommandPrefix = RegExp(
    r'^(?:ghi|lưu|tạo|thêm|chia|nhờ|tính|phân\s+bổ|đặt|nhắc|lập)\b',
    caseSensitive: false,
    unicode: true,
  );

  static ClauseSafetyResult screenClause(String rawClause) {
    final trimmed = rawClause.trim();
    if (trimmed.isEmpty) {
      return const ClauseSafetyResult.blocked(
        status: ClauseSafetyStatus.blockedNegated,
        reasonVi: 'Mệnh đề trống.',
      );
    }

    final lower = trimmed.toLowerCase();
    final ascii = FinancialTextNormalizer.stripVnAccents(
      trimmed,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();

    // 1. Cancellation / explicit do-not-record negation
    if (RegExp(
      r'^(?:huy|xoa|bo|hoan\s+tac)\s+(?:giao\s+dich|khoan\s+chi|khoan\s+thu|but\s+toan)\b',
    ).hasMatch(ascii)) {
      return const ClauseSafetyResult.blocked(
        status: ClauseSafetyStatus.blockedNegated,
        reasonVi:
            'Đây là lệnh hủy giao dịch, hệ thống không tạo khoản thu/chi mới.',
      );
    }

    // Accented "đừng" OR unambiguous negation ("không/chưa/đừng" + recording or spending verb).
    // Preserves "cà phê không đường 30k" and "dùng bữa 50k"!
    if (RegExp(
          r'(?:^|\b)(?:đừng|khong|chua|ko)\s+(?:ghi|lưu|luu|tính|tinh|tạo|tao|thêm|them|nhập|nhap|lên|len)\b',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(lower) ||
        RegExp(
          r'(?:^|\b)(?:dung|khong|ko)\s+(?:ghi|luu|tinh|tao|them|nhap)\s+(?:khoan|giao\s+dich|cai\s+nay|muc\s+nay)\b',
        ).hasMatch(ascii) ||
        RegExp(r'\bbo\s+qua\s+(?:khoan|giao\s+dich)\b').hasMatch(ascii) ||
        RegExp(
          r'\b(?:khong|chua)\s+(?:mua|tieu|chi|an|uong|do\s+xang|di|phat\s+sinh|chuyen|tra)\b',
        ).hasMatch(ascii)) {
      return const ClauseSafetyResult.blocked(
        status: ClauseSafetyStatus.blockedNegated,
        reasonVi:
            'Câu mang nghĩa phủ định hoặc yêu cầu không ghi nhận — đã chặn để bảo vệ sổ cái.',
      );
    }

    // 2. Financial overview query ("Tổng chi tháng này bao nhiêu?", "Hạn mức còn bao nhiêu?")
    if (_looksLikeFinancialOverviewQuery(ascii)) {
      return const ClauseSafetyResult.blocked(
        status: ClauseSafetyStatus.financialQuery,
        reasonVi:
            'Câu truy vấn tổng quan tài chính (chỉ xem số liệu, không tạo giao dịch).',
      );
    }

    // 3. Hypothetical / unexecuted future intention ("Tôi định mua xe 30 triệu", "Dự định mua...", "Tính mua...")
    final hasExplicitAllocationOrPlanCommand =
        ascii.contains('phan bo') ||
        ascii.contains('50 30 20') ||
        ascii.contains('6 lo') ||
        ascii.contains('6 hu') ||
        ascii.contains('chia luong') ||
        ascii.contains('tao ngan sach') ||
        ascii.contains('dat ngan sach');
    if (!hasExplicitAllocationOrPlanCommand &&
        (RegExp(
              r'(?:^|\b)(?:toi|minh|em|anh|bo|me|nha\s+minh)?\s*(?:du\s+dinh|dinh\s+(?:mua|chi|tra|di|sam|doi|thue|tieu|dat|chuyen|gui|vay)|sap\s+(?:mua|chi|di|doi|thue)|tinh\s+(?:mua|chi|di|doi|sam|thue)|can\s+nhac\s+(?:mua|chi|doi)|muon\s+(?:mua|doi|sam)|neu\s+(?:mua|chi|di)|gia\s+su|uoc\s+gi|len\s+ke\s+hoach\s+(?:mua|chi|di))\b',
            ).hasMatch(ascii) ||
            RegExp(
              r'\bco\s+nen\s+(?:mua|chi|tra|vay|doi|di|tieu|dat)\b',
            ).hasMatch(ascii))) {
      return const ClauseSafetyResult.blocked(
        status: ClauseSafetyStatus.blockedHypothetical,
        reasonVi:
            'Đây là dự định hoặc giả định trong tương lai (chưa phát sinh thu/chi thực tế).',
      );
    }

    // 4. Question without execution command ("Có nên mua điện thoại 15tr không?", "Mua cái này có đắt không?")
    final hasQuestionMark = trimmed.endsWith('?');
    final hasAdvisoryQuestionPattern =
        RegExp(
          r'\b(?:co\s+nen|co\s+(?:dat|re|hop\s+ly|tot|on)\s+khong|bao\s+nhieu\s+(?:tien|phan\s+tram)|nen\s+mua|duoc\s+khong)\b',
        ).hasMatch(ascii) ||
        (hasQuestionMark && !_explicitActionCommandPrefix.hasMatch(lower));
    if (hasAdvisoryQuestionPattern &&
        !lower.contains('chia ') &&
        !lower.contains('nhắc ')) {
      return const ClauseSafetyResult.blocked(
        status: ClauseSafetyStatus.blockedQuestion,
        reasonVi:
            'Đây là câu hỏi tham khảo, không phải lệnh tạo giao dịch mới.',
      );
    }

    // 5. Pure balance inquiry/statement ("còn 2 triệu trong tài khoản", "số dư hiện còn 5tr")
    final hasActionVerb = RegExp(
      r'\b(?:mua|an|uong|chi|tra|thanh\s+toan|do\s+xang|di|nhan|cong|thuong|luong|chuyen|rut|hoan\s+tien|nap)\b',
    ).hasMatch(ascii);
    if (!hasActionVerb &&
        RegExp(
          r'(?:^|\b)(?:con|so\s+du|hien\s+con|hien\s+co|dang\s+co)\s+.+\b(?:trong\s+(?:tai\s+khoan|vi|the)|kha\s+dung)\b',
        ).hasMatch(ascii)) {
      return const ClauseSafetyResult.blocked(
        status: ClauseSafetyStatus.blockedBalanceInquiry,
        reasonVi:
            'Đây là câu thông báo số dư còn lại trong tài khoản/ví, không phải giao dịch mới.',
      );
    }

    return const ClauseSafetyResult.allowed();
  }

  static bool _looksLikeFinancialOverviewQuery(String ascii) {
    final hasQueryWord = RegExp(
      r'\b(?:bao\s+nhieu|tong\s+(?:chi|thu|so\s+du|tai\s+san)|han\s+muc|tinh\s+hinh\s+tai\s+chinh|xem\s+(?:so\s+du|bao\s+cao|tong\s+chi))\b',
    ).hasMatch(ascii);
    if (!hasQueryWord) return false;
    // Exclude commands that explicitly create a transaction with a known amount
    if (ascii.contains(' gom ') || ascii.contains(' chia ')) {
      return false;
    }
    final hasConcreteAmount = RegExp(
      r'\d+\s*(?:k|tr|trieu|cu|nghin|ngan|d|vnd)\b',
    ).hasMatch(ascii);
    return !hasConcreteAmount ||
        ascii.contains('bao nhieu') ||
        ascii.startsWith('xem ') ||
        ascii.startsWith('cho xem ') ||
        ascii.startsWith('tong chi') ||
        ascii.startsWith('tong thu');
  }
}

/// Comprehensive Vietnamese Temporal, Unit-Safe Amount, Odometer/Vehicle/Wallet Entity
/// & Multi-Clause Sentence Resolver (Section 13).
abstract final class VietnameseTemporalAndEntityResolver {
  static final RegExp _nonCurrencyUnitAfterNumber = RegExp(
    r'^(?:km|ki\s*l[oô]\s*m[eé]t|kilomet|c[aâ]y\s*s[oố]|c[aâ]y|m[eé]t|met|cm|mm|ml|l[ií]t|lit|cc|mg|gam|kg|k[yý]|k[ií]|l[aạ]ng|vi[eê]n|vien|gi[oọ]t|c[oố]c|coc|ly|chai|lon|h[oộ]p|hop|ph[uú]t|phut|gi[aâ]y|giay|gi[oờ]|gio|h|ti[eế]ng|tieng|ng[aà]y|ngay|tu[aầ]n|tuan|th[aá]ng|thang|n[aă]m|nam|%|ph[aầ]n\s*tr[aă]m|su[aấ]t|ph[aầ]n|ng[uư][oờ]i|tu[oổ]i|c[aá]i|chi[eế]c|g[oó]i|qu[aả]|tr[aá]i|con)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _odoRegex = RegExp(
    r'(?:odo\s*[:=]?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d{2,6})\s*(?:km|ki\s*l[oô]\s*m[eé]t|kilomet|c[aâ]y\s*s[oố]|c[aâ]y)\b|odo\s*[:=]?\s*(\d{1,3}(?:[.,]\d{3})+|\d{2,6})',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _plateRegex = RegExp(
    r'\b\d{2}[A-Za-z]{1,2}\d?[-.\s]?\d{3,5}(?:\.\d{2})?\b',
    caseSensitive: false,
  );

  static const Map<String, String> _walletAliases = <String, String>{
    'vietcombank': 'VCB',
    'vcb': 'VCB',
    'techcombank': 'TCB',
    'tcb': 'TCB',
    'mbbank': 'MB',
    'mb bank': 'MB',
    'mb': 'MB',
    'acb': 'ACB',
    'vietinbank': 'CTG',
    'ctg': 'CTG',
    'bidv': 'BIDV',
    'tpbank': 'TPB',
    'tpb': 'TPB',
    'vpbank': 'VPB',
    'vpb': 'VPB',
    'sacombank': 'STB',
    'stb': 'STB',
    'vib': 'VIB',
    'msb': 'MSB',
    'hdbank': 'HDB',
    'ocb': 'OCB',
    'timo': 'TIMO',
    'cake': 'CAKE',
    'momo': 'MOMO',
    'zalopay': 'ZALOPAY',
    'tien mat': 'CASH',
    'vi tien mat': 'CASH',
    'tiet kiem': 'SAVINGS',
    'so tiet kiem': 'SAVINGS',
  };

  static const List<String> _vehicleKeywords = <String>[
    'sh mode',
    'air blade',
    'airblade',
    'vision',
    'lead',
    'wave',
    'winner',
    'exciter',
    'sirius',
    'vario',
    'grande',
    'janus',
    'nvx',
    'vespa',
    'liberty',
    'vinfast',
    'klara',
    'evo200',
    'vf3',
    'vf5',
    'vf8',
    'vios',
    'city',
    'cr-v',
    'crv',
    'mazda',
    'cx-5',
    'cx5',
    'toyota',
    'hyundai',
    'accent',
    'kia',
    'ford',
    'ranger',
    'honda',
    'yamaha',
    'xe máy',
    'xe tay ga',
    'xe số',
    'ô tô',
    'xe hơi',
  ];

  /// Returns true if the numeric match `[startIndex, endIndex)` has NO currency suffix
  /// and is immediately followed by a physical/measurement unit like `km`, `ml`, `viên`, `phút`, `kg`, `%`.
  static bool isFollowedByNonCurrencyUnit(
    String text,
    int matchEnd, {
    required bool hasExplicitCurrencySuffix,
  }) {
    if (hasExplicitCurrencySuffix || matchEnd >= text.length) {
      return false;
    }
    final after = text.substring(matchEnd).trimLeft();
    if (after.isEmpty) return false;
    return _nonCurrencyUnitAfterNumber.hasMatch(after);
  }

  /// Extracts odometer reading, vehicle hint, wallet hints, and location from Vietnamese text.
  static VietnameseEntitySnapshot extractEntities(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return const VietnameseEntitySnapshot();
    final lower = trimmed.toLowerCase();
    final ascii = FinancialTextNormalizer.stripVnAccents(trimmed);

    // 1. Odometer (e.g. "14.000 km", "odo 14500")
    int? odoKm;
    final odoMatch = _odoRegex.firstMatch(trimmed);
    if (odoMatch != null) {
      final rawDigits = (odoMatch.group(1) ?? odoMatch.group(2) ?? '')
          .replaceAll(RegExp(r'[.,]'), '');
      final parsed = int.tryParse(rawDigits);
      if (parsed != null && parsed > 0 && parsed < 2000000) {
        odoKm = parsed;
      }
    }

    // 2. Vehicle hint (model name or license plate)
    String? vehicleHint;
    for (final kw in _vehicleKeywords) {
      if (RegExp(
        '(?<![\\p{L}\\p{N}])${RegExp.escape(kw)}(?![\\p{L}\\p{N}])',
        caseSensitive: false,
        unicode: true,
      ).hasMatch(lower)) {
        vehicleHint = kw
            .split(' ')
            .map(
              (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
            )
            .join(' ');
        break;
      }
    }
    if (vehicleHint == null) {
      final plate = _plateRegex.firstMatch(trimmed);
      if (plate != null) {
        vehicleHint = plate.group(0)!.toUpperCase();
      }
    }

    // 3. Source & Destination wallet hints ("từ VCB sang MoMo", "bằng ví MoMo", "qua thẻ TCB")
    String? walletHint;
    String? destWalletHint;
    final transferMatch = RegExp(
      r'\btu\s+([a-z0-9\s]{2,24}?)\s+(?:sang|qua|vao|den)\s+([a-z0-9\s]{2,24})\b',
    ).firstMatch(ascii);
    if (transferMatch != null) {
      walletHint = _matchWalletAlias(transferMatch.group(1)!);
      destWalletHint = _matchWalletAlias(transferMatch.group(2)!);
    }
    walletHint ??= _matchWalletAlias(ascii);

    // 4. Location hint ("tại ...", "ở ...")
    String? location;
    final locMatch = RegExp(
      r'(?:tại|ở)\s+([A-Za-zÀ-ỹ0-9\s.,-]{2,40}?)(?=$|,|;|\bvà\b|\blúc\b|\bvào\b)',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(trimmed);
    if (locMatch != null) {
      final cand = locMatch.group(1)!.trim();
      if (cand.length >= 2 &&
          !RegExp(r'^\d+$').hasMatch(cand) &&
          !cand.toLowerCase().startsWith('nhà ')) {
        location = cand;
      }
    }

    return VietnameseEntitySnapshot(
      walletHint: walletHint,
      destinationWalletHint: destWalletHint,
      vehicleHint: vehicleHint,
      odometerKm: odoKm,
      locationHint: location,
    );
  }

  static String? _matchWalletAlias(String ascii) {
    // Prefer multi-word aliases first ("vi tien mat", "mb bank")
    final sortedKeys = _walletAliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final k in sortedKeys) {
      if (RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(ascii)) {
        return _walletAliases[k];
      }
    }
    return null;
  }

  /// Resolves Vietnamese temporal expressions:
  /// - `sau 30 phút`, `30 phút nữa`, `sau 2 tiếng`, `2 giờ nữa`
  /// - `20:00`, `8 giờ tối`, `8h30 tối`, `lúc 9 giờ`, `8 rưỡi sáng`
  /// - `chiều mai`, `sáng mốt`, `cuối tuần này`, `cuối tuần sau`
  /// - `thứ sáu tuần này`, `thứ hai tuần sau`, `thứ ba tuần trước`
  /// - `mùng 5 tháng sau`, `15 tháng 12`, `15/12/2026`
  static VietnameseTemporalResolution resolveTemporal(
    String rawClause, {
    required DateTime referenceNow,
    int defaultHour = 9,
  }) {
    var working = rawClause;
    final ascii = FinancialTextNormalizer.stripVnAccents(rawClause);

    // 0. Duration ("trong 45 phút", "kéo dài 2 tiếng")
    int? durationMinutes;
    final durMatch = RegExp(
      r'\b(?:trong|keo\s+dai|khoang)\s+(\d+)\s*(phut|tieng|gio)\b',
    ).firstMatch(ascii);
    if (durMatch != null) {
      final val = int.tryParse(durMatch.group(1) ?? '');
      final unit = durMatch.group(2) ?? '';
      if (val != null && val > 0) {
        durationMinutes = (unit == 'tieng' || unit == 'gio') ? val * 60 : val;
      }
    }

    // 1. Relative offset ("sau 30 phút", "30 phút nữa", "sau 2 tiếng", "1 tiếng rưỡi nữa")
    final relOffsetMatch = RegExp(
      r'(?:(?:sau|trong)\s+(\d{1,3})\s*(phut|tieng|gio)(?:\s*(ruoi))?|(\d{1,3})\s*(phut|tieng|gio)(?:\s*(ruoi))?\s+nua)\b',
    ).firstMatch(ascii);
    if (relOffsetMatch != null) {
      final n =
          int.tryParse(
            relOffsetMatch.group(1) ?? relOffsetMatch.group(4) ?? '',
          ) ??
          0;
      final unit = relOffsetMatch.group(2) ?? relOffsetMatch.group(5) ?? '';
      final half =
          (relOffsetMatch.group(3) ?? relOffsetMatch.group(6) ?? '').isNotEmpty;
      if (n > 0) {
        final mins = (unit == 'tieng' || unit == 'gio')
            ? (n * 60 + (half ? 30 : 0))
            : n;
        final target = referenceNow.add(Duration(minutes: mins));
        working = _stripRange(
          working,
          relOffsetMatch.start,
          relOffsetMatch.end,
        );
        return VietnameseTemporalResolution(
          dateTime: target,
          hasExplicitDate: true,
          hasExplicitTime: true,
          durationMinutes: durationMinutes,
          cleanedText: _tidyTitle(working),
        );
      }
    }

    var targetDate = DateTime(
      referenceNow.year,
      referenceNow.month,
      referenceNow.day,
    );
    var hasExplicitDate = false;
    var hasExplicitTime = false;
    var hour = defaultHour;
    var minute = 0;

    // 2. Date extraction
    // 2a. Explicit dd/MM(/yyyy) or dd-MM(-yyyy)
    final slashDate = RegExp(
      r'\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{4}))?\b',
    ).firstMatch(working);
    if (slashDate != null) {
      final d = int.tryParse(slashDate.group(1)!) ?? referenceNow.day;
      final mo = int.tryParse(slashDate.group(2)!) ?? referenceNow.month;
      final y = int.tryParse(slashDate.group(3) ?? '') ?? referenceNow.year;
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        final safeDay = _clampDay(y, mo, d);
        targetDate = DateTime(y, mo, safeDay);
        hasExplicitDate = true;
        working = _stripRange(working, slashDate.start, slashDate.end);
      }
    }

    // 2b. "mùng 5 tháng sau" / "ngày 15 tháng tới" / "15 tháng 12" / "mùng 5 tháng này"
    if (!hasExplicitDate) {
      final asciiWork = FinancialTextNormalizer.stripVnAccents(working);
      final dayMonthMatch = RegExp(
        r'\b(?:mung|mong|ngay)?\s*(\d{1,2})\s+thang\s+(sau|toi|nay|\d{1,2})(?:\s+nam\s+(\d{4}))?\b',
      ).firstMatch(asciiWork);
      if (dayMonthMatch != null) {
        final d = int.tryParse(dayMonthMatch.group(1) ?? '') ?? 1;
        final monthSpec = dayMonthMatch.group(2) ?? '';
        final explicitYear = int.tryParse(dayMonthMatch.group(3) ?? '');
        var targetYear = explicitYear ?? referenceNow.year;
        var targetMonth = referenceNow.month;
        if (monthSpec == 'sau' || monthSpec == 'toi') {
          targetMonth = referenceNow.month == 12 ? 1 : referenceNow.month + 1;
          if (referenceNow.month == 12 && explicitYear == null) {
            targetYear += 1;
          }
        } else if (monthSpec != 'nay') {
          targetMonth = int.tryParse(monthSpec) ?? referenceNow.month;
        }
        if (targetMonth >= 1 && targetMonth <= 12 && d >= 1 && d <= 31) {
          final safeDay = _clampDay(targetYear, targetMonth, d);
          targetDate = DateTime(targetYear, targetMonth, safeDay);
          hasExplicitDate = true;
          working = _stripRegexPreserveLength(
            working,
            RegExp(
              r'\b(?:mùng|mồng|mung|mong|ngày|ngay)?\s*\d{1,2}\s+tháng\s+(?:sau|tới|nay|\d{1,2})(?:\s+năm\s+\d{4})?\b|\b(?:mung|mong|ngay)?\s*\d{1,2}\s+thang\s+(?:sau|toi|nay|\d{1,2})(?:\s+nam\s+\d{4})?\b',
              caseSensitive: false,
              unicode: true,
            ),
          );
        }
      }
    }

    // 2c. Relative day words ("hôm kia", "hôm qua", "hôm nay", "ngày mai", "ngày mốt", "ngày kia", "cuối tuần sau/này")
    if (!hasExplicitDate) {
      final asciiWork = FinancialTextNormalizer.stripVnAccents(working);
      if (RegExp(r'\bhom\s+kia\b').hasMatch(asciiWork)) {
        targetDate = targetDate.subtract(const Duration(days: 2));
        hasExplicitDate = true;
      } else if (RegExp(
        r'\b(?:hom|sang|trua|chieu|toi|dem)\s+qua\b',
      ).hasMatch(asciiWork)) {
        targetDate = targetDate.subtract(const Duration(days: 1));
        hasExplicitDate = true;
      } else if (RegExp(
        r'\b(?:ngay\s+kia|ngay\s+mot|sang\s+mot|trua\s+mot|chieu\s+mot|toi\s+mot)\b',
      ).hasMatch(asciiWork)) {
        targetDate = targetDate.add(const Duration(days: 2));
        hasExplicitDate = true;
      } else if (RegExp(
        r'\b(?:ngay\s+mai|sang\s+mai|trua\s+mai|chieu\s+mai|toi\s+mai|mai)\b',
      ).hasMatch(asciiWork)) {
        targetDate = targetDate.add(const Duration(days: 1));
        hasExplicitDate = true;
      } else if (RegExp(
        r'\b(?:hom|sang|trua|chieu|toi)\s+nay\b',
      ).hasMatch(asciiWork)) {
        hasExplicitDate = true;
      } else if (RegExp(r'\bcuoi\s+tuan\s+(?:sau|toi)\b').hasMatch(asciiWork)) {
        final currentMonday = targetDate.subtract(
          Duration(days: referenceNow.weekday - DateTime.monday),
        );
        final nextWeekSaturday = currentMonday.add(const Duration(days: 12));
        targetDate = nextWeekSaturday;
        hasExplicitDate = true;
      } else if (RegExp(r'\bcuoi\s+tuan(?:\s+nay)?\b').hasMatch(asciiWork)) {
        final daysUntilSat = (DateTime.saturday - referenceNow.weekday) % 7;
        targetDate = targetDate.add(
          Duration(days: daysUntilSat == 0 ? 0 : daysUntilSat),
        );
        hasExplicitDate = true;
      } else {
        // Weekdays: "thứ sáu tuần này", "thứ hai tuần sau", "thứ hai tuần trước", bare "thứ sáu"
        const weekdayMap = <String, int>{
          'thu 2': DateTime.monday,
          'thu hai': DateTime.monday,
          'thu 3': DateTime.tuesday,
          'thu ba': DateTime.tuesday,
          'thu 4': DateTime.wednesday,
          'thu tu': DateTime.wednesday,
          'thu 5': DateTime.thursday,
          'thu nam': DateTime.thursday,
          'thu 6': DateTime.friday,
          'thu sau': DateTime.friday,
          'thu 7': DateTime.saturday,
          'thu bay': DateTime.saturday,
          'chu nhat': DateTime.sunday,
          'cn': DateTime.sunday,
        };
        final currentMonday = targetDate.subtract(
          Duration(days: referenceNow.weekday - DateTime.monday),
        );
        for (final entry in weekdayMap.entries) {
          final nextMatch = RegExp(
            '\\b${entry.key}\\s+tuan\\s+(?:sau|toi)\\b',
          ).firstMatch(asciiWork);
          if (nextMatch != null) {
            targetDate = currentMonday.add(
              Duration(days: 7 + (entry.value - DateTime.monday)),
            );
            hasExplicitDate = true;
            break;
          }
          final thisMatch = RegExp(
            '\\b${entry.key}\\s+tuan\\s+nay\\b',
          ).firstMatch(asciiWork);
          if (thisMatch != null) {
            targetDate = currentMonday.add(
              Duration(days: entry.value - DateTime.monday),
            );
            hasExplicitDate = true;
            break;
          }
          final prevMatch = RegExp(
            '\\b${entry.key}\\s+tuan\\s+truoc\\b',
          ).firstMatch(asciiWork);
          if (prevMatch != null) {
            targetDate = currentMonday.subtract(
              Duration(days: 7 - (entry.value - DateTime.monday)),
            );
            hasExplicitDate = true;
            break;
          }
          final bareMatch = RegExp('\\b${entry.key}\\b').firstMatch(asciiWork);
          if (bareMatch != null) {
            var diff = entry.value - referenceNow.weekday;
            if (diff <= 0) diff += 7;
            targetDate = targetDate.add(Duration(days: diff));
            hasExplicitDate = true;
            break;
          }
        }
      }
    }

    // 3. Part-of-day default hour ("sáng" -> 8, "trưa" -> 12, "chiều" -> 15, "tối" -> 20)
    if (RegExp(r'\b(?:sang|buoi\s+sang)\b').hasMatch(ascii)) {
      hour = 8;
    } else if (RegExp(r'\b(?:trua|buoi\s+trua)\b').hasMatch(ascii)) {
      hour = 12;
    } else if (RegExp(r'\b(?:chieu|buoi\s+chieu)\b').hasMatch(ascii)) {
      hour = 15;
    } else if (RegExp(r'\b(?:toi|buoi\s+toi|dem)\b').hasMatch(ascii)) {
      hour = 20;
    }

    // 4. Explicit time: "20:00", "8h30", "8 giờ tối", "9 giờ sáng", "lúc 9 giờ", "8 rưỡi tối"
    final explicitTimeRegex = RegExp(
      r'(?<![\p{L}\p{N}])(\d{1,2})\s*(?:(?::|h)\s*(\d{1,2})?|(?:giờ|gio)\s*(?:(\d{1,2})(?!\s*(?:người|nguoi|bạn|ban|cái|cai|kg|km|k|tr|triệu|trieu|lần|lan|viên|vien))|(rưỡi|ruoi))?|(rưỡi|ruoi)\s*(?=sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem))\s*(sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem)?(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    final tmMatch = explicitTimeRegex.firstMatch(working);
    if (tmMatch != null) {
      final parsedH = int.tryParse(tmMatch.group(1) ?? '');
      final rawMin =
          tmMatch.group(2) ??
          tmMatch.group(3) ??
          tmMatch.group(4) ??
          tmMatch.group(5);
      var periodStr = FinancialTextNormalizer.stripVnAccents(
        tmMatch.group(6) ?? '',
      );
      if (periodStr.isEmpty) {
        // Inherit leading part-of-day ("tối 8 giờ", "chiều mai 3 giờ")
        final before = FinancialTextNormalizer.stripVnAccents(
          working.substring(0, tmMatch.start),
        );
        if (before.contains('toi') || before.contains('dem')) {
          periodStr = 'toi';
        } else if (before.contains('chieu')) {
          periodStr = 'chieu';
        } else if (before.contains('trua')) {
          periodStr = 'trua';
        } else if (before.contains('sang')) {
          periodStr = 'sang';
        }
      }
      if (parsedH != null && parsedH >= 0 && parsedH <= 23) {
        hour = parsedH;
        if ((periodStr.contains('chieu') ||
                periodStr.contains('toi') ||
                periodStr.contains('dem')) &&
            hour >= 1 &&
            hour < 12) {
          hour += 12;
        } else if (periodStr.contains('sang') && hour == 12) {
          hour = 0;
        }
        hasExplicitTime = true;
      }
      if (rawMin != null && rawMin.isNotEmpty) {
        final minFolded = FinancialTextNormalizer.stripVnAccents(rawMin);
        if (minFolded.contains('ruoi')) {
          minute = 30;
        } else {
          final parsedM = int.tryParse(minFolded);
          if (parsedM != null && parsedM >= 0 && parsedM <= 59) {
            minute = parsedM;
          }
        }
      }
      working = _stripRange(working, tmMatch.start, tmMatch.end);
    }

    // Strip relative date / time filler words cleanly for human-readable title
    working = working
        .replaceAll(
          RegExp(
            r'(?<![\p{L}\p{N}])(?:vào\s+lúc|vào|lúc|vao\s+luc|vao|luc|sáng\s+mai|chiều\s+mai|tối\s+mai|trưa\s+mai|ngày\s+mai|mai|sáng\s+mốt|chiều\s+mốt|tối\s+mốt|trưa\s+mốt|ngày\s+mốt|ngày\s+kia|hôm\s+nay|tối\s+nay|chiều\s+nay|sáng\s+nay|trưa\s+nay|hôm\s+qua|hôm\s+kia|cuối\s+tuần\s+sau|cuối\s+tuần\s+tới|cuối\s+tuần\s+này|cuối\s+tuần|tuần\s+này|tuần\s+sau|tuần\s+tới|tuần\s+trước|tháng\s+sau|tháng\s+tới|tháng\s+này|thứ\s+(?:hai|ba|tư|năm|sáu|bảy|[2-7])|chủ\s+nhật|buổi\s+sáng|buổi\s+trưa|buổi\s+chiều|buổi\s+tối|sáng|trưa|chiều|tối)(?![\p{L}\p{N}])',
            caseSensitive: false,
            unicode: true,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'(?<![\p{L}\p{N}])(?:sang\s+mai|chieu\s+mai|toi\s+mai|trua\s+mai|ngay\s+mai|sang\s+mot|chieu\s+mot|toi\s+mot|trua\s+mot|ngay\s+mot|ngay\s+kia|hom\s+nay|toi\s+nay|chieu\s+nay|sang\s+nay|trua\s+nay|hom\s+qua|hom\s+kia|cuoi\s+tuan\s+sau|cuoi\s+tuan\s+toi|cuoi\s+tuan\s+nay|cuoi\s+tuan|tuan\s+nay|tuan\s+sau|tuan\s+toi|tuan\s+truoc|thang\s+sau|thang\s+toi|thang\s+nay|thu\s+(?:hai|ba|tu|nam|sau|bay|[2-7])|chu\s+nhat|buoi\s+sang|buoi\s+trua|buoi\s+chieu|buoi\s+toi)(?![\p{L}\p{N}])',
            caseSensitive: false,
            unicode: true,
          ),
          ' ',
        );

    return VietnameseTemporalResolution(
      dateTime: DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        hour,
        minute,
      ),
      hasExplicitDate: hasExplicitDate,
      hasExplicitTime: hasExplicitTime,
      durationMinutes: durationMinutes,
      cleanedText: _tidyTitle(working),
    );
  }

  static int _clampDay(int year, int month, int day) {
    final maxD = DateTime(year, month + 1, 0).day;
    return day > maxD ? maxD : day;
  }

  static String _stripRange(String s, int start, int end) {
    return '${s.substring(0, start)} ${s.substring(end)}';
  }

  static String _stripRegexPreserveLength(String s, RegExp rx) {
    return s.replaceAll(rx, ' ');
  }

  static String _tidyTitle(String s) {
    return s
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[-:,.\s]+|[-:,.\s]+$'), '')
        .trim();
  }
}
