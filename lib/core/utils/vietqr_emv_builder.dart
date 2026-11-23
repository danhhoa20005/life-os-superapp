import 'dart:convert';
import 'dart:math';

/// Official Vietnamese NAPAS 247 Bank Directory for Native VietQR Generation & Account Linking.
const List<({String bin, String shortName, String fullName})> kLifeOsVietQrBanks = [
  (bin: '970436', shortName: 'VCB', fullName: 'Vietcombank'),
  (bin: '970422', shortName: 'MB', fullName: 'MB Bank'),
  (bin: '970407', shortName: 'TCB', fullName: 'Techcombank'),
  (bin: '970418', shortName: 'BIDV', fullName: 'BIDV'),
  (bin: '970415', shortName: 'CTG', fullName: 'VietinBank'),
  (bin: '970416', shortName: 'ACB', fullName: 'ACB'),
  (bin: '970432', shortName: 'VPB', fullName: 'VPBank'),
  (bin: '970423', shortName: 'TPB', fullName: 'TPBank'),
  (bin: '970403', shortName: 'STB', fullName: 'Sacombank'),
  (bin: '970441', shortName: 'VIB', fullName: 'VIB'),
  (bin: '970426', shortName: 'MSB', fullName: 'MSB'),
  (bin: '970437', shortName: 'HDB', fullName: 'HDBank'),
  (bin: '970448', shortName: 'OCB', fullName: 'OCB'),
  (bin: '970443', shortName: 'SHB', fullName: 'SHB'),
  (bin: '970405', shortName: 'VBA', fullName: 'Agribank'),
  (bin: '546034', shortName: 'CAKE', fullName: 'Cake by VPBank'),
];

/// Pure-Dart EMVCo / NAPAS 247 (`QRIBFTTA`) Dynamic VietQR Builder & Auto-Match Payment Code Generator.
/// Zero external API dependency — generates bank-grade EMVCo payloads locally on device.
abstract final class VietQrEmvBuilder {
  static const Map<String, String> _viDiacritics = {
    'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
    'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
    'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
    'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
    'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
    'đ': 'd',
  };

  /// Converts Vietnamese text into bank-transfer-safe uppercase ASCII (no accents or special chars).
  static String toBankSafeAscii(String input, {int maxLength = 50}) {
    final sb = StringBuffer();
    for (final rune in input.trim().runes) {
      final ch = String.fromCharCode(rune);
      final lower = ch.toLowerCase();
      if (_viDiacritics.containsKey(lower)) {
        sb.write(_viDiacritics[lower]!.toUpperCase());
      } else if (RegExp(r'[A-Za-z0-9 ]').hasMatch(ch)) {
        sb.write(ch.toUpperCase());
      } else {
        sb.write(' ');
      }
    }
    final normalized = sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= maxLength ? normalized : normalized.substring(0, maxLength).trim();
  }

  /// Generates a short, collision-resistant alphanumeric payment reference code (e.g. `LO482910`)
  /// preserved verbatim by all Vietnamese banking apps inside transfer memos.
  static String generatePaymentCode({String prefix = 'LO'}) {
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rng = Random.secure();
    final buf = StringBuffer(prefix.toUpperCase());
    for (var i = 0; i < 6; i++) {
      buf.write(alphabet[rng.nextInt(alphabet.length)]);
    }
    return buf.toString();
  }

  /// ISO/IEC 13239 CRC-16/CCITT-FALSE (`poly = 0x1021`, `init = 0xFFFF`, `xorOut = 0x0000`).
  /// Standard vector: `crc16CcittHex("123456789") == "29B1"`.
  static String crc16CcittHex(String asciiPayload) {
    final bytes = utf8.encode(asciiPayload);
    var crc = 0xFFFF;
    for (final b in bytes) {
      crc ^= (b & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  static String _tlv(String tag, String value) {
    final len = utf8.encode(value).length.toString().padLeft(2, '0');
    return '$tag$len$value';
  }

  /// Builds an official NAPAS 247 (`QRIBFTTA`) EMVCo QR string scannable by every Vietnamese banking app.
  static String buildNapas247Payload({
    required String bankBin,
    required String accountNumber,
    int? amountVnd,
    String? memo,
  }) {
    final cleanBin = bankBin.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanAcc = accountNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final hasAmount = amountVnd != null && amountVnd > 0;
    final safeMemo = memo != null && memo.trim().isNotEmpty
        ? toBankSafeAscii(memo, maxLength: 50)
        : '';

    final beneficiaryOrg = _tlv('00', cleanBin) + _tlv('01', cleanAcc);
    final merchantAccountInfo = _tlv('00', 'A000000727') +
        _tlv('01', beneficiaryOrg) +
        _tlv('02', 'QRIBFTTA');

    final sb = StringBuffer()
      ..write(_tlv('00', '01'))
      ..write(_tlv('01', hasAmount || safeMemo.isNotEmpty ? '12' : '11'))
      ..write(_tlv('38', merchantAccountInfo))
      ..write(_tlv('53', '704'));

    if (hasAmount) {
      sb.write(_tlv('54', amountVnd.toString()));
    }

    sb.write(_tlv('58', 'VN'));

    if (safeMemo.isNotEmpty) {
      sb.write(_tlv('62', _tlv('08', safeMemo)));
    }

    final payloadWithoutCrc = '${sb.toString()}6304';
    final crc = crc16CcittHex(payloadWithoutCrc);
    return '$payloadWithoutCrc$crc';
  }

  /// Convenience VietQR image URL (compact2 NAPAS 247 card) for visual display when online.
  static String buildVisualQrUrl({
    required String bankBin,
    required String accountNumber,
    String? accountHolderName,
    int? amountVnd,
    String? memo,
  }) {
    final cleanBin = bankBin.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanAcc = accountNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final params = <String>[];
    if (amountVnd != null && amountVnd > 0) {
      params.add('amount=$amountVnd');
    }
    if (memo != null && memo.trim().isNotEmpty) {
      params.add('addInfo=${Uri.encodeComponent(toBankSafeAscii(memo))}');
    }
    if (accountHolderName != null && accountHolderName.trim().isNotEmpty) {
      params.add('accountName=${Uri.encodeComponent(toBankSafeAscii(accountHolderName))}');
    }
    final query = params.isEmpty ? '' : '?${params.join("&")}';
    return 'https://img.vietqr.io/image/$cleanBin-$cleanAcc-compact2.png$query';
  }
}
