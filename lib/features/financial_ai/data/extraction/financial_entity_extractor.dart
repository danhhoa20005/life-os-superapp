import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/utils/vietnamese_temporal_and_entity_resolver.dart';
import '../../domain/entities/financial_ai_entities.dart';
import '../normalization/financial_text_normalizer.dart';

class NonTransactionScreeningResult {
  final bool isBlockedOrNonTransaction;
  final AmbiguityFlag? flag;
  final String? explanationVi;

  const NonTransactionScreeningResult.pass()
    : isBlockedOrNonTransaction = false,
      flag = null,
      explanationVi = null;

  const NonTransactionScreeningResult.blocked({
    required AmbiguityFlag this.flag,
    required String this.explanationVi,
  }) : isBlockedOrNonTransaction = true;
}

/// Phase 5 & Phase 6 — Multi-Transaction Segmenter, Non-Transaction Screener,
/// 10-Way Transaction Type Detector & Financial Entity Extractor.
class FinancialEntityExtractor {
  final FinancialTextNormalizer _normalizer;

  const FinancialEntityExtractor(this._normalizer);

  static const Map<String, String> _bankAliases = <String, String>{
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
  };

  /// Screens out OTPs, pure balance statements ("còn 2 triệu trong tài khoản"),
  /// negations ("tôi không mua gì hôm nay", "đừng ghi khoản ăn trưa 50k"),
  /// hypothetical plans ("tôi định mua xe 30 triệu"), questions ("có nên mua 15tr không?"),
  /// and cancellation commands ("hủy giao dịch 100k vừa nhập").
  /// For compound sentences, only blocks whole input if EVERY clause is blocked!
  NonTransactionScreeningResult screenWholeInput(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const NonTransactionScreeningResult.blocked(
        flag: AmbiguityFlag.missingAmount,
        explanationVi: 'Nội dung trống.',
      );
    }

    if (OtpRedactor.containsOtpOrSecret(trimmed)) {
      return const NonTransactionScreeningResult.blocked(
        flag: AmbiguityFlag.otpOrSensitiveBlocked,
        explanationVi:
            'Đã chặn nội dung chứa mã OTP / bảo mật ngân hàng để bảo vệ an toàn tài khoản.',
      );
    }

    final parts = _splitRawCandidateClauses(trimmed);
    if (parts.length <= 1) {
      return _screenSingleClause(trimmed);
    }

