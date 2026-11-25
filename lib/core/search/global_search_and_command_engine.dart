import 'dart:math' as math;

import 'package:equatable/equatable.dart';

enum SearchDomainKind {
  quickCommand('Lệnh nhanh'),
  appFeature('Tính năng'),
  transaction('Giao dịch'),
  wallet('Ví & Tài khoản'),
  category('Danh mục'),
  budget('Ngân sách'),
  familyMember('Thành viên'),
  task('Nhiệm vụ'),
  calendarEvent('Lịch trình'),
  vehicle('Phương tiện'),
  document('Giấy tờ'),
  note('Ghi chú'),
  bill('Hóa đơn');

  final String labelVi;
  const SearchDomainKind(this.labelVi);
}

class SearchableEntityRecord extends Equatable {
  final String id;
  final SearchDomainKind domain;
  final String title;
  final String subtitle;
  final String? trailingBadge;
  final String targetRoute;
  final String ownerUserId;
  final String? familyId;
  final bool isPrivateToOwner;
  final List<String> keywords;

  const SearchableEntityRecord({
    required this.id,
    required this.domain,
    required this.title,
    required this.subtitle,
    this.trailingBadge,
    required this.targetRoute,
    required this.ownerUserId,
    this.familyId,
    this.isPrivateToOwner = true,
    this.keywords = const <String>[],
  });

  @override
  List<Object?> get props => [
    id,
    domain,
    title,
    subtitle,
    trailingBadge,
    targetRoute,
    ownerUserId,
    familyId,
    isPrivateToOwner,
    keywords,
  ];
}

class SearchScoredHit extends Equatable {
  final SearchableEntityRecord record;
  final double score;

  const SearchScoredHit({required this.record, required this.score});

  @override
  List<Object?> get props => [record, score];
}

/// Accent-Insensitive, Abbreviation-Aware, RBAC-Safe Global Search & Command Palette Engine (Section 18).
///
/// Guarantees:
/// - **Strict RBAC privacy**: Records marked `isPrivateToOwner` belonging to another `ownerUserId`
///   are NEVER returned even if two users share a Family Space! Shared family records require
///   `record.familyId` to be in `allowedFamilyIds`.
/// - Supports Vietnamese accents, unaccented queries, common abbreviations (`cf` -> `ca phe`,
///   `ck` -> `chuyen khoan`, `bhyt` -> `bao hiem y te`, `cccd` -> `can cuoc`), fuzzy typo tolerance,
///   and instant Quick Commands (`Thêm giao dịch`, `Tạo lịch`, `Chia tiền`, `Mở quỹ gia đình`, `Tìm giao dịch tháng trước`).
abstract final class GlobalSearchAndCommandEngine {
  static const Map<String, String> _abbreviations = <String, String>{
    'cf': 'ca phe',
    'cafe': 'ca phe',
    'ts': 'tra sua',
    'ck': 'chuyen khoan',
    'gd': 'giao dich',
    'ns': 'ngan sach',
    'bhyt': 'bao hiem y te',
    'bhxh': 'bao hiem xa hoi',
    'cccd': 'can cuoc cong dan',
    'evn': 'tien dien',
  };

  static List<SearchableEntityRecord> builtInQuickCommands(String activeUserId) {
    return <SearchableEntityRecord>[
      SearchableEntityRecord(
        id: 'cmd_add_tx',
        domain: SearchDomainKind.quickCommand,
        title: 'Thêm giao dịch',
        subtitle: 'Ghi nhanh khoản thu nhập, chi tiêu hoặc chuyển ví',
        targetRoute: '/finance',
        ownerUserId: activeUserId,
        keywords: const ['ghi thu chi', 'them khoan chi', 'nhap giao dich'],
      ),
      SearchableEntityRecord(
        id: 'cmd_create_event',
        domain: SearchDomainKind.quickCommand,
        title: 'Tạo lịch',
        subtitle: 'Đặt lịch hẹn, khung giờ làm việc hoặc lời nhắc mới',
        targetRoute: '/planning',
        ownerUserId: activeUserId,
        keywords: const ['tao su kien', 'lich hop', 'hen gio'],
      ),
      SearchableEntityRecord(
        id: 'cmd_split_bill',
        domain: SearchDomainKind.quickCommand,
        title: 'Chia tiền',
        subtitle: 'Chia đều, chia theo phần trăm hoặc suất cho nhóm',
        targetRoute: '/family',
        ownerUserId: activeUserId,
        keywords: const ['chia hoa don', 'campuchia', 'cua doi'],
      ),
      SearchableEntityRecord(
        id: 'cmd_open_family_fund',
        domain: SearchDomainKind.quickCommand,
        title: 'Mở quỹ gia đình',
        subtitle: 'Xem số dư quỹ chung, góp quỹ và duyệt đề xuất chi',
        targetRoute: '/family-funds',
        ownerUserId: activeUserId,
        keywords: const ['quy chung', 'so quy to am'],
      ),
      SearchableEntityRecord(
        id: 'cmd_search_last_month_tx',
        domain: SearchDomainKind.quickCommand,
        title: 'Tìm giao dịch tháng trước',
        subtitle: 'Mở báo cáo và lịch sử sổ thu chi kỳ tháng trước',
        targetRoute: '/finance-report',
        ownerUserId: activeUserId,
        keywords: const ['sao ke thang truoc', 'bao cao thang truoc'],
      ),
      SearchableEntityRecord(
        id: 'cmd_automation_studio',
        domain: SearchDomainKind.quickCommand,
        title: 'Quản lý Tự động hóa',
        subtitle: 'Bật/tắt quy tắc liên kết lương, xăng xe, hóa đơn & bảo hành',
        targetRoute: '/automation-studio',
        ownerUserId: activeUserId,
        keywords: const ['automation', 'quy tac tu dong'],
      ),
    ];
  }

