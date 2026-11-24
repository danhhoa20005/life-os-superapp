import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/error/app_exception.dart';
import '../../../../core/services/native_secure_vault_bridge.dart';
import '../../../../core/utils/smart_omni_intent_parser.dart';
import '../../../daily_life/domain/entities/daily_life_entities.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../domain/entities/gemini_copilot_entities.dart';

/// Privacy-safe Gemini Developer REST API DataSource (`generativelanguage.googleapis.com`).
/// - API keys live strictly inside hardware-backed `NativeSecureVaultBridge` (Android Keystore AES-256-GCM).
/// - Sent via `x-goog-api-key` HTTP header (never appended to URL query strings, never logged).
class GeminiRemoteDataSource {
  static const String _keyApiKey = 'gemini_ai_api_key_v1';
  static const String _keyConfigJson = 'gemini_ai_config_v1';

  final http.Client _httpClient;
  final NativeSecureVaultBridge _vault;

  GeminiRemoteDataSource({
    http.Client? httpClient,
    NativeSecureVaultBridge? vault,
  }) : _httpClient = httpClient ?? http.Client(),
       _vault = vault ?? NativeSecureVaultBridge.instance;

  Future<GeminiConnectionConfig> readConfig() async {
    final storedKey = await _vault.readSecret(_keyApiKey);
    final hasKey = storedKey != null && storedKey.trim().isNotEmpty;
    final masked = hasKey ? GeminiConnectionConfig.maskKey(storedKey) : '';

    final rawCfg = await _vault.readSecret(_keyConfigJson);
    if (rawCfg == null || rawCfg.trim().isEmpty) {
      return GeminiConnectionConfig(
        enabled: hasKey,
        hasApiKey: hasKey,
        maskedApiKey: masked,
      );
    }

    try {
      final map = jsonDecode(rawCfg) as Map<String, dynamic>;
      final verifiedIso = map['lastVerifiedAt'] as String?;
      return GeminiConnectionConfig(
        enabled: (map['enabled'] as bool?) ?? hasKey,
        hasApiKey: hasKey,
        maskedApiKey: masked,
        modelId:
            (map['modelId'] as String?) ?? GeminiModelPreset.flash25.modelId,
        maskSensitiveInfo: (map['maskSensitiveInfo'] as bool?) ?? true,
        lastVerifiedAt: verifiedIso != null
            ? DateTime.tryParse(verifiedIso)
            : null,
      );
    } catch (_) {
      return GeminiConnectionConfig(
        enabled: hasKey,
        hasApiKey: hasKey,
        maskedApiKey: masked,
      );
    }
  }

  Future<GeminiConnectionConfig> writeConfig({
    String? newApiKey,
    bool? enabled,
    String? modelId,
    bool? maskSensitiveInfo,
    DateTime? lastVerifiedAt,
  }) async {
    final current = await readConfig();
    if (newApiKey != null && newApiKey.trim().isNotEmpty) {
      await _vault.writeSecret(key: _keyApiKey, value: newApiKey.trim());
    }
    final storedKey = await _vault.readSecret(_keyApiKey);
    final hasKey = storedKey != null && storedKey.trim().isNotEmpty;

    final next = current.copyWith(
      enabled: enabled ?? (newApiKey != null && hasKey ? true : current.enabled),
      hasApiKey: hasKey,
      maskedApiKey: hasKey ? GeminiConnectionConfig.maskKey(storedKey) : '',
      modelId: modelId ?? current.modelId,
      maskSensitiveInfo: maskSensitiveInfo ?? current.maskSensitiveInfo,
      lastVerifiedAt: lastVerifiedAt ?? current.lastVerifiedAt,
    );

    await _vault.writeSecret(
      key: _keyConfigJson,
      value: jsonEncode(<String, dynamic>{
        'enabled': next.enabled,
        'modelId': next.modelId,
        'maskSensitiveInfo': next.maskSensitiveInfo,
        if (next.lastVerifiedAt != null)
          'lastVerifiedAt': next.lastVerifiedAt!.toIso8601String(),
      }),
    );

    return next;
  }

  Future<GeminiConnectionConfig> clearKeyAndDisable() async {
    await _vault.deleteSecret(_keyApiKey);
    await _vault.deleteSecret(_keyConfigJson);
    return const GeminiConnectionConfig();
  }

