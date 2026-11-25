import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/smart_omni_intent_parser.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../domain/entities/financial_ai_entities.dart';
import '../../domain/entities/gemini_copilot_entities.dart';
import '../../domain/repositories/gemini_copilot_repository.dart';
import '../../domain/services/financial_classifier.dart';
import '../datasources/financial_ai_local_sync_datasource.dart';
import '../datasources/gemini_remote_datasource.dart';
import '../inference/taxonomy_catalog.dart';
import '../normalization/financial_text_normalizer.dart';

class GeminiCopilotRepositoryImpl implements GeminiCopilotRepository {
  final GeminiRemoteDataSource _remote;
  final FinancialClassifier? _localClassifier;
  final FinancialAiLocalSyncDataSource? _localSync;
  final FinancialTextNormalizer? _normalizer;
  final FirebaseAuth? _firebaseAuth;

  const GeminiCopilotRepositoryImpl(
    this._remote, {
    FinancialClassifier? localClassifier,
    FinancialAiLocalSyncDataSource? localSync,
    FinancialTextNormalizer? normalizer,
    FirebaseAuth? firebaseAuth,
  }) : _localClassifier = localClassifier,
       _localSync = localSync,
       _normalizer = normalizer,
       _firebaseAuth = firebaseAuth;

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
    final rawOfflineDrafts = SmartOmniIntentParser.parseMulti(
      trimmed,
      now: refNow,
    );

    final config = await _remote.readConfig();
    final gateDecision = SmartHybridGate.evaluate(
      rawInput: trimmed,
      localDrafts: rawOfflineDrafts,
      config: config,
      allowCloudIfConfigured: forceGeminiIfConfigured,
    );
    if (gateDecision.shouldUseCloud && config.isReadyForCloud) {
      try {
        final cloudRes = await _remote.generateMultiDomainPlan(
          rawInput: trimmed,
          config: config,
          referenceNow: refNow,
          contextSnapshot: contextSnapshot,
        );

        // Preserve any non-financial offline drafts if cloud returned empty on an actionable command
        final resolvedDrafts = cloudRes.drafts.isNotEmpty
            ? cloudRes.drafts
            : await _enrichOfflineDrafts(rawOfflineDrafts);
        sw.stop();

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
        final enrichedOffline = await _enrichOfflineDrafts(rawOfflineDrafts);
        sw.stop();
        return Success(
          GeminiHybridAnalysisResult(
            originalInput: trimmed,
            usedGeminiCloud: false,
            usedOfflineFallback: true,
            fallbackNoticeVi: e.message,
            assistantInsightVi: _buildOfflineCoachingVi(
              enrichedOffline,
              contextSnapshot,
            ),
            actionDrafts: enrichedOffline,
            latencyMs: sw.elapsedMilliseconds,
          ),
        );
      } catch (_) {
        final enrichedOffline = await _enrichOfflineDrafts(rawOfflineDrafts);
        sw.stop();
        return Success(
          GeminiHybridAnalysisResult(
            originalInput: trimmed,
            usedGeminiCloud: false,
            usedOfflineFallback: true,
            fallbackNoticeVi:
                'Tạm gián đoạn kết nối mạng; hệ thống đã xử lý an toàn trên máy.',
            assistantInsightVi: _buildOfflineCoachingVi(
              enrichedOffline,
              contextSnapshot,
            ),
            actionDrafts: enrichedOffline,
            latencyMs: sw.elapsedMilliseconds,
          ),
        );
      }
    }

