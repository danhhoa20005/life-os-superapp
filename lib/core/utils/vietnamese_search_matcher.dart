/// Fast, zero-allocation-friendly Vietnamese diacritic-insensitive & multi-token search matcher
/// used across all search bars and filter lists in Life OS (`< 0.05ms` per item).
abstract final class VietnameseSearchMatcher {
  static const Map<String, String> _diacriticMap = <String, String>{
    'à': 'a',
    'á': 'a',
    'ả': 'a',
    'ã': 'a',
    'ạ': 'a',
    'ă': 'a',
    'ằ': 'a',
    'ắ': 'a',
    'ẳ': 'a',
    'ẵ': 'a',
    'ặ': 'a',
    'â': 'a',
    'ầ': 'a',
    'ấ': 'a',
    'ẩ': 'a',
    'ẫ': 'a',
    'ậ': 'a',
    'đ': 'd',
    'è': 'e',
    'é': 'e',
    'ẻ': 'e',
    'ẽ': 'e',
    'ẹ': 'e',
    'ê': 'e',
    'ề': 'e',
    'ế': 'e',
    'ể': 'e',
    'ễ': 'e',
    'ệ': 'e',
    'ì': 'i',
    'í': 'i',
    'ỉ': 'i',
    'ĩ': 'i',
    'ị': 'i',
    'ò': 'o',
    'ó': 'o',
    'ỏ': 'o',
    'õ': 'o',
    'ọ': 'o',
    'ô': 'o',
    'ồ': 'o',
    'ố': 'o',
    'ổ': 'o',
    'ỗ': 'o',
    'ộ': 'o',
    'ơ': 'o',
    'ờ': 'o',
    'ớ': 'o',
    'ở': 'o',
    'ỡ': 'o',
    'ợ': 'o',
    'ù': 'u',
    'ú': 'u',
    'ủ': 'u',
    'ũ': 'u',
    'ụ': 'u',
    'ư': 'u',
    'ừ': 'u',
    'ứ': 'u',
    'ử': 'u',
    'ữ': 'u',
    'ự': 'u',
    'ỳ': 'y',
    'ý': 'y',
    'ỷ': 'y',
    'ỹ': 'y',
    'ỵ': 'y',
  };

  static final RegExp _combiningMarks = RegExp(r'[\u0300-\u036f]');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _nonDigits = RegExp(r'[^0-9]');
  static final RegExp _kShorthand = RegExp(r'^(\d+)(?:[.,](\d{1,3}))?k$');
  static final RegExp _trShorthand = RegExp(
    r'^(\d+)(?:[.,](\d{1,3}))?tr(\d{0,3})$',
  );
  static final Map<String, String> _foldCache = <String, String>{};
  static const int _maxFoldCacheEntries = 512;

  /// Folds Vietnamese accents/tones (`ă/â -> a`, `đ -> d`, etc.), lowercases, and trims whitespace.
  static String fold(String input) {
    if (input.isEmpty) return '';
    final cached = _foldCache[input];
    if (cached != null) return cached;

    final lower = input
        .replaceAll('\u00A0', ' ')
        .toLowerCase()
        .replaceAll(_combiningMarks, '');
    final sb = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      sb.write(_diacriticMap[ch] ?? ch);
    }
    final result = sb.toString().replaceAll(_whitespace, ' ').trim();
    if (input.length <= 160) {
      if (_foldCache.length >= _maxFoldCacheEntries) {
        _foldCache.remove(_foldCache.keys.first);
      }
      _foldCache[input] = result;
    }
    return result;
  }

  /// Splits a query/label into folded non-empty tokens.
  static List<String> tokenize(String input) {
    final folded = fold(input);
    if (folded.isEmpty) return const <String>[];
    return folded.split(' ').where((t) => t.isNotEmpty).toList(growable: false);
  }

  /// Checks whether [foldedHaystack] contains [foldedPhrase] using token boundaries
  /// for short abbreviations (`<= 4` chars) without allocating a RegExp in the hot loop.
  static bool containsPhrase(String foldedHaystack, String foldedPhrase) {
    if (foldedHaystack.isEmpty || foldedPhrase.isEmpty) return false;
    if (foldedPhrase.length <= 4 && !foldedPhrase.contains(' ')) {
      final pLen = foldedPhrase.length;
      final hLen = foldedHaystack.length;
      var start = 0;
      while (start <= hLen - pLen) {
        final idx = foldedHaystack.indexOf(foldedPhrase, start);
        if (idx < 0) return false;
        final leftOk = idx == 0 || foldedHaystack.codeUnitAt(idx - 1) == 0x20;
        final end = idx + pLen;
        final rightOk = end == hLen || foldedHaystack.codeUnitAt(end) == 0x20;
        if (leftOk && rightOk) return true;
        start = idx + 1;
      }
      return false;
    }
    return foldedHaystack.contains(foldedPhrase);
  }

  /// Returns `true` when every whitespace-separated token in [rawQuery] matches across [fields]
  /// (accent-insensitive Vietnamese + numeric amount formatting tolerance such as `65000` == `65.000 ₫`).
  static bool matchesAny(String rawQuery, Iterable<String?> fields) {
    final foldedQuery = fold(rawQuery);
    if (foldedQuery.isEmpty) return true;

    final queryTokens = foldedQuery
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (queryTokens.isEmpty) return true;

    final combinedBuf = StringBuffer();
    final digitsBuf = StringBuffer();
    for (final field in fields) {
      if (field == null || field.isEmpty) continue;
      if (combinedBuf.isNotEmpty) combinedBuf.write(' ');
      combinedBuf.write(fold(field));
      final digits = field.replaceAll(_nonDigits, '');
      if (digits.isNotEmpty) {
        if (digitsBuf.isNotEmpty) digitsBuf.write(' ');
        digitsBuf.write(digits);
      }
    }

    final haystack = combinedBuf.toString();
    if (haystack.isEmpty) return false;
    final digitsHaystack = digitsBuf.toString();

    for (final token in queryTokens) {
      if (haystack.contains(token)) continue;
      final normalizedDigits = _expandNumericTokenDigits(token);
      if (normalizedDigits.length >= 2 &&
          digitsHaystack.contains(normalizedDigits)) {
        continue;
      }
      return false;
    }
    return true;
  }

  static String _expandNumericTokenDigits(String token) {
    final kMatch = _kShorthand.firstMatch(token);
    if (kMatch != null) {
      final whole = int.tryParse(kMatch.group(1) ?? '') ?? 0;
      final dec = kMatch.group(2);
      var total = whole * 1000;
      if (dec != null && dec.isNotEmpty) {
        total += int.parse(dec.padRight(3, '0').substring(0, 3));
      }
      if (total > 0) return total.toString();
    }
    final trMatch = _trShorthand.firstMatch(token);
    if (trMatch != null) {
      final whole = int.tryParse(trMatch.group(1) ?? '') ?? 0;
      final dec = trMatch.group(2);
      final tail = trMatch.group(3);
      var total = whole * 1000000;
      if (dec != null && dec.isNotEmpty) {
        total += int.parse(dec.padRight(6, '0').substring(0, 6));
      } else if (tail != null && tail.isNotEmpty) {
        final scale = switch (tail.length) {
          1 => 100000,
          2 => 10000,
          _ => 1000,
        };
        total += (int.tryParse(tail) ?? 0) * scale;
      }
      if (total > 0) return total.toString();
    }
    return token.replaceAll(_nonDigits, '');
  }
}
