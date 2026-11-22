import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../utils/vnd_amount.dart';

/// Pure Dart security redactor and Vietnamese Bank Notification Parser.
/// Zero Flutter/Firebase imports so Domain and Tests can invoke directly.
abstract final class OtpRedactor {
  static final List<RegExp> _otpPatterns = [
    RegExp(r'\b(otp|smart\s*otp|digital\s*otp|s-otp|m-otp)\b', caseSensitive: false),
    RegExp(
      r'\bm[aã]\s*(x[aá]c\s*th[uự]c|x[aá]c\s*nh[aậ]n|b[aả]o\s*m[aậ]t|k[ií]ch\s*ho[aạ]t|giao\s*d[iị]ch)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(verification|security|auth|activation|one[- ]time)\s*(code|pin|password)\b',
      caseSensitive: false,
    ),
    RegExp(r'\bkh[oô]ng\s*chia\s*s[eẻ]\s*m[aã]\b', caseSensitive: false),
    RegExp(r'\b(cvv|cvc|m[aã]\s*pin|m[aậ]t\s*kh[aẩ]u)\b', caseSensitive: false),
  ];

  static bool containsOtpOrSecret(String text) {
    if (text.isEmpty) return false;
    for (final pattern in _otpPatterns) {
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  static String redact(String text) {
    if (text.isEmpty) return '';
    var out = text;
    out = out.replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false), 'Bearer [REDACTED]');
    out = out.replaceAll(RegExp(r'\b(?:\d[ -]*?){13,19}\b'), '[REDACTED_CARD]');
    if (containsOtpOrSecret(out)) {
      out = out.replaceAll(RegExp(r'\b\d{4,8}\b'), '[REDACTED_OTP]');
    }
    return out;
  }

  static String maskLicensePlate(String plate) {
    final clean = plate.trim();
    if (clean.length <= 4) return '***';
    final dashIdx = clean.indexOf('-');
    if (dashIdx > 0 && clean.length > dashIdx + 3) {
      return '${clean.substring(0, dashIdx + 1)}***${clean.substring(clean.length - 2)}';
    }
    return '${clean.substring(0, 2)}***${clean.substring(clean.length - 2)}';
  }
}

final class SupportedVnBank {
  final String packageName;
  final String bankCode;
  final String displayName;
  final bool supportsCredit;
  final bool supportsDebit;
  final bool supportsVerifiedBalance;

  const SupportedVnBank({
    required this.packageName,
    required this.bankCode,
    required this.displayName,
    required this.supportsCredit,
    required this.supportsDebit,
    required this.supportsVerifiedBalance,
  });
}

/// Bank capability matrix aligned with SePay_LifeOS_Blueprint_2026.md Section 3 & 4.2.
const List<SupportedVnBank> kSupportedVnBanks = [
  SupportedVnBank(
    packageName: 'com.VCB',
    bankCode: 'VCB',
    displayName: 'Vietcombank',
    supportsCredit: true,
    supportsDebit: true,
    supportsVerifiedBalance: false,
  ),
  SupportedVnBank(
    packageName: 'com.techcombank.bb.app',
    bankCode: 'TCB',
    displayName: 'Techcombank',
    supportsCredit: true,
    supportsDebit: true,
    supportsVerifiedBalance: false,
  ),
  SupportedVnBank(
    packageName: 'com.mbmobile',
    bankCode: 'MB',
    displayName: 'MBBank',
    supportsCredit: true,
    supportsDebit: true,
    supportsVerifiedBalance: false,
  ),
  SupportedVnBank(
    packageName: 'mobile.acb.com.vn',
    bankCode: 'ACB',
    displayName: 'ACB One',
    supportsCredit: true,
    supportsDebit: true,
    supportsVerifiedBalance: false,
  ),
  SupportedVnBank(
    packageName: 'com.vietinbank.ipay',
    bankCode: 'CTG',
    displayName: 'VietinBank iPay',
    supportsCredit: true,
    supportsDebit: true,
    supportsVerifiedBalance: true,
  ),
  SupportedVnBank(
    packageName: 'com.tpb.mb.gprsandroid',
    bankCode: 'TPB',
    displayName: 'TPBank Mobile',
    supportsCredit: true,
    supportsDebit: true,
    supportsVerifiedBalance: true,
  ),
  SupportedVnBank(
    packageName: 'com.vnpay.bidv',
    bankCode: 'BIDV',
    displayName: 'BIDV SmartBanking',
    supportsCredit: true,
    supportsDebit: false,
    supportsVerifiedBalance: false,
  ),
  SupportedVnBank(
    packageName: 'com.vnpay.vpbankonline',
    bankCode: 'VPB',
    displayName: 'VPBank NEO',
    supportsCredit: true,
    supportsDebit: false,
    supportsVerifiedBalance: false,
  ),
];

