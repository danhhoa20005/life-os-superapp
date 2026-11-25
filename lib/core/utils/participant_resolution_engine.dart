import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../features/family/domain/entities/family_entities.dart';
import '../../features/financial_ai/data/normalization/financial_text_normalizer.dart';

enum ParticipantResolutionStatus {
  resolved,
  ambiguous,
  unresolvedGuest,
}

class ParticipantCandidateMatch extends Equatable {
  final String participantId;
  final String displayName;
  final double score;
  final String matchReason;

  const ParticipantCandidateMatch({
    required this.participantId,
    required this.displayName,
    required this.score,
    required this.matchReason,
  });

  @override
  List<Object?> get props => [participantId, displayName, score, matchReason];
}

class ParticipantResolutionOutcome extends Equatable {
  final String spokenName;
  final ParticipantResolutionStatus status;
  final String participantId;
  final String displayName;
  final double confidence;
  final List<ParticipantCandidateMatch> ambiguousCandidates;

  const ParticipantResolutionOutcome({
    required this.spokenName,
    required this.status,
    required this.participantId,
    required this.displayName,
    required this.confidence,
    this.ambiguousCandidates = const <ParticipantCandidateMatch>[],
  });

  bool get isAmbiguous => status == ParticipantResolutionStatus.ambiguous;

  @override
  List<Object?> get props => [
    spokenName,
    status,
    participantId,
    displayName,
    confidence,
    ambiguousCandidates,
  ];
}

/// 4-Tier Vietnamese Participant Resolution Engine (FIX-005):
/// Tier 1: Exact userId / 1st-person self-pronoun (`tôi`, `mình`, `tớ`, `tui`) / exact full name.
/// Tier 2: Personalized learned nicknames (`nicknamesByUserId`).
/// Tier 3: Compound & primary Vietnamese given name (last token of full name scores higher than middle/surname) + initials.
/// Tier 4: Accent-folded ASR & Jaro-Winkler / Levenshtein similarity, plus ambiguity detection for homonyms (`Lê Hà` vs `Phạm Hà`).
abstract final class ParticipantResolutionEngine {
  static const double defaultConfidenceThreshold = 0.70;
  static const double _tieMargin = 0.05;

  static const Set<String> _selfPronounsAccentedOrSafe = <String>{
    'tôi',
    'toi',
    'mình',
    'tớ',
    'tui',
  };

  static final RegExp _honorificPrefixRegex = RegExp(
    r'^(?:anh|chị|chi|em|bạn|ban|chú|chu|cô|co|bác|bac|ông|ong|bà|ba|nhà|nha|gia\s+đình|gia\s+dinh|phòng|phong|team|nhóm|nhom)\s+(.+)$',
    caseSensitive: false,
    unicode: true,
  );

