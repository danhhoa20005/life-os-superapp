import 'package:equatable/equatable.dart';

import '../../../../core/utils/smart_omni_intent_parser.dart';

enum GeminiModelPreset {
  flash25('gemini-2.5-flash', 'Gemini 2.5 Flash · Phản hồi tức thì'),
  pro25('gemini-2.5-pro', 'Gemini 2.5 Pro · Phân tích chuyên sâu');

  final String modelId;
  final String labelVi;
  const GeminiModelPreset(this.modelId, this.labelVi);

  static GeminiModelPreset fromId(String? id) {
    return GeminiModelPreset.values.firstWhere(
      (m) => m.modelId == id,
      orElse: () => GeminiModelPreset.flash25,
    );
  }
}

class GeminiConnectionConfig extends Equatable {
  final bool enabled;
  final bool hasApiKey;
  final String maskedApiKey;
  final String modelId;
  final bool maskSensitiveInfo;
  final DateTime? lastVerifiedAt;

  const GeminiConnectionConfig({
    this.enabled = false,
    this.hasApiKey = false,
    this.maskedApiKey = '',
    this.modelId = 'gemini-2.5-flash',
    this.maskSensitiveInfo = true,
    this.lastVerifiedAt,
  });

  bool get isReadyForCloud => enabled && hasApiKey;

  GeminiConnectionConfig copyWith({
    bool? enabled,
    bool? hasApiKey,
    String? maskedApiKey,
    String? modelId,
    bool? maskSensitiveInfo,
    DateTime? lastVerifiedAt,
    bool clearVerifiedAt = false,
  }) {
    return GeminiConnectionConfig(
      enabled: enabled ?? this.enabled,
      hasApiKey: hasApiKey ?? this.hasApiKey,
      maskedApiKey: maskedApiKey ?? this.maskedApiKey,
      modelId: modelId ?? this.modelId,
      maskSensitiveInfo: maskSensitiveInfo ?? this.maskSensitiveInfo,
      lastVerifiedAt: clearVerifiedAt
          ? null
          : (lastVerifiedAt ?? this.lastVerifiedAt),
    );
  }

  static String maskKey(String rawKey) {
    final trimmed = rawKey.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 8) return '••••••••';
    return '${trimmed.substring(0, 4)}••••${trimmed.substring(trimmed.length - 4)}';
  }

  @override
  List<Object?> get props => [
    enabled,
    hasApiKey,
    maskedApiKey,
    modelId,
    maskSensitiveInfo,
    lastVerifiedAt,
  ];
}

/// Optional anonymized behavioral & financial snapshot so Gemini can offer grounded coaching
/// without exposing personal identifiers.
class GeminiContextSnapshot extends Equatable {
  final int monthlyIncomeMinor;
  final int monthlyExpenseMinor;
  final int safeDailyAllowanceMinor;
  final int upcomingEventsCount;
  final int openTasksCount;
  final List<String> topHabitLabels;

  const GeminiContextSnapshot({
    this.monthlyIncomeMinor = 0,
    this.monthlyExpenseMinor = 0,
    this.safeDailyAllowanceMinor = 0,
    this.upcomingEventsCount = 0,
    this.openTasksCount = 0,
    this.topHabitLabels = const <String>[],
  });

  @override
  List<Object?> get props => [
    monthlyIncomeMinor,
    monthlyExpenseMinor,
    safeDailyAllowanceMinor,
    upcomingEventsCount,
    openTasksCount,
    topHabitLabels,
  ];
}

class GeminiHybridAnalysisResult extends Equatable {
  final String originalInput;
  final String? sanitizedPromptSent;
  final bool usedGeminiCloud;
  final bool usedOfflineFallback;
  final String? fallbackNoticeVi;
  final String assistantInsightVi;
  final List<OmniActionDraft> actionDrafts;
  final int latencyMs;

  const GeminiHybridAnalysisResult({
    required this.originalInput,
    this.sanitizedPromptSent,
    required this.usedGeminiCloud,
    this.usedOfflineFallback = false,
    this.fallbackNoticeVi,
    required this.assistantInsightVi,
    required this.actionDrafts,
    this.latencyMs = 0,
  });