final class ParsedBankSignal {
  final int amountMinor;
  final String direction; // 'debit' | 'credit'
  final String bankCode;
  final String merchant;
  final String categorySuggestion;
  final bool isVehicleMaintenanceHint;
  final double confidence;
  final String sourceEventKey;
  final String crossSourceFingerprint;
  final DateTime occurredAt;

  /// Per SePay Blueprint T15: accumulated=0 from IPN/alert NEVER implies 0 VND account balance!
  final int? observedBalanceMinor;

  const ParsedBankSignal({
    required this.amountMinor,
    required this.direction,
    required this.bankCode,
    required this.merchant,
    required this.categorySuggestion,
    required this.isVehicleMaintenanceHint,
    required this.confidence,
    required this.sourceEventKey,
    required this.crossSourceFingerprint,
    required this.occurredAt,
    this.observedBalanceMinor,
  });
}

enum BankSignalDropReason { otpOrSecret, nonFinancial, invalidAmount }

final class BankSignalParseOutcome {
  final ParsedBankSignal? signal;
  final BankSignalDropReason? dropReason;

  const BankSignalParseOutcome._({this.signal, this.dropReason});
  const BankSignalParseOutcome.accepted(ParsedBankSignal signal) : this._(signal: signal);
  const BankSignalParseOutcome.dropped(BankSignalDropReason reason) : this._(dropReason: reason);
}

abstract final class BankNotificationParser {
  static final RegExp _vehicleRegex = RegExp(
    r'\b(thay\s*nh[oớ]t|thay\s*d[aầ]u|b[aả]o\s*d[uư][oỡ]ng\s*xe|head\s*honda|yamaha\s*town|s[uử]a\s*xe|l[oố]p\s*xe|[aắ]c\s*quy|gara)\b',
    caseSensitive: false,
  );