    final enrichedOffline = await _enrichOfflineDrafts(rawOfflineDrafts);
    sw.stop();
    return Success(
      GeminiHybridAnalysisResult(
        originalInput: trimmed,
        usedGeminiCloud: false,
        usedOfflineFallback: false,
        assistantInsightVi: _buildOfflineCoachingVi(
          enrichedOffline,
          contextSnapshot,
        ),
        actionDrafts: enrichedOffline,
        latencyMs: sw.elapsedMilliseconds,
      ),
    );
  }

  Future<List<OmniActionDraft>> _enrichOfflineDrafts(
    List<OmniActionDraft> drafts,
  ) async {
    if (drafts.isEmpty) return drafts;
    if (!drafts.any((d) => d.kind == OmniActionKind.transaction)) {
      return drafts;
    }

    UserAiClassificationPreferences? prefs;
    List<PersonalizationRule> rules = const <PersonalizationRule>[];
    final userId = _firebaseAuth?.currentUser?.uid;
    final localSync = _localSync;
    if (localSync != null && userId != null && userId.isNotEmpty) {
      try {
        prefs = await localSync.getPreferences(userId);
        if (prefs.personalizationEnabled) {
          rules = await localSync.getRulesForUser(userId);
        }
      } catch (_) {}
    }

    final classifier = _localClassifier;
    final canClassify =
        classifier != null && (prefs == null || prefs.aiClassificationEnabled);
    var classifierInitialized = false;
    final norm = _normalizer ?? FinancialTextNormalizer();

    final enriched = <OmniActionDraft>[];
    for (final d in drafts) {
      if (d.kind != OmniActionKind.transaction) {
        enriched.add(d);
        continue;
      }

      final expectedDirection = d.transactionKind == TransactionKind.income
          ? 'credit'
          : 'debit';
      var matchedPersonalRule = false;

      // 1. User-scoped PersonalizationRule match
      if (rules.isNotEmpty && (prefs?.personalizationEnabled ?? false)) {
        final canonKey = FinancialTextNormalizer.canonicalizeMerchant(d.title);
        if (canonKey != null && canonKey.isNotEmpty) {
          for (final rule in rules) {
            if (rule.matchesContext(
                  canonicalKey: canonKey,
                  direction: expectedDirection,
                  source: FinancialInputSource.manualText,
                  amountMinor: d.amountMinor,
                ) &&
                rule.selectedCategoryId.isNotEmpty &&
                rule.selectedCategoryName.isNotEmpty) {
              enriched.add(
                d.copyWith(
                  categoryId: rule.selectedCategoryId,
                  categoryName: rule.selectedCategoryName,
                  sourceWalletHint:
                      d.sourceWalletHint ??
                      rule.preferredWalletName ??
                      rule.preferredWalletId,
                ),
              );
              matchedPersonalRule = true;
              break;
            }
          }
        }
      }
      if (matchedPersonalRule) continue;

      // 2. Neural FastText INT8 classifier enrichment when category is generic 'other'
      if (canClassify &&
          (d.categoryId == 'cat_other_exp' || d.categoryId == 'cat_other_inc')) {
        try {
          if (!classifierInitialized) {
            await classifier.initialize();
            classifierInitialized = true;
          }
          final clsInput = norm.toClassifierInput(d.title);
          if (clsInput.isNotEmpty) {
            final clsRes = await classifier.classify(clsInput);
            if (!clsRes.isOutOfDomain) {
              final minConf = prefs?.minAutoSuggestConfidence ?? 0.45;
              SemanticCategorySpec? matchedSpec;
              var matchedProb = 0.0;
              for (final pred in clsRes.predictions) {
                if (pred.isOutOfDomain) continue;
                final spec = FinancialTaxonomyCatalog.specs
                    .where(
                      (s) =>
                          s.semanticKey == pred.semanticKey &&
                          s.direction == expectedDirection,
                    )
                    .firstOrNull;
                if (spec != null) {
                  matchedSpec = spec;
                  matchedProb = pred.probability;
                  break;
                }
              }
              if (matchedSpec != null && matchedProb >= minConf) {
                enriched.add(
                  OmniActionDraft(
                    id: d.id,
                    kind: d.kind,
                    title: d.title,
                    amountMinor: d.amountMinor,
                    transactionKind: d.transactionKind,
                    categoryId: matchedSpec.defaultSystemCategoryIdHint,
                    categoryName: matchedSpec.defaultSystemCategoryName,
                    participantCount: d.participantCount,
                    participantNames: d.participantNames,
                    scheduledAt: d.scheduledAt,
                    durationMinutes: d.durationMinutes,
                    location: d.location,
                    taskPriority: d.taskPriority,
                    quantityLabel: d.quantityLabel,
                    waterMl: d.waterMl,
                    medicationSlot: d.medicationSlot,
                    dosage: d.dosage,
                    originLabel: d.originLabel,
                  ),
                );
                continue;
              }
            }
          }
        } catch (_) {
          // Preserve deterministic offline draft if classifier throws
        }
      }

      enriched.add(d);
    }

    return enriched;
  }

  String _buildOfflineCoachingVi(
    List<OmniActionDraft> drafts,
    GeminiContextSnapshot? snap,
  ) {
    if (drafts.isEmpty) {
      if (snap != null && snap.safeDailyAllowanceMinor > 0) {
        final parts = <String>[
          'Hạn mức chi tiêu an toàn hôm nay là ${VndAmount.format(snap.safeDailyAllowanceMinor)}/ngày.',
        ];
        if (snap.monthlyIncomeMinor > 0 || snap.monthlyExpenseMinor > 0) {
          parts.add(
            'Tổng quan tháng: thu ${VndAmount.format(snap.monthlyIncomeMinor)}, chi ${VndAmount.format(snap.monthlyExpenseMinor)}.',
          );
        }
        if (snap.openTasksCount > 0) {
          parts.add('Đang có ${snap.openTasksCount} việc cần hoàn thành.');
        }
        return parts.join(' ');
      }
      if (snap != null && snap.openTasksCount > 0) {
        return 'Cố vấn nội bộ sẵn sàng trên thiết bị (đang mở ${snap.openTasksCount} việc). Hãy nhập câu kèm số tiền, lịch hẹn hoặc việc cần làm.';
      }
      return 'Cố vấn nội bộ đang hoạt động tức thì trên thiết bị. Hãy nhập câu kèm số tiền, lịch hẹn hoặc việc cần làm.';
    }

    final totalSpend = drafts.fold<int>(0, (sum, d) {
      if (d.kind == OmniActionKind.transaction &&
          d.transactionKind == TransactionKind.expense &&
          d.amountMinor > 0) {
        return sum + d.amountMinor;
      }
      if (d.kind == OmniActionKind.groupSplit && d.perPersonShareMinor > 0) {
        return sum + d.perPersonShareMinor;
      }
      return sum;
    });

    final totalIncome = drafts
        .where(
          (d) =>
              d.kind == OmniActionKind.transaction &&
              d.transactionKind == TransactionKind.income &&
              d.amountMinor > 0,
        )
        .fold<int>(0, (sum, d) => sum + d.amountMinor);

    final kindsCount = drafts.map((d) => d.kind).toSet().length;
    final totalsSummary = _formatDraftTotalsParen(
      totalSpend: totalSpend,
      totalIncome: totalIncome,
    );

    if (snap != null &&
        snap.safeDailyAllowanceMinor > 0 &&
        totalSpend > snap.safeDailyAllowanceMinor) {
      final overMinor = totalSpend - snap.safeDailyAllowanceMinor;
      if (kindsCount >= 2 || drafts.length >= 2) {
        return 'Đã bóc tách ${drafts.length} mục$totalsSummary — vượt hạn mức ngày an toàn (${VndAmount.format(snap.safeDailyAllowanceMinor)}/ngày) đúng ${VndAmount.format(overMinor)}; hãy kiểm tra trước khi xác nhận.';
      }
      return 'Khoản chi ${VndAmount.format(totalSpend)} vượt hạn mức ngày an toàn (${VndAmount.format(snap.safeDailyAllowanceMinor)}/ngày) đúng ${VndAmount.format(overMinor)}; hãy cân nhắc trước khi xác nhận.';
    }

    if (snap != null &&
        snap.safeDailyAllowanceMinor > 0 &&
        totalSpend > 0 &&
        totalSpend <= snap.safeDailyAllowanceMinor) {
      final remainingMinor = snap.safeDailyAllowanceMinor - totalSpend;
      if (kindsCount >= 2) {
        return 'Đã bóc tách ${drafts.length} mục đa miền$totalsSummary. Bạn vẫn còn dư ${VndAmount.format(remainingMinor)} trong hạn mức an toàn hôm nay — bấm Xác nhận để lưu.';
      }
      if (drafts.length >= 2) {
        return 'Đã bóc tách ${drafts.length} mục$totalsSummary. Bạn vẫn còn dư ${VndAmount.format(remainingMinor)} trong hạn mức an toàn hôm nay — bấm Xác nhận để lưu.';
      }
      return 'Nhịp chi tiêu tốt! Sau khoản ${VndAmount.format(totalSpend)}, bạn vẫn còn dư ${VndAmount.format(remainingMinor)} trong hạn mức an toàn hôm nay (${VndAmount.format(snap.safeDailyAllowanceMinor)}/ngày).';
    }

    if (kindsCount >= 2) {
      return 'Đã tự động bóc tách ${drafts.length} mục đa miền$totalsSummary trên thiết bị — bấm Xác nhận để lưu ngay.';
    }
    if (drafts.length >= 2) {
      return 'Đã bóc tách ${drafts.length} mục$totalsSummary trên thiết bị — bấm Xác nhận để lưu ngay.';
    }
    if (totalIncome > 0) {
      return 'Đã nhận diện khoản thu ${VndAmount.format(totalIncome)} trên thiết bị — bấm Xác nhận để lưu ngay.';
    }
    return 'Đã nhận diện sẵn ${drafts.length} mục trên thiết bị — chạm Xác nhận để lưu ngay.';
  }

  String _formatDraftTotalsParen({
    required int totalSpend,
    required int totalIncome,
  }) {
    final parts = <String>[];
    if (totalSpend > 0) {
      parts.add('tổng chi ${VndAmount.format(totalSpend)}');
    }
    if (totalIncome > 0) {
      parts.add('tổng thu ${VndAmount.format(totalIncome)}');
    }
    if (parts.isEmpty) return '';
    return ' (${parts.join(' · ')})';
  }
}