  GeminiHybridAnalysisResult copyWith({
    List<OmniActionDraft>? actionDrafts,
    String? assistantInsightVi,
  }) {
    return GeminiHybridAnalysisResult(
      originalInput: originalInput,
      sanitizedPromptSent: sanitizedPromptSent,
      usedGeminiCloud: usedGeminiCloud,
      usedOfflineFallback: usedOfflineFallback,
      fallbackNoticeVi: fallbackNoticeVi,
      assistantInsightVi: assistantInsightVi ?? this.assistantInsightVi,
      actionDrafts: actionDrafts ?? this.actionDrafts,
      latencyMs: latencyMs,
    );
  }

  @override
  List<Object?> get props => [
    originalInput,
    sanitizedPromptSent,
    usedGeminiCloud,
    usedOfflineFallback,
    fallbackNoticeVi,
    assistantInsightVi,
    actionDrafts,
    latencyMs,
  ];
}

enum SmartHybridRoute { localOnly, cloudGemini }

class SmartHybridDecision extends Equatable {
  final SmartHybridRoute route;
  final String reasonVi;
  final bool hasComplexMultiIntent;
  final bool hasAdvisoryOrQuestion;

  const SmartHybridDecision({
    required this.route,
    required this.reasonVi,
    this.hasComplexMultiIntent = false,
    this.hasAdvisoryOrQuestion = false,
  });

  bool get shouldUseCloud => route == SmartHybridRoute.cloudGemini;

  @override
  List<Object?> get props => [
    route,
    reasonVi,
    hasComplexMultiIntent,
    hasAdvisoryOrQuestion,
  ];
}

/// Section 16 Hybrid Routing Policy:
/// - Default Local AI (`< 5ms`) for straightforward single-intent utterances or when Gemini is off.
/// - Escalates to opt-in Gemini Cloud ONLY when user enabled + provided API key AND input
///   is an advisory/financial question, complex multi-intent, or unparsed locally.
abstract final class SmartHybridGate {
  static final RegExp _advisoryOrQuestionRegex = RegExp(
    r'(?:\?|\b(?:tư\s+vấn|tu\s+van|có\s+nên|co\s+nen|nên\s+hay|bao\s+nhiêu|bao\s+nhieu|phân\s+tích|phan\s+tich|kế\s+hoạch|ke\s+hoach|so\s+sánh|so\s+sanh|tối\s+ưu|toi\s+uu|gợi\s+ý|goi\s+y|nhận\s+xét|nhan\s+xet|đánh\s+giá|danh\s+gia|cố\s+vấn|co\s+van)\b)',
    caseSensitive: false,
    unicode: true,
  );

  static SmartHybridDecision evaluate({
    required String rawInput,
    required GeminiConnectionConfig config,
    required List<OmniActionDraft> localDrafts,
    bool allowCloudIfConfigured = true,
  }) {
    if (!allowCloudIfConfigured || !config.isReadyForCloud) {
      return const SmartHybridDecision(
        route: SmartHybridRoute.localOnly,
        reasonVi:
            'Xử lý hoàn toàn trên máy (< 5ms) — chưa bật hoặc chưa liên kết Gemini Cloud.',
      );
    }

    final trimmed = rawInput.trim();
    final isAdvisory = _advisoryOrQuestionRegex.hasMatch(trimmed);
    final isMultiIntent = localDrafts.length >= 2;
    final hasMultipleConnectors = RegExp(
      r'[,;\n]|\s+(?:và|rồi)\s+',
      caseSensitive: false,
    ).allMatches(trimmed).isNotEmpty;
    final unparsedLocally = localDrafts.isEmpty;

    if (isAdvisory ||
        isMultiIntent ||
        unparsedLocally ||
        hasMultipleConnectors) {
      return SmartHybridDecision(
        route: SmartHybridRoute.cloudGemini,
        reasonVi: isAdvisory
            ? 'Câu hỏi tư vấn / phân tích chuyên sâu — kết hợp Gemini Cloud đã che PII.'
            : (unparsedLocally
                  ? 'Câu nói tự nhiên chưa khớp mẫu cục bộ — nhờ Gemini Cloud bóc tách an toàn.'
                  : 'Câu ghép đa tác vụ — kết hợp Gemini Cloud để chuẩn hóa đa miền.'),
        hasComplexMultiIntent: isMultiIntent || hasMultipleConnectors,
        hasAdvisoryOrQuestion: isAdvisory,
      );
    }

    return const SmartHybridDecision(
      route: SmartHybridRoute.localOnly,
      reasonVi:
          'Câu lệnh đơn rõ ràng — AI trên máy đã xử lý tức thì (< 5ms) mà không cần gọi Gemini.',
    );
  }
}
