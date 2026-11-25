import 'package:equatable/equatable.dart';

/// Supported domains aggregated into the unified read-only Life Timeline
/// without duplicating business records across modules.
enum LifeTimelineDomain {
  finance('finance', 'Tài chính'),
  calendar('calendar', 'Lịch trình'),
  tasks('tasks', 'Việc làm'),
  vehiclesAndBills('vehicles_bills', 'Xe & Hóa đơn'),
  family('family', 'Gia đình'),
  goals('goals', 'Mục tiêu & Quỹ');

  final String code;
  final String labelVi;
  const LifeTimelineDomain(this.code, this.labelVi);
}

class LifeTimelineEntry extends Equatable {
  final String dedupKey;
  final String sourceId;
  final LifeTimelineDomain domain;
  final DateTime timestamp;
  final String title;
  final String subtitle;
  final int? amountMinor;
  final bool? isCredit;
  final String badgeLabel;
  final String targetRoute;
  final bool isUpcoming;

  const LifeTimelineEntry({
    required this.dedupKey,
    required this.sourceId,
    required this.domain,
    required this.timestamp,
    required this.title,
    required this.subtitle,
    this.amountMinor,
    this.isCredit,
    required this.badgeLabel,
    required this.targetRoute,
    this.isUpcoming = false,
  });

  @override
  List<Object?> get props => [
    dedupKey,
    sourceId,
    domain,
    timestamp,
    title,
    subtitle,
    amountMinor,
    isCredit,
    badgeLabel,
    targetRoute,
    isUpcoming,
  ];
}

class LifeTimelineDayGroup extends Equatable {
  final String dayKey;
  final String labelVi;
  final DateTime date;
  final List<LifeTimelineEntry> entries;

  const LifeTimelineDayGroup({
    required this.dayKey,
    required this.labelVi,
    required this.date,
    required this.entries,
  });

  @override
  List<Object?> get props => [dayKey, labelVi, date, entries];
}

/// Pure-Dart read-only cross-domain Life Timeline projection engine (Section 20).
///
/// Guarantees:
/// - **Zero data duplication**: projects live domain snapshots into chronological
///   views in memory and deduplicates by `(domain, sourceId)`.
/// - **Deterministic ordering**: sorts descending by timestamp with stable tie-breaking.
abstract final class LifeTimelineEngine {
  static List<LifeTimelineEntry> mergeAndFilter({
    required List<LifeTimelineEntry> rawEntries,
    LifeTimelineDomain? domainFilter,
    String query = '',
    int maxEntries = 200,
  }) {
    final seen = <String>{};
    final deduped = <LifeTimelineEntry>[];
    final queryTokens = _foldVi(
      query.trim(),
    ).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    for (final entry in rawEntries) {
      if (!seen.add(entry.dedupKey)) continue;
      if (domainFilter != null && entry.domain != domainFilter) continue;
      if (queryTokens.isNotEmpty) {
        final haystack = _foldVi(
          '${entry.title} ${entry.subtitle} ${entry.badgeLabel} ${entry.domain.labelVi}',
        );
        if (!queryTokens.every(haystack.contains)) continue;
      }
      deduped.add(entry);
    }

    deduped.sort((a, b) {
      final tsCmp = b.timestamp.compareTo(a.timestamp);
      if (tsCmp != 0) return tsCmp;
      return a.dedupKey.compareTo(b.dedupKey);
    });

    if (deduped.length > maxEntries) {
      return deduped.sublist(0, maxEntries);
    }
    return deduped;
  }

  static List<LifeTimelineDayGroup> groupByDay(
    List<LifeTimelineEntry> entries, {
    DateTime? referenceNow,
  }) {
    final now = referenceNow ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    final map = <String, List<LifeTimelineEntry>>{};
    final dates = <String, DateTime>{};

    for (final entry in entries) {
      final d = DateTime(
        entry.timestamp.year,
        entry.timestamp.month,
        entry.timestamp.day,
      );
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => <LifeTimelineEntry>[]).add(entry);
      dates[key] = d;
    }

    final sortedKeys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return sortedKeys.map((key) {
      final d = dates[key]!;
      final String label;
      if (d == today) {
        label = 'Hôm nay';
      } else if (d == yesterday) {
        label = 'Hôm qua';
      } else if (d == tomorrow) {
        label = 'Ngày mai';
      } else {
        label =
            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      }
      return LifeTimelineDayGroup(
        dayKey: key,
        labelVi: label,
        date: d,
        entries: map[key]!,
      );
    }).toList();
  }

  static String _foldVi(String input) {
    var s = input.toLowerCase();
    const pairs = <List<String>>[
      ['àáạảãâầấậẩẫăằắặẳẵ', 'a'],
      ['èéẹẻẽêềếệểễ', 'e'],
      ['ìíịỉĩ', 'i'],
      ['òóọỏõôồốộổỗơờớợởỡ', 'o'],
      ['ùúụủũưừứựửữ', 'u'],
      ['ỳýỵỷỹ', 'y'],
      ['đ', 'd'],
    ];
    for (final p in pairs) {
      for (var i = 0; i < p[0].length; i++) {
        s = s.replaceAll(p[0][i], p[1]);
      }
    }
    return s;
  }
}
