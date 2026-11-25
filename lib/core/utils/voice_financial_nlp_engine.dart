import '../../features/family/domain/entities/family_entities.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import 'smart_money_split_ai_engine.dart';
import 'smart_quick_entry_parser.dart';
import 'vietnamese_temporal_and_entity_resolver.dart';

export 'smart_money_split_ai_engine.dart'
    show SplitValidationStatus, ParticipantResolutionOutcome;

enum VoiceSentenceIntentKind {
  singleTransaction,
  batchTransactions,
  multiCategoryReceipt,
  groupBillSplit,
}

class ParsedParticipantShare {
  final String participantId;
  final String displayName;
  final int amountMinor;
  final int? percentage;
  final int? sharesWeight;

  const ParsedParticipantShare({
    required this.participantId,
    required this.displayName,
    required this.amountMinor,
    this.percentage,
    this.sharesWeight,
  });
}

class ParsedGroupSplitIntent {
  final String title;
  final int totalAmountMinor;
  final SharedExpenseTopic topic;
  final SplitMethod splitMethod;
  final String? paidByParticipantId;
  final String? paidByDisplayName;
  final List<ParsedParticipantShare> shares;
  final Map<String, int> rawInputValuesByUserId;
  final SplitValidationStatus validationStatus;
  final String? validationMessageVi;
  final List<ParticipantResolutionOutcome> ambiguousParticipants;

  const ParsedGroupSplitIntent({
    required this.title,
    required this.totalAmountMinor,
    required this.topic,
    required this.splitMethod,
    this.paidByParticipantId,
    this.paidByDisplayName,
    required this.shares,
    required this.rawInputValuesByUserId,
    this.validationStatus = SplitValidationStatus.valid,
    this.validationMessageVi,
    this.ambiguousParticipants = const <ParticipantResolutionOutcome>[],
  });

  bool get isValid => validationStatus == SplitValidationStatus.valid;
}

class ParsedMultiCategoryReceiptIntent {
  final String merchant;
  final int totalAmountMinor;
  final List<TransactionSplitLine> splitLines;
  final SplitValidationStatus validationStatus;
  final String? validationMessageVi;

  const ParsedMultiCategoryReceiptIntent({
    required this.merchant,
    required this.totalAmountMinor,
    required this.splitLines,
    this.validationStatus = SplitValidationStatus.valid,
    this.validationMessageVi,
  });

  bool get isValid => validationStatus == SplitValidationStatus.valid;
}

class VoiceFinancialAnalysisResult {
  final String originalText;
  final String normalizedText;
  final VoiceSentenceIntentKind intentKind;
  final List<ParsedSmartEntry> personalEntries;
  final ParsedMultiCategoryReceiptIntent? multiCategoryReceipt;
  final ParsedGroupSplitIntent? groupSplit;
  final String summaryHeadline;

  const VoiceFinancialAnalysisResult({
    required this.originalText,
    required this.normalizedText,
    required this.intentKind,
    this.personalEntries = const [],
    this.multiCategoryReceipt,
    this.groupSplit,
    required this.summaryHeadline,
  });
}

/// Deep Vietnamese Spoken Currency & Natural Language Sentence Analyzer for Life OS.
/// Understands spoken Vietnamese numbers ("mười tám triệu rưỡi", "bốn trăm năm mươi nghìn",
/// "hai trăm rưỡi", "1 triệu 2", "củ", "lít", "cành") and classifies spoken sentences into:
/// 1. Group / Family / Roommate Bill Splitting (Equal, Exact per person, Remainder, Percentage)
/// 2. Multi-Category Single Receipt Splitting ("siêu thị 500k gồm ăn uống 320k việc nhà 180k")
/// 3. Multi-Item Batch Personal Ledger Recording ("sáng ăn phở 65k đổ xăng 90k nhận lương 18tr5")
/// 4. Single Fast Income / Expense Entry
abstract final class VoiceFinancialNlpEngine {
  static const Map<String, int> _vnDigitWords = {
    'không': 0,
    'linh': 0,
    'lẻ': 0,
    'một': 1,
    'mốt': 1,
    'hai': 2,
    'ba': 3,
    'bốn': 4,
    'tư': 4,
    'năm': 5,
    'lăm': 5,
    'nhăm': 5,
    'sáu': 6,
    'bảy': 7,
    'bẩy': 7,
    'tám': 8,
    'chín': 9,
    'mười': 10,
  };

