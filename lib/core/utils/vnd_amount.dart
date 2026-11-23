import 'package:equatable/equatable.dart';
import '../error/failure.dart';

/// Immutable Value Object representing exact Vietnamese Dong (VND) minor units (1 VND = 1 integer).
/// Never uses floating-point arithmetic for ledger accounting.
final class VndAmount extends Equatable {
  static const int maxAllowedMinor = 1000000000000000; // 1 quadrillion VND

  final int minor;

  const VndAmount._(this.minor);

  factory VndAmount.fromMinor(int value) {
    if (value < 0 || value > maxAllowedMinor) {
      throw const ValidationFailure(message: 'Số tiền VND không hợp lệ.');
    }
    return VndAmount._(value);
  }

  factory VndAmount.positiveFromMinor(int value, {String fieldLabel = 'Số tiền'}) {
    if (value <= 0 || value > maxAllowedMinor) {
      throw ValidationFailure(message: '$fieldLabel phải lớn hơn 0 ₫.');
    }
    return VndAmount._(value);
  }

  static int? tryParseInput(String raw) {
    var cleaned = raw
        .trim()
        .replaceFirst(RegExp(r'^(GD:|PS:|So tien:?)\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*(VND|VNĐ|₫|đ|d)\s*$', caseSensitive: false), '')
        .trim();

    cleaned = cleaned.replaceFirst(RegExp(r'^[+-]\s*'), '');

    if (RegExp(r'^\d{1,3}(,\d{3})+\.00$').hasMatch(cleaned)) {
      cleaned = cleaned.substring(0, cleaned.length - 3).replaceAll(',', '');
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+,00$').hasMatch(cleaned)) {
      cleaned = cleaned.substring(0, cleaned.length - 3).replaceAll('.', '');
    } else if (RegExp(r'^\d+[.,]00$').hasMatch(cleaned)) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(cleaned)) {
      cleaned = cleaned.replaceAll('.', '');
    } else if (RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(cleaned)) {
      cleaned = cleaned.replaceAll(',', '');
    } else if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
      return null;
    }

    final parsed = int.tryParse(cleaned);
    if (parsed == null || parsed <= 0 || parsed > maxAllowedMinor) {
      return null;
    }
    return parsed;
  }

  static String format(int amountMinor, {bool showPlus = false}) {
    final isNegative = amountMinor < 0;
    final absStr = amountMinor.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < absStr.length; i++) {
      if (i > 0 && (absStr.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(absStr[i]);
    }
    final sign = isNegative ? '-' : (showPlus && amountMinor > 0 ? '+' : '');
    return '$sign${buffer.toString()} ₫';
  }

  static String formatCompact(int amountMinor) {
    final abs = amountMinor.abs();
    final sign = amountMinor < 0 ? '-' : '';
    if (abs >= 1000000000) {
      final ty = (abs / 1000000000).toStringAsFixed(1).replaceAll('.0', '');
      return '$sign$ty tỷ';
    }
    if (abs >= 1000000) {
      final tr = (abs / 1000000).toStringAsFixed(1).replaceAll('.0', '');
      return '$sign$tr tr';
    }
    if (abs >= 1000) {
      final k = (abs ~/ 1000);
      return '$sign${k}k ₫';
    }
    return format(amountMinor);
  }

  /// Exact integer decimal parser for VND amounts (NEVER routes through IEEE-754 `double`).
  /// Handles strings such as `"500000.00"`, `"12,345,678.50"`, `"-45000"`, or integer inputs.
  static int parseExactDecimalVnd(Object? raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    final rawText = raw.toString().trim();
    if (rawText.isEmpty) return 0;

    final isNegative = rawText.startsWith('-');
    final cleaned = rawText.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return 0;

    final dotIndex = cleaned.indexOf('.');
    if (dotIndex < 0) {
      final whole = int.tryParse(cleaned) ?? 0;
      return isNegative ? -whole : whole;
    }

    final wholePartStr = dotIndex == 0 ? '0' : cleaned.substring(0, dotIndex);
    final fracPartStr = cleaned.substring(dotIndex + 1).replaceAll('.', '');
    var whole = int.tryParse(wholePartStr) ?? 0;
    if (fracPartStr.isNotEmpty) {
      final firstFracDigit = int.tryParse(fracPartStr[0]) ?? 0;
      if (firstFracDigit >= 5) {
        whole += 1;
      }
    }
    return isNegative ? -whole : whole;
  }

  @override
  List<Object?> get props => [minor];
}