  static List<SearchScoredHit> search({
    required String rawQuery,
    required String activeUserId,
    required List<SearchableEntityRecord> corpus,
    Set<String> allowedFamilyIds = const <String>{},
    int limit = 30,
  }) {
    final fullCorpus = <SearchableEntityRecord>[
      ...builtInQuickCommands(activeUserId),
      ...corpus,
    ];

    final accessible = fullCorpus.where((rec) {
      if (rec.ownerUserId == activeUserId) return true;
      if (rec.isPrivateToOwner) return false;
      return rec.familyId != null && allowedFamilyIds.contains(rec.familyId);
    }).toList();

    final cleanQuery = rawQuery.trim();
    if (cleanQuery.isEmpty) {
      return accessible
          .where((r) => r.domain == SearchDomainKind.quickCommand)
          .take(limit)
          .map((r) => SearchScoredHit(record: r, score: 100.0))
          .toList();
    }

    final foldedQuery = _expandAndFold(cleanQuery);
    final queryTokens = foldedQuery
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (queryTokens.isEmpty) return const <SearchScoredHit>[];

    final hits = <SearchScoredHit>[];

    for (final rec in accessible) {
      final foldedTitle = _expandAndFold(rec.title);
      final foldedSub = _expandAndFold(rec.subtitle);
      final foldedKw = rec.keywords.map(_expandAndFold).join(' ');
      final combined = '$foldedTitle $foldedSub $foldedKw';

      var score = 0.0;
      if (foldedTitle == foldedQuery) {
        score += 120.0;
      } else if (foldedTitle.startsWith(foldedQuery)) {
        score += 95.0;
      } else if (foldedTitle.contains(foldedQuery)) {
        score += 75.0;
      } else if (combined.contains(foldedQuery)) {
        score += 55.0;
      }

      var matchedTokens = 0;
      for (final qt in queryTokens) {
        if (foldedTitle.contains(qt)) {
          matchedTokens++;
          score += 22.0;
        } else if (combined.contains(qt)) {
          matchedTokens++;
          score += 12.0;
        } else if (qt.length >= 4 && _hasFuzzyWordMatch(foldedTitle, qt)) {
          matchedTokens++;
          score += 9.0;
        }
      }

      if (matchedTokens == queryTokens.length) {
        score += 20.0;
      } else if (score < 40.0) {
        continue;
      }

      if (rec.domain == SearchDomainKind.quickCommand) {
        score += 5.0;
      }

      if (score > 0) {
        hits.add(SearchScoredHit(record: rec, score: score));
      }
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  static String stripVnAccents(String input) {
    const map = <String, String>{
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
    final lower = input.toLowerCase();
    final sb = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  static String _expandAndFold(String raw) {
    final folded = stripVnAccents(raw)
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (folded.isEmpty) return '';
    return folded
        .split(' ')
        .map((tok) => _abbreviations[tok] ?? tok)
        .join(' ');
  }

  static bool _hasFuzzyWordMatch(String targetSentence, String token) {
    for (final w in targetSentence.split(' ')) {
      if (w.length < 3) continue;
      if ((w.length - token.length).abs() > 1) continue;
      if (_editDistanceAtMostOne(w, token)) return true;
    }
    return false;
  }

  static bool _editDistanceAtMostOne(String a, String b) {
    if (a == b) return true;
    final la = a.length;
    final lb = b.length;
    if ((la - lb).abs() > 1) return false;
    var i = 0;
    var j = 0;
    var edits = 0;
    while (i < la && j < lb) {
      if (a.codeUnitAt(i) == b.codeUnitAt(j)) {
        i++;
        j++;
      } else {
        edits++;
        if (edits > 1) return false;
        if (la > lb) {
          i++;
        } else if (lb > la) {
          j++;
        } else {
          i++;
          j++;
        }
      }
    }
    if (i < la || j < lb) edits++;
    return edits <= 1;
  }

  /// Maintains bounded, deduplicated recent search history (max [maxItems]).
  static List<String> recordRecentQuery(
    List<String> currentHistory,
    String query, {
    int maxItems = 8,
  }) {
    final clean = query.trim();
    if (clean.length < 2) return currentHistory;
    final filtered = currentHistory
        .where((q) => q.toLowerCase() != clean.toLowerCase())
        .toList();
    return <String>[clean, ...filtered].take(math.max(1, maxItems)).toList();
  }
}