  Future<String> verifyConnection({
    String? candidateApiKey,
    String? modelId,
    DateTime? now,
  }) async {
    final storedKey = await _vault.readSecret(_keyApiKey);
    final apiKey = (candidateApiKey != null && candidateApiKey.trim().isNotEmpty)
        ? candidateApiKey.trim()
        : (storedKey ?? '').trim();

    if (apiKey.isEmpty) {
      throw const AppException(
        code: 'GEMINI_KEY_MISSING',
        message: 'Vui lòng nhập khóa Gemini API trước khi kiểm tra kết nối.',
      );
    }

    final current = await readConfig();
    final targetModel = (modelId != null && modelId.trim().isNotEmpty)
        ? modelId.trim()
        : current.modelId;

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$targetModel:generateContent',
    );

    final body = jsonEncode(<String, dynamic>{
      'generationConfig': <String, dynamic>{
        'responseMimeType': 'application/json',
        'temperature': 0.0,
      },
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'text': 'Trả về JSON {"status":"ok","message":"Kết nối thành công"}',
            },
          ],
        },
      ],
    });

    http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'x-goog-api-key': apiKey,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const AppException(
        code: 'GEMINI_TIMEOUT',
        message: 'Phản hồi quá thời gian chờ; vui lòng kiểm tra mạng Internet.',
      );
    } catch (_) {
      throw const AppException(
        code: 'GEMINI_OFFLINE',
        message: 'Không thể kết nối mạng; ứng dụng vẫn hoạt động Offline 100%.',
      );
    }

    if (response.statusCode != 200) {
      throw AppException(
        code: 'GEMINI_HTTP_${response.statusCode}',
        message: _mapHttpStatusMessage(response.statusCode),
      );
    }

    await writeConfig(
      newApiKey: candidateApiKey,
      enabled: true,
      modelId: targetModel,
      lastVerifiedAt: now ?? DateTime.now(),
    );

    return 'Đã kết nối Gemini AI ($targetModel) thành công!';
  }

  Future<({
    String sanitizedPrompt,
    String assistantInsightVi,
    List<OmniActionDraft> drafts,
  })> generateMultiDomainPlan({
    required String rawInput,
    required GeminiConnectionConfig config,
    required DateTime referenceNow,
    GeminiContextSnapshot? contextSnapshot,
  }) async {
    final apiKey = (await _vault.readSecret(_keyApiKey) ?? '').trim();
    if (apiKey.isEmpty) {
      throw const AppException(
        code: 'GEMINI_KEY_MISSING',
        message: 'Chưa cấu hình khóa Gemini API.',
      );
    }

    final safeInput = config.maskSensitiveInfo
        ? GeminiPrivacySanitizer.sanitize(rawInput)
        : rawInput;

    final contextLine = contextSnapshot == null
        ? ''
        : '\nNgữ cảnh tóm tắt ẩn danh (VND nguyên): Thu tháng=${contextSnapshot.monthlyIncomeMinor}, '
              'Chi tháng=${contextSnapshot.monthlyExpenseMinor}, '
              'Mức an toàn/ngày=${contextSnapshot.safeDailyAllowanceMinor}, '
              'Lịch sắp tới=${contextSnapshot.upcomingEventsCount}, '
              'Việc đang mở=${contextSnapshot.openTasksCount}, '
              'Thói quen=${contextSnapshot.topHabitLabels.join(", ")}.';

    final systemPrompt =
        'Bạn là Trợ lý Tài chính & Nhịp sống thông minh của siêu ứng dụng Life OS tại Việt Nam. '
        'Thời điểm tham chiếu hiện tại: ${referenceNow.toIso8601String()}.$contextLine\n'
        'Nhiệm vụ: Phân tích câu tiếng Việt tự nhiên của người dùng thành JSON cấu trúc chặt chẽ gồm:\n'
        '1. "assistantInsightVi": Nhận xét hoặc lời khuyên ngắn gọn, ấm áp, hữu ích (1-2 câu tiếng Việt, không dùng thuật ngữ kỹ thuật).\n'
        '2. "transactions": Mảng các giao dịch thu/chi [{"type":"expense"|"income","amountMinor":số_nguyên_VND,"categoryName":"Ăn uống"|"Xe cộ & Di chuyển"|"Điện/Nước/Internet"|"Chợ & Mua sắm"|"Việc nhà & Gia dụng"|"Nhà cửa & Thuê nhà"|"Sức khỏe & Giáo dục"|"Giải trí & Đăng ký"|"Lương & Thu nhập"|"Chi tiêu khác","merchant":"mô tả ngắn"}]. Lưu ý: 55k = 55000, 1tr5 = 1500000. Không tạo giao dịch nếu câu chỉ hỏi thông tin hoặc báo hủy.\n'
        '3. "groupSplits": Mảng chia hóa đơn nhóm [{"title":"mô tả","amountMinor":số_nguyên_VND,"participantCount":số_người>=2}].\n'
        '4. "calendarEvents": Mảng lịch hẹn có thời gian cụ thể [{"title":"tiêu đề","startsAtIso":"ISO8601","durationMinutes":60,"location":""}].\n'
        '5. "tasks": Mảng việc cần làm / nhắc nhở [{"title":"tiêu đề","dueAtIso":"ISO8601","priority":"low"|"medium"|"high"}].\n'
        '6. "groceries": Mảng món cần mua đi chợ khi chưa thanh toán tiền [{"name":"tên món","quantityLabel":"1 phần","estimatedMinor":0}].\n'
        '7. "waterLogs": Mảng lượng nước lọc uống vào cơ thể [{"waterMl":250}].\n'
        '8. "medications": Mảng lịch nhắc uống thuốc/vitamin [{"name":"tên thuốc","dosage":"1 viên sau ăn","slot":"morning"|"noon"|"evening","hour":8,"minute":0}].';

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/${config.modelId}:generateContent',
    );

    final payload = jsonEncode(<String, dynamic>{
      'systemInstruction': <String, dynamic>{
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{'text': systemPrompt},
        ],
      },
      'generationConfig': <String, dynamic>{
        'responseMimeType': 'application/json',
        'temperature': 0.15,
      },
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': safeInput},
          ],
        },
      ],
    });

    http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'x-goog-api-key': apiKey,
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const AppException(
        code: 'GEMINI_TIMEOUT',
        message: 'Gemini phản hồi chậm; đã tự động chuyển sang AI Trên máy.',
      );
    } catch (_) {
      throw const AppException(
        code: 'GEMINI_OFFLINE',
        message: 'Thiết bị đang ngoại tuyến; đã xử lý tức thì bằng AI Trên máy.',
      );
    }

    if (response.statusCode != 200) {
      throw AppException(
        code: 'GEMINI_HTTP_${response.statusCode}',
        message: _mapHttpStatusMessage(response.statusCode),
      );
    }

    final decodedEnvelope =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final rawText = _extractCandidateText(decodedEnvelope);
    final parsedJson = _decodeJsonBody(rawText);

    final insight =
        (parsedJson['assistantInsightVi'] as String?)?.trim().isNotEmpty == true
        ? (parsedJson['assistantInsightVi'] as String).trim()
        : 'Đã bóc tách thông minh các tác vụ từ câu lệnh của bạn.';

    final drafts = _parseActionDraftsFromJson(
      parsedJson,
      referenceNow: referenceNow,
    );

    return (
      sanitizedPrompt: safeInput,
      assistantInsightVi: insight,
      drafts: drafts,
    );
  }

  String _extractCandidateText(Map<String, dynamic> envelope) {
    final candidates = envelope['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final first = candidates.first;
      if (first is Map) {
        final content = first['content'];
        if (content is Map) {
          final parts = content['parts'];
          if (parts is List && parts.isNotEmpty) {
            final part0 = parts.first;
            if (part0 is Map && part0['text'] is String) {
              return part0['text'] as String;
            }
          }
        }
      }
    }
    throw const AppException(
      code: 'GEMINI_EMPTY_CANDIDATE',
      message: 'Phản hồi từ Gemini trống; đã chuyển sang bộ phân tích Trên máy.',
    );
  }

  Map<String, dynamic> _decodeJsonBody(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    final decoded = jsonDecode(cleaned);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const AppException(
      code: 'GEMINI_INVALID_JSON',
      message: 'Định dạng dữ liệu Gemini không khớp; đã dùng AI Trên máy.',
    );
  }

  List<OmniActionDraft> _parseActionDraftsFromJson(
    Map<String, dynamic> json, {
    required DateTime referenceNow,
  }) {
    final out = <OmniActionDraft>[];
    var idx = 0;

    final txs = json['transactions'];
    if (txs is List) {
      for (final item in txs.whereType<Map<dynamic, dynamic>>()) {
        final amt = (item['amountMinor'] as num?)?.toInt() ?? 0;
        if (amt <= 0) continue;
        final typeStr = ((item['type'] as String?) ?? 'expense').toLowerCase();
        final isIncome = typeStr == 'income';
        final catName =
            ((item['categoryName'] as String?) ?? '').trim().isNotEmpty
            ? (item['categoryName'] as String).trim()
            : (isIncome ? 'Lương & Thu nhập' : 'Chi tiêu khác');
        final merchant =
            ((item['merchant'] as String?) ?? '').trim().isNotEmpty
            ? (item['merchant'] as String).trim()
            : catName;
        out.add(
          OmniActionDraft(
            id: 'gemini_tx_${idx++}',
            kind: OmniActionKind.transaction,
            title: merchant,
            amountMinor: amt,
            transactionKind: isIncome
                ? TransactionKind.income
                : TransactionKind.expense,
            categoryId: _mapCategoryNameToId(catName, isIncome: isIncome),
            categoryName: catName,
            originLabel: 'Gemini AI',
          ),
        );
      }
    }

    final splits = json['groupSplits'];
    if (splits is List) {
      for (final item in splits.whereType<Map<dynamic, dynamic>>()) {
        final amt = (item['amountMinor'] as num?)?.toInt() ?? 0;
        if (amt <= 0) continue;
        final count = ((item['participantCount'] as num?)?.toInt() ?? 2).clamp(
          2,
          30,
        );
        final title = ((item['title'] as String?) ?? '').trim().isNotEmpty
            ? (item['title'] as String).trim()
            : 'Chia hóa đơn nhóm';
        out.add(
          OmniActionDraft(
            id: 'gemini_split_${idx++}',
            kind: OmniActionKind.groupSplit,
            title: title,
            amountMinor: amt,
            participantCount: count,
            categoryId: 'cat_food',
            categoryName: 'Ăn uống',
            originLabel: 'Gemini AI',
          ),
        );
      }
    }

    final events = json['calendarEvents'];
    if (events is List) {
      for (final item in events.whereType<Map<dynamic, dynamic>>()) {
        final title = ((item['title'] as String?) ?? '').trim();
        if (title.length < 2) continue;
        final startsIso = item['startsAtIso'] as String?;
        final startsAt =
            (startsIso != null ? DateTime.tryParse(startsIso)?.toLocal() : null) ??
            DateTime(
              referenceNow.year,
              referenceNow.month,
              referenceNow.day + 1,
              9,
            );
        final duration = ((item['durationMinutes'] as num?)?.toInt() ?? 60)
            .clamp(15, 720);
        final loc = (item['location'] as String?)?.trim();
        out.add(
          OmniActionDraft(
            id: 'gemini_event_${idx++}',
            kind: OmniActionKind.calendarEvent,
            title: title,
            scheduledAt: startsAt,
            durationMinutes: duration,
            location: (loc != null && loc.isNotEmpty) ? loc : null,
            originLabel: 'Gemini AI',
          ),
        );
      }
    }

    final tasks = json['tasks'];
    if (tasks is List) {
      for (final item in tasks.whereType<Map<dynamic, dynamic>>()) {
        final title = ((item['title'] as String?) ?? '').trim();
        if (title.length < 2) continue;
        final dueIso = item['dueAtIso'] as String?;
        final dueAt = dueIso != null
            ? DateTime.tryParse(dueIso)?.toLocal()
            : DateTime(
                referenceNow.year,
                referenceNow.month,
                referenceNow.day,
                20,
              );
        final prioRaw = ((item['priority'] as String?) ?? 'medium')
            .toLowerCase();
        final prio = switch (prioRaw) {
          'high' => TaskPriorityLevel.high,
          'low' => TaskPriorityLevel.low,
          _ => TaskPriorityLevel.medium,
        };
        out.add(
          OmniActionDraft(
            id: 'gemini_task_${idx++}',
            kind: OmniActionKind.task,
            title: title,
            scheduledAt: dueAt,
            taskPriority: prio,
            originLabel: 'Gemini AI',
          ),
        );
      }
    }

    final groceries = json['groceries'];
    if (groceries is List) {
      for (final item in groceries.whereType<Map<dynamic, dynamic>>()) {
        final name = ((item['name'] as String?) ?? '').trim();
        if (name.length < 2) continue;
        final qty = ((item['quantityLabel'] as String?) ?? '').trim().isNotEmpty
            ? (item['quantityLabel'] as String).trim()
            : '1 phần';
        final est = ((item['estimatedMinor'] as num?)?.toInt() ?? 0).clamp(
          0,
          500000000,
        );
        out.add(
          OmniActionDraft(
            id: 'gemini_grocery_${idx++}',
            kind: OmniActionKind.grocery,
            title: name,
            quantityLabel: qty,
            amountMinor: est,
            originLabel: 'Gemini AI',
          ),
        );
      }
    }

    final waterLogs = json['waterLogs'];
    if (waterLogs is List) {
      for (final item in waterLogs.whereType<Map<dynamic, dynamic>>()) {
        final ml = ((item['waterMl'] as num?)?.toInt() ?? 250).clamp(50, 3000);
        out.add(
          OmniActionDraft(
            id: 'gemini_water_${idx++}',
            kind: OmniActionKind.waterLog,
            title: 'Nước lọc',
            waterMl: ml,
            originLabel: 'Gemini AI',
          ),
        );
      }
    }

    final meds = json['medications'];
    if (meds is List) {
      for (final item in meds.whereType<Map<dynamic, dynamic>>()) {
        final name = ((item['name'] as String?) ?? '').trim();
        if (name.length < 2) continue;
        final dosage = ((item['dosage'] as String?) ?? '').trim().isNotEmpty
            ? (item['dosage'] as String).trim()
            : '1 viên sau ăn';
        final slot = MedicationScheduleSlot.fromName(item['slot'] as String?);
        final h = ((item['hour'] as num?)?.toInt() ?? slot.defaultHour).clamp(
          0,
          23,
        );
        final m = ((item['minute'] as num?)?.toInt() ?? slot.defaultMinute)
            .clamp(0, 59);
        out.add(
          OmniActionDraft(
            id: 'gemini_med_${idx++}',
            kind: OmniActionKind.medication,
            title: name,
            dosage: dosage,
            medicationSlot: slot,
            scheduledAt: DateTime(
              referenceNow.year,
              referenceNow.month,
              referenceNow.day,
              h,
              m,
            ),
            originLabel: 'Gemini AI',
          ),
        );
      }
    }

    return out;
  }

  String _mapCategoryNameToId(String name, {required bool isIncome}) {
    if (isIncome) return 'cat_salary';
    final lower = name.toLowerCase();
    if (lower.contains('ăn') || lower.contains('uống')) return 'cat_food';
    if (lower.contains('xe') || lower.contains('di chuyển')) {
      return 'cat_vehicle';
    }
    if (lower.contains('điện') ||
        lower.contains('nước') ||
        lower.contains('internet')) {
      return 'cat_utilities';
    }
    if (lower.contains('chợ') || lower.contains('mua sắm')) {
      return 'cat_shopping';
    }
    if (lower.contains('việc nhà') || lower.contains('gia dụng')) {
      return 'cat_housework';
    }
    if (lower.contains('nhà cửa') || lower.contains('thuê nhà')) {
      return 'cat_housing';
    }
    if (lower.contains('sức khỏe') || lower.contains('giáo dục')) {
      return 'cat_health';
    }
    if (lower.contains('giải trí')) return 'cat_entertainment';
    return 'cat_other_exp';
  }

  String _mapHttpStatusMessage(int statusCode) {
    return switch (statusCode) {
      400 || 401 || 403 =>
        'Khóa Gemini API chưa hợp lệ hoặc chưa được kích hoạt.',
      429 =>
        'Tạm chạm hạn mức gọi miễn phí của Gemini; hệ thống đã tự chuyển sang AI Trên máy.',
      >= 500 =>
        'Máy chủ Gemini đang bận; hệ thống đã tự chuyển sang AI Trên máy.',
      _ => 'Không thể gọi Gemini (mã $statusCode); đã dùng AI Trên máy.',
    };
  }
}