  static String computeCrossSourceFingerprint({
    required String ownerId,
    required String direction,
    required int amountMinor,
    required DateTime occurredAt,
    String? referenceCode,
  }) {
    final bucket15m = occurredAt.millisecondsSinceEpoch ~/ (15 * 60 * 1000);
    // If distinct official reference code exists (Scenario T06), two same-amount payments stay distinct;
    // when reference code is absent across notification vs bank feed, match by 15m bucket!
    final refSegment = (referenceCode != null && referenceCode.trim().isNotEmpty)
        ? referenceCode.trim().toUpperCase()
        : 'BUCKET_$bucket15m';
    final raw = '$ownerId|$direction|$amountMinor|$refSegment';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  static String computeSoftWindowFingerprint({
    required String ownerId,
    required String direction,
    required int amountMinor,
    required DateTime occurredAt,
  }) {
    final bucket15m = occurredAt.millisecondsSinceEpoch ~/ (15 * 60 * 1000);
    final raw = '$ownerId|$direction|$amountMinor|SOFT_$bucket15m';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  /// Returns overlapping adjacent 15-minute bucket fingerprints `[prev, current, next]`
  /// so events straddling `:00`, `:15`, `:30`, or `:45` clock boundaries still match reliably.
  static List<String> computeOverlappingSoftWindowFingerprints({
    required String ownerId,
    required String direction,
    required int amountMinor,
    required DateTime occurredAt,
  }) {
    const window = Duration(minutes: 15);
    return <String>{
      computeSoftWindowFingerprint(
        ownerId: ownerId,
        direction: direction,
        amountMinor: amountMinor,
        occurredAt: occurredAt.subtract(window),
      ),
      computeSoftWindowFingerprint(
        ownerId: ownerId,
        direction: direction,
        amountMinor: amountMinor,
        occurredAt: occurredAt,
      ),
      computeSoftWindowFingerprint(
        ownerId: ownerId,
        direction: direction,
        amountMinor: amountMinor,
        occurredAt: occurredAt.add(window),
      ),
    }.toList(growable: false);
  }

  static String computeSourceEventKey(String source, String uniqueHint) {
    return sha256.convert(utf8.encode('$source:$uniqueHint')).toString().substring(0, 36);
  }

  /// Generates a deterministic SePay / VietQR-compatible transfer content reference.
  /// Preserves the mandatory `SEVQR` prefix per SePay_LifeOS_Blueprint_2026.md Section 3 (VietinBank/Bank Hub).
  static String buildSePayTransferCode({
    required String scopePrefix,
    required String seed,
  }) {
    final cleanPrefix = scopePrefix.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final digest = sha256.convert(utf8.encode('$cleanPrefix:$seed')).toString().toUpperCase();
    return 'SEVQR LIFEOS $cleanPrefix${digest.substring(0, 6)}';
  }

  static ({String category, bool isVehicleMaintenance}) inferCategory(
    String text,
    String direction,
  ) {
    final isVeh = _vehicleRegex.hasMatch(text);
    if (direction == 'credit') {
      if (RegExp(r'\b(l[uư][oơ]ng|salary|th[uư][oở]ng)\b', caseSensitive: false).hasMatch(text)) {
        return (category: 'Lương & Thu nhập', isVehicleMaintenance: false);
      }
      return (category: 'Thu nhập khác', isVehicleMaintenance: false);
    }

    if (isVeh ||
        RegExp(r'\b(x[aă]ng|petrolimex|pvoil|grab|xanh\s*sm|g[uử]i\s*xe|epass|vetc)\b',
                caseSensitive: false)
            .hasMatch(text)) {
      return (category: 'Xe cộ & Di chuyển', isVehicleMaintenance: isVeh);
    }
    if (RegExp(
      r'\b(qu[aá]n|c[oơ]m|ph[oở]|b[uú]n|cafe|coffee|highlands|phuc\s*long|kfc|pizza|ăn|uống)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return (category: 'Ăn uống', isVehicleMaintenance: false);
    }
    if (RegExp(
      r'\b(vi[eệ]c\s*nh[aà]|d[oọ]n\s*nh[aà]|d[oọ]n\s*d[eẹ]p|gi[aặ]t\s*[uủ]i|btaskee|gi[uú]p\s*vi[eệ]c|n[uư][oớ]c\s*r[uử]a\s*ch[eé]n|b[oộ]t\s*gi[aặ]t)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return (category: 'Việc nhà & Gia dụng', isVehicleMaintenance: false);
    }
    if (RegExp(
      r'\b(thu[eê]\s*nh[aà]|ti[eề]n\s*tr[oọ]|ph[ií]\s*chung\s*c[uư]|ph[ií]\s*qu[aả]n\s*l[yý])\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return (category: 'Nhà cửa & Thuê nhà', isVehicleMaintenance: false);
    }
    if (RegExp(
      r'\b(evn|điện|nước|sawaco|viettel|vnpt|fpt|internet|wifi|tiền\s*nhà)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return (category: 'Điện/Nước/Internet', isVehicleMaintenance: false);
    }
    if (RegExp(
      r'\b(b[eệ]nh\s*vi[eệ]n|ph[oò]ng\s*kh[aá]m|nh[aà]\s*thu[oố]c|pharmacity|long\s*ch[aâ]u|h[oọ]c\s*ph[ií])\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return (category: 'Sức khỏe & Giáo dục', isVehicleMaintenance: false);
    }
    if (RegExp(r'\b(netflix|spotify|youtube|icloud|google\s*one)\b', caseSensitive: false)
        .hasMatch(text)) {
      return (category: 'Giải trí & Đăng ký', isVehicleMaintenance: false);
    }
    if (RegExp(r'\b(si[eê]u\s*th[iị]|coopmart|winmart|aeon|b[aá]ch\s*h[oó]a\s*xanh|shopee|lazada|mua\s*s[aắ]m)\b',
            caseSensitive: false)
        .hasMatch(text)) {
      return (category: 'Chợ & Mua sắm', isVehicleMaintenance: false);
    }
    if (RegExp(r'\b(tr[aả]\s*g[oó]p|kho[aả]n\s*vay|fe\s*credit|home\s*credit|tr[aả]\s*n[oợ])\b',
            caseSensitive: false)
        .hasMatch(text)) {
      return (category: 'Trả nợ & Cho vay', isVehicleMaintenance: false);
    }
    if (RegExp(r'\b(ph[ií]\s*th[uư][oờ]ng\s*ni[eê]n|ph[ií]\s*sms|ph[ií]\s*duy\s*tr[iì]|ph[ií]\s*chuy[eể]n\s*kho[aả]n)\b',
            caseSensitive: false)
        .hasMatch(text)) {
      return (category: 'Phí ngân hàng', isVehicleMaintenance: false);
    }
    return (category: 'Chi tiêu khác', isVehicleMaintenance: false);
  }

  /// Safely interprets SePay IPN `accumulated` field (Scenario T15: accumulated=0 NEVER means 0 VND!).
  static int? safeObservedBalanceFromIpn({
    required int? accumulated,
    required bool bankSupportsBalance,
  }) {
    if (!bankSupportsBalance || accumulated == null || accumulated <= 0) {
      return null;
    }
    return accumulated;
  }

  static BankSignalParseOutcome parseAndroidNotification({
    required String ownerId,
    required String packageName,
    required String title,
    required String body,
    DateTime? postedAt,
    String? notificationId,
  }) {
    final combined = '$title $body'.trim();
    if (OtpRedactor.containsOtpOrSecret(combined)) {
      return const BankSignalParseOutcome.dropped(BankSignalDropReason.otpOrSecret);
    }

    if (RegExp(
      r'\b(khuy[eế]n\s*m[aã]i|[uư]u\s*đ[aã]i|vay\s*nhanh|m[oở]\s*th[eẻ])\b',
      caseSensitive: false,
    ).hasMatch(combined)) {
      return const BankSignalParseOutcome.dropped(BankSignalDropReason.nonFinancial);
    }

    final signedMatch = RegExp(
      r'([+-])\s*(\d{1,3}(?:[.,]\d{3})+(?:[.,]00)?|\d{4,15})(?:\s*(?:VND|VNĐ|đ|₫|d))?',
      caseSensitive: false,
    ).firstMatch(combined);

    String? direction;
    int? amountMinor;

    if (signedMatch != null) {
      direction = signedMatch.group(1) == '-' ? 'debit' : 'credit';
      amountMinor = VndAmount.tryParseInput(signedMatch.group(2) ?? '');
    } else {
      final verbMatch = RegExp(
        r'\b(thanh\s*to[aá]n|chi\s*ti[eê]u|tr[uừ]|nh[aậ]n\s*đ[uư][oợ]c|c[oộ]ng)\s+(\d{1,3}(?:[.,]\d{3})+|\d{4,15})\s*(VND|VNĐ|đ|₫)',
        caseSensitive: false,
      ).firstMatch(combined);
      if (verbMatch != null) {
        final verb = (verbMatch.group(1) ?? '').toLowerCase();
        direction = RegExp(r'(nh[aậ]n|c[oộ]ng)').hasMatch(verb) ? 'credit' : 'debit';
        amountMinor = VndAmount.tryParseInput(verbMatch.group(2) ?? '');
      }
    }

    if (direction == null) {
      return const BankSignalParseOutcome.dropped(BankSignalDropReason.nonFinancial);
    }
    if (amountMinor == null || amountMinor <= 0) {
      return const BankSignalParseOutcome.dropped(BankSignalDropReason.invalidAmount);
    }

    final bankMeta = kSupportedVnBanks.where((b) => b.packageName == packageName).firstOrNull;
    final occurred = (postedAt ?? DateTime.now()).toUtc();

    var merchant = combined;
    final contentMatch = RegExp(
      r'(?:ND|N[oộ]i\s*dung|t[aạ]i|tai)[:\s]+([^.;|\n]{3,100})',
      caseSensitive: false,
    ).firstMatch(combined);
    if (contentMatch != null) {
      merchant = contentMatch.group(1)!.trim();
    }
    merchant = merchant.replaceFirst(RegExp(r'\bSD[:\s].*$', caseSensitive: false), '').trim();
    if (merchant.length > 72) {
      merchant = merchant.substring(0, 72);
    }

    final refMatch = RegExp(r'\b(FT[A-Z0-9_]{5,24}|REF[:\s]*([A-Z0-9_-]{5,24}))\b', caseSensitive: false)
        .firstMatch(combined);
    final refCode = refMatch?.group(2) ?? refMatch?.group(1);

    final inferred = inferCategory(combined, direction);
    final uniqueHint = notificationId != null && notificationId.isNotEmpty
        ? '$packageName:$notificationId'
        : '$packageName:${occurred.toIso8601String()}:$direction:$amountMinor:$merchant';

    return BankSignalParseOutcome.accepted(
      ParsedBankSignal(
        amountMinor: amountMinor,
        direction: direction,
        bankCode: bankMeta?.bankCode ?? 'BANK',
        merchant: merchant.isEmpty ? 'Giao dịch ngân hàng' : merchant,
        categorySuggestion: inferred.category,
        isVehicleMaintenanceHint: inferred.isVehicleMaintenance,
        confidence: bankMeta != null && signedMatch != null ? 0.92 : 0.76,
        sourceEventKey: computeSourceEventKey('android_notification', uniqueHint),
        crossSourceFingerprint: computeCrossSourceFingerprint(
          ownerId: ownerId,
          direction: direction,
          amountMinor: amountMinor,
          occurredAt: occurred,
          referenceCode: refCode,
        ),
        occurredAt: occurred,
      ),
    );
  }
}
