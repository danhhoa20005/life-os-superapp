import '../../features/family/domain/entities/family_entities.dart';
import 'smart_omni_intent_parser.dart';
import 'voice_financial_nlp_engine.dart';

enum VoiceReadinessStage {
  idle,
  speakingIncomplete,
  readyComplete,
}

class VoiceUtteranceEvaluation {
  final VoiceReadinessStage stage;
  final VoiceFinancialAnalysisResult? financialAnalysis;
  final List<OmniActionDraft> omniDrafts;
  final List<BlockedClauseInfo> blockedClauses;
  final List<OmniActionDraft> queryDrafts;
  final bool hasDanglingConnector;
  final Duration silenceAutoStopDelay;
  final String liveStatusVi;
  final String confirmationBadgeVi;

  const VoiceUtteranceEvaluation({
    required this.stage,
    required this.financialAnalysis,
    required this.omniDrafts,
    this.blockedClauses = const <BlockedClauseInfo>[],
    this.queryDrafts = const <OmniActionDraft>[],
    required this.hasDanglingConnector,
    required this.silenceAutoStopDelay,
    required this.liveStatusVi,
    required this.confirmationBadgeVi,
  });

  List<OmniActionDraft> get nonFinancialOmniDrafts => omniDrafts
      .where(
        (d) =>
            d.kind != OmniActionKind.transaction &&
            d.kind != OmniActionKind.groupSplit,
      )
      .toList();

  bool get hasInvalidSplit {
    final gs = financialAnalysis?.groupSplit;
    if (gs != null && !gs.isValid) return true;
    final rec = financialAnalysis?.multiCategoryReceipt;
    if (rec != null && !rec.isValid) return true;
    return false;
  }

  bool get hasActionableDraft =>
      financialAnalysis != null || omniDrafts.isNotEmpty;

  bool get isReadyComplete => stage == VoiceReadinessStage.readyComplete;
}

/// Evaluates streaming Vietnamese speech in `< 1ms` on-device to detect
/// whether the speaker is mid-sentence or has uttered a complete, valid command,
/// driving smart auto-endpointing and structured confirmation review.
abstract final class VoiceUtteranceEvaluator {
  /// Trailing connectors/prepositions indicating the speaker is still mid-clause.
  static final RegExp _danglingTailRegex = RegExp(
    r'\b(?:và|với|cùng|rồi|thêm|hoặc|chia|chia cho|chia đều|chia đều cho|gồm|'
    r'gồm có|lúc|vào|vào lúc|hết|mất|giá|khoảng|tầm|từ|sang|cho|ở|tại|'
    r'nhắc|uống|mua|ăn|đổ|chuyển|nhận)$',
    caseSensitive: false,
    unicode: true,
  );

  /// Bare number at the very end waiting for unit (`"55"`, `"450"`, `"1"`, `"2"`)
  /// where the speaker might still be about to say `"nghìn"` / `"triệu"` / `"ml"` / `"giờ"`.
  static final RegExp _bareSmallDigitsTailRegex = RegExp(
    r'(?:^|\s)\d{1,3}$',
  );

