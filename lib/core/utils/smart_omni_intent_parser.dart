import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../features/daily_life/domain/entities/daily_life_entities.dart';
import '../../features/tasks/domain/entities/task_entities.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import 'smart_quick_entry_parser.dart';
import 'vietnamese_search_matcher.dart';
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

/// Cross-domain actionable draft produced by either the `< 2ms` Offline `SmartOmniIntentParser`
/// or the opt-in Connected `GeminiCopilotRepository`.
class OmniActionDraft extends Equatable {
  final String id;
  final OmniActionKind kind;
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

  const OmniActionDraft({
    required this.id,
    required this.kind,
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
  });

  String get badgeLabelVi => switch (kind) {
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

  int get perPersonShareMinor {
    if (participantCount <= 0) return amountMinor;
    return amountMinor ~/ participantCount;
  }

  String get summaryLineVi {
    final dtFmt = DateFormat('HH:mm dd/MM');
    final hmFmt = DateFormat('HH:mm');
    return switch (kind) {
      OmniActionKind.transaction =>
        '$badgeLabelVi · $title · $categoryName · ${VndAmount.format(amountMinor)}',
      OmniActionKind.groupSplit =>
        'Chia nhóm · $title · ${VndAmount.format(amountMinor)} (${VndAmount.format(perPersonShareMinor)}/người × $participantCount)',
      OmniActionKind.calendarEvent =>
        'Lịch hẹn · $title${scheduledAt != null ? " · ${dtFmt.format(scheduledAt!)}" : ""}',
      OmniActionKind.task =>
        '$badgeLabelVi · $title${scheduledAt != null ? " · Hạn ${dtFmt.format(scheduledAt!)}" : ""}',
      OmniActionKind.grocery =>
        'Đi chợ · $title ($quantityLabel)${amountMinor > 0 ? " · ~${VndAmount.format(amountMinor)}" : ""}',
      OmniActionKind.waterLog => 'Uống nước · +$waterMl ml hôm nay',
      OmniActionKind.medication =>
        'Nhắc thuốc · $title · $dosage${scheduledAt != null ? " · Lúc ${hmFmt.format(scheduledAt!)}" : ""}',
    };
  }

  @override
  List<Object?> get props => [
    id,
    kind,
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
  ];
}

/// Scrubs PII (Vietnamese phone numbers, emails, national IDs, standalone bank account numbers)
/// before any text is sent to an opt-in cloud LLM.
abstract final class GeminiPrivacySanitizer {
  static final RegExp _emailRegex = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );
  static final RegExp _vnPhoneRegex = RegExp(
    r'(?<!\d)(?:\+?84|0)(?:3|5|7|8|9)\d{8}(?!\d)',
  );
  static final RegExp _longAccountOrIdRegex = RegExp(
    r'(?<!\d)\d{9,19}(?!\d)(?!\s*(?:đ|d|vnd|vnđ|k|tr|triệu|trieu|nghìn|nghin|ngàn|ngan)\b)',
    caseSensitive: false,
  );

  static String sanitize(String rawText) {
    if (rawText.trim().isEmpty) return rawText;
    var out = rawText.replaceAll(_emailRegex, '[ẨN_EMAIL]');
    out = out.replaceAll(_vnPhoneRegex, '[ẨN_SĐT]');
    out = out.replaceAll(_longAccountOrIdRegex, '[ẨN_SỐ_TK]');
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
    r'\b(\d{1,2})(?:h|:)(\d{0,2})\s*(sáng|sang|trưa|trua|chiều|chieu|tối|toi)?\b',
    caseSensitive: false,
  );

  static final RegExp _clauseSplitter = RegExp(
    r'(?:[;\n]+|\s+(?:và|va)\s+(?=(?:nhắc|nhac|nhớ|nho|họp|hop|lịch|lich|hẹn|hen|đi chợ|di cho|mua|ăn|an|đổ|do|trả|tra|nhận|nhan|chuyển|chuyen|uống|uong|chiều|chieu|sáng|sang|tối|toi|mai)\b)|,\s+(?=(?:chiều|chieu|sáng|sang|tối|toi|trưa|trua|ngày mai|ngay mai|mai|nhắc|nhac|nhớ|nho|họp|hop|lịch|lich|hẹn|hen|đi chợ|di cho|uống|uong)\b))',
    caseSensitive: false,
  );

  static final RegExp _waterMlRegex = RegExp(
    r'\b(\d{2,4})\s*ml(?:\s+nước|\s+nuoc)?\b',
    caseSensitive: false,
  );

