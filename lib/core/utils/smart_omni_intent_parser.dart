import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../features/daily_life/domain/entities/daily_life_entities.dart';
import '../../features/tasks/domain/entities/task_entities.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import '../security/bank_notification_parser.dart';
import 'smart_quick_entry_parser.dart';
import 'vietnamese_search_matcher.dart';
import 'vietnamese_temporal_and_entity_resolver.dart';
import 'vnd_amount.dart';

enum OmniActionKind {
  transaction,
  groupSplit,
  calendarEvent,
  task,
  grocery,
  waterLog,
  medication,
}

enum OmniIntentSubtype {
  income,
  expense,
  internalTransfer,
  refund,
  loanOrBorrow,
  groupBillSplit,
  debtSettlement,
  budgetSetup,
  salaryAllocation,
  calendarEvent,
  task,
  alarm,
  reminder,
  shoppingGrocery,
  fuelRefill,
  vehicleMaintenance,
  waterLog,
  medication,
  smartNote,
  financialOverviewQuery,
}

/// Cross-domain actionable draft produced by either the `< 5ms` Offline `SmartOmniIntentParser`
/// or the opt-in Connected `GeminiCopilotRepository`.
class OmniActionDraft extends Equatable {
  final String id;
  final OmniActionKind kind;
  final OmniIntentSubtype? subtype;
  final String title;
  final int amountMinor;
  final TransactionKind transactionKind;
  final String categoryId;
  final String categoryName;
  final int participantCount;
  final List<String> participantNames;
  final DateTime? scheduledAt;
  final int durationMinutes;
  final String? location;
  final TaskPriorityLevel taskPriority;
  final String quantityLabel;
  final int waterMl;
  final MedicationScheduleSlot medicationSlot;
  final String dosage;
  final String originLabel;
  final String? sourceWalletHint;
  final String? destinationWalletHint;
  final String? vehicleHint;
  final int? odometerKm;
  final String? noteText;
  final bool requiresConfirmation;
  final String? warningMessageVi;

  const OmniActionDraft({
    required this.id,
    required this.kind,
    this.subtype,
    required this.title,
    this.amountMinor = 0,
    this.transactionKind = TransactionKind.expense,
    this.categoryId = 'cat_other_exp',
    this.categoryName = 'Chi tiêu khác',
    this.participantCount = 2,
    this.participantNames = const <String>[],
    this.scheduledAt,
    this.durationMinutes = 60,
    this.location,
    this.taskPriority = TaskPriorityLevel.medium,
    this.quantityLabel = '1 phần',
    this.waterMl = 0,
    this.medicationSlot = MedicationScheduleSlot.morning,
    this.dosage = '1 viên sau ăn',
    this.originLabel = 'Trên máy',
    this.sourceWalletHint,
    this.destinationWalletHint,
    this.vehicleHint,
    this.odometerKm,
    this.noteText,
    this.requiresConfirmation = false,
    this.warningMessageVi,
  });

  OmniIntentSubtype get resolvedSubtype {
    if (subtype != null) return subtype!;
    return switch (kind) {
      OmniActionKind.transaction =>
        transactionKind == TransactionKind.income
            ? OmniIntentSubtype.income
            : transactionKind == TransactionKind.transfer
            ? OmniIntentSubtype.internalTransfer
            : OmniIntentSubtype.expense,
      OmniActionKind.groupSplit => OmniIntentSubtype.groupBillSplit,
      OmniActionKind.calendarEvent => OmniIntentSubtype.calendarEvent,
      OmniActionKind.task => OmniIntentSubtype.task,
      OmniActionKind.grocery => OmniIntentSubtype.shoppingGrocery,
      OmniActionKind.waterLog => OmniIntentSubtype.waterLog,
      OmniActionKind.medication => OmniIntentSubtype.medication,
    };
  }

  String get badgeLabelVi {
    if (subtype != null) {
      return switch (subtype!) {
        OmniIntentSubtype.income => 'Thu nhập',
        OmniIntentSubtype.expense => 'Chi tiêu',
        OmniIntentSubtype.internalTransfer => 'Chuyển ví',
        OmniIntentSubtype.refund => 'Hoàn tiền',
        OmniIntentSubtype.loanOrBorrow => 'Vay / Cho vay',
        OmniIntentSubtype.groupBillSplit => 'Chia nhóm',
        OmniIntentSubtype.debtSettlement => 'Tất toán nợ',
        OmniIntentSubtype.budgetSetup => 'Ngân sách',
        OmniIntentSubtype.salaryAllocation => 'Phân bổ lương',
        OmniIntentSubtype.calendarEvent => 'Lịch hẹn',
        OmniIntentSubtype.task =>
          taskPriority == TaskPriorityLevel.high ? 'Việc gấp' : 'Việc làm',
        OmniIntentSubtype.alarm => 'Báo thức',
        OmniIntentSubtype.reminder => 'Nhắc nhở',
        OmniIntentSubtype.shoppingGrocery => 'Đi chợ',
        OmniIntentSubtype.fuelRefill => 'Đổ xăng',
        OmniIntentSubtype.vehicleMaintenance => 'Bảo dưỡng xe',
        OmniIntentSubtype.waterLog => 'Uống nước',
        OmniIntentSubtype.medication => 'Nhắc thuốc',
        OmniIntentSubtype.smartNote => 'Ghi chú',
        OmniIntentSubtype.financialOverviewQuery => 'Truy vấn',
      };
    }
    return switch (kind) {
      OmniActionKind.transaction =>
        transactionKind == TransactionKind.income ? 'Thu nhập' : 'Chi tiêu',
      OmniActionKind.groupSplit => 'Chia nhóm',
      OmniActionKind.calendarEvent => 'Lịch hẹn',
      OmniActionKind.task =>
        taskPriority == TaskPriorityLevel.high ? 'Việc gấp' : 'Việc làm',
      OmniActionKind.grocery => 'Đi chợ',
      OmniActionKind.waterLog => 'Uống nước',
      OmniActionKind.medication => 'Nhắc thuốc',
    };
  }

