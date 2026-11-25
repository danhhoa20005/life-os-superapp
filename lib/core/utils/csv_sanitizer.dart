/// OWASP-compliant CSV cell escaping utility that neutralizes spreadsheet
/// formula injection (`=`, `+`, `-`, `@`, `\t`, `\r`) while preserving UTF-8
/// Vietnamese text and RFC 4180 double-quote escaping.
abstract final class CsvSanitizer {
  static const Set<String> _dangerousFormulaPrefixes = <String>{
    '=',
    '+',
    '-',
    '@',
    '\t',
    '\r',
  };

  /// Escapes [raw] as a double-quoted RFC 4180 CSV field and prefixes a
  /// leading single quote `'` whenever the cell could be interpreted as an
  /// executable formula by Excel, Google Sheets, or LibreOffice Calc.
  static String escapeQuotedCell(String raw) {
    final normalized = raw
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');
    final trimmedLeft = normalized.trimLeft();
    final needsFormulaGuard =
        normalized.isNotEmpty &&
        (_dangerousFormulaPrefixes.contains(normalized[0]) ||
            (trimmedLeft.isNotEmpty &&
                _dangerousFormulaPrefixes.contains(trimmedLeft[0])));
    final safeValue = needsFormulaGuard ? "'$normalized" : normalized;
    final escapedQuotes = safeValue.replaceAll('"', '""');
    return '"$escapedQuotes"';
  }
}