  static final RegExp _waterCupRegex = RegExp(
    r'\b(?:uống|uong)\s+(\d{1,2})\s*(?:cốc|coc|ly|chai)\s+(?:nước|nuoc)\b',
    caseSensitive: false,
  );

  static OmniActionDraft? tryParsePrimary(String rawInput, {DateTime? now}) {
    final all = parseMulti(rawInput, now: now);
    return all.isEmpty ? null : all.first;
  }

  static List<OmniActionDraft> parseMulti(String rawInput, {DateTime? now}) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return const <OmniActionDraft>[];

    final refNow = now ?? DateTime.now();

    // Check if the entire sentence is a pure grocery list first ("đi chợ mua sữa, trứng, rau")
    final wholeLower = trimmed.toLowerCase();
    if (_looksLikeGroceryCommand(wholeLower) &&
        SmartQuickEntryParser.tryParse(trimmed) == null &&
        !_containsScheduleCue(wholeLower)) {
      return _parseGroceryItems(trimmed, startIndex: 0);
    }

    final rawClauses = trimmed
        .split(_clauseSplitter)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final results = <OmniActionDraft>[];
    var seq = 0;

    for (final clause in rawClauses) {
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

    return results;
  }

  static List<OmniActionDraft> _parseSingleClause(
    String clause, {
    required DateTime refNow,
    required int index,
  }) {
    final lower = clause.toLowerCase();

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

    // 1. Group Bill Split ("Ăn lẩu 600k chia 4 người")
    final splitMatch = _splitCountRegex.firstMatch(lower);
    if (splitMatch != null) {
      final count = (int.tryParse(splitMatch.group(1) ?? '2') ?? 2).clamp(
        2,
        30,
      );
      final cleanedForMoney = clause
          .replaceFirst(splitMatch.group(0) ?? '', '')
          .trim();
      final tx = SmartQuickEntryParser.tryParse(cleanedForMoney);
      if (tx != null && tx.amountMinor > 0) {
        return <OmniActionDraft>[
          OmniActionDraft(
            id: 'omni_split_$index',
            kind: OmniActionKind.groupSplit,
            title: tx.merchant,
            amountMinor: tx.amountMinor,
            categoryId: tx.categoryId,
            categoryName: tx.categoryName,
            participantCount: count,
          ),
        ];
      }
    }

    // 2. Grocery Basket ("Đi chợ mua sữa tươi, trứng gà" when no completed spend amount)
    final moneyCandidate = SmartQuickEntryParser.tryParse(clause);
    if (_looksLikeGroceryCommand(lower) && moneyCandidate == null) {
      return _parseGroceryItems(clause, startIndex: index);
    }

    // 3. Financial Transaction ("Ăn phở 55k", "Nhận lương 18tr5")
    // Guard: ensure "9h" or "15h" in a schedule isn't misread as money (SmartQuickEntryParser requires k/tr/đ or >=4 digits).
    if (moneyCandidate != null && !_isPureTimeNumberFalsePositive(lower)) {
      return <OmniActionDraft>[
        OmniActionDraft(
          id: 'omni_tx_$index',
          kind: OmniActionKind.transaction,
          title: moneyCandidate.merchant,
          amountMinor: moneyCandidate.amountMinor,
          transactionKind: moneyCandidate.kind,
          categoryId: moneyCandidate.categoryId,
          categoryName: moneyCandidate.categoryName,
        ),
      ];
    }

    // 4. Calendar Event ("Họp dự án 9h sáng mai", "Lịch khám răng 14:30 thứ 7")
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
          title: strippedTitle,
          scheduledAt: scheduledTime,
          durationMinutes: 60,
        ),
      ];
    }

    // 5. Task / Reminder ("Nhắc đóng tiền điện tối nay !gấp", "Việc: gửi báo cáo ngày mai")
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
      return <OmniActionDraft>[
        OmniActionDraft(
          id: 'omni_task_$index',
          kind: OmniActionKind.task,
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

  static bool _isPureTimeNumberFalsePositive(String lower) {
    return (lower.startsWith('lịch ') ||
            lower.startsWith('họp ') ||
            lower.startsWith('hẹn ')) &&
        !RegExp(
          r'\b\d+(?:[.,]\d+)?\s*(?:k|tr|triệu|trieu|nghìn|nghin|ngàn|ngan|đ|vnd|vnđ)\b',
          caseSensitive: false,
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
    final folded = VietnameseSearchMatcher.fold(lower);
    if (folded.startsWith('lich ') ||
        folded.startsWith('lich:') ||
        folded.startsWith('hop ') ||
        folded.startsWith('hen ') ||
        folded.startsWith('kham ')) {
      return true;
    }
    if (_explicitHourRegex.hasMatch(folded) &&
        (folded.contains('hop') ||
            folded.contains('hen') ||
            folded.contains('lich') ||
            folded.contains('gap') ||
            folded.contains('kham') ||
            folded.contains('sang mai') ||
            folded.contains('chieu mai') ||
            folded.contains('toi mai'))) {
      return true;
    }
    return false;
  }

  static bool _containsTaskCue(String lower) {
    final folded = VietnameseSearchMatcher.fold(lower);
    return folded.startsWith('nhac ') ||
        folded.startsWith('nho ') ||
        folded.startsWith('viec:') ||
        folded.startsWith('viec ') ||
        folded.startsWith('can lam') ||
        folded.startsWith('hoan thanh ') ||
        folded.startsWith('gui bao cao') ||
        folded.startsWith('dong tien ');
  }

  static (DateTime, String) _extractDateTimeAndTitle(
    String rawClause, {
    required DateTime refNow,
    required int defaultHour,
  }) {
    final lower = rawClause.toLowerCase();
    final folded = VietnameseSearchMatcher.fold(lower);
    var dayOffset = 0;
    if (folded.contains('ngay kia') || folded.contains('ngay mot')) {
      dayOffset = 2;
    } else if (folded.contains('ngay mai') ||
        folded.contains('sang mai') ||
        folded.contains('trua mai') ||
        folded.contains('chieu mai') ||
        folded.contains('toi mai') ||
        RegExp(r'\bmai\b').hasMatch(folded)) {
      dayOffset = 1;
    } else if (folded.contains('cuoi tuan')) {
      final daysUntilSat = (DateTime.saturday - refNow.weekday) % 7;
      dayOffset = daysUntilSat == 0 ? 1 : daysUntilSat;
    } else {
      final weekdayMap = <String, int>{
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
      };
      for (final entry in weekdayMap.entries) {
        if (folded.contains(entry.key)) {
          var diff = entry.value - refNow.weekday;
          if (diff <= 0) diff += 7;
          dayOffset = diff;
          break;
        }
      }
    }

    var hour = defaultHour;
    var minute = 0;

    if (folded.contains('sang')) {
      hour = 8;
    } else if (folded.contains('trua')) {
      hour = 12;
    } else if (folded.contains('chieu')) {
      hour = 15;
    } else if (folded.contains('toi')) {
      hour = 20;
    }

    final hm = _explicitHourRegex.firstMatch(lower);
    if (hm != null) {
      final parsedH = int.tryParse(hm.group(1) ?? '');
      final parsedM = int.tryParse(hm.group(2) ?? '');
      final period = VietnameseSearchMatcher.fold(hm.group(3) ?? '');
      if (parsedH != null && parsedH >= 0 && parsedH <= 23) {
        hour = parsedH;
        if ((period.contains('chieu') || period.contains('toi')) && hour < 12) {
          hour += 12;
        }
      }
      if (parsedM != null && parsedM >= 0 && parsedM <= 59) {
        minute = parsedM;
      }
    }

    var cleanTitle = rawClause
        .replaceFirst(
          RegExp(
            r'^(?:nhắc nhở:?|nhac nho:?|nhắc:?|nhac:?|nhớ:?|nho:?|việc cần làm:?|viec can lam:?|việc:?|viec:?|cần làm:?|can lam:?|lịch:?|lich:?)\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(_explicitHourRegex, '')
        .replaceAll(
          RegExp(
            r'\b(?:lúc|luc|vào|vao|sáng mai|sang mai|chiều mai|chieu mai|tối mai|toi mai|trưa mai|trua mai|ngày mai|ngay mai|ngày kia|ngay kia|hôm nay|hom nay|tối nay|toi nay|chiều nay|chieu nay|sáng nay|sang nay|cuối tuần|cuoi tuan)\b',
            caseSensitive: false,
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

    final targetDate = DateTime(
      refNow.year,
      refNow.month,
      refNow.day + dayOffset,
      hour,
      minute,
    );
    return (targetDate, cleanTitle);
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
            r'\b(?:lúc|vào|buổi sáng|buổi trưa|buổi tối|sau ăn sáng|sau ăn trưa|sau ăn tối|sau ăn|trước ăn|sáng nay|sáng mai|tối nay|mỗi ngày)\b',
            caseSensitive: false,
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
