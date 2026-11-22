import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/error/app_exception.dart';

class SePayRawBankTransaction {
  final String externalId;
  final String bankBrandName;
  final String accountNumber;
  final String direction; // 'credit' | 'debit'
  final int amountMinor;
  final int? accumulatedBalanceMinor;
  final String content;
  final String? referenceCode;
  final DateTime occurredAt;

  const SePayRawBankTransaction({
    required this.externalId,
    required this.bankBrandName,
    required this.accountNumber,
    required this.direction,
    required this.amountMinor,
    this.accumulatedBalanceMinor,
    required this.content,
    this.referenceCode,
    required this.occurredAt,
  });
}

/// Official SePay User REST API v1 client (`https://my.sepay.vn/userapi/transactions/list`).
class SePayApiDataSource {
  static const String baseUrl = 'https://my.sepay.vn/userapi';

  final http.Client _httpClient;

  SePayApiDataSource({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  static int _parseSePayDecimalVnd(Object? raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.round();
    final clean = raw.toString().trim();
    if (clean.isEmpty) return 0;
    // SePay returns strings like "500000.00" or "0.00"
    final doubleVal = double.tryParse(clean.replaceAll(',', ''));
    if (doubleVal != null) return doubleVal.round();
    final digits = clean.replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(digits) ?? 0;
  }

  static DateTime _parseSePayDateTime(Object? raw) {
    if (raw == null) return DateTime.now();
    final text = raw.toString().trim();
    if (text.isEmpty) return DateTime.now();
    // SePay standard format: "YYYY-MM-DD HH:mm:ss" (Vietnam GMT+7)
    final normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized) ?? DateTime.now();
  }

  Future<List<SePayRawBankTransaction>> fetchRecentTransactions({
    required String apiToken,
    int limit = 40,
  }) async {
    final token = apiToken.trim();
    if (token.isEmpty) {
      throw const AppException(
        code: 'VALIDATION_FAILURE',
        message: 'Vui lòng nhập SePay API Token (từ my.sepay.vn → Cấu hình Công ty → API Access).',
      );
    }

    final uri = Uri.parse('$baseUrl/transactions/list?limit=$limit');
    final http.Response res;
    try {
      res = await _httpClient
          .get(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const AppException(
        code: 'NETWORK_FAILURE',
        message: 'Không thể kết nối máy chủ SePay (my.sepay.vn). Kiểm tra kết nối Internet.',
      );
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const AppException(
        code: 'PERMISSION_DENIED',
        message: 'SePay API Token không hợp lệ hoặc đã hết hạn.',
      );
    }
    if (res.statusCode == 429) {
      throw const AppException(
        code: 'CONFLICT_FAILURE',
        message: 'SePay giới hạn tần suất gọi API. Vui lòng thử lại sau ít giây.',
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppException(
        code: 'UNEXPECTED_FAILURE',
        message: 'Máy chủ SePay trả về mã HTTP ${res.statusCode}.',
      );
    }

    final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const AppException(
        code: 'UNEXPECTED_FAILURE',
        message: 'Định dạng phản hồi JSON từ SePay không hợp lệ.',
      );
    }

    final rawList = decoded['transactions'];
    if (rawList is! List) {
      return const <SePayRawBankTransaction>[];
    }

    final parsed = <SePayRawBankTransaction>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;

      final amountIn = _parseSePayDecimalVnd(item['amount_in']);
      final amountOut = _parseSePayDecimalVnd(item['amount_out']);
      if (amountIn <= 0 && amountOut <= 0) continue;

      final direction = amountIn > 0 ? 'credit' : 'debit';
      final amountMinor = amountIn > 0 ? amountIn : amountOut;
      final accumRaw = item['accumulated'];
      final accum = accumRaw != null ? _parseSePayDecimalVnd(accumRaw) : null;
      final brand = (item['bank_brand_name'] ?? 'Bank').toString().trim();
      final accNo = (item['account_number'] ?? '').toString().trim();
      final content = (item['transaction_content'] ?? item['content'] ?? 'Giao dịch SePay')
          .toString()
          .trim();
      final refCode = (item['reference_number'] ?? item['code'] ?? '').toString().trim();

      parsed.add(
        SePayRawBankTransaction(
          externalId: 'sepay_$id',
          bankBrandName: brand,
          accountNumber: accNo,
          direction: direction,
          amountMinor: amountMinor,
          accumulatedBalanceMinor: (accum != null && accum > 0) ? accum : null,
          content: content.isEmpty ? 'Giao dịch $brand' : content,
          referenceCode: refCode.isEmpty ? null : refCode,
          occurredAt: _parseSePayDateTime(item['transaction_date']),
        ),
      );
    }

    // Sort oldest -> newest so wallet running balances replay chronologically
    parsed.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return parsed;
  }
}