  int get perPersonShareMinor {
    if (participantCount <= 0) return amountMinor;
    return amountMinor ~/ participantCount;
  }

  String get summaryLineVi {
    final dtFmt = DateFormat('HH:mm dd/MM');
    final hmFmt = DateFormat('HH:mm');
    final s = resolvedSubtype;
    if (s == OmniIntentSubtype.budgetSetup) {
      return 'Ngân sách · $title · Hạn mức ${VndAmount.format(amountMinor)}';
    }
    if (s == OmniIntentSubtype.salaryAllocation) {
      return 'Phân bổ lương · $title · ${VndAmount.format(amountMinor)}';
    }
    if (s == OmniIntentSubtype.smartNote) {
      return 'Ghi chú · $title';
    }
    if (s == OmniIntentSubtype.vehicleMaintenance && amountMinor <= 0) {
      return 'Bảo dưỡng xe · $title${odometerKm != null ? " · $odometerKm km" : ""}';
    }
    return switch (kind) {
      OmniActionKind.transaction =>
        '$badgeLabelVi · $title · $categoryName · ${VndAmount.format(amountMinor)}',
      OmniActionKind.groupSplit =>
        'Chia nhóm · $title · ${VndAmount.format(amountMinor)} (${VndAmount.format(perPersonShareMinor)}/người × $participantCount)',
      OmniActionKind.calendarEvent =>
        'Lịch hẹn · $title${scheduledAt != null ? " · ${dtFmt.format(scheduledAt!)}" : ""}',
      OmniActionKind.task =>
        '$badgeLabelVi · $title${scheduledAt != null ? " · Lúc ${dtFmt.format(scheduledAt!)}" : ""}',
      OmniActionKind.grocery =>
        'Đi chợ · $title ($quantityLabel)${amountMinor > 0 ? " · ~${VndAmount.format(amountMinor)}" : ""}',
      OmniActionKind.waterLog => 'Uống nước · +$waterMl ml hôm nay',
      OmniActionKind.medication =>
        'Nhắc thuốc · $title · $dosage${scheduledAt != null ? " · Lúc ${hmFmt.format(scheduledAt!)}" : ""}',
    };
  }

  OmniActionDraft copyWith({
    String? id,
    OmniActionKind? kind,
    OmniIntentSubtype? subtype,
    String? title,
    int? amountMinor,
    TransactionKind? transactionKind,
    String? categoryId,
    String? categoryName,
    int? participantCount,
    List<String>? participantNames,
    DateTime? scheduledAt,
    int? durationMinutes,
    String? location,
    TaskPriorityLevel? taskPriority,
    String? quantityLabel,
    int? waterMl,
    MedicationScheduleSlot? medicationSlot,
    String? dosage,
    String? originLabel,
    String? sourceWalletHint,
    String? destinationWalletHint,
    String? vehicleHint,
    int? odometerKm,
    String? noteText,
    bool? requiresConfirmation,
    String? warningMessageVi,
  }) {
    return OmniActionDraft(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      subtype: subtype ?? this.subtype,
      title: title ?? this.title,
      amountMinor: amountMinor ?? this.amountMinor,
      transactionKind: transactionKind ?? this.transactionKind,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      participantCount: participantCount ?? this.participantCount,
      participantNames: participantNames ?? this.participantNames,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      location: location ?? this.location,
      taskPriority: taskPriority ?? this.taskPriority,
      quantityLabel: quantityLabel ?? this.quantityLabel,
      waterMl: waterMl ?? this.waterMl,
      medicationSlot: medicationSlot ?? this.medicationSlot,
      dosage: dosage ?? this.dosage,
      originLabel: originLabel ?? this.originLabel,
      sourceWalletHint: sourceWalletHint ?? this.sourceWalletHint,
      destinationWalletHint:
          destinationWalletHint ?? this.destinationWalletHint,
      vehicleHint: vehicleHint ?? this.vehicleHint,
      odometerKm: odometerKm ?? this.odometerKm,
      noteText: noteText ?? this.noteText,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      warningMessageVi: warningMessageVi ?? this.warningMessageVi,
    );
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    subtype,
    title,
    amountMinor,
    transactionKind,
    categoryId,
    categoryName,
    participantCount,
    participantNames,
    scheduledAt,
    durationMinutes,
    location,
    taskPriority,
    quantityLabel,
    waterMl,
    medicationSlot,
    dosage,
    originLabel,
    sourceWalletHint,
    destinationWalletHint,
    vehicleHint,
    odometerKm,
    noteText,
    requiresConfirmation,
    warningMessageVi,
  ];
}

class BlockedClauseInfo extends Equatable {
  final String clause;
  final ClauseSafetyStatus status;
  final String reasonVi;

  const BlockedClauseInfo({
    required this.clause,
    required this.status,
    required this.reasonVi,
  });

  @override
  List<Object?> get props => [clause, status, reasonVi];
}

class OmniParseEnvelope extends Equatable {
  final List<OmniActionDraft> drafts;
  final List<BlockedClauseInfo> blockedClauses;
  final List<OmniActionDraft> queryDrafts;

  const OmniParseEnvelope({
    required this.drafts,
    this.blockedClauses = const <BlockedClauseInfo>[],
    this.queryDrafts = const <OmniActionDraft>[],
  });