    NonTransactionScreeningResult? firstBlocked;
    for (final part in parts) {
      final res = _screenSingleClause(part);
      if (!res.isBlockedOrNonTransaction) {
        return const NonTransactionScreeningResult.pass();
      }
      firstBlocked ??= res;
    }
    return firstBlocked ?? const NonTransactionScreeningResult.pass();
  }

  NonTransactionScreeningResult _screenSingleClause(String clause) {
    final safety = ClauseSafetyScreener.screenClause(clause);
    if (safety.isBlocked) {
      final flag = switch (safety.status) {
        ClauseSafetyStatus.blockedBalanceInquiry ||
        ClauseSafetyStatus.financialQuery =>
          AmbiguityFlag.balanceStatementNotIncome,
        ClauseSafetyStatus.blockedNegated =>
          clause.toLowerCase().startsWith('hủy') ||
                  clause.toLowerCase().startsWith('huy') ||
                  clause.toLowerCase().startsWith('xóa') ||
                  clause.toLowerCase().startsWith('xoa')
              ? AmbiguityFlag.cancellationCommandNotExpense
              : AmbiguityFlag.negatedStatement,
        ClauseSafetyStatus.blockedHypothetical ||
        ClauseSafetyStatus.blockedQuestion => AmbiguityFlag.negatedStatement,
        ClauseSafetyStatus.allowed => AmbiguityFlag.negatedStatement,
      };
      return NonTransactionScreeningResult.blocked(
        flag: flag,
        explanationVi:
            safety.reasonVi ?? 'Nội dung không tạo giao dịch tài chính mới.',
      );
    }
    return const NonTransactionScreeningResult.pass();
  }

  List<String> _splitRawCandidateClauses(String text) {
    final conjRegex = RegExp(
      r'(?:\s*[;\n]\s*|(?<!\d)\s*,\s*(?!\d)|\s+(?:và|va|rồi|roi|xong|tiếp\s+theo)\s+)',
      caseSensitive: false,
      unicode: true,
    );
    return text
        .split(conjRegex)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  /// Extracts one or multiple structured [ExtractedFinancialEntity] items from a single user/voice/bank utterance.
  List<ExtractedFinancialEntity> extractAll(
    String rawText, {
    DateTime? referenceTime,
  }) {
    final screen = screenWholeInput(rawText);
    if (screen.isBlockedOrNonTransaction) {
      return const [];
    }

    final normalizedFull = _normalizer.normalizeText(rawText);
    final refTime = referenceTime ?? _normalizer.currentReferenceTime();
    final sentenceLevelDate = _normalizer.extractRelativeDate(
      normalizedFull,
      referenceTime: refTime,
    );

    final segments = _segmentIntoClauses(normalizedFull);
    final entities = <ExtractedFinancialEntity>[];

    for (final seg in segments) {
      final extracted = _extractSingleClause(
        seg,
        referenceTime: refTime,
        inheritedDate: sentenceLevelDate,
      );
      if (extracted != null) {
        entities.add(extracted);
      }
    }

    return entities;
  }

  /// Splits multi-transaction Vietnamese sentences accurately without breaking compound amounts
  /// like `"2 triệu 300 nghìn"` or internal transfers like `"Chuyển 2tr từ MB sang VCB"`,
  /// while also isolating trailing non-financial schedule/reminder/negated clauses.
  List<String> _segmentIntoClauses(String normalized) {
    final explicitParts = <String>[];
    final conjRegex = RegExp(
      r'(?:\s*[;\n]\s*|(?<!\d)\s*,\s*(?!\d)|\s+(?:và|va|rồi|roi|xong|tiếp\s+theo)\s+)',
      caseSensitive: false,
      unicode: true,
    );

    var cursor = 0;
    for (final m in conjRegex.allMatches(normalized)) {
      final candidateLeft = normalized.substring(cursor, m.start).trim();
      final candidateRight = normalized.substring(m.end).trim();
      final leftHasAmount = _normalizer
          .extractAmounts(candidateLeft)
          .isNotEmpty;
      final rightHasBoundaryClause =
          _normalizer.extractAmounts(candidateRight).isNotEmpty ||
          _looksLikeNonFinancialOrBlockedTail(candidateRight);
      if (leftHasAmount && rightHasBoundaryClause) {
        explicitParts.add(candidateLeft);
        cursor = m.end;
      }
    }
    explicitParts.add(normalized.substring(cursor).trim());

    // Second pass: within any part that STILL has >= 2 amounts (e.g. "chiều nay ăn 45k đổ xăng 70k"),
    // slice right after each amount token when trailing text starts a new action!
    final finalSegments = <String>[];
    for (final part in explicitParts) {
      final subAmounts = _normalizer.extractAmounts(part);
      if (subAmounts.length <= 1) {
        finalSegments.add(part);
        continue;
      }
      var subCursor = 0;
      for (var i = 0; i < subAmounts.length; i++) {
        final amt = subAmounts[i];
        if (i < subAmounts.length - 1) {
          final nextAmt = subAmounts[i + 1];
          final between = part
              .substring(amt.endIndex, nextAmt.startIndex)
              .trim();
          final beforeAmt = part.substring(subCursor, amt.startIndex).trim();
          final beforeWords = beforeAmt
              .replaceAll(
                RegExp(
                  r'\b(hôm|hom|sáng|sang|trưa|trua|chiều|chieu|tối|toi|nay|qua|kia|tôi|toi|mình|minh|em|anh)\b',
                  caseSensitive: false,
                  unicode: true,
                ),
                '',
              )
              .trim();
          if (beforeWords.isNotEmpty || between.isNotEmpty) {
            final segEnd = amt.endIndex;
            final seg = part.substring(subCursor, segEnd).trim();
            if (seg.isNotEmpty) {
              finalSegments.add(seg);
            }
            subCursor = segEnd;
          }
        } else {
          final tailSeg = part.substring(subCursor).trim();
          if (tailSeg.isNotEmpty) {
            finalSegments.add(tailSeg);
          }
        }
      }
    }

    return finalSegments.where((s) => s.isNotEmpty).toList(growable: false);
  }

  bool _looksLikeNonFinancialOrBlockedTail(String tail) {
    final safety = ClauseSafetyScreener.screenClause(tail);
    if (safety.isBlocked) return true;
    final ascii = FinancialTextNormalizer.stripVnAccents(tail);
    return RegExp(
      r'\b(?:nhac|lich|hop|hen|kham|bao\s+thuc|uong\s+\d+\s*(?:ml|lit|coc)|uong\s+thuoc|ghi\s+chu|di\s+cho)\b',
    ).hasMatch(ascii);
  }

  ExtractedFinancialEntity? _extractSingleClause(
    String clause, {
    required DateTime referenceTime,
    ParsedRelativeDate? inheritedDate,
  }) {
    final screen = _screenSingleClause(clause);
    if (screen.isBlockedOrNonTransaction) return null;

    final amounts = _normalizer.extractAmounts(clause);
    if (amounts.isEmpty && _looksLikeNonFinancialOrBlockedTail(clause)) {
      return null;
    }
    final flags = <AmbiguityFlag>[];

    int? amountMinor;
    var currencyCode = 'VND';
    var decimalDigits = 0;
    var amountConf = 0.0;
    String matchedAmountToken = '';

    if (amounts.isEmpty) {
      flags.add(AmbiguityFlag.missingAmount);
    } else {
      final primary = amounts.first;
      amountMinor = primary.amountMinor;
      currencyCode = primary.currencyCode;
      decimalDigits = primary.decimalDigits;
      amountConf = primary.confidence;
      matchedAmountToken = primary.matchedToken;
      if (primary.isAmbiguous) {
        flags.add(AmbiguityFlag.ambiguousDecimalOrThousands);
      }
      if (primary.amountMinor <= 0) {
        flags.add(AmbiguityFlag.zeroOrNegativeAmount);
      }
    }

    final clauseDate =
        _normalizer.extractRelativeDate(clause, referenceTime: referenceTime) ??
        inheritedDate;
    final entitySnap = VietnameseTemporalAndEntityResolver.extractEntities(
      clause,
    );
    if (clauseDate != null && clauseDate.isAmbiguous) {
      // Keep date but note mild relative-window ambiguity if "tuần trước" / "tháng trước"
    }

    final typeDetection = _detectTransactionTypeAndRouting(clause);
    if (typeDetection.type == FinancialTransactionType.nonTransaction) {
      return null;
    }
    if (typeDetection.type == FinancialTransactionType.unknown) {
      flags.add(AmbiguityFlag.ambiguousTransactionType);
    }

    // Build clean human-readable description (strip raw amount & relative date tokens)
    var desc = clause;
    if (matchedAmountToken.isNotEmpty) {
      desc = desc.replaceFirst(matchedAmountToken, ' ');
    }
    if (clauseDate != null &&
        clauseDate.matchedPhrase.isNotEmpty &&
        clause.contains(clauseDate.matchedPhrase)) {
      desc = desc.replaceFirst(clauseDate.matchedPhrase, ' ');
    }
    desc = desc
        .replaceAll(
          RegExp(
            r'^(?:tôi|mình|em|anh|vừa|mới|đã|chi|hết|mất|tốn|khoảng)\s+',
            caseSensitive: false,
            unicode: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\s+(?:hết|mất|tốn|khoảng)$',
            caseSensitive: false,
            unicode: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'^[,;:\-.\s]+|[,;:\-.\s]+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    if (desc.isEmpty) {
      desc = typeDetection.type.displayLabelVi;
    } else {
      desc = '${desc[0].toUpperCase()}${desc.substring(1)}';
    }

    final canonicalMerchant = FinancialTextNormalizer.canonicalizeMerchant(
      typeDetection.explicitMerchant ?? desc,
    );
    final classifierInput = _normalizer.toClassifierInput(clause);

    return ExtractedFinancialEntity(
      rawSegment: clause,
      normalizedSegment: clause,
      classifierInput: classifierInput,
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      currencyDecimalDigits: decimalDigits,
      transactionType: typeDetection.type,
      explicitOccurredAt: clauseDate?.resolvedDateTime,
      merchant: typeDetection.explicitMerchant ?? desc,
      merchantCanonicalKey: canonicalMerchant,
      description: desc,
      sourceAccountHint:
          typeDetection.sourceAccountHint ?? entitySnap.walletHint,
      destinationAccountHint:
          typeDetection.destinationAccountHint ??
          entitySnap.destinationWalletHint,
      recipient: typeDetection.recipient,
      paymentMethod: typeDetection.paymentMethod,
      candidateSemanticKey: typeDetection.deterministicSemanticHint,
      amountConfidence: amountConf,
      typeConfidence: typeDetection.confidence,
      merchantConfidence: canonicalMerchant != null ? 0.86 : 0.45,
      ambiguityFlags: List.unmodifiable(flags),
    );
  }

  ({
    FinancialTransactionType type,
    double confidence,
    String? sourceAccountHint,
    String? destinationAccountHint,
    String? recipient,
    String? paymentMethod,
    String? explicitMerchant,
    String? deterministicSemanticHint,
  })
  _detectTransactionTypeAndRouting(String clause) {
    final ascii = FinancialTextNormalizer.stripVnAccents(clause);

    // 1. ATM Cash Withdrawal -> Asset rebalance (bank -> cash), NEVER expense! (Phase 6)
    if (RegExp(
      r'\brut\s+(?:tien\s+)?(?:tu\s+|o\s+|tai\s+)?atm\b|\brut\s+.*\btu\s+atm\b|\batm\s+rut\s+tien\b',
    ).hasMatch(ascii)) {
      final srcBank = _findFirstBankCode(ascii) ?? 'BANK';
      return (
        type: FinancialTransactionType.internalTransfer,
        confidence: 0.96,
        sourceAccountHint: srcBank,
        destinationAccountHint: 'CASH',
        recipient: null,
        paymentMethod: 'atm_withdrawal',
        explicitMerchant: 'Rút tiền mặt ATM',
        deterministicSemanticHint: null,
      );
    }

    // 2. Explicit Bank-to-Bank Self Transfer: "chuyển 2tr từ MB sang VCB (của tôi)" / "nạp ví từ VCB"
    final fromToMatch = RegExp(
      r'\btu\s+([a-z0-9\s]{2,20}?)\s+(?:sang|qua|vao|den)\s+([a-z0-9\s]{2,24})\b',
    ).firstMatch(ascii);
    if (fromToMatch != null &&
        RegExp(r'\b(chuyen|nap|rut)\b').hasMatch(ascii)) {
      final rawDst = fromToMatch
          .group(2)!
          .replaceAll(RegExp(r'\b(cua\s+toi|cua\s+minh|noi\s+bo)\b'), '')
          .trim();
      final srcCode = _resolveBankOrWalletHint(fromToMatch.group(1)!);
      final dstCode = _resolveBankOrWalletHint(rawDst);
      final isSelfOwned =
          ascii.contains('cua toi') ||
          ascii.contains('cua minh') ||
          ascii.contains('noi bo') ||
          (srcCode != null && dstCode != null);
      if (isSelfOwned) {
        return (
          type: FinancialTransactionType.internalTransfer,
          confidence: ascii.contains('cua toi') ? 0.98 : 0.88,
          sourceAccountHint: srcCode,
          destinationAccountHint: dstCode,
          recipient: null,
          paymentMethod: 'bank_transfer',
          explicitMerchant: 'Chuyển nội bộ ${srcCode ?? ""} → ${dstCode ?? ""}'
              .trim(),
          deterministicSemanticHint: null,
        );
      }
    }

    // 3. Refund ("shop hoàn tiền 200k", "hoàn tiền đơn hàng") -> Refund, NOT regular income!
    if (RegExp(r'\b(hoan\s+tien|refund|boi\s+hoan\s+don)\b').hasMatch(ascii)) {
      return (
        type: FinancialTransactionType.refund,
        confidence: 0.95,
        sourceAccountHint: _findFirstBankCode(ascii),
        destinationAccountHint: null,
        recipient: null,
        paymentMethod: 'refund',
        explicitMerchant: null,
        deterministicSemanticHint: 'shopping.general',
      );
    }

    // 4. Reversal ("đảo bút toán", "ngân hàng thu hồi giao dịch lỗi")
    if (RegExp(
      r'\b(dao\s+but\s+toan|reversal|hoan\s+tra\s+loi)\b',
    ).hasMatch(ascii)) {
      return (
        type: FinancialTransactionType.reversal,
        confidence: 0.93,
        sourceAccountHint: _findFirstBankCode(ascii),
        destinationAccountHint: null,
        recipient: null,
        paymentMethod: null,
        explicitMerchant: null,
        deterministicSemanticHint: null,
      );
    }

    // 5. Loan Disbursement vs Loan Repayment
    if (RegExp(
      r'\b(giai\s+ngan|vay\s+ngan\s+hang|muon\s+tien\s+tu)\b',
    ).hasMatch(ascii)) {
      return (
        type: FinancialTransactionType.loanDisbursement,
        confidence: 0.90,
        sourceAccountHint: _findFirstBankCode(ascii),
        destinationAccountHint: null,
        recipient: null,
        paymentMethod: null,
        explicitMerchant: null,
        deterministicSemanticHint: 'income.other',
      );
    }
    if (RegExp(
      r'\b(tra\s+no|tra\s+gop|thanh\s+toan\s+khoan\s+vay|dong\s+lai\s+vay|fe\s+credit|home\s+credit)\b',
    ).hasMatch(ascii)) {
      return (
        type: FinancialTransactionType.loanRepayment,
        confidence: 0.94,
        sourceAccountHint: _findFirstBankCode(ascii),
        destinationAccountHint: null,
        recipient: null,
        paymentMethod: null,
        explicitMerchant: null,
        deterministicSemanticHint: 'debt.interest',
      );
    }

    // 6. Investment / Savings Transfer ("gửi tiết kiệm 5tr", "nạp tiền chứng khoán")
    if (RegExp(
      r'\b(gui\s+tiet\s+kiem|mo\s+so\s+tiet\s+kiem|nap\s+chung\s+khoan|mua\s+chung\s+chi\s+quy)\b',
    ).hasMatch(ascii)) {
      return (
        type: FinancialTransactionType.investmentTransfer,
        confidence: 0.91,
        sourceAccountHint: _findFirstBankCode(ascii),
        destinationAccountHint: 'SAVINGS',
        recipient: null,
        paymentMethod: 'bank_transfer',
        explicitMerchant: null,
        deterministicSemanticHint: null,
      );
    }

    // 7. External Transfer to another person ("Chuyển 500k cho mẹ", "ck 300k cho bạn")
    final recipientMatch = RegExp(
      r'\b(?:chuyen(?:\s+khoan)?|gui\s+tien|bieu)\b.*?\bcho\s+([a-z\s]{2,20})$',
    ).firstMatch(ascii);
    if (recipientMatch != null) {
      final rawRecip = recipientMatch.group(1)!.trim();
      final isFamilySupport = RegExp(
        r'\b(me|bo|ba|ong|gia\s+dinh|con)\b',
      ).hasMatch(rawRecip);
      return (
        type: FinancialTransactionType.externalTransfer,
        confidence: 0.93,
        sourceAccountHint: _findFirstBankCode(ascii),
        destinationAccountHint: null,
        recipient: rawRecip,
        paymentMethod: 'bank_transfer',
        explicitMerchant: null,
        deterministicSemanticHint: isFamilySupport ? 'family' : 'gifts',
      );
    }

    // 8. Income ("nhận lương 12tr", "thưởng 500k", "nhận 200k từ bạn", "+500.000", "lãi tiết kiệm")
    if (RegExp(
          r'\b(nhan\s+luong|luong\s+thang|tien\s+luong|ung\s+luong|payroll|salary)\b',
        ).hasMatch(ascii) ||
        RegExp(
          r'\b(duoc\s+thuong|nhan\s+thuong|^thuong\b|\sthuong\s+\d)',
        ).hasMatch(ascii) ||
        RegExp(
          r'\b(nhan\s+\d[a-z0-9.,]*|nhan\s+tien|nhan\s+duoc|duoc\s+nhan|duoc\s+cho|duoc\s+cong|lai\s+tiet\s+kiem|co\s+tuc|thu\s+lao|tien\s+job|doanh\s+thu)\b',
        ).hasMatch(ascii) ||
        RegExp(r'(?:^|\s)\+\s*\d').hasMatch(clause)) {
      String? semHint;
      if (ascii.contains('luong') || ascii.contains('salary')) {
        semHint = 'income.salary';
      } else if (ascii.contains('thuong')) {
        semHint = 'income.bonus';
      } else if (ascii.contains('freelance') || ascii.contains('job')) {
        semHint = 'income.freelance';
      } else if (ascii.contains('lai tiet kiem') || ascii.contains('co tuc')) {
        semHint = 'income.interest';
      } else if (ascii.contains('li xi') || ascii.contains('tang')) {
        semHint = 'income.gift';
      } else {
        semHint = 'income.other';
      }

      String? sender;
      final fromMatch = RegExp(r'\btu\s+([a-z\s]{2,20})$').firstMatch(ascii);
      if (fromMatch != null) {
        sender = fromMatch.group(1)!.trim();
      }
      return (
        type: FinancialTransactionType.income,
        confidence: 0.95,
        sourceAccountHint: _findFirstBankCode(ascii),
        destinationAccountHint: null,
        recipient: sender,
        paymentMethod: null,
        explicitMerchant: null,
        deterministicSemanticHint: semHint,
      );
    }

    // 9. Expense (explicit spending verbs/nouns or bank debit `-` sign)
    final hasExpenseCue =
        RegExp(
          r'\b(an|uong|mua|chi|tra|thanh\s+toan|do\s+xang|xang|cafe|cf|ca\s+phe|tra\s+sua|taxi|grab|xanh\s+sm|be|gui\s+xe|thay\s+nhot|sua\s+xe|rua\s+xe|tien\s+dien|tien\s+nuoc|tien\s+nha|tien\s+tro|wifi|internet|kham|thuoc|sach|hoc\s+phi|xem\s+phim|netflix|spotify|mung\s+cuoi|li\s+xi|di\s+cho|sieu\s+thi|shopee|lazada|phi\s+sms|phi\s+thuong\s+nien)\b',
        ).hasMatch(ascii) ||
        RegExp(r'(?:^|\s)-\s*\d').hasMatch(clause);

    if (hasExpenseCue) {
      return (
        type: FinancialTransactionType.expense,
        confidence: 0.94,
        sourceAccountHint: _findFirstBankCode(ascii),
        destinationAccountHint: null,
        recipient: null,
        paymentMethod: ascii.contains('chuyen khoan') ? 'bank_transfer' : null,
        explicitMerchant: null,
        deterministicSemanticHint: null,
      );
    }

    // 10. Bare number + unknown noun without clear direction -> safe conservative fallback
    if (clause.trim().split(RegExp(r'\s+')).length >= 2) {
      return (
        type: FinancialTransactionType.expense,
        confidence: 0.68,
        sourceAccountHint: _findFirstBankCode(ascii),
        destinationAccountHint: null,
        recipient: null,
        paymentMethod: null,
        explicitMerchant: null,
        deterministicSemanticHint: null,
      );
    }

    return (
      type: FinancialTransactionType.unknown,
      confidence: 0.25,
      sourceAccountHint: null,
      destinationAccountHint: null,
      recipient: null,
      paymentMethod: null,
      explicitMerchant: null,
      deterministicSemanticHint: null,
    );
  }

  String? _findFirstBankCode(String ascii) {
    for (final entry in _bankAliases.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(ascii)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _resolveBankOrWalletHint(String rawPhrase) {
    final clean = rawPhrase.trim();
    if (clean.contains('tien mat') || clean.contains('vi tien mat')) {
      return 'CASH';
    }
    return _findFirstBankCode(clean);
  }
}
