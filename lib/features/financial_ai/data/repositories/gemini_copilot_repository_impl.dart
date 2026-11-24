import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/smart_omni_intent_parser.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../domain/entities/gemini_copilot_entities.dart';
import '../../domain/repositories/gemini_copilot_repository.dart';
import '../datasources/gemini_remote_datasource.dart';

class GeminiCopilotRepositoryImpl implements GeminiCopilotRepository {
  final GeminiRemoteDataSource _remote;

  const GeminiCopilotRepositoryImpl(this._remote);

  @override
  Future<Result<GeminiConnectionConfig>> loadConfig() async {
    try {
      final cfg = await _remote.readConfig();
      return Success(cfg);
    } catch (_) {
      return const Err(
        UnexpectedFailure(message: 'Không thể đọc cấu hình kết nối Gemini.'),
      );
    }
  }

  @override
  Future<Result<GeminiConnectionConfig>> saveConnectionSettings({
    String? newApiKey,
    bool? enabled,
    String? modelId,
    bool? maskSensitiveInfo,
  }) async {
    try {
      final updated = await _remote.writeConfig(
        newApiKey: newApiKey,
        enabled: enabled,
        modelId: modelId,
        maskSensitiveInfo: maskSensitiveInfo,
      );
      return Success(updated);
    } catch (_) {
      return const Err(
        UnexpectedFailure(message: 'Không thể lưu cài đặt kết nối Gemini.'),
      );
    }
  }

  @override
  Future<Result<GeminiConnectionConfig>> disconnectAndClearKey() async {
    try {
      final cleared = await _remote.clearKeyAndDisable();
      return Success(cleared);
    } catch (_) {
      return const Err(
        UnexpectedFailure(message: 'Không thể xóa khóa kết nối Gemini.'),
      );
    }
  }

  @override
  Future<Result<String>> verifyConnection({
    String? candidateApiKey,
    String? modelId,
  }) async {
    try {
      final msg = await _remote.verifyConnection(
        candidateApiKey: candidateApiKey,
        modelId: modelId,
      );
      return Success(msg);
    } on AppException catch (e) {
      if (e.code == 'GEMINI_KEY_MISSING' || e.code.startsWith('GEMINI_HTTP_4')) {
        return Err(ValidationFailure(message: e.message, code: e.code));
      }
      return Err(NetworkFailure(message: e.message, code: e.code));
    } catch (_) {
      return const Err(
        NetworkFailure(
          message: 'Không thể kiểm tra kết nối Gemini lúc này.',
        ),
      );
    }
  }

  @override
  Future<Result<GeminiHybridAnalysisResult>> analyzeHybridOmniCommand({
    required String rawInput,
    GeminiContextSnapshot? contextSnapshot,
    DateTime? referenceTime,
    bool forceGeminiIfConfigured = true,
  }) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const Err(
        ValidationFailure(message: 'Hãy nhập câu lệnh hoặc câu hỏi cần phân tích.'),
      );
    }

    final sw = Stopwatch()..start();
    final refNow = referenceTime ?? DateTime.now();

    // Tier 1: Instant `< 2ms` Offline Omni-Intent Parser
    final offlineDrafts = SmartOmniIntentParser.parseMulti(
      trimmed,
      now: refNow,
    );

    final config = await _remote.readConfig();
    if (forceGeminiIfConfigured && config.isReadyForCloud) {
      try {
        final cloudRes = await _remote.generateMultiDomainPlan(
          rawInput: trimmed,
          config: config,
          referenceNow: refNow,
          contextSnapshot: contextSnapshot,
        );
        sw.stop();

        // Preserve any non-financial offline drafts if cloud returned empty on an actionable command
        final resolvedDrafts = cloudRes.drafts.isNotEmpty
            ? cloudRes.drafts
            : offlineDrafts;

        return Success(
          GeminiHybridAnalysisResult(
            originalInput: trimmed,
            sanitizedPromptSent: cloudRes.sanitizedPrompt,
            usedGeminiCloud: true,
            usedOfflineFallback: false,
            assistantInsightVi: cloudRes.assistantInsightVi,
            actionDrafts: resolvedDrafts,
            latencyMs: sw.elapsedMilliseconds,
          ),
        );
      } on AppException catch (e) {
        sw.stop();
        return Success(
          GeminiHybridAnalysisResult(
            originalInput: trimmed,
            usedGeminiCloud: false,
            usedOfflineFallback: true,
            fallbackNoticeVi: e.message,
            assistantInsightVi: _buildOfflineCoachingVi(
              offlineDrafts,
              contextSnapshot,
            ),
            actionDrafts: offlineDrafts,
            latencyMs: sw.elapsedMilliseconds,
          ),
        );
      } catch (_) {
        sw.stop();
        return Success(
          GeminiHybridAnalysisResult(
            originalInput: trimmed,
            usedGeminiCloud: false,
            usedOfflineFallback: true,
            fallbackNoticeVi:
                'Tạm gián đoạn kết nối mạng; hệ thống đã xử lý an toàn trên máy.',
            assistantInsightVi: _buildOfflineCoachingVi(
              offlineDrafts,
              contextSnapshot,
            ),
            actionDrafts: offlineDrafts,
            latencyMs: sw.elapsedMilliseconds,
          ),
        );
      }
    }

    sw.stop();
    return Success(
      GeminiHybridAnalysisResult(
        originalInput: trimmed,
        usedGeminiCloud: false,
        usedOfflineFallback: false,
        assistantInsightVi: _buildOfflineCoachingVi(
          offlineDrafts,
          contextSnapshot,
        ),
        actionDrafts: offlineDrafts,
        latencyMs: sw.elapsedMilliseconds,
      ),
    );
  }

  String _buildOfflineCoachingVi(
    List<OmniActionDraft> drafts,
    GeminiContextSnapshot? snap,
  ) {
    if (drafts.isEmpty) {
      if (snap != null && snap.safeDailyAllowanceMinor > 0) {
        return 'Nhịp chi tiêu an toàn hôm nay của bạn là ${VndAmount.format(snap.safeDailyAllowanceMinor)}/ngày. Bạn có thể liên kết Gemini AI trong Cài đặt để trò chuyện sâu hơn.';
      }
      return 'Chế độ Trên máy đang hoạt động tức thì. Hãy nhập câu kèm số tiền, lịch hẹn hoặc việc cần làm.';
    }

    final totalSpend = drafts
        .where((d) => d.kind == OmniActionKind.transaction && d.amountMinor > 0)
        .fold<int>(0, (s, d) => s + d.amountMinor);

    if (snap != null &&
        snap.safeDailyAllowanceMinor > 0 &&
        totalSpend > snap.safeDailyAllowanceMinor) {
      return 'Khoản này (${VndAmount.format(totalSpend)}) cao hơn nhịp an toàn mỗi ngày (${VndAmount.format(snap.safeDailyAllowanceMinor)}); hãy kiểm tra trước khi lưu.';
    }

    final kindsCount = drafts.map((d) => d.kind).toSet().length;
    if (kindsCount >= 2) {
      return 'Đã tự động bóc tách ${drafts.length} tác vụ liên thông (Tài chính · Lịch · Việc làm) chỉ từ một câu!';
    }
    return 'Đã nhận diện sẵn ${drafts.length} mục trên thiết bị — chạm Xác nhận để lưu ngay.';
  }
}