  static VoiceUtteranceEvaluation evaluate(
    String rawTranscript, {
    required String currentUserId,
    required String currentUserName,
    List<FamilyMemberInfo> knownMembers = const <FamilyMemberInfo>[],
    Map<String, List<String>> nicknamesByUserId =
        const <String, List<String>>{},
    Map<String, String> explicitParticipantOverrides = const <String, String>{},
  }) {
    final trimmed = rawTranscript
        .trim()
        .replaceAll(RegExp(r'[,.;:!?…]+$'), '')
        .trim();

    if (trimmed.isEmpty) {
      return const VoiceUtteranceEvaluation(
        stage: VoiceReadinessStage.idle,
        financialAnalysis: null,
        omniDrafts: <OmniActionDraft>[],
        hasDanglingConnector: false,
        silenceAutoStopDelay: Duration(milliseconds: 2400),
        liveStatusVi: 'Đang thu âm... Hãy nói tự nhiên',
        confirmationBadgeVi: 'Chưa có nội dung giọng nói',
      );
    }

    final hasDangling = _danglingTailRegex.hasMatch(trimmed);
    final endsWithBareSmallNumber = _bareSmallDigitsTailRegex.hasMatch(trimmed);

    final finAnalysis = VoiceFinancialNlpEngine.analyze(
      trimmed,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      knownMembers: knownMembers,
      nicknamesByUserId: nicknamesByUserId,
      explicitParticipantOverrides: explicitParticipantOverrides,
    );
    final omniEnvelope = SmartOmniIntentParser.parseDetailed(trimmed);
    final omniDrafts = omniEnvelope.drafts;

    final hasStructuredIntent = finAnalysis != null || omniDrafts.isNotEmpty;
    final splitWarning =
        finAnalysis?.groupSplit?.validationMessageVi ??
        finAnalysis?.multiCategoryReceipt?.validationMessageVi;
    final hasInvalidSplit =
        (finAnalysis?.groupSplit != null && !finAnalysis!.groupSplit!.isValid) ||
        (finAnalysis?.multiCategoryReceipt != null &&
            !finAnalysis!.multiCategoryReceipt!.isValid);

    if (hasInvalidSplit && splitWarning != null) {
      return VoiceUtteranceEvaluation(
        stage: VoiceReadinessStage.speakingIncomplete,
        financialAnalysis: finAnalysis,
        omniDrafts: omniDrafts,
        blockedClauses: omniEnvelope.blockedClauses,
        queryDrafts: omniEnvelope.queryDrafts,
        hasDanglingConnector: hasDangling,
        silenceAutoStopDelay: const Duration(milliseconds: 1400),
        liveStatusVi: 'Cần kiểm tra lại số tiền/thành viên chia nhóm...',
        confirmationBadgeVi: '⚠ $splitWarning',
      );
    }

    if (hasStructuredIntent && !hasDangling && !endsWithBareSmallNumber) {
      return VoiceUtteranceEvaluation(
        stage: VoiceReadinessStage.readyComplete,
        financialAnalysis: finAnalysis,
        omniDrafts: omniDrafts,
        blockedClauses: omniEnvelope.blockedClauses,
        queryDrafts: omniEnvelope.queryDrafts,
        hasDanglingConnector: false,
        silenceAutoStopDelay: const Duration(milliseconds: 850),
        liveStatusVi: '✓ Đã nhận diện chuẩn — ngưng nói để chuyển sang xác nhận',
        confirmationBadgeVi: '✓ Đã nhận diện chuẩn — Mời bạn xác nhận',
      );
    }

    // If ends with bare small digits (e.g. "Ăn phở 55"), wait slightly longer (~1.4s)
    // in case speaker is still adding "nghìn" / "triệu" / "ml", while still keeping parsed preview ready!
    if (hasStructuredIntent && !hasDangling && endsWithBareSmallNumber) {
      return VoiceUtteranceEvaluation(
        stage: VoiceReadinessStage.speakingIncomplete,
        financialAnalysis: finAnalysis,
        omniDrafts: omniDrafts,
        blockedClauses: omniEnvelope.blockedClauses,
        queryDrafts: omniEnvelope.queryDrafts,
        hasDanglingConnector: false,
        silenceAutoStopDelay: const Duration(milliseconds: 1450),
        liveStatusVi: 'Đang chờ đơn vị (nghìn / triệu / giờ)...',
        confirmationBadgeVi: '✓ Đã nhận diện — Kiểm tra lại số lượng trước khi lưu',
      );
    }

    final blockedNote = omniEnvelope.blockedClauses.isNotEmpty
        ? '⚠ ${omniEnvelope.blockedClauses.first.reasonVi}'
        : null;

    return VoiceUtteranceEvaluation(
      stage: VoiceReadinessStage.speakingIncomplete,
      financialAnalysis: finAnalysis,
      omniDrafts: omniDrafts,
      blockedClauses: omniEnvelope.blockedClauses,
      queryDrafts: omniEnvelope.queryDrafts,
      hasDanglingConnector: hasDangling,
      silenceAutoStopDelay: const Duration(milliseconds: 2200),
      liveStatusVi: hasDangling
          ? 'Đang nghe tiếp vế sau...'
          : 'Đang nghe thêm số tiền hoặc thời gian...',
      confirmationBadgeVi: hasStructuredIntent
          ? '✓ Kiểm tra lại nội dung trước khi lưu'
          : (blockedNote ??
                '⚠ Chưa rõ số tiền / thời gian — bấm Nói lại hoặc sửa nhanh'),
    );
  }
}
