import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/error/app_exception.dart';
import '../../../../core/security/bank_notification_parser.dart';
import '../../../../core/services/native_secure_vault_bridge.dart';
import '../../../../core/utils/smart_omni_intent_parser.dart';
import '../../../tasks/domain/entities/task_entities.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../domain/entities/gemini_copilot_entities.dart';

/// Privacy-safe Gemini Developer REST API DataSource (`generativelanguage.googleapis.com`).
/// - API keys live strictly inside hardware-backed `NativeSecureVaultBridge` (Android Keystore AES-256-GCM).
/// - Sent via `x-goog-api-key` HTTP header (never appended to URL query strings, never logged).
class GeminiRemoteDataSource {
  static const String _legacyKeyApiKey = 'gemini_ai_api_key_v1';
  static const String _legacyKeyConfigJson = 'gemini_ai_config_v1';
  static const String _scopedKeyPrefixApiKey = 'gemini_ai_api_key_v2__u_';
  static const String _scopedKeyPrefixConfigJson = 'gemini_ai_config_v2__u_';

  final http.Client _httpClient;
  final NativeSecureVaultBridge _vault;
  String? _activeUserId;
  bool _userScopingConfigured;
  bool _cloudAiConsentGranted = false;

  GeminiRemoteDataSource({
    http.Client? httpClient,
    NativeSecureVaultBridge? vault,
    String? initialUserId,
  }) : _httpClient = httpClient ?? http.Client(),
       _vault = vault ?? NativeSecureVaultBridge.instance,
       _activeUserId = initialUserId,
       _userScopingConfigured = initialUserId != null;

  /// Explicit Cloud AI opt-in consent state for the most recently loaded or saved config.
  bool get cloudAiConsentGranted => _cloudAiConsentGranted;

  void setActiveUserId(String? userId) {
    _userScopingConfigured = true;
    _activeUserId = userId?.trim();
  }

