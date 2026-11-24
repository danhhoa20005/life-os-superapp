import '../../../../core/error/app_exception.dart';
import '../entities/gemini_copilot_entities.dart';

abstract interface class GeminiCopilotRepository {
  Future<Result<GeminiConnectionConfig>> loadConfig();

  Future<Result<GeminiConnectionConfig>> saveConnectionSettings({
    String? newApiKey,
    bool? enabled,
    String? modelId,
    bool? maskSensitiveInfo,
  });

  Future<Result<GeminiConnectionConfig>> disconnectAndClearKey();

  Future<Result<String>> verifyConnection({
    String? candidateApiKey,
    String? modelId,
  });

  Future<Result<GeminiHybridAnalysisResult>> analyzeHybridOmniCommand({
    required String rawInput,
    GeminiContextSnapshot? contextSnapshot,
    DateTime? referenceTime,
    bool forceGeminiIfConfigured = true,
  });
}
