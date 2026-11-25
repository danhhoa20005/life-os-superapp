import 'package:equatable/equatable.dart';

enum ReceiptDocumentType {
  restaurant('Nhà hàng & Đồ uống'),
  supermarket('Siêu thị & Tạp hóa'),
  shopping('Mua sắm & Điện máy'),
  utilityBill('Hóa đơn Điện / Nước / Viễn thông'),
  vehicleService('Bảo dưỡng & Nhiên liệu Xe'),
  bankTransferSlip('Biên lai Chuyển khoản');

  final String labelVi;
  const ReceiptDocumentType(this.labelVi);
}

class ParsedReceiptLineItem extends Equatable {
  final String id;
  final String name;
  final double quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;
  final String suggestedCategoryName;
  final List<String> assignedMemberIds; // empty = shared equally across group

  const ParsedReceiptLineItem({
    required this.id,
    required this.name,
    this.quantity = 1.0,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.suggestedCategoryName,
    this.assignedMemberIds = const <String>[],
  });

  ParsedReceiptLineItem copyWith({
    String? name,
    double? quantity,
    int? unitPriceMinor,
    int? lineTotalMinor,
    String? suggestedCategoryName,
    List<String>? assignedMemberIds,
  }) {
    return ParsedReceiptLineItem(
      id: id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unitPriceMinor: unitPriceMinor ?? this.unitPriceMinor,
      lineTotalMinor: lineTotalMinor ?? this.lineTotalMinor,
      suggestedCategoryName:
          suggestedCategoryName ?? this.suggestedCategoryName,
      assignedMemberIds: assignedMemberIds ?? this.assignedMemberIds,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    quantity,
    unitPriceMinor,
    lineTotalMinor,
    suggestedCategoryName,
    assignedMemberIds,
  ];
}

class StructuredReceiptAnalysis extends Equatable {
  final ReceiptDocumentType documentType;
  final String merchantName;
  final List<ParsedReceiptLineItem> items;
  final int itemsSubtotalMinor;
  final int vatMinor;
  final int surchargeMinor;
  final int discountMinor;
  final int? statedTotalMinor;
  final int computedNetTotalMinor;
  final int discrepancyMinor;

  const StructuredReceiptAnalysis({
    required this.documentType,
    required this.merchantName,
    required this.items,
    required this.itemsSubtotalMinor,
    required this.vatMinor,
    required this.surchargeMinor,
    required this.discountMinor,
    this.statedTotalMinor,
    required this.computedNetTotalMinor,
    required this.discrepancyMinor,
  });

  int get effectiveTotalMinor => statedTotalMinor ?? computedNetTotalMinor;

  bool get isTotalVerified =>
      effectiveTotalMinor > 0 && discrepancyMinor == 0;

  bool get requiresManualTotalReview =>
      effectiveTotalMinor <= 0 || discrepancyMinor != 0;

  @override
  List<Object?> get props => [
    documentType,
    merchantName,
    items,
    itemsSubtotalMinor,
    vatMinor,
    surchargeMinor,
    discountMinor,
    statedTotalMinor,
    computedNetTotalMinor,
    discrepancyMinor,
  ];
}

/// Pure-Dart Receipt Structure Parser, VAT/Discount Validator & Itemized Group Split Calculator (Section 19).
///
/// Guarantees:
/// - Never auto-creates a transaction when `requiresManualTotalReview == true` (discrepancy != 0 or total <= 0).
/// - Supports per-item category rollup AND itemized per-person + shared-remainder group splitting
///   with exact integer VND (`BigInt` Largest Remainder) apportionment (`sum == effectiveTotalMinor`).
abstract final class ReceiptIntelligenceEngine {
  static final RegExp _trailingMoneyRe = RegExp(
    r'^(.*?)\s+(?:x\s*(\d+(?:[.,]\d+)?)\s+)?(-?\d{1,3}(?:[.,]\d{3})+|-?\d{4,10})\s*(?:đ|₫|vnd|vnđ|d)?$',
    caseSensitive: false,
    unicode: true,
  );

  static StructuredReceiptAnalysis analyzeOcrText(String rawOcrText) {
    final lines = rawOcrText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const StructuredReceiptAnalysis(
        documentType: ReceiptDocumentType.supermarket,
        merchantName: 'Hóa đơn trống',
        items: <ParsedReceiptLineItem>[],
        itemsSubtotalMinor: 0,
        vatMinor: 0,
        surchargeMinor: 0,
        discountMinor: 0,
        computedNetTotalMinor: 0,
        discrepancyMinor: 0,
      );
    }

    String merchant = lines.first;
    final items = <ParsedReceiptLineItem>[];
    var vatMinor = 0;
    var surchargeMinor = 0;
    var discountMinor = 0;
    int? statedTotal;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();