  static ParticipantResolutionOutcome resolve({
    required String spokenName,
    required int index,
    required String currentUserId,
    required String currentUserName,
    List<FamilyMemberInfo> knownMembers = const <FamilyMemberInfo>[],
    Map<String, List<String>> nicknamesByUserId = const <String, List<String>>{},
    Map<String, String> explicitOverridesBySpoken = const <String, String>{},
    double minConfidence = defaultConfidenceThreshold,
  }) {
    final trimmedSpoken = spokenName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final lowerSpoken = trimmedSpoken.toLowerCase();
    final foldedSpoken = FinancialTextNormalizer.stripVnAccents(trimmedSpoken)
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final slug = foldedSpoken.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(
      RegExp(r'^_|_$'),
      '',
    );
    final guestId = 'voice_member_${index}_${slug.isEmpty ? 'guest' : slug}';

    if (trimmedSpoken.isEmpty) {
      return ParticipantResolutionOutcome(
        spokenName: spokenName,
        status: ParticipantResolutionStatus.unresolvedGuest,
        participantId: guestId,
        displayName: 'Thành viên ${index + 1}',
        confidence: 0.0,
      );
    }

    // Build deduplicated candidate pool including current user
    final pool = <FamilyMemberInfo>[];
    final seenIds = <String>{};
    for (final m in knownMembers) {
      if (m.userId.isNotEmpty && seenIds.add(m.userId)) {
        pool.add(m);
      }
    }
    if (currentUserId.isNotEmpty &&
        seenIds.add(currentUserId) &&
        currentUserName.trim().isNotEmpty) {
      pool.add(
        FamilyMemberInfo(
          userId: currentUserId,
          fullName: currentUserName.trim(),
          role: HouseholdRole.owner,
        ),
      );
    }

    // Explicit UI disambiguation override selected by user (case- & accent-tolerant key lookup)
    var overrideId =
        explicitOverridesBySpoken[trimmedSpoken] ??
        explicitOverridesBySpoken[lowerSpoken] ??
        explicitOverridesBySpoken[foldedSpoken];
    if (overrideId == null && explicitOverridesBySpoken.isNotEmpty) {
      for (final entry in explicitOverridesBySpoken.entries) {
        final kLower = entry.key.trim().toLowerCase();
        final kFolded = FinancialTextNormalizer.stripVnAccents(entry.key)
            .trim();
        if (kLower == lowerSpoken || kFolded == foldedSpoken) {
          overrideId = entry.value;
          break;
        }
      }
    }
    if (overrideId != null && overrideId.isNotEmpty) {
      final matchedMember = pool
          .where((m) => m.userId == overrideId)
          .firstOrNull;
      if (matchedMember != null) {
        return ParticipantResolutionOutcome(
          spokenName: trimmedSpoken,
          status: ParticipantResolutionStatus.resolved,
          participantId: matchedMember.userId,
          displayName: matchedMember.fullName,
          confidence: 1.0,
        );
      }
    }

    // Tier 1a: Explicit 1st-person pronoun (`tôi`, `mình`, `tớ`, `tui` — NEVER `anh`, `em`, `minh`, `a`, `b`)
    if (_selfPronounsAccentedOrSafe.contains(lowerSpoken)) {
      return ParticipantResolutionOutcome(
        spokenName: trimmedSpoken,
        status: ParticipantResolutionStatus.resolved,
        participantId: currentUserId,
        displayName: currentUserName.trim().isNotEmpty
            ? currentUserName.trim()
            : 'Tôi',
        confidence: 0.99,
      );
    }

    // Prepare stripped honorific variant ONLY if stripping leaves >= 1 meaningful token
    final honorificMatch = _honorificPrefixRegex.firstMatch(trimmedSpoken);
    final strippedName = honorificMatch?.group(1)?.trim();
    final hasRoomOrGroupPrefix = RegExp(
      r'^(?:phòng|phong|team|nhóm|nhom)\s+',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(trimmedSpoken);

    final scored = <ParticipantCandidateMatch>[];
    // Bare honorific pronouns (`anh`, `em`) must NEVER auto-map to currentUserId.
    const blockedSelfPronouns = <String>{'anh', 'em'};
    for (final member in pool) {
      if (member.userId == currentUserId &&
          blockedSelfPronouns.contains(foldedSpoken)) {
        continue;
      }
      final candidate = _scoreMember(
        member: member,
        spokenRaw: trimmedSpoken,
        spokenLower: lowerSpoken,
        spokenFolded: foldedSpoken,
        strippedRaw: hasRoomOrGroupPrefix ? null : strippedName,
        nicknames: nicknamesByUserId[member.userId] ?? const <String>[],
      );
      if (candidate != null) {
        scored.add(candidate);
      }
    }

    if (scored.isEmpty) {
      return ParticipantResolutionOutcome(
        spokenName: trimmedSpoken,
        status: ParticipantResolutionStatus.unresolvedGuest,
        participantId: guestId,
        displayName: _capitalize(trimmedSpoken),
        confidence: 0.0,
      );
    }

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.participantId.compareTo(b.participantId);
    });

    final top = scored.first;

    // Check close ties / homonym ambiguity (`Lê Hà` vs `Phạm Hà`)
    final closeMatches = scored
        .where(
          (c) =>
              c.score >= 0.55 &&
              (top.score - c.score) <= _tieMargin,
        )
        .take(5)
        .toList(growable: false);

    if (closeMatches.length >= 2) {
      return ParticipantResolutionOutcome(
        spokenName: trimmedSpoken,
        status: ParticipantResolutionStatus.ambiguous,
        participantId: guestId,
        displayName: _capitalize(trimmedSpoken),
        confidence: top.score,
        ambiguousCandidates: closeMatches,
      );
    }