  /// Converts common spoken Vietnamese currency phrases into numeric shorthand
  /// so downstream regexes parse spoken ASR transcripts accurately.
  static String normalizeSpokenVietnamese(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;

    // Normalize common spoken currency slang & words
    s = s
        .replaceAll(RegExp(r'\bnửa\s+triệu\b', caseSensitive: false), '500k')
        .replaceAll(RegExp(r'\bnửa\s+củ\b', caseSensitive: false), '500k')
        .replaceAll(
          RegExp(r'\bmột\s+củ\s+rưỡi\b', caseSensitive: false),
          '1tr5',
        )
        .replaceAll(
          RegExp(r'\bmột\s+triệu\s+rưỡi\b', caseSensitive: false),
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
        )
        .replaceAll(
          RegExp(r'\bmột\s+trăm\s+rưỡi\b', caseSensitive: false),
          '150k',
        )
        .replaceAll(RegExp(r'\bphần\s+trăm\b', caseSensitive: false), '%')
        .replaceAll(
          RegExp(r'\bchia\s+đôi\b', caseSensitive: false),
          'chia đều 2 người',
        )
        .replaceAll(RegExp(r'\bcampuchia\b', caseSensitive: false), 'chia đều');

    // Convert "<number> triệu rưỡi" / "<number> củ rưỡi" -> "<number>tr5"
    s = s.replaceAllMapped(
      RegExp(
        r'(\d+)\s*(?:triệu|trieu|tr|củ|cu)\s*rưỡi\b',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}tr5',
    );

    // Convert "<number> trăm rưỡi" -> "<number>50k"
    s = s.replaceAllMapped(
      RegExp(r'(\d+)\s*trăm\s*rưỡi\b', caseSensitive: false),
      (m) => '${m.group(1)}50k',
    );

    // Convert "<number> lít" -> "<number>00k" (Vietnamese slang: 1 lít = 100k, skipping fuel/liquid)
    s = s.replaceAllMapped(
      RegExp(
        r'\b(\d+)\s*lít\b(?!(?:\s+(?:xăng|dầu|nước|sữa|bia|rượu|nhớt|gas)\b))',
        caseSensitive: false,
      ),
      (m) => '${(int.tryParse(m.group(1) ?? '0') ?? 0) * 100}k',
    );

    // Convert "<number> chục" -> "<number>0k" ("5 chục" -> "50k")
    s = s.replaceAllMapped(
      RegExp(r'\b(\d+)\s*chục\b', caseSensitive: false),
      (m) => '${(int.tryParse(m.group(1) ?? '0') ?? 0) * 10}k',
    );

    // Convert "<number> cành" -> "<number>k"
    s = s.replaceAllMapped(
      RegExp(r'\b(\d+)\s*cành\b', caseSensitive: false),
      (m) => '${m.group(1)}k',
    );

    // Convert simple spoken Vietnamese tens/hundreds before triệu/nghìn/ngàn
    // e.g. "mười tám triệu rưỡi", "bốn trăm năm mươi nghìn", "sáu mươi lăm nghìn"
    s = _replaceSpokenNumberBeforeUnit(s);

    // Re-apply "<number> triệu rưỡi" after word-to-digit conversion!
    s = s.replaceAllMapped(
      RegExp(
        r'(\d+)\s*(?:triệu|trieu|tr|củ|cu)\s*rưỡi\b',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}tr5',
    );

    return s;
  }

  static String _replaceSpokenNumberBeforeUnit(String input) {
    final unitPattern = RegExp(
      r'((?:(?:không|một|mốt|hai|ba|bốn|tư|năm|lăm|sáu|bảy|tám|chín|mười|mươi|trăm|linh|lẻ)\s+){1,6})(triệu|nghìn|ngàn|củ|người)\b',
      caseSensitive: false,
    );
    return input.replaceAllMapped(unitPattern, (match) {
      final wordsStr = (match.group(1) ?? '').trim().toLowerCase();
      final unit = match.group(2) ?? '';
      final val = _parseSpokenSmallNumber(wordsStr);
      if (val == null || val <= 0) return match.group(0) ?? '';
      return '$val $unit';
    });
  }

