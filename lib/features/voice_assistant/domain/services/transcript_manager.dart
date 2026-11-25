import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../entities/voice_transcript.dart';

class _TranscriptToken {
  final String normalized;
  final int start;
  final int end;
  final bool hasClausePunctuationAfter;

  const _TranscriptToken({
    required this.normalized,
    required this.start,
    required this.end,
    required this.hasClausePunctuationAfter,
  });
}

/// Pure Dart manager separating committed clauses, live partial, final result,
/// and user-edited text (`VOICE-009`).
class TranscriptManager {
  static final RegExp _danglingConnectorRegex = RegExp(
    r'(?:^|\s)(?:và|với|cùng|rồi|thêm|hoặc|chia|gồm|lúc|vào|hết|mất|giá|'
    r'khoảng|tầm|từ|sang|cho|ở|tại|nhắc|uống|mua|ăn|đổ|chuyển|nhận)$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _bareDigitsRegex = RegExp(r'(?:^|\s)\d+$');
  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _trailingSeparators = RegExp(r'[,;\s]+$');
  static final RegExp _duplicateTrailingPunctuation = RegExp(
    r'(?:[,.]\s*){2,}$',
  );
  static final RegExp _clausePunctuation = RegExp(r'[,.;!?…]');
  static final RegExp _tokenScan = RegExp(r'\S+');
  static final RegExp _trimEdgePunctuation = RegExp(
    r'''^[,.;:!?…"'()\[\]{}]+|[,.;:!?…"'()\[\]{}]+$''',
  );

  VoiceTranscriptState _state;

  TranscriptManager([VoiceTranscriptState initial = VoiceTranscriptState.empty])
    : _state = initial;

  VoiceTranscriptState get state => _state;

  String get currentPartial => _state.currentPartial;

  String get effectiveText => _state.effectiveText;

  /// Begins a new capture turn, binding session/attempt and promoting prior edits cleanly.
  VoiceTranscriptState beginTurn({
    required String sessionId,
    required int attemptId,
    bool clearExisting = false,
  }) {
    if (clearExisting) {
      _state = VoiceTranscriptState(
        committedSegments: const <String>[],
        currentPartial: '',
        finalSegment: null,
        userEditedText: null,
        activeSessionId: sessionId,
        activeAttemptId: attemptId,
        lastSequenceNumber: 0,
        effectiveText: '',
      );
      return _state;
    }

    var nextCommitted = List<String>.from(_state.committedSegments);
    if (_state.userEditedText != null) {
      final cleanedEdited = _cleanClause(_state.userEditedText!);
      nextCommitted = cleanedEdited.isEmpty
          ? <String>[]
          : <String>[cleanedEdited];
    }

    final effective = computeEffectiveText(
      committedSegments: nextCommitted,
      currentPartial: '',
      userEditedText: null,
    );
    _state = VoiceTranscriptState(
      committedSegments: List<String>.unmodifiable(nextCommitted),
      currentPartial: '',
      finalSegment: null,
      userEditedText: null,
      activeSessionId: sessionId,
      activeAttemptId: attemptId,
      lastSequenceNumber: 0,
      effectiveText: effective,
    );
    return _state;
  }

  /// Applies a streaming partial result without touching [VoiceTranscriptState.committedSegments].
  bool onPartial({
    required String sessionId,
    required int attemptId,
    required int sequenceNumber,
    required String text,
  }) {
    if (!_isAcceptableEnvelope(
      sessionId: sessionId,
      attemptId: attemptId,
      sequenceNumber: sequenceNumber,
    )) {
      return false;
    }
    // Preserve manual user edits while in review; never let stale partial overwrite them.
    if (_state.userEditedText != null) {
      return false;
    }

    final cleaned = _normalizeSpaces(text);
    final nextSeq = sequenceNumber > 0
        ? sequenceNumber
        : _state.lastSequenceNumber;
    final effective = computeEffectiveText(
      committedSegments: _state.committedSegments,
      currentPartial: cleaned,
      userEditedText: null,
    );

    _state = _state.copyWith(
      currentPartial: cleaned,
      lastSequenceNumber: nextSeq,
      effectiveText: effective,
    );
    return true;
  }

  /// Replaces [currentPartial] with [text] and commits it ONCE into [committedSegments].
  bool onFinal({
    required String sessionId,
    required int attemptId,
    required int sequenceNumber,
    required String text,
    bool rescuePartialOnEmptyFinal = false,
  }) {
    if (!_isAcceptableEnvelope(
      sessionId: sessionId,
      attemptId: attemptId,
      sequenceNumber: sequenceNumber,
    )) {
      return false;
    }

    final nextSeq = sequenceNumber > 0
        ? sequenceNumber
        : _state.lastSequenceNumber;

    var resolved = _cleanClause(text);
    if (resolved.isEmpty && rescuePartialOnEmptyFinal) {
      resolved = _cleanClause(_state.currentPartial);
    }

    if (resolved.isEmpty) {
      final effective = computeEffectiveText(
        committedSegments: _state.committedSegments,
        currentPartial: '',
        userEditedText: _state.userEditedText,
      );
      _state = _state.copyWith(
        currentPartial: '',
        clearFinalSegment: true,
        lastSequenceNumber: nextSeq,
        effectiveText: effective,
      );
      return true;
    }

    final nextCommitted = _commitSegmentDeduped(
      _state.committedSegments,
      resolved,
    );
    final effective = computeEffectiveText(
      committedSegments: nextCommitted,
      currentPartial: '',
      userEditedText: null,
    );

    _state = _state.copyWith(
      committedSegments: List<String>.unmodifiable(nextCommitted),
      currentPartial: '',
      finalSegment: resolved,
      clearUserEditedText: true,
      lastSequenceNumber: nextSeq,
      effectiveText: effective,
    );
    return true;
  }

  /// Stores user-edited transcript cleanly and cancels partial overwrite while in review.
  VoiceTranscriptState onUserEdit(String editedText) {
    final normalized = editedText.replaceAll('\u00A0', ' ');
    _state = _state.copyWith(
      userEditedText: normalized,
      currentPartial: '',
      effectiveText: normalized,
    );
    return _state;
  }

  void clear() {
    _state = VoiceTranscriptState.empty;
  }

  bool _isAcceptableEnvelope({
    required String sessionId,
    required int attemptId,
    required int sequenceNumber,
  }) {
    if (_state.activeSessionId == null ||
        _state.activeSessionId != sessionId ||
        _state.activeAttemptId != attemptId) {
      return false;
    }
    if (sequenceNumber > 0 && sequenceNumber <= _state.lastSequenceNumber) {
      return false;
    }
    return true;
  }

  static String computeEffectiveText({
    required List<String> committedSegments,
    required String currentPartial,
    String? userEditedText,
  }) {
    if (userEditedText != null) {
      return userEditedText;
    }
    final parts = <String>[];
    for (final seg in committedSegments) {
      final cleaned = _cleanClause(seg);
      if (cleaned.isNotEmpty) {
        parts.add(cleaned);
      }
    }
    final partialClean = _cleanClause(currentPartial);
    if (partialClean.isNotEmpty) {
      parts.add(partialClean);
    }
    if (parts.isEmpty) return '';

    final buf = StringBuffer(parts.first);
    var prev = parts.first;
    for (var i = 1; i < parts.length; i++) {
      final next = parts[i];
      final joinWithSpace =
          _danglingConnectorRegex.hasMatch(prev) ||
          _bareDigitsRegex.hasMatch(prev);
      buf.write(joinWithSpace ? ' ' : ', ');
      buf.write(next);
      prev = next;
    }

    return _stripTrailingDuplicatePunctuation(buf.toString());
  }

  static List<String> _commitSegmentDeduped(
    List<String> existing,
    String incoming,
  ) {
    final updated = List<String>.from(existing);
    if (updated.isEmpty) {
      updated.add(incoming);
      return updated;
    }

    final incomingTokens = _tokenizeWithSpans(incoming);
    if (incomingTokens.isEmpty) return updated;

    // 1. Check cumulative full-transcript re-emit across all committed segments.
    final allCommittedTokens = <_TranscriptToken>[];
    for (final seg in updated) {
      allCommittedTokens.addAll(_tokenizeWithSpans(seg));
    }
    if (_tokensStartWith(incomingTokens, allCommittedTokens)) {
      final matchedCount = allCommittedTokens.length;
      if (incomingTokens.length == matchedCount) {
        // Exact duplicate of committed text.
        return updated;
      }
      final boundaryToken = incomingTokens[matchedCount - 1];
      final nextToken = incomingTokens[matchedCount];
      final tail = _cleanClause(incoming.substring(nextToken.start));
      if (tail.isEmpty) return updated;
      if (boundaryToken.hasClausePunctuationAfter) {
        updated.add(tail);
      } else {
        updated[updated.length - 1] = _mergeInline(updated.last, tail);
      }
      return updated;
    }

    // 2. Check cumulative repeat of the last committed segment.
    final lastTokens = _tokenizeWithSpans(updated.last);
    if (lastTokens.isNotEmpty && _tokensStartWith(incomingTokens, lastTokens)) {
      final matchedCount = lastTokens.length;
      if (incomingTokens.length == matchedCount) {
        return updated;
      }
      final boundaryToken = incomingTokens[matchedCount - 1];
      final nextToken = incomingTokens[matchedCount];
      final tail = _cleanClause(incoming.substring(nextToken.start));
      if (tail.isEmpty) return updated;
      if (boundaryToken.hasClausePunctuationAfter) {
        updated.add(tail);
      } else {
        updated[updated.length - 1] = _mergeInline(updated.last, tail);
      }
      return updated;
    }

    // 3. Check multi-token suffix-prefix overlap (>= 2 tokens) between last segment & incoming.
    final maxOverlap = lastTokens.length < incomingTokens.length
        ? lastTokens.length
        : incomingTokens.length;
    for (var k = maxOverlap; k >= 2; k--) {
      if (_suffixMatchesPrefix(lastTokens, incomingTokens, k)) {
        if (k == incomingTokens.length) {
          return updated;
        }
        final boundaryToken = incomingTokens[k - 1];
        final nextToken = incomingTokens[k];
        final tail = _cleanClause(incoming.substring(nextToken.start));
        if (tail.isNotEmpty) {
          if (boundaryToken.hasClausePunctuationAfter) {
            updated.add(tail);
          } else {
            updated[updated.length - 1] = _mergeInline(updated.last, tail);
          }
        }
        return updated;
      }
    }

    updated.add(incoming);
    return updated;
  }

  static String _mergeInline(String left, String right) {
    final cleanLeft = _cleanClause(left);
    final cleanRight = _cleanClause(right);
    if (cleanLeft.isEmpty) return cleanRight;
    if (cleanRight.isEmpty) return cleanLeft;
    return '$cleanLeft $cleanRight';
  }

  static bool _tokensStartWith(
    List<_TranscriptToken> full,
    List<_TranscriptToken> prefix,
  ) {
    if (prefix.isEmpty || full.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (full[i].normalized != prefix[i].normalized) return false;
    }
    return true;
  }

  static bool _suffixMatchesPrefix(
    List<_TranscriptToken> left,
    List<_TranscriptToken> right,
    int count,
  ) {
    final leftOffset = left.length - count;
    for (var i = 0; i < count; i++) {
      if (left[leftOffset + i].normalized != right[i].normalized) {
        return false;
      }
    }
    return true;
  }

  static List<_TranscriptToken> _tokenizeWithSpans(String input) {
    final tokens = <_TranscriptToken>[];
    final matches = _tokenScan.allMatches(input).toList(growable: false);
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final raw = m.group(0) ?? '';
      final core = raw.replaceAll(_trimEdgePunctuation, '');
      final norm = VietnameseSearchMatcher.fold(core);
      if (norm.isEmpty) continue;
      final betweenEnd = (i + 1 < matches.length)
          ? matches[i + 1].start
          : input.length;
      final afterSlice = input.substring(m.start + core.length, betweenEnd);
      tokens.add(
        _TranscriptToken(
          normalized: norm,
          start: m.start,
          end: m.end,
          hasClausePunctuationAfter: _clausePunctuation.hasMatch(afterSlice),
        ),
      );
    }
    return tokens;
  }

  static String _normalizeSpaces(String raw) {
    return raw.replaceAll('\u00A0', ' ').replaceAll(_whitespaceRun, ' ').trim();
  }

  static String _cleanClause(String raw) {
    return _normalizeSpaces(raw).replaceAll(_trailingSeparators, '').trim();
  }

  static String _stripTrailingDuplicatePunctuation(String raw) {
    var out = raw.trim();
    if (_duplicateTrailingPunctuation.hasMatch(out)) {
      final lastChar = out.endsWith('.') ? '.' : '';
      out = out.replaceAll(_duplicateTrailingPunctuation, '').trim();
      if (lastChar.isNotEmpty && out.isNotEmpty) {
        out = '$out$lastChar';
      }
    }
    return out;
  }
}