      final moneyMatch = _trailingMoneyRe.firstMatch(line);
      if (moneyMatch == null) {
        if (i == 0) merchant = line;
        continue;
      }

      final rawLabel = (moneyMatch.group(1) ?? '')
          .replaceAll(RegExp(r'[:\-–]+$'), '')
          .trim();
      final qty =
          double.tryParse((moneyMatch.group(2) ?? '1').replaceAll(',', '.')) ??
          1.0;
      final parsedAmt = _parseIntegerVnd(moneyMatch.group(3) ?? '');
      if (parsedAmt == null) continue;
      final absAmt = parsedAmt.abs();

      if (_isTotalLine(lower)) {
        statedTotal = absAmt;
        continue;
      }
      if (_isSubtotalLine(lower)) {
        continue;
      }
      if (_isVatLine(lower)) {
        vatMinor += absAmt;
        continue;
      }
      if (_isDiscountLine(lower) || parsedAmt < 0) {
        discountMinor += absAmt;
        continue;
      }
      if (_isSurchargeLine(lower)) {
        surchargeMinor += absAmt;
        continue;
      }

      if (rawLabel.isEmpty) continue;
      final unitMinor = qty > 0 ? (absAmt / qty).round() : absAmt;
      items.add(
        ParsedReceiptLineItem(
          id: 'item_${items.length + 1}',
          name: rawLabel,
          quantity: qty,
          unitPriceMinor: unitMinor,
          lineTotalMinor: absAmt,
          suggestedCategoryName: inferItemCategory(rawLabel, merchant),
        ),
      );
    }

    final itemsSubtotal = items.fold<int>(0, (s, e) => s + e.lineTotalMinor);
    final computedNet = itemsSubtotal > 0
        ? (itemsSubtotal + vatMinor + surchargeMinor - discountMinor)
        : (statedTotal ?? 0);
    final discrepancy = (statedTotal != null && itemsSubtotal > 0)
        ? (statedTotal - computedNet)
        : 0;