  static int? _parseSpokenSmallNumber(String phrase) {
    final tokens = phrase
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    var hundreds = 0;
    var tens = 0;
    var ones = 0;
    var i = 0;

    if (i + 1 < tokens.length && tokens[i + 1] == 'trăm') {
      final h = _vnDigitWords[tokens[i]];
      if (h == null) return null;
      hundreds = h * 100;
      i += 2;
      if (i < tokens.length && (tokens[i] == 'linh' || tokens[i] == 'lẻ')) {
        i += 1;
      }
    }

    if (i < tokens.length) {
      if (tokens[i] == 'mười') {
        tens = 10;
        i += 1;
        if (i < tokens.length && _vnDigitWords.containsKey(tokens[i])) {
          ones = _vnDigitWords[tokens[i]]!;
          i += 1;
        }
      } else if (i + 1 < tokens.length && tokens[i + 1] == 'mươi') {
        final t = _vnDigitWords[tokens[i]];
        if (t == null) return null;
        tens = t * 10;
        i += 2;
        if (i < tokens.length && _vnDigitWords.containsKey(tokens[i])) {
          ones = _vnDigitWords[tokens[i]]!;
          i += 1;
        }
      } else if (_vnDigitWords.containsKey(tokens[i])) {
        ones = _vnDigitWords[tokens[i]]!;
        i += 1;
      }
    }

    final sum = hundreds + tens + ones;
    return sum > 0 ? sum : null;
  }

  static final RegExp _amountTokenRegex = RegExp(
    r'(\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu)(?:\s*\d{1,3})?|\d+(?:[.,]\d+)?\s*(?:k|nghìn|nghin|ngàn|ngan)(?:\s*\d{1,2})?|\d{1,3}(?:[.,]\d{3})+\s*(?:đ|d|vnd|vnđ)?|\b\d{5,11}\s*(?:đ|d|vnd|vnđ)?)\b',
    caseSensitive: false,
  );

  static SharedExpenseTopic inferSharedTopic(String text) {
    final l = text.toLowerCase();
    if (l.contains('việc nhà') ||
        l.contains('nước giặt') ||
        l.contains('lau nhà') ||
        l.contains('rác') ||
        l.contains('dọn') ||
        l.contains('rửa chén')) {
      return SharedExpenseTopic.housework;
    }
    if (l.contains('điện') ||
        l.contains('nước') ||
        l.contains('wifi') ||
        l.contains('internet')) {
      return SharedExpenseTopic.utilities;
    }
    if (l.contains('tiền nhà') ||
        l.contains('tiền phòng') ||
        l.contains('thuê') ||
        l.contains('chung cư')) {
      return SharedExpenseTopic.housing;
    }
    if (l.contains('du lịch') ||
        l.contains('vé') ||
        l.contains('khách sạn') ||
        l.contains('homestay')) {
      return SharedExpenseTopic.travel;
    }
    if (l.contains('siêu thị') ||
        l.contains('đi chợ') ||
        l.contains('bách hóa')) {
      return SharedExpenseTopic.shopping;
    }
    if (l.contains('ăn') ||
        l.contains('lẩu') ||
        l.contains('nướng') ||
        l.contains('cafe') ||
        l.contains('cà phê') ||
        l.contains('trà sữa') ||
        l.contains('nhậu') ||
        l.contains('bữa')) {
      return SharedExpenseTopic.dining;
    }
    return SharedExpenseTopic.other;
  }

  static List<RegExpMatch> _extractValidMoneyMatches(String text) {
    final matches = <RegExpMatch>[];
    for (final m in _amountTokenRegex.allMatches(text)) {
      final tok = (m.group(0) ?? '').trim();
      final hasSuffix = RegExp(
        r'(?:đ|d|₫|vnd|vnđ|đồng|dong|tr|triệu|trieu|củ|cu|k|nghìn|nghin|ngàn|ngan)\s*$',
        caseSensitive: false,
      ).hasMatch(tok);
      if (VietnameseTemporalAndEntityResolver.isFollowedByNonCurrencyUnit(
        text,
        m.end,
        hasExplicitCurrencySuffix: hasSuffix,
      )) {
        continue;
      }
      matches.add(m);
    }
    return matches;
  }