  String? _resolveUid(String? userId) {
    if (userId != null) {
      final trimmed = userId.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (_userScopingConfigured) {
      final candidate = _activeUserId?.trim();
      if (candidate == null || candidate.isEmpty) return null;
      return candidate;
    }
    return '__standalone_test_user__';
  }

  String _apiKeyVaultKey(String uid) => '$_scopedKeyPrefixApiKey$uid';
  String _configVaultKey(String uid) => '$_scopedKeyPrefixConfigJson$uid';

  Future<void> _purgeLegacyUnscopedKeys() async {
    await _vault.deleteSecret(_legacyKeyApiKey);
    await _vault.deleteSecret(_legacyKeyConfigJson);
  }

  Future<GeminiConnectionConfig> readConfig({String? userId}) async {
    // Purge legacy device-global keys so unscoped credentials never leak across accounts
    // and require explicit per-account re-linking.
    await _purgeLegacyUnscopedKeys();

    final uid = _resolveUid(userId);
    if (uid == null) {
      _cloudAiConsentGranted = false;
      return const GeminiConnectionConfig(
        enabled: false,
        hasApiKey: false,
        maskedApiKey: '',
      );
    }

    final storedKey = await _vault.readSecret(_apiKeyVaultKey(uid));
    final hasKey = storedKey != null && storedKey.trim().isNotEmpty;
    final masked = hasKey ? GeminiConnectionConfig.maskKey(storedKey) : '';

    final rawCfg = await _vault.readSecret(_configVaultKey(uid));
    if (rawCfg == null || rawCfg.trim().isEmpty) {
      _cloudAiConsentGranted = false;
      return GeminiConnectionConfig(
        enabled: false,
        hasApiKey: hasKey,
        maskedApiKey: masked,
      );
    }

    try {
      final map = jsonDecode(rawCfg) as Map<String, dynamic>;
      final verifiedIso = map['lastVerifiedAt'] as String?;
      final storedEnabled = map['enabled'] as bool?;
      final hasExplicitConsentField = map.containsKey('cloudAiConsentGranted');
      // Backward compatibility: older configs that explicitly saved `enabled: true`
      // prior to `cloudAiConsentGranted` retain consent, while new configs default to false.
      final consentGranted = hasExplicitConsentField
          ? (map['cloudAiConsentGranted'] == true)
          : (storedEnabled == true);
      _cloudAiConsentGranted = consentGranted;
      final effectiveEnabled = (storedEnabled == true) && consentGranted;

      return GeminiConnectionConfig(
        enabled: effectiveEnabled,
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
      _cloudAiConsentGranted = false;
      return GeminiConnectionConfig(
        enabled: false,
        hasApiKey: hasKey,
        maskedApiKey: masked,
      );
    }
  }

  Future<bool> readCloudAiConsent({String? userId}) async {
    await readConfig(userId: userId);
    return _cloudAiConsentGranted;
  }

  Future<GeminiConnectionConfig> writeConfig({
    String? userId,
    String? newApiKey,
    bool? enabled,
    bool? cloudAiConsentGranted,
    String? modelId,
    bool? maskSensitiveInfo,
    DateTime? lastVerifiedAt,
  }) async {
    await _purgeLegacyUnscopedKeys();
    final uid = _resolveUid(userId);
    if (uid == null) {
      throw const AppException(
        code: 'GEMINI_AUTH_REQUIRED',
        message:
            'Vui lòng đăng nhập tài khoản trước khi lưu khóa kết nối Gemini.',
      );
    }

    final current = await readConfig(userId: uid);
    final currentConsent = _cloudAiConsentGranted;
    if (newApiKey != null && newApiKey.trim().isNotEmpty) {
      await _vault.writeSecret(
        key: _apiKeyVaultKey(uid),
        value: newApiKey.trim(),
      );
    }
    final storedKey = await _vault.readSecret(_apiKeyVaultKey(uid));
    final hasKey = storedKey != null && storedKey.trim().isNotEmpty;

    final bool nextConsent;
    if (cloudAiConsentGranted != null) {
      nextConsent = cloudAiConsentGranted;
    } else if (enabled != null) {
      nextConsent = enabled;
    } else {
      nextConsent = currentConsent;
    }

    final bool nextEnabled;
    if (!nextConsent) {
      nextEnabled = false;
    } else if (enabled != null) {
      nextEnabled = enabled;
    } else if (cloudAiConsentGranted == true && hasKey) {
      nextEnabled = true;
    } else {
      nextEnabled = current.enabled;
    }

    _cloudAiConsentGranted = nextConsent;
    final next = current.copyWith(
      enabled: nextEnabled,
      hasApiKey: hasKey,
      maskedApiKey: hasKey ? GeminiConnectionConfig.maskKey(storedKey) : '',
      modelId: modelId ?? current.modelId,
      maskSensitiveInfo: maskSensitiveInfo ?? current.maskSensitiveInfo,
      lastVerifiedAt: lastVerifiedAt ?? current.lastVerifiedAt,
    );

    await _vault.writeSecret(
      key: _configVaultKey(uid),
      value: jsonEncode(<String, dynamic>{
        'ownerUserId': uid,
        'enabled': next.enabled,
        'cloudAiConsentGranted': nextConsent,
        'modelId': next.modelId,
        'maskSensitiveInfo': next.maskSensitiveInfo,
        if (next.lastVerifiedAt != null)
          'lastVerifiedAt': next.lastVerifiedAt!.toIso8601String(),
      }),
    );

    return next;
  }

  Future<GeminiConnectionConfig> clearKeyAndDisable({String? userId}) async {
    await _purgeLegacyUnscopedKeys();
    _cloudAiConsentGranted = false;
    final uid = _resolveUid(userId);
    if (uid != null) {
      await _vault.deleteSecret(_apiKeyVaultKey(uid));
      await _vault.deleteSecret(_configVaultKey(uid));
    }
    return const GeminiConnectionConfig();
  }

  Future<String> verifyConnection({
    String? userId,
    String? candidateApiKey,
    String? modelId,
    DateTime? now,
  }) async {
    await _purgeLegacyUnscopedKeys();
    final uid = _resolveUid(userId);
    final storedKey = uid != null
        ? await _vault.readSecret(_apiKeyVaultKey(uid))
        : null;
    final apiKey =
        (candidateApiKey != null && candidateApiKey.trim().isNotEmpty)
        ? candidateApiKey.trim()
        : (storedKey ?? '').trim();

    if (apiKey.isEmpty) {
      throw const AppException(
        code: 'GEMINI_KEY_MISSING',
        message: 'Vui lòng nhập khóa Gemini API trước khi kiểm tra kết nối.',
      );
    }

    final current = await readConfig(userId: uid);
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
              'text':
                  'Trả về JSON {"status":"ok","message":"Kết nối thành công"}',
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

    if (uid != null) {
      await writeConfig(
        userId: uid,
        newApiKey: candidateApiKey,
        enabled: true,
        modelId: targetModel,
        lastVerifiedAt: now ?? DateTime.now(),
      );
    }

    return 'Đã kết nối Gemini AI ($targetModel) thành công!';
  }

  /// Builds the privacy-minimized prompt components before sending any request
  /// to Gemini Cloud. When [maskSensitiveInfo] is true (default), raw personal
  /// habit titles are omitted and PII (emails/phones/bank accounts/OTP) is redacted.
  @visibleForTesting
  static ({String safeInput, String contextLine, String systemPrompt})
  buildSanitizedPromptPayload({
    required String rawInput,
    required bool maskSensitiveInfo,
    required DateTime referenceNow,
    GeminiContextSnapshot? contextSnapshot,
  }) {
    // SEC-F04: ALWAYS run OtpRedactor even if maskSensitiveInfo toggle is off!
    final safeInput = maskSensitiveInfo
        ? GeminiPrivacySanitizer.sanitize(rawInput)
        : OtpRedactor.redact(rawInput);

    final String contextLine;
    if (contextSnapshot == null) {
      contextLine = '';
    } else if (maskSensitiveInfo) {
      // PRIV-01: Minimize outgoing context by omitting raw personal habit labels.
      contextLine =
          '\nNgữ cảnh tóm tắt ẩn danh (VND nguyên): Thu tháng=${contextSnapshot.monthlyIncomeMinor}, '
          'Chi tháng=${contextSnapshot.monthlyExpenseMinor}, '
          'Mức an toàn/ngày=${contextSnapshot.safeDailyAllowanceMinor}, '
          'Lịch sắp tới=${contextSnapshot.upcomingEventsCount}, '
          'Việc đang mở=${contextSnapshot.openTasksCount}, '
          'Số thói quen theo dõi=${contextSnapshot.topHabitLabels.length}.';
    } else {
      final redactedHabits = contextSnapshot.topHabitLabels
          .map(OtpRedactor.redact)
          .join(', ');
      contextLine =
          '\nNgữ cảnh tóm tắt ẩn danh (VND nguyên): Thu tháng=${contextSnapshot.monthlyIncomeMinor}, '
          'Chi tháng=${contextSnapshot.monthlyExpenseMinor}, '
          'Mức an toàn/ngày=${contextSnapshot.safeDailyAllowanceMinor}, '
          'Lịch sắp tới=${contextSnapshot.upcomingEventsCount}, '
          'Việc đang mở=${contextSnapshot.openTasksCount}, '
          'Thói quen=$redactedHabits.';
    }

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
        '7. "waterLogs": Mảng lượng nước lọc uống vào cơ thể [{"waterMl":250}].';

    return (
      safeInput: safeInput,
      contextLine: contextLine,
      systemPrompt: systemPrompt,
    );
  }

  Future<
    ({
      String sanitizedPrompt,
      String assistantInsightVi,
      List<OmniActionDraft> drafts,
    })
  >
  generateMultiDomainPlan({
    String? userId,
    required String rawInput,
    required GeminiConnectionConfig config,
    required DateTime referenceNow,
    GeminiContextSnapshot? contextSnapshot,
  }) async {
    await _purgeLegacyUnscopedKeys();
    final storedConfig = await readConfig(userId: userId);
    if (!config.enabled || !storedConfig.enabled || !_cloudAiConsentGranted) {
      throw const AppException(
        code: 'GEMINI_CONSENT_REQUIRED',
        message:
            'Chưa bật đồng ý chia sẻ với Gemini Cloud; tiếp tục xử lý hoàn toàn trên máy.',
      );
    }

    final uid = _resolveUid(userId);
    final apiKey = uid != null
        ? (await _vault.readSecret(_apiKeyVaultKey(uid)) ?? '').trim()
        : '';
    if (apiKey.isEmpty) {
      throw const AppException(
        code: 'GEMINI_KEY_MISSING',
        message: 'Chưa cấu hình khóa Gemini API.',
      );
    }

    final prepared = buildSanitizedPromptPayload(
      rawInput: rawInput,
      maskSensitiveInfo: config.maskSensitiveInfo,
      referenceNow: referenceNow,
      contextSnapshot: contextSnapshot,
    );
    final safeInput = prepared.safeInput;
    final systemPrompt = prepared.systemPrompt;

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
        message:
            'Thiết bị đang ngoại tuyến; đã xử lý tức thì bằng AI Trên máy.',
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
      message:
          'Phản hồi từ Gemini trống; đã chuyển sang bộ phân tích Trên máy.',
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
        final merchant = ((item['merchant'] as String?) ?? '').trim().isNotEmpty
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
            (startsIso != null
                ? DateTime.tryParse(startsIso)?.toLocal()
                : null) ??
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
      400 ||
      401 ||
      403 => 'Khóa Gemini API chưa hợp lệ hoặc chưa được kích hoạt.',
      429 =>
        'Tạm chạm hạn mức gọi miễn phí của Gemini; hệ thống đã tự chuyển sang AI Trên máy.',
      >= 500 =>
        'Máy chủ Gemini đang bận; hệ thống đã tự chuyển sang AI Trên máy.',
      _ => 'Không thể gọi Gemini (mã $statusCode); đã dùng AI Trên máy.',
    };
  }
}