  @override
  List<Object?> get props => [drafts, blockedClauses, queryDrafts];
}

/// Scrubs PII (OTP, emails, spaced/standard phones, CCCD/BHYT/FAM codes, license plates,
/// bank cards & standalone bank account numbers) before any text is sent to an opt-in cloud LLM.
abstract final class GeminiPrivacySanitizer {
  static final RegExp _emailRegex = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );
  static final RegExp _vnPhoneRegex = RegExp(
    r'(?<!\d)(?:\+?84|0)(?:3|5|7|8|9)(?:[\s.\-]*\d){8}(?!\d)',
  );
  static final RegExp _famInviteRegex = RegExp(
    r'\bFAM[-_\s]?[A-Z0-9]{4,12}\b',
    caseSensitive: false,
  );
  static final RegExp _bhytRegex = RegExp(
    r'\b[A-Z]{2}\d{13}\b',
    caseSensitive: false,
  );
  static final RegExp _spacedCardRegex = RegExp(
    r'(?<!\d)(?:\d{4}[\s\-]){3}\d{4}(?!\d)',
  );
  static final RegExp _plateRegex = RegExp(
    r'(?<![\p{L}\p{N}])\d{2}[A-Z]\d?[-\s.]?\d{3,5}(?:\.\d{2})?(?![\p{L}\p{N}])',
    unicode: true,
  );
  static final RegExp _cccdContextRegex = RegExp(
    r'\b(?:cccd|cmnd|căn\s+cước|chứng\s+minh|hộ\s+chiếu|passport)\s*(?:số|:)?\s*([A-Z0-9\-\s]{8,16})',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _longAccountOrIdRegex = RegExp(
    r'(?<!\d)\d{9,19}(?!\d)(?!\s*(?:đ|d|₫|vnd|vnđ|đồng|dong|k|tr|triệu|trieu|nghìn|nghin|ngàn|ngan)\b)',
    caseSensitive: false,
  );

  static String sanitize(String rawText) {
    if (rawText.trim().isEmpty) return rawText;
    var out = rawText.replaceAll(_emailRegex, '[ẨN_EMAIL]');
    out = out.replaceAll(_famInviteRegex, '[ẨN_MÃ_NHÓM]');
    out = out.replaceAll(_bhytRegex, '[ẨN_BHYT]');
    out = out.replaceAllMapped(_cccdContextRegex, (m) => '[ẨN_CCCD]');
    out = out.replaceAll(_plateRegex, '[ẨN_BIỂN_SỐ]');
    out = out.replaceAll(_vnPhoneRegex, '[ẨN_SĐT]');
    out = out.replaceAll(_longAccountOrIdRegex, '[ẨN_SỐ_TK]');
    out = out.replaceAll(_spacedCardRegex, '[ẨN_SỐ_THẺ]');
    // Always finish with OtpRedactor so OTP digits, Bearer tokens, and remaining PAN patterns are redacted.
    out = OtpRedactor.redact(out);
    return out;
  }
}

/// Deterministic `< 2ms` Offline Omni-Intent Parser inspired by Todoist, TickTick,
/// Splitwise, Revolut & MoMo: routes natural Vietnamese sentences to Finance, Group Split,
/// Calendar, Tasks, or Groceries without requiring internet.
abstract final class SmartOmniIntentParser {
  static final RegExp _splitCountRegex = RegExp(
    r'chia(?:\s+đều|\s+deu)?(?:\s+cho)?\s+(\d{1,2})\s*(?:người|nguoi|bạn|ban|đứa|dua|thành viên)?',
    caseSensitive: false,
  );

