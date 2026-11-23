import '../../features/family/domain/entities/family_entities.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import 'smart_quick_entry_parser.dart';

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

  const ParsedParticipantShare({
    required this.participantId,
    required this.displayName,
    required this.amountMinor,
    this.percentage,
  });
}

class ParsedGroupSplitIntent {
  final String title;
  final int totalAmountMinor;
  final SharedExpenseTopic topic;
  final SplitMethod splitMethod;
  final List<ParsedParticipantShare> shares;
  final Map<String, int> rawInputValuesByUserId;

  const ParsedGroupSplitIntent({
    required this.title,
    required this.totalAmountMinor,
    required this.topic,
    required this.splitMethod,
    required this.shares,
    required this.rawInputValuesByUserId,
  });
}

class ParsedMultiCategoryReceiptIntent {
  final String merchant;
  final int totalAmountMinor;
  final List<TransactionSplitLine> splitLines;

  const ParsedMultiCategoryReceiptIntent({
    required this.merchant,
    required this.totalAmountMinor,
    required this.splitLines,
  });
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

    // Convert "<number> lít" -> "<number>00k" (Vietnamese slang: 1 lít = 100k)
    s = s.replaceAllMapped(
      RegExp(r'\b(\d+)\s*lít\b', caseSensitive: false),
      (m) => '${(int.tryParse(m.group(1) ?? '0') ?? 0) * 100}k',
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

  static int? _parseSingleAmountToken(String token) {
    final entry = SmartQuickEntryParser.tryParse('chi $token');
    return entry?.amountMinor;
  }

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

  /// Analyzes any spoken or typed Vietnamese sentence and returns structured financial intent.
  static VoiceFinancialAnalysisResult? analyze(
    String rawTranscript, {
    String currentUserId = 'me',
    String currentUserName = 'Tôi',
    List<FamilyMemberInfo> knownMembers = const [],
  }) {
    final raw = rawTranscript.trim();
    if (raw.isEmpty) return null;

    final normalized = normalizeSpokenVietnamese(raw);
    final lower = normalized.toLowerCase();

    // 1. Check Multi-Category Single Receipt Split ("siêu thị 500k gồm ăn uống 320k việc nhà 180k")
    if (_looksLikeMultiCategoryReceipt(lower)) {
      final receipt = _tryParseMultiCategoryReceipt(normalized);
      if (receipt != null) {
        return VoiceFinancialAnalysisResult(
          originalText: raw,
          normalizedText: normalized,
          intentKind: VoiceSentenceIntentKind.multiCategoryReceipt,
          multiCategoryReceipt: receipt,
          summaryHeadline:
              'Tách 1 hóa đơn (${receipt.splitLines.length} hạng mục) · Tổng ${_fmtShort(receipt.totalAmountMinor)}',
        );
      }
    }

    // 2. Check Group / Family / Roommate Bill Split ("chia đều", "chia cho", "%", per-person shares)
    if (_looksLikeGroupSplit(lower)) {
      final split = _tryParseGroupSplit(
        normalized,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        knownMembers: knownMembers,
      );
      if (split != null) {
        return VoiceFinancialAnalysisResult(
          originalText: raw,
          normalizedText: normalized,
          intentKind: VoiceSentenceIntentKind.groupBillSplit,
          groupSplit: split,
          summaryHeadline:
              'Chia tiền nhóm (${split.shares.length} người · ${split.splitMethod.displayLabel.split('(').first.trim()})',
        );
      }
    }

    // 3. Check Multi-Item Batch Spoken Transactions ("ăn phở 65k đổ xăng 90k nhận lương 18tr5")
    final amountMatches = _amountTokenRegex.allMatches(normalized).toList();
    if (amountMatches.length >= 2) {
      final batch = <ParsedSmartEntry>[];
      var cursor = 0;
      for (final m in amountMatches) {
        final segment = normalized.substring(cursor, m.end).trim();
        cursor = m.end;
        final cleanedSeg = segment
            .replaceAll(
              RegExp(r'^[,;.\s]+|\b(và|rồi|xong|tiếp)\b', caseSensitive: false),
              ' ',
            )
            .trim();
        final parsed = SmartQuickEntryParser.tryParse(cleanedSeg);
        if (parsed != null) {
          batch.add(parsed);
        }
      }
      if (batch.length >= 2) {
        return VoiceFinancialAnalysisResult(
          originalText: raw,
          normalizedText: normalized,
          intentKind: VoiceSentenceIntentKind.batchTransactions,
          personalEntries: batch,
          summaryHeadline:
              'Ghi hàng loạt ${batch.length} bút toán trong 1 câu nói',
        );
      }
    }

    // 4. Fallback: Single Smart Personal Transaction
    final single = SmartQuickEntryParser.tryParse(normalized);
    if (single != null) {
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
    if (lower.contains('chia ') ||
        lower.contains('người') ||
        lower.contains('%')) {
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
    final matches = _amountTokenRegex.allMatches(tail).toList();
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
    return lower.contains('chia ') ||
        lower.contains('chia đều') ||
        lower.contains('mỗi người') ||
        lower.contains('người chịu') ||
        lower.contains('còn lại') ||
        RegExp(r'\b\d+\s*%').hasMatch(lower);
  }

  static ParsedGroupSplitIntent? _tryParseGroupSplit(
    String normalized, {
    required String currentUserId,
    required String currentUserName,
    required List<FamilyMemberInfo> knownMembers,
  }) {
    final allAmounts = _amountTokenRegex.allMatches(normalized).toList();
    if (allAmounts.isEmpty) return null;

    final firstAmtMatch = allAmounts.first;
    final totalMinor = _parseSingleAmountToken(firstAmtMatch.group(0) ?? '');
    if (totalMinor == null || totalMinor <= 0) return null;

    var rawTitle = normalized.substring(0, firstAmtMatch.start).trim();
    rawTitle = rawTitle.replaceAll(RegExp(r'^[-:,.\s]+|[-:,.\s]+$'), '');
    if (rawTitle.length < 2) {
      rawTitle = 'Khoản chi chung nhóm';
    } else {
      rawTitle = '${rawTitle[0].toUpperCase()}${rawTitle.substring(1)}';
    }
    final topic = inferSharedTopic(normalized);
    final afterFirstAmount = normalized.substring(firstAmtMatch.end).trim();

    // Case A: Percentage Split (e.g. "Hòa 60% Minh 40%")
    final pctMatches = RegExp(
      r'([A-Za-zÀ-ỹ]+)\s+(\d{1,3})\s*%',
      unicode: true,
    ).allMatches(afterFirstAmount).toList();
    if (pctMatches.length >= 2) {
      var pctSum = 0;
      final shares = <ParsedParticipantShare>[];
      final rawMap = <String, int>{};
      var allocated = 0;
      for (var i = 0; i < pctMatches.length; i++) {
        final name = _capitalizeName(pctMatches[i].group(1)!);
        final pct = int.tryParse(pctMatches[i].group(2)!) ?? 0;
        pctSum += pct;
        final pid = _resolveParticipantId(
          name,
          index: i,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          knownMembers: knownMembers,
        );
        final amt = i == pctMatches.length - 1
            ? (totalMinor - allocated)
            : (totalMinor * pct) ~/ 100;
        allocated += amt;
        rawMap[pid] = pct;
        shares.add(
          ParsedParticipantShare(
            participantId: pid,
            displayName: name,
            amountMinor: amt,
            percentage: pct,
          ),
        );
      }
      if (pctSum == 100 && shares.isNotEmpty) {
        return ParsedGroupSplitIntent(
          title: rawTitle,
          totalAmountMinor: totalMinor,
          topic: topic,
          splitMethod: SplitMethod.percentage,
          shares: shares,
          rawInputValuesByUserId: rawMap,
        );
      }
    }

    // Case B: Exact per-person amounts + optional "còn lại <Name> chịu"
    if (allAmounts.length >= 2) {
      final personAmtRegex = RegExp(
        r'([A-Za-zÀ-ỹ]+)\s+(\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu)(?:\s*\d{1,3})?|\d+(?:[.,]\d+)?\s*(?:k|nghìn|nghin|ngàn|ngan)(?:\s*\d{1,2})?|\d{1,3}(?:[.,]\d{3})+|\d{5,11})',
        caseSensitive: false,
        unicode: true,
      );
      final personMatches = personAmtRegex
          .allMatches(afterFirstAmount)
          .where((m) => !_isStopWord(m.group(1)!))
          .toList();

      if (personMatches.isNotEmpty) {
        final shares = <ParsedParticipantShare>[];
        final rawMap = <String, int>{};
        var assignedSum = 0;
        for (var i = 0; i < personMatches.length; i++) {
          final name = _capitalizeName(personMatches[i].group(1)!);
          final amt = _parseSingleAmountToken(personMatches[i].group(2)!) ?? 0;
          if (amt <= 0) continue;
          final pid = _resolveParticipantId(
            name,
            index: i,
            currentUserId: currentUserId,
            currentUserName: currentUserName,
            knownMembers: knownMembers,
          );
          assignedSum += amt;
          rawMap[pid] = amt;
          shares.add(
            ParsedParticipantShare(
              participantId: pid,
              displayName: name,
              amountMinor: amt,
            ),
          );
        }

        // Check "còn lại <Name> (chịu|trả|đóng)?"
        final remMatch = RegExp(
          r'còn\s+lại\s+([A-Za-zÀ-ỹ]+)',
          caseSensitive: false,
          unicode: true,
        ).firstMatch(afterFirstAmount);
        if (remMatch != null && assignedSum < totalMinor) {
          final remName = _capitalizeName(remMatch.group(1)!);
          final remAmt = totalMinor - assignedSum;
          final pid = _resolveParticipantId(
            remName,
            index: shares.length,
            currentUserId: currentUserId,
            currentUserName: currentUserName,
            knownMembers: knownMembers,
          );
          rawMap[pid] = remAmt;
          shares.add(
            ParsedParticipantShare(
              participantId: pid,
              displayName: remName,
              amountMinor: remAmt,
            ),
          );
          assignedSum += remAmt;
        }

        if (shares.length >= 2 && assignedSum == totalMinor) {
          return ParsedGroupSplitIntent(
            title: rawTitle,
            totalAmountMinor: totalMinor,
            topic: topic,
            splitMethod: SplitMethod.exact,
            shares: shares,
            rawInputValuesByUserId: rawMap,
          );
        }
      }
    }

    // Case C: Equal Split by Explicit Headcount ("chia đều 4 người", "chia 3") or Named List ("chia cho Hòa, Minh và Lan")
    final countMatch = RegExp(
      r'(?:chia\s*(?:đều)?\s*(?:cho\s*)?|mỗi\s+người\s+)(\d{1,2})\s*(?:người|bạn|anh\s+em|thành\s+viên)?\b',
      caseSensitive: false,
    ).firstMatch(afterFirstAmount);

    var participantNames = <String>[];
    if (countMatch != null) {
      final count = (int.tryParse(countMatch.group(1)!) ?? 2).clamp(2, 20);
      if (knownMembers.length >= count) {
        participantNames = knownMembers
            .take(count)
            .map((m) => m.fullName)
            .toList();
      } else {
        participantNames = List<String>.generate(
          count,
          (i) => i == 0 ? currentUserName : 'Thành viên ${i + 1}',
        );
      }
    } else {
      // Extract names after "chia cho" / "chia đều cho" / "với"
      final namesClauseMatch = RegExp(
        r'(?:chia\s*(?:đều)?\s*cho|cùng\s+với|với)\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(afterFirstAmount);
      if (namesClauseMatch != null) {
        final rawNames = namesClauseMatch
            .group(1)!
            .split(RegExp(r'\s*(?:,|và|với|&)\s*', caseSensitive: false))
            .map(
              (s) => s
                  .replaceAll(RegExp(r'[^A-Za-zÀ-ỹ\s]', unicode: true), '')
                  .trim(),
            )
            .where((s) => s.isNotEmpty && !_isStopWord(s))
            .map(_capitalizeName)
            .toList();
        if (rawNames.length == 1) {
          // e.g. "chia với Minh" -> CurrentUser + Minh (2 people)
          participantNames = [currentUserName, rawNames.single];
        } else if (rawNames.length >= 2) {
          participantNames = rawNames;
        }
      }
    }

    if (participantNames.isEmpty) {
      if (knownMembers.length >= 2) {
        participantNames = knownMembers.map((m) => m.fullName).toList();
      } else {
        participantNames = [currentUserName, 'Thành viên 2'];
      }
    }

    final n = participantNames.length;
    final baseShare = totalMinor ~/ n;
    final remainder = totalMinor % n;
    final shares = <ParsedParticipantShare>[];
    for (var i = 0; i < n; i++) {
      final name = participantNames[i];
      final pid = _resolveParticipantId(
        name,
        index: i,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        knownMembers: knownMembers,
      );
      shares.add(
        ParsedParticipantShare(
          participantId: pid,
          displayName: name,
          amountMinor: baseShare + (i < remainder ? 1 : 0),
        ),
      );
    }

    return ParsedGroupSplitIntent(
      title: rawTitle,
      totalAmountMinor: totalMinor,
      topic: topic,
      splitMethod: SplitMethod.equal,
      shares: shares,
      rawInputValuesByUserId: const {},
    );
  }

  static String _resolveParticipantId(
    String spokenName, {
    required int index,
    required String currentUserId,
    required String currentUserName,
    required List<FamilyMemberInfo> knownMembers,
  }) {
    final lower = spokenName.toLowerCase().trim();
    if (lower == 'tôi' ||
        lower == 'mình' ||
        lower == 'em' ||
        lower == 'anh' ||
        currentUserName.toLowerCase().contains(lower)) {
      return currentUserId;
    }
    for (final m in knownMembers) {
      final mLower = m.fullName.toLowerCase();
      if (mLower == lower ||
          mLower.endsWith(' $lower') ||
          mLower.contains(lower)) {
        return m.userId;
      }
    }
    final slug = lower.replaceAll(RegExp(r'\s+'), '_');
    return 'voice_member_${index}_$slug';
  }

  static bool _isStopWord(String word) {
    const stops = {
      'chia',
      'đều',
      'cho',
      'với',
      'người',
      'mỗi',
      'còn',
      'lại',
      'chịu',
      'trả',
      'gồm',
      'tổng',
    };
    return stops.contains(word.toLowerCase().trim());
  }

  static String _capitalizeName(String raw) {
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
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