    return StructuredReceiptAnalysis(
      documentType: inferReceiptType(rawOcrText),
      merchantName: merchant,
      items: items,
      itemsSubtotalMinor: itemsSubtotal,
      vatMinor: vatMinor,
      surchargeMinor: surchargeMinor,
      discountMinor: discountMinor,
      statedTotalMinor: statedTotal,
      computedNetTotalMinor: computedNet > 0 ? computedNet : 0,
      discrepancyMinor: discrepancy,
    );
  }

  /// Computes exact per-member VND shares combining private assigned items, unassigned shared items,
  /// and proportional VAT/surcharge/discount distribution (`sum == analysis.effectiveTotalMinor`).
  static Map<String, int> computeItemizedGroupShares({
    required StructuredReceiptAnalysis analysis,
    required List<String> allParticipantIds,
  }) {
    if (allParticipantIds.isEmpty || analysis.effectiveTotalMinor <= 0) {
      return const <String, int>{};
    }
    final uniqueMembers = allParticipantIds.toSet().toList();
    final baseSubtotalByMember = <String, int>{
      for (final m in uniqueMembers) m: 0,
    };

    for (final item in analysis.items) {
      final assignees = item.assignedMemberIds
          .where(uniqueMembers.contains)
          .toList();
      final targetGroup = assignees.isNotEmpty ? assignees : uniqueMembers;
      final splitShares = _apportionBigIntEqual(
        item.lineTotalMinor,
        targetGroup.length,
      );
      for (var i = 0; i < targetGroup.length; i++) {
        baseSubtotalByMember[targetGroup[i]] =
            (baseSubtotalByMember[targetGroup[i]] ?? 0) + splitShares[i];
      }
    }

    final totalBase = baseSubtotalByMember.values.fold<int>(0, (a, b) => a + b);
    if (totalBase <= 0) {
      final eq = _apportionBigIntEqual(
        analysis.effectiveTotalMinor,
        uniqueMembers.length,
      );
      return <String, int>{
        for (var i = 0; i < uniqueMembers.length; i++) uniqueMembers[i]: eq[i],
      };
    }

    // Scale proportionally to `effectiveTotalMinor` (distributing VAT + surcharge - discount fairly!)
    final weights = uniqueMembers
        .map((m) => baseSubtotalByMember[m] ?? 0)
        .toList();
    final finalShares = _apportionBigIntWeighted(
      analysis.effectiveTotalMinor,
      weights,
    );
    return <String, int>{
      for (var i = 0; i < uniqueMembers.length; i++)
        uniqueMembers[i]: finalShares[i],
    };
  }

  static ReceiptDocumentType inferReceiptType(String text) {
    final l = text.toLowerCase();
    if (l.contains('chuyển khoản') ||
        l.contains('mã giao dịch') ||
        l.contains('vietqr') ||
        l.contains('thụ hưởng')) {
      return ReceiptDocumentType.bankTransferSlip;
    }
    if (l.contains('evn') ||
        l.contains('điện lực') ||
        l.contains('cấp nước') ||
        l.contains('sawaco') ||
        l.contains('viễn thông')) {
      return ReceiptDocumentType.utilityBill;
    }
    if (l.contains('head') ||
        l.contains('yamaha') ||
        l.contains('thay nhớt') ||
        l.contains('petrolimex') ||
        l.contains('gara')) {
      return ReceiptDocumentType.vehicleService;
    }
    if (l.contains('co.op') ||
        l.contains('winmart') ||
        l.contains('bách hóa') ||
        l.contains('aeon') ||
        l.contains('siêu thị')) {
      return ReceiptDocumentType.supermarket;
    }
    if (l.contains('nhà hàng') ||
        l.contains('coffee') ||
        l.contains('cà phê') ||
        l.contains('lẩu') ||
        l.contains('quán')) {
      return ReceiptDocumentType.restaurant;
    }
    return ReceiptDocumentType.shopping;
  }

  static String inferItemCategory(String itemName, String merchantName) {
    final l = '${itemName.toLowerCase()} ${merchantName.toLowerCase()}';
    if (l.contains('nước rửa') ||
        l.contains('bột giặt') ||
        l.contains('lau nhà') ||
        l.contains('khăn giấy') ||
        l.contains('túi rác')) {
      return 'Việc nhà & Gia dụng';
    }
    if (l.contains('điện') || l.contains('nước máy') || l.contains('internet')) {
      return 'Điện/Nước/Internet';
    }
    if (l.contains('nhớt') || l.contains('xăng') || l.contains('lốp xe')) {
      return 'Xe cộ & Di chuyển';
    }
    if (l.contains('thuốc') || l.contains('vitamin') || l.contains('khẩu trang')) {
      return 'Sức khỏe & Giáo dục';
    }
    if (l.contains('thịt') ||
        l.contains('rau') ||
        l.contains('sữa') ||
        l.contains('cơm') ||
        l.contains('phở') ||
        l.contains('cà phê') ||
        l.contains('trà')) {
      return 'Ăn uống';
    }
    return 'Chợ & Mua sắm';
  }

  static bool _isTotalLine(String l) =>
      l.contains('tổng cộng') ||
      l.contains('tổng thanh toán') ||
      l.contains('thành tiền') ||
      l.startsWith('tổng:') ||
      l.startsWith('total');

  static bool _isSubtotalLine(String l) =>
      l.contains('tạm tính') || l.contains('subtotal');

  static bool _isVatLine(String l) =>
      l.contains('vat') || l.contains('thuế gtgt');

  static bool _isDiscountLine(String l) =>
      l.contains('giảm giá') ||
      l.contains('chiết khấu') ||
      l.contains('khuyến mãi') ||
      l.contains('voucher');

  static bool _isSurchargeLine(String l) =>
      l.contains('phí phục vụ') ||
      l.contains('phụ thu') ||
      l.contains('phí giao hàng');

  static int? _parseIntegerVnd(String token) {
    final neg = token.trim().startsWith('-');
    final digits = token.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final val = int.tryParse(digits);
    if (val == null) return null;
    return neg ? -val : val;
  }

  static List<int> _apportionBigIntEqual(int total, int count) =>
      _apportionBigIntWeighted(total, List<int>.filled(count, 1));

  static List<int> _apportionBigIntWeighted(int total, List<int> weights) {
    if (weights.isEmpty) return const <int>[];
    if (total <= 0) return List<int>.filled(weights.length, 0);
    final weightSum = weights.fold<BigInt>(
      BigInt.zero,
      (s, w) => s + BigInt.from(w > 0 ? w : 0),
    );
    if (weightSum <= BigInt.zero) {
      return _apportionBigIntWeighted(total, List<int>.filled(weights.length, 1));
    }

    final bigTotal = BigInt.from(total);
    final floors = List<int>.filled(weights.length, 0);
    final rems = <({int idx, BigInt rem})>[];
    var allocated = 0;

    for (var i = 0; i < weights.length; i++) {
      final w = BigInt.from(weights[i] > 0 ? weights[i] : 0);
      final prod = bigTotal * w;
      final q = (prod ~/ weightSum).toInt();
      final r = prod % weightSum;
      floors[i] = q;
      allocated += q;
      rems.add((idx: i, rem: r));
    }

    final leftover = total - allocated;
    rems.sort((a, b) {
      final cmp = b.rem.compareTo(a.rem);
      return cmp != 0 ? cmp : a.idx.compareTo(b.idx);
    });
    for (var k = 0; k < leftover; k++) {
      floors[rems[k % rems.length].idx] += 1;
    }
    return floors;
  }
}