  static final RegExp _explicitHourRegex = RegExp(
    r'\b(\d{1,2})\s*(?:h|g|giờ|gio|:)\s*(\d{0,2})\s*(?:phút|phut)?\s*(sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem)?\b',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _vnPhoneWithoutCurrencyRegex = RegExp(
    r'(?:^|\s)(?:\+?84|0)(?:3|5|7|8|9)(?:[\s.\-]*\d){8}(?!\s*(?:đ|d|₫|vnd|vnđ|đồng|dong|k|tr|triệu|trieu)\b)',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _hardClauseDelimiter = RegExp(r'[;\n]+');

  static final RegExp _candidateClauseConnector = RegExp(
    r'(?:\s+(?:và|va|rồi|roi|xong|tiếp\s+theo|tiep\s+theo|sau\s+đó|sau\s+do)\s+|(?<!\d),\s*|,\s+)',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _waterMlRegex = RegExp(
    r'\b(\d{2,4})\s*ml(?:\s+nước|\s+nuoc)?\b',
    caseSensitive: false,
  );

  static final RegExp _waterCupRegex = RegExp(
    r'\b(?:uống|uong)\s+(\d{1,2})\s*(?:cốc|coc|ly|chai)\s+(?:nước|nuoc)\b',
    caseSensitive: false,
  );

  static final RegExp _waterLiterRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:uống|uong)\s+(\d{1,2})\s*(?:lít|lit)(?:\s*(rưỡi|ruoi))?\s+(?:nước|nuoc)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static OmniActionDraft? tryParsePrimary(String rawInput, {DateTime? now}) {
    final all = parseMulti(rawInput, now: now);
    return all.isEmpty ? null : all.first;
  }

  static List<OmniActionDraft> parseMulti(String rawInput, {DateTime? now}) {
    return parseDetailed(rawInput, now: now).drafts;
  }

  /// Parses compound multi-domain utterances into validated actionable drafts
  /// while surfacing safety-blocked clauses (negations, hypotheticals, questions, balance checks)
  /// and read-only financial overview queries separately.
  static OmniParseEnvelope parseDetailed(String rawInput, {DateTime? now}) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const OmniParseEnvelope(drafts: <OmniActionDraft>[]);
    }

    final refNow = now ?? DateTime.now();

    // Check if the entire sentence is a pure grocery list first ("đi chợ mua sữa, trứng, rau")
    final wholeLower = trimmed.toLowerCase();
    if (ClauseSafetyScreener.screenClause(trimmed).isAllowed &&
        _looksLikeGroceryCommand(wholeLower) &&
        SmartQuickEntryParser.tryParse(trimmed) == null &&
        !_containsScheduleCue(wholeLower)) {
      return OmniParseEnvelope(
        drafts: _parseGroceryItems(trimmed, startIndex: 0),
      );
    }

    final hardBlocks = trimmed
        .split(_hardClauseDelimiter)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    final rawClauses = <String>[];
    for (final block in hardBlocks) {
      rawClauses.addAll(_splitValidatedClauses(block, refNow: refNow));
    }

    final results = <OmniActionDraft>[];
    final blocked = <BlockedClauseInfo>[];
    final queries = <OmniActionDraft>[];
    var seq = 0;

    for (final clause in rawClauses) {
      final safety = ClauseSafetyScreener.screenClause(clause);
      if (safety.isBlocked) {
        if (safety.status == ClauseSafetyStatus.financialQuery) {
          queries.add(
            OmniActionDraft(
              id: 'omni_query_$seq',
              kind: OmniActionKind.task,
              subtype: OmniIntentSubtype.financialOverviewQuery,
              title: _capitalizeFirst(clause),
            ),
          );
          seq++;
        } else {
          blocked.add(
            BlockedClauseInfo(
              clause: clause,
              status: safety.status,
              reasonVi:
                  safety.reasonVi ??
                  'Mệnh đề này không tạo giao dịch để đảm bảo an toàn.',
            ),
          );
        }
        continue;
      }

      final parsedClause = _parseSingleClause(
        clause,
        refNow: refNow,
        index: seq,
      );
      if (parsedClause.isNotEmpty) {
        results.addAll(parsedClause);
        seq += parsedClause.length;
      }
    }

    return OmniParseEnvelope(
      drafts: results,
      blockedClauses: blocked,
      queryDrafts: queries,
    );
  }