  /// Analyzes any spoken or typed Vietnamese sentence and returns structured financial intent.
  static VoiceFinancialAnalysisResult? analyze(
    String rawTranscript, {
    String currentUserId = 'me',
    String currentUserName = 'Tôi',
    List<FamilyMemberInfo> knownMembers = const [],
    Map<String, List<String>> nicknamesByUserId = const {},
    Map<String, String> explicitParticipantOverrides = const {},
  }) {
    final raw = rawTranscript.trim();
    if (raw.isEmpty) return null;

    final normalized = normalizeSpokenVietnamese(raw);
    final lower = normalized.toLowerCase();

    // 1. Check Multi-Category Single Receipt Split ("siêu thị 500k gồm ăn uống 320k việc nhà 180k")
    if (_looksLikeMultiCategoryReceipt(lower)) {
      if (ClauseSafetyScreener.screenClause(raw).isBlocked) {
        return null;
      }
      final receipt = _tryParseMultiCategoryReceipt(normalized);
      if (receipt != null) {
        return VoiceFinancialAnalysisResult(
          originalText: raw,
          normalizedText: normalized,
          intentKind: VoiceSentenceIntentKind.multiCategoryReceipt,
          multiCategoryReceipt: receipt,
          summaryHeadline:
              receipt.validationStatus ==
                      SplitValidationStatus.requiresConfirmation
                  ? 'Cảnh báo lệch tổng (${receipt.splitLines.length} hạng mục) · Tổng ${_fmtShort(receipt.totalAmountMinor)}'
                  : 'Tách 1 hóa đơn (${receipt.splitLines.length} hạng mục) · Tổng ${_fmtShort(receipt.totalAmountMinor)}',
        );
      }
    }

    // 2. Check Group / Family / Roommate Bill Split ("chia đều", "chia cho", "%", per-person shares)
    if (_looksLikeGroupSplit(lower)) {
      if (!ClauseSafetyScreener.screenClause(raw).isBlocked) {
        final split = _tryParseGroupSplit(
          normalized,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          knownMembers: knownMembers,
          nicknamesByUserId: nicknamesByUserId,
          explicitParticipantOverrides: explicitParticipantOverrides,
        );
        if (split != null) {
          return VoiceFinancialAnalysisResult(
            originalText: raw,
            normalizedText: normalized,
            intentKind: VoiceSentenceIntentKind.groupBillSplit,
            groupSplit: split,
            summaryHeadline:
                split.isValid
                    ? 'Chia tiền nhóm (${split.shares.length} người · ${split.splitMethod.displayLabel.split('(').first.trim()})'
                    : 'Cần kiểm tra chia tiền (${split.validationMessageVi ?? 'Chưa hợp lệ'})',
          );
        }
      } else {
        return null;
      }
    }

    // 3. Clause-safe Multi-Item / Single Ledger Extraction
    final clauses = raw
        .split(
          RegExp(
            r'(?:[,;\n]+|\s+(?:và|rồi|sau\s+đó|với\s+lại|kèm\s+theo)\s+)',
            caseSensitive: false,
          ),
        )
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    final extractedEntries = <ParsedSmartEntry>[];
    for (final rawClause in clauses) {
      if (ClauseSafetyScreener.screenClause(rawClause).isBlocked) {
        continue;
      }
      final normClause = normalizeSpokenVietnamese(rawClause);
      final amountMatches = _extractValidMoneyMatches(normClause);
      if (amountMatches.isEmpty) continue;

      if (amountMatches.length >= 2) {
        var cursor = 0;
        for (final m in amountMatches) {
          final segment = normClause.substring(cursor, m.end).trim();
          cursor = m.end;
          final cleanedSeg = segment
              .replaceAll(
                RegExp(
                  r'^[,;.\s]+|\b(và|rồi|xong|tiếp)\b',
                  caseSensitive: false,
                ),
                ' ',
              )
              .trim();
          final parsed = SmartQuickEntryParser.tryParse(cleanedSeg);
          if (parsed != null) {
            extractedEntries.add(parsed);
          }
        }
      } else {
        final parsed = SmartQuickEntryParser.tryParse(normClause);
        if (parsed != null) {
          extractedEntries.add(parsed);
        }
      }
    }

    if (extractedEntries.length >= 2) {
      return VoiceFinancialAnalysisResult(
        originalText: raw,
        normalizedText: normalized,
        intentKind: VoiceSentenceIntentKind.batchTransactions,
        personalEntries: extractedEntries,
        summaryHeadline:
            'Ghi hàng loạt ${extractedEntries.length} bút toán trong 1 câu nói',
      );
    }

    if (extractedEntries.length == 1) {
      final single = extractedEntries.single;
      return VoiceFinancialAnalysisResult(
        originalText: raw,
        normalizedText: normalized,
        intentKind: VoiceSentenceIntentKind.singleTransaction,
        personalEntries: [single],
        summaryHeadline:
            '${single.kind == TransactionKind.income ? "Thu nhập" : "Chi tiêu"} · ${single.categoryName}',
      );
    }

    return null;
  }

  static bool _looksLikeMultiCategoryReceipt(String lower) {
    if (SmartMoneySplitAiEngine.looksLikeGroupSplitUtterance(lower)) {
      return false;
    }
    return lower.contains(' gồm ') ||
        lower.contains(' bao gồm ') ||
        lower.contains(' trong đó ') ||
        lower.contains(' tách ');
  }

  static ParsedMultiCategoryReceiptIntent? _tryParseMultiCategoryReceipt(
    String normalized,
  ) {
    final splitMatch = RegExp(
      r'\b(bao\s+gồm|trong\s+đó|gồm|tách)\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (splitMatch == null) return null;

    final head = normalized.substring(0, splitMatch.start).trim();
    final tail = normalized.substring(splitMatch.end).trim();

    final headEntry = SmartQuickEntryParser.tryParse(head);
    final matches = _extractValidMoneyMatches(tail);
    if (matches.isEmpty) return null;

    final lines = <TransactionSplitLine>[];
    var cursor = 0;
    var sumLines = 0;
    for (final m in matches) {
      final seg = tail.substring(cursor, m.end).trim();
      cursor = m.end;
      final p = SmartQuickEntryParser.tryParse(seg);
      if (p != null && p.amountMinor > 0) {
        lines.add(
          TransactionSplitLine(
            categoryName: p.categoryName,
            amountMinor: p.amountMinor,
            note: p.merchant,
          ),
        );
        sumLines += p.amountMinor;
      }
    }
    if (lines.isEmpty) return null;

    // FIX-004: Nếu tổng các dòng chi tiết vượt quá tổng hóa đơn gốc,
    // KHÔNG tự ghi đè total = sumLines âm thầm mà gắn cảnh báo yêu cầu xác nhận!
    if (headEntry != null &&
        headEntry.amountMinor > 0 &&
        sumLines > headEntry.amountMinor) {
      return ParsedMultiCategoryReceiptIntent(
        merchant: headEntry.merchant,
        totalAmountMinor: headEntry.amountMinor,
        splitLines: lines,
        validationStatus: SplitValidationStatus.requiresConfirmation,
        validationMessageVi:
            'Tổng các hạng mục (${_fmtShort(sumLines)}) vượt quá tổng hóa đơn ban đầu (${_fmtShort(headEntry.amountMinor)}). Vui lòng xác nhận hoặc chỉnh lại số tiền.',
      );
    }

    final total = (headEntry != null && headEntry.amountMinor >= sumLines)
        ? headEntry.amountMinor
        : sumLines;

    if (total > sumLines) {
      lines.add(
        TransactionSplitLine(
          categoryName: 'Chi tiêu khác',
          amountMinor: total - sumLines,
          note: 'Phần còn lại trên hóa đơn',
        ),
      );
    }

    return ParsedMultiCategoryReceiptIntent(
      merchant: headEntry?.merchant ?? 'Hóa đơn tách khoản',
      totalAmountMinor: total,
      splitLines: lines,
    );
  }

  static bool _looksLikeGroupSplit(String lower) {
    return SmartMoneySplitAiEngine.looksLikeGroupSplitUtterance(lower);
  }

  static ParsedGroupSplitIntent? _tryParseGroupSplit(
    String normalized, {
    required String currentUserId,
    required String currentUserName,
    required List<FamilyMemberInfo> knownMembers,
    Map<String, List<String>> nicknamesByUserId = const {},
    Map<String, String> explicitParticipantOverrides = const {},
  }) {
    final topic = inferSharedTopic(normalized);
    final adv = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
      normalized,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      topic: topic,
      knownMembers: knownMembers,
      nicknamesByUserId: nicknamesByUserId,
      explicitParticipantOverrides: explicitParticipantOverrides,
    );
    if (adv == null) return null;
    return ParsedGroupSplitIntent(
      title: adv.title,
      totalAmountMinor: adv.totalAmountMinor,
      topic: adv.topic,
      splitMethod: adv.splitMethod,
      paidByParticipantId: adv.paidByParticipantId,
      paidByDisplayName: adv.paidByDisplayName,
      shares: adv.shares
          .map(
            (s) => ParsedParticipantShare(
              participantId: s.participantId,
              displayName: s.displayName,
              amountMinor: s.amountMinor,
              percentage: s.percentage,
              sharesWeight: s.sharesWeight,
            ),
          )
          .toList(),
      rawInputValuesByUserId: adv.rawInputValuesByUserId,
      validationStatus: adv.validationStatus,
      validationMessageVi: adv.validationMessageVi,
      ambiguousParticipants: adv.ambiguousParticipants,
    );
  }

  static String _fmtShort(int minor) {
    if (minor >= 1000000) {
      final tr = minor / 1000000.0;
      return '${tr.toStringAsFixed(tr.truncateToDouble() == tr ? 0 : 1)}tr ₫';
    }
    if (minor >= 1000) {
      return '${minor ~/ 1000}k ₫';
    }
    return '$minor ₫';
  }
}
