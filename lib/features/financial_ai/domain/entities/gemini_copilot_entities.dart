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
