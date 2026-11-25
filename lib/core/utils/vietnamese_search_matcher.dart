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

  /// Folds Vietnamese accents/tones (`ă/â -> a`, `đ -> d`, etc.), lowercases, and trims whitespace.
  static String fold(String input) {
    if (input.isEmpty) return '';
    final lower = input.toLowerCase().replaceAll(_combiningMarks, '');
    final sb = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      sb.write(_diacriticMap[ch] ?? ch);
    }
    return sb.toString().replaceAll(_whitespace, ' ').trim();
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
      // Numeric amount convenience: "85.000" or "85000" or "85k"
      var normalizedDigits = token.replaceAll(_nonDigits, '');
      if (token.endsWith('k') && normalizedDigits.isNotEmpty) {
        normalizedDigits = '${normalizedDigits}000';
      }
      if (normalizedDigits.length >= 2 &&
          digitsHaystack.contains(normalizedDigits)) {
        continue;
      }
      return false;
    }
    return true;
  }
}