    // Weak confidence below threshold (e.g., surname/middle-name only or distant fuzzy)
    if (top.score < minConfidence) {
      final plausible = scored
          .where((c) => c.score >= 0.55)
          .take(4)
          .toList(growable: false);
      if (plausible.isNotEmpty) {
        return ParticipantResolutionOutcome(
          spokenName: trimmedSpoken,
          status: ParticipantResolutionStatus.ambiguous,
          participantId: guestId,
          displayName: _capitalize(trimmedSpoken),
          confidence: top.score,
          ambiguousCandidates: plausible,
        );
      }
      return ParticipantResolutionOutcome(
        spokenName: trimmedSpoken,
        status: ParticipantResolutionStatus.unresolvedGuest,
        participantId: guestId,
        displayName: _capitalize(trimmedSpoken),
        confidence: top.score,
      );
    }

    return ParticipantResolutionOutcome(
      spokenName: trimmedSpoken,
      status: ParticipantResolutionStatus.resolved,
      participantId: top.participantId,
      displayName: top.displayName,
      confidence: top.score,
    );
  }

  static ParticipantCandidateMatch? _scoreMember({
    required FamilyMemberInfo member,
    required String spokenRaw,
    required String spokenLower,
    required String spokenFolded,
    required String? strippedRaw,
    required List<String> nicknames,
  }) {
    final mName = member.fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (mName.isEmpty) return null;

    var bestScore = 0.0;
    var bestReason = '';

    void consider(double score, String reason) {
      if (score > bestScore) {
        bestScore = score;
        bestReason = reason;
      }
    }

    // Exact userId match
    if (member.userId == spokenRaw) {
      consider(1.0, 'exact_id');
    }

    final queries = <({String lower, String folded, double penalty})>[
      (lower: spokenLower, folded: spokenFolded, penalty: 0.0),
      if (strippedRaw != null && strippedRaw.isNotEmpty)
        (
          lower: strippedRaw.toLowerCase(),
          folded: FinancialTextNormalizer.stripVnAccents(strippedRaw).trim(),
          penalty: 0.01,
        ),
    ];

    final mLower = mName.toLowerCase();
    final mFolded = FinancialTextNormalizer.stripVnAccents(mName).trim();
    final mLowerTokens = mLower.split(' ').where((t) => t.isNotEmpty).toList();
    final mFoldedTokens = mFolded
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();

    for (final q in queries) {
      if (q.lower.isEmpty || q.folded.isEmpty) continue;

      // Tier 1b: Full name match
      if (mLower == q.lower) {
        consider(0.99 - q.penalty, 'full_name');
      } else if (mFolded == q.folded) {
        consider(0.96 - q.penalty, 'full_name_folded');
      }

      // Tier 2: Personalized nickname match (exact token/phrase)
      for (final nick in nicknames) {
        final nLower = nick.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final nFolded = FinancialTextNormalizer.stripVnAccents(nLower).trim();
        if (nLower.isEmpty) continue;
        if (nLower == q.lower) {
          consider(0.95 - q.penalty, 'nickname');
        } else if (nFolded == q.folded) {
          consider(0.93 - q.penalty, 'nickname_folded');
        }
      }

      // Tier 3a: Compound 2-syllable given name (e.g., "Minh Anh" in "Nguyễn Minh Anh")
      if (mLowerTokens.length >= 2) {
        final compLower =
            '${mLowerTokens[mLowerTokens.length - 2]} ${mLowerTokens.last}';
        final compFolded =
            '${mFoldedTokens[mFoldedTokens.length - 2]} ${mFoldedTokens.last}';
        if (compLower == q.lower) {
          consider(0.94 - q.penalty, 'compound_given_name');
        } else if (compFolded == q.folded) {
          consider(0.90 - q.penalty, 'compound_given_name_folded');
        }
      }

      // Tier 3b: Primary Vietnamese given name (LAST token of full name!)
      if (mLowerTokens.isNotEmpty) {
        final givenLower = mLowerTokens.last;
        final givenFolded = mFoldedTokens.last;
        if (givenLower == q.lower) {
          consider(0.90 - q.penalty, 'given_name');
        } else if (givenFolded == q.folded) {
          consider(0.86 - q.penalty, 'given_name_folded');
        }
      }

      // Tier 3c: Initials ("LVM" -> "Lê Văn Minh", "MA" -> "Minh Anh")
      final compactQuery = q.folded.replaceAll(RegExp(r'[.\s]+'), '');
      if (compactQuery.length >= 2 &&
          RegExp(r'^[a-z0-9]+$').hasMatch(compactQuery) &&
          mFoldedTokens.length >= 2) {
        final fullInitials = mFoldedTokens.map((t) => t[0]).join();
        final lastTwoInitials = mFoldedTokens
            .sublist(mFoldedTokens.length - 2)
            .map((t) => t[0])
            .join();
        if (compactQuery == fullInitials ||
            (mFoldedTokens.length >= 2 && compactQuery == lastTwoInitials)) {
          consider(0.80 - q.penalty, 'initials');
        }
      }

      // Tier 3d: Middle name token (strictly lower than given name so "Minh" picks "Lê Văn Minh" over "Nguyễn Minh Hoàng")
      if (mLowerTokens.length >= 3) {
        for (var i = 1; i < mLowerTokens.length - 1; i++) {
          if (mLowerTokens[i] == q.lower) {
            consider(0.64 - q.penalty, 'middle_name');
          } else if (mFoldedTokens[i] == q.folded) {
            consider(0.60 - q.penalty, 'middle_name_folded');
          }
        }
      }

      // Tier 3e: Family surname token (token 0 when multi-token name)
      if (mLowerTokens.length >= 2) {
        if (mLowerTokens.first == q.lower) {
          consider(0.56 - q.penalty, 'surname');
        } else if (mFoldedTokens.first == q.folded) {
          consider(0.52 - q.penalty, 'surname_folded');
        }
      }

      // Tier 4: Fuzzy ASR similarity on given name or full name (only length >= 2, never single char!)
      if (q.folded.length >= 2 && mFoldedTokens.isNotEmpty) {
        final givenFolded = mFoldedTokens.last;
        if (givenFolded.length >= 2 &&
            (q.folded.length - givenFolded.length).abs() <= 2 &&
            !q.folded.contains(' ')) {
          final sim = _combinedSimilarity(q.folded, givenFolded);
          if (sim >= 0.80) {
            consider(
              (0.72 + (sim - 0.80) * 0.65).clamp(0.70, 0.85) - q.penalty,
              'fuzzy_given_name',
            );
          }
        }
        if (q.folded.contains(' ') && mFolded.contains(' ')) {
          final simFull = _combinedSimilarity(q.folded, mFolded);
          if (simFull >= 0.84) {
            consider(
              (0.72 + (simFull - 0.84) * 0.75).clamp(0.70, 0.85) - q.penalty,
              'fuzzy_full_name',
            );
          }
        }
      }
    }

    if (bestScore < 0.50) return null;
    return ParticipantCandidateMatch(
      participantId: member.userId,
      displayName: mName,
      score: double.parse(bestScore.toStringAsFixed(4)),
      matchReason: bestReason,
    );
  }

  static double _combinedSimilarity(String a, String b) {
    final jw = jaroWinkler(a, b);
    final dist = levenshtein(a, b);
    final maxLen = math.max(a.length, b.length);
    final levSim = maxLen == 0 ? 1.0 : 1.0 - (dist / maxLen);
    return 0.60 * jw + 0.40 * levSim;
  }

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var prev = List<int>.generate(b.length + 1, (j) => j);
    var curr = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = math.min(
          math.min(curr[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[b.length];
  }

  static double jaroWinkler(String s1, String s2) {
    if (s1 == s2) return 1.0;
    final len1 = s1.length;
    final len2 = s2.length;
    if (len1 == 0 || len2 == 0) return 0.0;

    final matchDistance = math.max(0, (math.max(len1, len2) ~/ 2) - 1);
    final s1Matches = List<bool>.filled(len1, false);
    final s2Matches = List<bool>.filled(len2, false);

    var matches = 0;
    for (var i = 0; i < len1; i++) {
      final start = math.max(0, i - matchDistance);
      final end = math.min(i + matchDistance + 1, len2);
      for (var j = start; j < end; j++) {
        if (s2Matches[j] || s1[i] != s2[j]) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0.0;

    var t = 0;
    var k = 0;
    for (var i = 0; i < len1; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) {
        k++;
      }
      if (s1[i] != s2[k]) t++;
      k++;
    }

    final m = matches.toDouble();
    final jaro = (m / len1 + m / len2 + (m - t / 2.0) / m) / 3.0;

    var prefix = 0;
    final maxPrefix = math.min(4, math.min(len1, len2));
    for (var i = 0; i < maxPrefix; i++) {
      if (s1[i] == s2[i]) {
        prefix++;
      } else {
        break;
      }
    }
    return jaro + prefix * 0.1 * (1.0 - jaro);
  }

  static String _capitalize(String raw) {
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}