  static List<String> _splitValidatedClauses(
    String segment, {
    required DateTime refNow,
  }) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) return const <String>[];

    final out = <String>[];
    var cursor = 0;

    for (final m in _candidateClauseConnector.allMatches(trimmed)) {
      if (m.start < cursor) continue;
      final left = trimmed.substring(cursor, m.start).trim();
      final right = trimmed.substring(m.end).trim();
      if (left.isEmpty || right.isEmpty) continue;

      final isComma = m.group(0)!.contains(',');
      if (isComma &&
          _looksLikeGroceryCommand(left.toLowerCase()) &&
          SmartQuickEntryParser.tryParse(left) == null &&
          !_containsScheduleCue(left.toLowerCase())) {
        final nextMatch = _candidateClauseConnector.firstMatch(right);
        final immediateRight = nextMatch == null
            ? right
            : right.substring(0, nextMatch.start).trim();
        if (_parseSingleClause(
              immediateRight,
              refNow: refNow,
              index: 0,
            ).isEmpty &&
            ClauseSafetyScreener.screenClause(immediateRight).isAllowed) {
          continue;
        }
      }

      final leftIsBlocked = ClauseSafetyScreener.screenClause(left).isBlocked;
      final leftDrafts = leftIsBlocked
          ? const <OmniActionDraft>[]
          : _parseSingleClause(left, refNow: refNow, index: 0);
      if (!leftIsBlocked && leftDrafts.isEmpty) continue;

      if (!_hasValidOrBlockedDraftInTail(right, refNow: refNow)) continue;

      out.add(left);
      cursor = m.end;
    }

    final tail = trimmed.substring(cursor).trim();
    if (tail.isNotEmpty) {
      out.add(tail);
    }
    return out;
  }

  static bool _hasValidOrBlockedDraftInTail(
    String tail, {
    required DateTime refNow,
  }) {
    final subClauses = _splitValidatedClauses(tail, refNow: refNow);
    for (final sub in subClauses) {
      if (ClauseSafetyScreener.screenClause(sub).isBlocked) {
        return true;
      }
      if (_parseSingleClause(sub, refNow: refNow, index: 0).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  static List<OmniActionDraft> _parseSingleClause(
    String clause, {
    required DateTime refNow,
    required int index,
  }) {
    final lower = clause.toLowerCase();
    final folded = VietnameseSearchMatcher.fold(lower);
    final entities = VietnameseTemporalAndEntityResolver.extractEntities(
      clause,
    );

    // 0A. Water Hydration Log ("uống 250ml nước", "uống 2 cốc nước", "nhắc uống nước")
    final waterDraft = _tryParseWaterClause(clause, lower, index: index);
    if (waterDraft != null) {
      return <OmniActionDraft>[waterDraft];
    }

    // 0B. Medication Reminder ("nhắc uống thuốc Vitamin D3 8h sáng", "uống thuốc cảm sau ăn tối")
    final medDraft = _tryParseMedicationClause(
      clause,
      lower,
      refNow: refNow,
      index: index,
    );
    if (medDraft != null) {
      return <OmniActionDraft>[medDraft];
    }

    // 0C. Smart Note ("ghi chú: ...", "note ...")
    if (folded.startsWith('ghi chu') || folded.startsWith('note')) {
      final noteBody = clause
          .replaceFirst(
            RegExp(
              r'^(?:ghi\s+chú|ghi\s+chu|note)\s*:?\s*',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      if (noteBody.isNotEmpty) {
        return <OmniActionDraft>[
          OmniActionDraft(
            id: 'omni_note_$index',
            kind: OmniActionKind.task,
            subtype: OmniIntentSubtype.smartNote,
            title: _capitalizeFirst(noteBody),
            noteText: noteBody,
          ),
        ];
      }
    }

    // 0D. Alarm ("báo thức 6 giờ 30 sáng mai", "đặt chuông 7h sáng")
    if (folded.startsWith('bao thuc') || folded.startsWith('dat chuong')) {
      final (alarmAt, cleanedTitle) = _extractDateTimeAndTitle(
        clause.replaceFirst(
          RegExp(
            r'^(?:báo\s+thức|bao\s+thuc|đặt\s+chuông|dat\s+chuong)\s*:?\s*',
            caseSensitive: false,
          ),
          '',
        ),
        refNow: refNow,
        defaultHour: 7,
      );
      return <OmniActionDraft>[
        OmniActionDraft(
          id: 'omni_alarm_$index',
          kind: OmniActionKind.task,
          subtype: OmniIntentSubtype.alarm,
          title: cleanedTitle.isEmpty ? 'Báo thức' : cleanedTitle,
          scheduledAt: alarmAt,
          taskPriority: TaskPriorityLevel.high,
        ),
      ];
    }

    // Ignore Vietnamese phone tokens inside non-financial text before trying SmartQuickEntryParser
    final clauseWithoutPhones = clause
        .replaceAll(_vnPhoneWithoutCurrencyRegex, ' ')
        .trim();
    final moneyCandidate = SmartQuickEntryParser.tryParse(clauseWithoutPhones);

    // 0E. Budget setup ("đặt ngân sách ăn uống 5 triệu", "hạn mức mua sắm 3tr")
    if ((folded.contains('ngan sach') || folded.contains('han muc')) &&
        moneyCandidate != null &&
        moneyCandidate.amountMinor > 0) {
      return <OmniActionDraft>[
        OmniActionDraft(
          id: 'omni_budget_$index',
          kind: OmniActionKind.transaction,
          subtype: OmniIntentSubtype.budgetSetup,
          title: moneyCandidate.categoryName,
          amountMinor: moneyCandidate.amountMinor,
          categoryId: moneyCandidate.categoryId,
          categoryName: moneyCandidate.categoryName,
          sourceWalletHint: entities.walletHint,
        ),
      ];
    }

    // 0F. Salary allocation ("phân bổ lương 30 triệu", "chia lương 25tr")
    if ((folded.contains('phan bo luong') ||
            folded.contains('chia luong') ||
            folded.contains('50/30/20') ||
            folded.contains('6 lo')) &&
        moneyCandidate != null &&
        moneyCandidate.amountMinor > 0) {
      return <OmniActionDraft>[
        OmniActionDraft(
          id: 'omni_alloc_$index',
          kind: OmniActionKind.transaction,
          subtype: OmniIntentSubtype.salaryAllocation,
          title: moneyCandidate.merchant,
          amountMinor: moneyCandidate.amountMinor,
          transactionKind: TransactionKind.income,
          categoryId: moneyCandidate.categoryId,
          categoryName: 'Phân bổ thu nhập',
        ),
      ];
    }

    // 1. Group Bill Split ("Ăn lẩu 600k chia 4 người")
    final splitMatch = _splitCountRegex.firstMatch(lower);
    if (splitMatch != null) {
      final count = (int.tryParse(splitMatch.group(1) ?? '2') ?? 2).clamp(
        2,
        30,
      );
      final cleanedForMoney = clauseWithoutPhones
          .replaceFirst(splitMatch.group(0) ?? '', '')
          .trim();
      final tx = SmartQuickEntryParser.tryParse(cleanedForMoney);
      if (tx != null && tx.amountMinor > 0) {
        return <OmniActionDraft>[
          OmniActionDraft(
            id: 'omni_split_$index',
            kind: OmniActionKind.groupSplit,
            subtype: OmniIntentSubtype.groupBillSplit,
            title: tx.merchant,
            amountMinor: tx.amountMinor,
            categoryId: tx.categoryId,
            categoryName: tx.categoryName,
            participantCount: count,
          ),
        ];
      }
    }

    // 2. Vehicle Maintenance & Odometer Log
    final hasVehicleMaintenanceCue =
        folded.contains('bao duong') ||
        folded.contains('thay nhot') ||
        folded.contains('sua xe') ||
        folded.contains('thay lop') ||
        folded.contains('rua xe') ||
        (entities.vehicleHint != null && entities.odometerKm != null);
    if (hasVehicleMaintenanceCue) {
      if (moneyCandidate != null && moneyCandidate.amountMinor > 0) {
        return <OmniActionDraft>[
          OmniActionDraft(
            id: 'omni_veh_$index',
            kind: OmniActionKind.transaction,
            subtype: OmniIntentSubtype.vehicleMaintenance,
            title: moneyCandidate.merchant,
            amountMinor: moneyCandidate.amountMinor,
            transactionKind: TransactionKind.expense,
            categoryId: 'cat_transport',
            categoryName: 'Bảo dưỡng xe',
            sourceWalletHint: entities.walletHint,
            vehicleHint: entities.vehicleHint,
            odometerKm: entities.odometerKm,
          ),
        ];
      } else {
        return <OmniActionDraft>[
          OmniActionDraft(
            id: 'omni_veh_task_$index',
            kind: OmniActionKind.task,
            subtype: OmniIntentSubtype.vehicleMaintenance,
            title: _capitalizeFirst(clause),
            scheduledAt: refNow,
            vehicleHint: entities.vehicleHint,
            odometerKm: entities.odometerKm,
          ),
        ];
      }
    }

    // 3. Grocery Basket ("Đi chợ mua sữa tươi, trứng gà" when no completed spend amount)
    if (_looksLikeGroceryCommand(lower) && moneyCandidate == null) {
      return _parseGroceryItems(clause, startIndex: index);
    }

    // 4. Financial Transaction (Internal Transfer / Debt Settlement / Refund / Loan / Fuel / Expense / Income)
    if (moneyCandidate != null &&
        !_isPureTimeNumberFalsePositive(lower) &&
        !(folded.contains('lich ') && _containsScheduleCue(lower)) &&
        !(folded.contains('hop ') && _explicitHourRegex.hasMatch(folded))) {
      final txSubtype = _inferFinancialSubtype(
        folded: folded,
        parsed: moneyCandidate,
        entities: entities,
      );
      final resolvedTxKind = txSubtype == OmniIntentSubtype.internalTransfer
          ? TransactionKind.transfer
          : txSubtype == OmniIntentSubtype.refund
          ? TransactionKind.income
          : moneyCandidate.kind;
      final resolvedCatId = txSubtype == OmniIntentSubtype.internalTransfer
          ? 'cat_transfer'
          : txSubtype == OmniIntentSubtype.fuelRefill
          ? 'cat_transport'
          : moneyCandidate.categoryId;
      final resolvedCatName = switch (txSubtype) {
        OmniIntentSubtype.internalTransfer => 'Chuyển khoản nội bộ',
        OmniIntentSubtype.refund => 'Hoàn tiền',
        OmniIntentSubtype.loanOrBorrow => 'Vay & Cho vay',
        OmniIntentSubtype.debtSettlement => 'Tất toán nợ',
        OmniIntentSubtype.fuelRefill => moneyCandidate.categoryName,
        _ => moneyCandidate.categoryName,
      };
      return <OmniActionDraft>[
        OmniActionDraft(
          id: 'omni_tx_$index',
          kind: OmniActionKind.transaction,
          subtype: txSubtype,
          title: moneyCandidate.merchant,
          amountMinor: moneyCandidate.amountMinor,
          transactionKind: resolvedTxKind,
          categoryId: resolvedCatId,
          categoryName: resolvedCatName,
          sourceWalletHint: entities.walletHint,
          destinationWalletHint: entities.destinationWalletHint,
          vehicleHint: entities.vehicleHint,
          odometerKm: entities.odometerKm,
          location: entities.locationHint,
        ),
      ];
    }

    // 5. Calendar Event ("Họp dự án 9h sáng mai", "Ngày mai có lịch họp lúc 9 giờ")
    if (_containsScheduleCue(lower)) {
      final (scheduledTime, strippedTitle) = _extractDateTimeAndTitle(
        clause,
        refNow: refNow,
        defaultHour: 9,
      );
      return <OmniActionDraft>[
        OmniActionDraft(
          id: 'omni_event_$index',
          kind: OmniActionKind.calendarEvent,
          subtype: OmniIntentSubtype.calendarEvent,
          title: strippedTitle,
          scheduledAt: scheduledTime,
          durationMinutes: 60,
          location: entities.locationHint,
        ),
      ];
    }

    // 6. Task / Reminder ("Tối 8 giờ nhắc tôi gọi mẹ", "Nhắc đóng tiền điện tối nay !gấp")
    if (_containsTaskCue(lower)) {
      final isUrgent =
          lower.contains('!gấp') ||
          lower.contains('!gap') ||
          lower.contains('khẩn') ||
          lower.contains('quan trọng');
      final cleanedUrgent = clause
          .replaceAll(
            RegExp(r'!gấp|!gap|!quan trọng', caseSensitive: false),
            '',
          )
          .trim();
      final (dueTime, strippedTitle) = _extractDateTimeAndTitle(
        cleanedUrgent,
        refNow: refNow,
        defaultHour: 19,
      );
      final isReminder = folded.contains('nhac');
      return <OmniActionDraft>[
        OmniActionDraft(
          id: 'omni_task_$index',
          kind: OmniActionKind.task,
          subtype: isReminder
              ? OmniIntentSubtype.reminder
              : OmniIntentSubtype.task,
          title: strippedTitle,
          scheduledAt: dueTime,
          taskPriority: isUrgent
              ? TaskPriorityLevel.high
              : TaskPriorityLevel.medium,
        ),
      ];
    }

    return const <OmniActionDraft>[];
  }

  static OmniIntentSubtype _inferFinancialSubtype({
    required String folded,
    required ParsedSmartEntry parsed,
    required VietnameseEntitySnapshot entities,
  }) {
    if (folded.contains('tat toan') || folded.contains('tra no')) {
      return OmniIntentSubtype.debtSettlement;
    }
    if ((folded.contains('chuyen') ||
            folded.contains('nap sang') ||
            (folded.contains('nap ') && folded.contains(' sang '))) &&
        (entities.destinationWalletHint != null ||
            folded.contains('tu vi') ||
            folded.contains('sang vi') ||
            folded.contains('noi bo'))) {
      return OmniIntentSubtype.internalTransfer;
    }
    if (folded.contains('hoan tien') || folded.contains('refund')) {
      return OmniIntentSubtype.refund;
    }
    if (folded.contains('cho vay') ||
        folded.contains('muon ') ||
        RegExp(r'\bvay\b').hasMatch(folded)) {
      return OmniIntentSubtype.loanOrBorrow;
    }
    if (folded.contains('do xang') ||
        folded.contains('xang') ||
        folded.contains('sac xe')) {
      return OmniIntentSubtype.fuelRefill;
    }
    return parsed.kind == TransactionKind.income
        ? OmniIntentSubtype.income
        : OmniIntentSubtype.expense;
  }

  static bool _isPureTimeNumberFalsePositive(String lower) {
    return (lower.startsWith('lịch ') ||
            lower.startsWith('họp ') ||
            lower.startsWith('hẹn ')) &&
        !RegExp(
          r'(?<![\p{L}\p{N}])\d+(?:[.,]\d+)?\s*(?:k|tr|triệu|trieu|củ|cu|cành|canh|nhành|nhanh|xị|xi|chục|chuc|lít|lit|nghìn|nghin|ngàn|ngan|đ|₫|vnd|vnđ)(?![\p{L}\p{N}])',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(lower) &&
        !RegExp(
          r'(?<![\p{L}\p{N}])(?:nửa\s+(?:triệu|trieu|củ|cu|xị)|(?:một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)\s+(?:trăm\s+rưỡi|xị|cành|nhành|chục|củ|triệu)|trăm\s+rưỡi)(?![\p{L}\p{N}])',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(lower);
  }

  static bool _looksLikeGroceryCommand(String lower) {
    return lower.startsWith('đi chợ') ||
        lower.startsWith('di cho') ||
        lower.startsWith('giỏ chợ') ||
        lower.startsWith('thêm món') ||
        lower.startsWith('cần mua ') ||
        lower.startsWith('mua sữa') ||
        lower.startsWith('mua rau') ||
        lower.startsWith('mua thịt') ||
        lower.startsWith('mua trái cây');
  }

  static List<OmniActionDraft> _parseGroceryItems(
    String raw, {
    required int startIndex,
  }) {
    var body = raw.replaceFirst(
      RegExp(
        r'^(?:đi chợ(?:\s+mua)?|di cho(?:\s+mua)?|giỏ chợ:?|thêm món:?|cần mua|mua)\s*',
        caseSensitive: false,
      ),
      '',
    );
    body = body.trim();
    if (body.isEmpty) return const <OmniActionDraft>[];

    final parts = body
        .split(RegExp(r'[,،]+|\s+và\s+', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.length >= 2)
        .toList();

    if (parts.isEmpty) return const <OmniActionDraft>[];
    final out = <OmniActionDraft>[];
    for (var i = 0; i < parts.length; i++) {
      final item = _capitalizeFirst(parts[i]);
      out.add(
        OmniActionDraft(
          id: 'omni_grocery_${startIndex + i}',
          kind: OmniActionKind.grocery,
          title: item,
        ),
      );
    }
    return out;
  }

  static bool _containsScheduleCue(String lower) {
    final cleanedUrgent = lower.replaceAll(
      RegExp(r'!gấp|!gap|!quan trọng', caseSensitive: false),
      '',
    );
    final folded = VietnameseSearchMatcher.fold(cleanedUrgent);
    if (folded.startsWith('lich ') ||
        folded.startsWith('lich:') ||
        folded.startsWith('co lich') ||
        folded.startsWith('hop ') ||
        folded.startsWith('hen ') ||
        folded.startsWith('kham ') ||
        folded.startsWith('di kham ')) {
      return true;
    }
    if (RegExp(r'\b(co\s+)?lich\s+(hop|hen|kham|di|lam)\b').hasMatch(folded) ||
        RegExp(r'\b(hop|hen|kham)\s+(?:luc|vao|\d)').hasMatch(folded) ||
        RegExp(r'\bdi\s+kham\b').hasMatch(folded)) {
      return true;
    }
    if (_explicitHourRegex.hasMatch(folded) &&
        (folded.contains('hop') ||
            folded.contains('hen') ||
            folded.contains('lich') ||
            RegExp(r'\bgap\b').hasMatch(folded) ||
            folded.contains('kham') ||
            folded.contains('sang mai') ||
            folded.contains('chieu mai') ||
            folded.contains('toi mai') ||
            folded.contains('sang mot') ||
            folded.contains('trua mot') ||
            folded.contains('chieu mot') ||
            folded.contains('toi mot') ||
            folded.contains('ngay mot'))) {
      return true;
    }
    return false;
  }

  static bool _containsTaskCue(String lower) {
    final folded = VietnameseSearchMatcher.fold(lower);
    if (folded.startsWith('nhac ') ||
        folded.startsWith('nho ') ||
        folded.startsWith('viec:') ||
        folded.startsWith('viec ') ||
        folded.startsWith('can lam') ||
        folded.startsWith('hoan thanh ') ||
        folded.startsWith('gui bao cao') ||
        folded.startsWith('dong tien ')) {
      return true;
    }
    return RegExp(
      r'\b(?:nhac\s+(?:toi|minh|nho|lai)?|can\s+lam|hoan\s+thanh|gui\s+bao\s+cao|bao\s+thuc)\b',
    ).hasMatch(folded);
  }

  static (DateTime, String) _extractDateTimeAndTitle(
    String rawClause, {
    required DateTime refNow,
    required int defaultHour,
  }) {
    final temporal = VietnameseTemporalAndEntityResolver.resolveTemporal(
      rawClause,
      referenceNow: refNow,
      defaultHour: defaultHour,
    );

    var cleanTitle = temporal.cleanedText
        .replaceFirst(
          RegExp(
            r'^(?:có\s+lịch\s+|co\s+lich\s+|nhắc nhở:?|nhac nho:?|nhắc\s+(?:tôi|mình|nhở)?:?|nhac\s+(?:toi|minh|nho)?:?|nhớ:?|nho:?|việc cần làm:?|viec can lam:?|việc:?|viec:?|cần làm:?|can lam:?|lịch:?|lich:?)\s*',
            caseSensitive: false,
            unicode: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(?:nhắc\s+(?:tôi|mình)|nhac\s+(?:toi|minh)|có\s+lịch|co\s+lich)\b',
            caseSensitive: false,
            unicode: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[-:,.\s]+|[-:,.\s]+$'), '')
        .trim();

    if (cleanTitle.length < 2) {
      cleanTitle = _capitalizeFirst(rawClause.trim());
    } else {
      cleanTitle = _capitalizeFirst(cleanTitle);
    }

    return (temporal.dateTime, cleanTitle);
  }

  static String _capitalizeFirst(String input) {
    if (input.isEmpty) return input;
    return '${input[0].toUpperCase()}${input.substring(1)}';
  }

  static OmniActionDraft? _tryParseWaterClause(
    String clause,
    String lower, {
    required int index,
  }) {
    final folded = VietnameseSearchMatcher.fold(lower);
    // Avoid matching paid beverages like "mua nước 15 nghìn" or "tiền nước 150k"
    if (SmartQuickEntryParser.tryParse(clause) != null &&
        !folded.contains('ml')) {
      return null;
    }

    final mlMatch = _waterMlRegex.firstMatch(folded);
    if (mlMatch != null &&
        (folded.contains('nuoc') || folded.startsWith('uong '))) {
      final ml = (int.tryParse(mlMatch.group(1) ?? '250') ?? 250).clamp(
        50,
        3000,
      );
      return OmniActionDraft(
        id: 'omni_water_$index',
        kind: OmniActionKind.waterLog,
        title: 'Nước lọc',
        waterMl: ml,
      );
    }

    final literMatch = _waterLiterRegex.firstMatch(clause);
    if (literMatch != null) {
      final liters = int.tryParse(literMatch.group(1) ?? '1') ?? 1;
      final hasHalf =
          literMatch.group(2) != null && literMatch.group(2)!.isNotEmpty;
      final ml = (liters * 1000 + (hasHalf ? 500 : 0)).clamp(50, 3000);
      return OmniActionDraft(
        id: 'omni_water_$index',
        kind: OmniActionKind.waterLog,
        title: 'Nước lọc',
        waterMl: ml,
      );
    }

    final cupMatch = _waterCupRegex.firstMatch(folded);
    if (cupMatch != null) {
      final cups = (int.tryParse(cupMatch.group(1) ?? '1') ?? 1).clamp(1, 10);
      return OmniActionDraft(
        id: 'omni_water_$index',
        kind: OmniActionKind.waterLog,
        title: 'Nước lọc',
        waterMl: cups * 250,
      );
    }

    if (folded == 'uong nuoc' || folded.startsWith('uong 1 coc nuoc')) {
      return OmniActionDraft(
        id: 'omni_water_$index',
        kind: OmniActionKind.waterLog,
        title: 'Nước lọc',
        waterMl: 250,
      );
    }
    return null;
  }

  static OmniActionDraft? _tryParseMedicationClause(
    String clause,
    String lower, {
    required DateTime refNow,
    required int index,
  }) {
    final folded = VietnameseSearchMatcher.fold(lower);
    final hasMedCue =
        folded.contains('uong thuoc') ||
        folded.contains('nhac thuoc') ||
        folded.startsWith('them thuoc ') ||
        (folded.contains('vitamin') &&
            (folded.contains('nhac') || folded.contains('uong')));
    if (!hasMedCue) return null;

    // Exclude paid pharmacy purchase like "mua thuốc 120k"
    if (folded.startsWith('mua thuoc') &&
        SmartQuickEntryParser.tryParse(clause) != null) {
      return null;
    }

    var slot = MedicationScheduleSlot.morning;
    if (lower.contains('trưa') || lower.contains('trua')) {
      slot = MedicationScheduleSlot.noon;
    } else if (lower.contains('tối') || lower.contains('toi')) {
      slot = MedicationScheduleSlot.evening;
    }

    final (scheduledTime, _) = _extractDateTimeAndTitle(
      clause,
      refNow: refNow,
      defaultHour: slot.defaultHour,
    );

    var medName = clause
        .replaceFirst(
          RegExp(
            r'^(?:nhắc nhở\s+)?(?:nhắc\s+)?(?:nhớ\s+)?(?:thêm\s+)?(?:uống\s+)?(?:thuốc\s*)?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(_explicitHourRegex, '')
        .replaceAll(
          RegExp(
            r'(?<![\p{L}\p{N}])(?:lúc|vào|buổi sáng|buổi trưa|buổi tối|sau ăn sáng|sau ăn trưa|sau ăn tối|sau ăn|trước ăn|sáng nay|sáng mai|sáng mốt|chiều mốt|tối mốt|ngày mốt|tối nay|mỗi ngày)(?![\p{L}\p{N}])',
            caseSensitive: false,
            unicode: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[-:,.\s]+|[-:,.\s]+$'), '')
        .trim();

    if (medName.length < 2) {
      medName = 'Thuốc / Vitamin hằng ngày';
    } else {
      medName = _capitalizeFirst(medName);
    }

    final dosage = lower.contains('trước ăn')
        ? '1 viên trước ăn'
        : '1 viên sau ăn';

    return OmniActionDraft(
      id: 'omni_med_$index',
      kind: OmniActionKind.medication,
      title: medName,
      medicationSlot: slot,
      dosage: dosage,
      scheduledAt: scheduledTime,
    );
  }
}
