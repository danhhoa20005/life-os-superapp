import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/utils/smart_omni_intent_parser.dart';
import '../../../../core/utils/vnd_amount.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../../transactions/presentation/bloc/transaction_bloc.dart';
import '../../domain/entities/financial_ai_entities.dart';
import '../../domain/entities/gemini_copilot_entities.dart';
import '../../domain/repositories/financial_ai_repository.dart';
import '../bloc/financial_ai_bloc.dart';
import '../bloc/gemini_copilot_bloc.dart';

B? _tryReadOptionalBloc<B extends StateStreamableSource<Object?>>(
  BuildContext context,
) {
  try {
    return context.read<B>();
  } catch (_) {
    return null;
  }
}

typedef _StandardCategorySpec = ({
  String id,
  String name,
  String direction,
  String semanticKey,
});

const List<_StandardCategorySpec> _kStandardLifeOsCategories = [
  (
    id: 'cat_food',
    name: 'Ăn uống',
    direction: 'debit',
    semanticKey: 'food.meals',
  ),
  (
    id: 'cat_vehicle',
    name: 'Xe cộ & Di chuyển',
    direction: 'debit',
    semanticKey: 'transport.ride_hailing',
  ),
  (
    id: 'cat_shopping',
    name: 'Chợ & Mua sắm',
    direction: 'debit',
    semanticKey: 'shopping.general',
  ),
  (
    id: 'cat_utilities',
    name: 'Điện/Nước/Internet',
    direction: 'debit',
    semanticKey: 'housing.utilities',
  ),
  (
    id: 'cat_housework',
    name: 'Việc nhà & Gia dụng',
    direction: 'debit',
    semanticKey: 'housing.housework',
  ),
  (
    id: 'cat_health',
    name: 'Sức khỏe & Giáo dục',
    direction: 'debit',
    semanticKey: 'health.medicine',
  ),
  (
    id: 'cat_entertainment',
    name: 'Giải trí & Đăng ký',
    direction: 'debit',
    semanticKey: 'entertainment',
  ),
  (
    id: 'cat_housing',
    name: 'Nhà cửa & Thuê nhà',
    direction: 'debit',
    semanticKey: 'housing.rent',
  ),
  (
    id: 'cat_family_social',
    name: 'Hiếu hỉ & Đối ngoại',
    direction: 'debit',
    semanticKey: 'gifts',
  ),
  (
    id: 'cat_vehicle_maint',
    name: 'Bảo dưỡng & Sửa xe',
    direction: 'debit',
    semanticKey: 'transport.maintenance',
  ),
  (
    id: 'cat_salary',
    name: 'Lương & Thu nhập',
    direction: 'credit',
    semanticKey: 'income.salary',
  ),
  (
    id: 'cat_other_exp',
    name: 'Chi tiêu khác',
    direction: 'debit',
    semanticKey: 'other',
  ),
];

String _inferSemanticKeyForCategory({
  required String categoryId,
  required String categoryName,
  required String direction,
}) {
  for (final spec in _kStandardLifeOsCategories) {
    if (spec.id == categoryId) return spec.semanticKey;
  }
  final lower = categoryName.toLowerCase();
  if (direction == 'credit' || lower.contains('lương')) return 'income.salary';
  if (lower.contains('ăn') || lower.contains('cà phê')) return 'food.meals';
  if (lower.contains('xe') || lower.contains('di chuyển')) {
    return 'transport.ride_hailing';
  }
  if (lower.contains('chợ') || lower.contains('mua sắm')) {
    return 'shopping.general';
  }
  if (lower.contains('điện') || lower.contains('nước')) {
    return 'housing.utilities';
  }
  if (lower.contains('việc nhà') || lower.contains('gia dụng')) {
    return 'housing.housework';
  }
  if (lower.contains('sức khỏe') || lower.contains('thuốc')) {
    return 'health.medicine';
  }
  if (lower.contains('giải trí')) return 'entertainment';
  if (lower.contains('nhà cửa') || lower.contains('thuê nhà')) {
    return 'housing.rent';
  }
  if (lower.contains('hiếu') || lower.contains('quà')) return 'gifts';
  return direction == 'credit' ? 'income.other' : 'other';
}

List<CategoryEntity> _buildSandboxCategoryPool(
  String userId,
  List<CategoryEntity>? existing,
) {
  final out = <CategoryEntity>[...(existing ?? const <CategoryEntity>[])];
  final knownIds = out.map((e) => e.id).toSet();
  for (final spec in _kStandardLifeOsCategories) {
    if (!knownIds.contains(spec.id)) {
      out.add(
        CategoryEntity(
          id: spec.id,
          ownerId: userId,
          name: spec.name,
          direction: spec.direction,
          iconKey: 'category',
        ),
      );
    }
  }
  return out;
}

/// Phase 16.3, Tầng A.2 & Gemini Connector — Agent Local Studio, Sandbox, Confidence Tuning & Opt-in Gemini AI Studio.
class FinancialAiSettingsPage extends StatelessWidget {
  const FinancialAiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EnsureGeminiCopilotScope(child: _FinancialAiSettingsView());
  }
}

class _FinancialAiSettingsView extends StatelessWidget {
  const _FinancialAiSettingsView();

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dateFmt = DateFormat('dd/MM/yyyy');

    return MultiBlocListener(
      listeners: [
        BlocListener<FinancialAiBloc, FinancialAiState>(
          listenWhen: (p, n) =>
              p.failure != n.failure || p.feedbackMessage != n.feedbackMessage,
          listener: (context, state) {
            if (state.failure != null) {
              LifeOsTopToast.show(
                context,
                state.failure!.message,
                kind: LifeOsToastKind.error,
              );
            } else if (state.feedbackMessage != null &&
                state.feedbackMessage!.isNotEmpty) {
              LifeOsTopToast.show(context, state.feedbackMessage!);
            }
          },
        ),
        BlocListener<GeminiCopilotBloc, GeminiCopilotState>(
          listenWhen: (p, n) =>
              p.failure != n.failure || p.feedbackMessage != n.feedbackMessage,
          listener: (context, gState) {
            if (gState.failure != null) {
              LifeOsTopToast.show(
                context,
                gState.failure!.message,
                kind: LifeOsToastKind.error,
              );
            } else if (gState.feedbackMessage != null &&
                gState.feedbackMessage!.isNotEmpty) {
              LifeOsTopToast.show(context, gState.feedbackMessage!);
            }
          },
        ),
      ],
      child: Scaffold(
        body: LifeOsMintWaveCanvas(
          child: SafeArea(
            child: Column(
              children: [
                const LifeOsTopBrandHeader(
                  title: 'Cài đặt AI & Liên kết Gemini',
                  showBackButton: true,
                ),
                Expanded(
                  child: BlocBuilder<FinancialAiBloc, FinancialAiState>(
                    builder: (context, state) {
                      final prefs =
                          state.preferences ??
                          UserAiClassificationPreferences(userId: user.id);
                      final meta = state.modelMetadata;
                      final rules = state.personalizationRules;

                      void updatePrefs(
                        UserAiClassificationPreferences nextPrefs,
                      ) {
                        context.read<FinancialAiBloc>().add(
                          FinancialAiPreferencesUpdated(nextPrefs),
                        );
                      }

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppSpacing.maxContentWidth,
                          ),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              6,
                              AppSpacing.md,
                              AppSpacing.xxl,
                            ),
                            children: [
                              // 1. Opt-in Gemini AI Connector Studio Card (Top Priority — Above the Fold at 360x800)
                              const _GeminiConnectionStudioCard(),
                              const SizedBox(height: 14),

                              // 2. Offline On-Device Agent Local Studio + Interactive Sandbox Card
                              _LocalAiEngineStudioCard(
                                userId: user.id,
                                meta: meta,
                                rulesCount: rules.length,
                              ),
                              const SizedBox(height: 14),

                              // 3. AI Classification, Confirmation & Confidence Threshold Policy
                              const LifeOsSectionHeader(
                                title: 'Chế độ Phân loại & Xác nhận',
                              ),
                              const SizedBox(height: 6),
                              LifeOsSoftCard(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SwitchListTile(
                                      key: const Key('toggle_ai_enabled'),
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Bật phân loại AI thông minh',
                                      ),
                                      subtitle: const Text(
                                        'Khi tắt, ứng dụng chỉ dùng bộ từ khóa cố định cơ bản',
                                      ),
                                      value: prefs.aiClassificationEnabled,
                                      onChanged: (v) => updatePrefs(
                                        prefs.copyWith(
                                          aiClassificationEnabled: v,
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 12),
                                    SwitchListTile(
                                      key: const Key(
                                        'toggle_personalization_enabled',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Học cá nhân hóa theo cửa hàng',
                                      ),
                                      subtitle: const Text(
                                        'Tự ghi nhớ khi bạn đổi danh mục (riêng tư cho từng tài khoản)',
                                      ),
                                      value: prefs.personalizationEnabled,
                                      onChanged: (v) => updatePrefs(
                                        prefs.copyWith(
                                          personalizationEnabled: v,
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 12),
                                    SwitchListTile(
                                      key: const Key(
                                        'toggle_bank_auto_classify',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Tự động gợi ý danh mục cho thông báo ngân hàng',
                                      ),
                                      subtitle: const Text(
                                        'Áp dụng cho nguồn thông báo ngân hàng đã được bạn cấp quyền',
                                      ),
                                      value:
                                          prefs.autoClassifyBankNotifications,
                                      onChanged: (v) => updatePrefs(
                                        prefs.copyWith(
                                          autoClassifyBankNotifications: v,
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 12),
                                    SwitchListTile(
                                      key: const Key(
                                        'toggle_require_confirm_before_save',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Luôn yêu cầu xác nhận trước khi ghi sổ',
                                      ),
                                      subtitle: const Text(
                                        'Khuyến nghị bật để đảm bảo an toàn tuyệt đối cho số dư ví',
                                      ),
                                      value:
                                          prefs.requireConfirmationBeforeSave,
                                      onChanged: (v) => updatePrefs(
                                        prefs.copyWith(
                                          requireConfirmationBeforeSave: v,
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 16),
                                    _ConfidenceThresholdSliderSection(
                                      prefs: prefs,
                                      onChanged: updatePrefs,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 4. Learned & Manual Personalization Rules Manager
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Text(
                                    'Quy tắc đã học từ bạn (${rules.length})',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      FilledButton.tonalIcon(
                                        key: const Key(
                                          'btn_add_manual_ai_rule',
                                        ),
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () =>
                                            _showAddManualRuleSheet(
                                              context,
                                              user.id,
                                            ),
                                        icon: const Icon(
                                          Icons.add_rounded,
                                          size: 18,
                                        ),
                                        label: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('Dạy quy tắc mới'),
                                        ),
                                      ),
                                      if (rules.isNotEmpty)
                                        TextButton.icon(
                                          key: const Key(
                                            'clear_all_ai_rules_btn',
                                          ),
                                          style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          onPressed: () => _confirmClearAll(
                                            context,
                                            user.id,
                                          ),
                                          icon: const Icon(
                                            Icons.delete_sweep_outlined,
                                            size: 18,
                                          ),
                                          label: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text('Xóa tất cả quy tắc'),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (rules.isEmpty)
                                LifeOsSoftCard(
                                  child: Text(
                                    'Chưa có quy tắc cá nhân hóa nào. Bấm "Dạy quy tắc mới" hoặc sửa danh mục của một cửa hàng (ví dụ: Circle K → Ăn uống) để Agent Local tự động ghi nhớ.',
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12.8,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                )
                              else
                                ...rules.map((rule) {
                                  final dirLabel = switch (
                                    rule.directionCondition
                                  ) {
                                    'credit' => ' · Chiều: Thu nhập',
                                    'debit' => ' · Chiều: Chi tiêu',
                                    _ => '',
                                  };
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LifeOsSoftCard(
                                      child: Row(
                                        children: [
                                          const LifeOsIconSquircle(
                                            icon: Icons.psychology_rounded,
                                            tone: LifeOsAccentTone.emerald,
                                            size: 40,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${rule.merchantDisplay} → ${rule.selectedCategoryName}',
                                                  softWrap: true,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                    color: c.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  'Đã xác nhận ${rule.confirmationCount} lần$dirLabel · Cập nhật ${dateFmt.format(rule.lastCorrectedAt)}',
                                                  softWrap: true,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.textSecondary,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            key: Key(
                                              'delete_ai_rule_${rule.id}',
                                            ),
                                            tooltip: 'Xóa quy tắc này',
                                            onPressed: () => context
                                                .read<FinancialAiBloc>()
                                                .add(
                                                  FinancialPersonalizationRuleDeleted(
                                                    userId: user.id,
                                                    ruleId: rule.id,
                                                  ),
                                                ),
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddManualRuleSheet(
    BuildContext context,
    String userId,
  ) async {
    final aiBloc = context.read<FinancialAiBloc>();
    final txCategories =
        _tryReadOptionalBloc<TransactionListBloc>(context)?.state.categories ??
        const <CategoryEntity>[];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _AddManualAiRuleSheet(
        userId: userId,
        aiBloc: aiBloc,
        userCategories: txCategories,
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context, String userId) async {
    final bloc = context.read<FinancialAiBloc>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa dữ liệu cá nhân hóa AI?'),
        content: const Text(
          'Toàn bộ quy tắc gợi ý danh mục theo cửa hàng đã học trên tài khoản này sẽ bị xóa. Các giao dịch lịch sử trong sổ cái hoàn toàn không bị ảnh hưởng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm_clear_all_ai_rules_dialog_btn'),
            onPressed: () {
              bloc.add(FinancialPersonalizationCleared(userId));
              Navigator.of(ctx).pop();
            },
            child: const Text('Xóa dữ liệu học'),
          ),
        ],
      ),
    );
  }
}

class _SandboxRunSummary {
  final String input;
  final int totalActionsCount;
  final int confidencePercent;
  final String latencyLabel;
  final bool matchedLearnedRule;
  final List<String> itemLines;

  const _SandboxRunSummary({
    required this.input,
    required this.totalActionsCount,
    required this.confidencePercent,
    required this.latencyLabel,
    required this.matchedLearnedRule,
    required this.itemLines,
  });
}

class _LocalAiEngineStudioCard extends StatefulWidget {
  final String userId;
  final FinancialModelMetadata meta;
  final int rulesCount;

  const _LocalAiEngineStudioCard({
    required this.userId,
    required this.meta,
    required this.rulesCount,
  });

  @override
  State<_LocalAiEngineStudioCard> createState() =>
      _LocalAiEngineStudioCardState();
}

class _LocalAiEngineStudioCardState extends State<_LocalAiEngineStudioCard> {
  final TextEditingController _sandboxCtrl = TextEditingController();
  bool _isRunning = false;
  _SandboxRunSummary? _lastSummary;

  static const List<(String label, String sample)> _quickSamples = [
    ('Ăn phở 45k, cf 25k', 'Ăn phở 45k, cf 25k'),
    ('Xăng 70k & họp 15h', 'Đổ xăng 70k, chiều mai 15h họp dự án'),
    ('Bún chả 45 cành', 'Ăn bún chả 45 cành và trà đá 5k'),
  ];

  @override
  void dispose() {
    _sandboxCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSandbox([String? presetSample]) async {
    if (_isRunning) return;
    final typed = (presetSample ?? _sandboxCtrl.text).trim();
    final sampleOrInput = typed.isEmpty ? 'Ăn phở 45k, cf 25k' : typed;
    if (presetSample != null || _sandboxCtrl.text.trim().isEmpty) {
      _sandboxCtrl.text = sampleOrInput;
      _sandboxCtrl.selection = TextSelection.collapsed(
        offset: sampleOrInput.length,
      );
    }

    setState(() => _isRunning = true);

    final txBloc = _tryReadOptionalBloc<TransactionListBloc>(context);
    final knownWallets = txBloc?.state.wallets;
    final sandboxCategories = _buildSandboxCategoryPool(
      widget.userId,
      txBloc?.state.categories,
    );

    FinancialAnalysisResult? finAnalysis;
    final sw = Stopwatch()..start();
    try {
      if (sl.isRegistered<FinancialAiRepository>()) {
        final res = await sl<FinancialAiRepository>().analyzeText(
          userId: widget.userId,
          text: sampleOrInput,
          knownWallets: knownWallets,
          knownCategories: sandboxCategories,
        );
        res.fold((_) {}, (ok) => finAnalysis = ok);
      }
      final omniDrafts = SmartOmniIntentParser.parseMulti(sampleOrInput);
      sw.stop();

      if (!mounted) return;

      final candidates =
          finAnalysis?.candidates ?? const <TransactionCandidate>[];
      final extraOmni = omniDrafts
          .where(
            (d) => candidates.isEmpty || d.kind != OmniActionKind.transaction,
          )
          .toList(growable: false);

      final totalCount = candidates.length + extraOmni.length;
      final elapsedMs = sw.elapsedMicroseconds / 1000.0;
      final latencyLabel = elapsedMs < 0.1
          ? '0.1 ms'
          : '${elapsedMs.toStringAsFixed(1)} ms';

      var confPct = 0;
      var matchedRule = false;
      final lines = <String>[];

      if (candidates.isNotEmpty) {
        final avgConf =
            candidates.fold<double>(
              0.0,
              (sum, c) => sum + c.confidence.categoryConfidence,
            ) /
            candidates.length;
        confPct = (avgConf * 100).round().clamp(1, 100);
        matchedRule = candidates.any(
          (c) => c.appliedPersonalizationRuleId != null,
        );
        for (final cand in candidates) {
          final itemConf = (cand.confidence.categoryConfidence * 100)
              .round()
              .clamp(1, 100);
          lines.add(
            '• ${cand.description} → ${cand.resolvedCategoryName} (${VndAmount.format(cand.amountMinor)} · $itemConf%)',
          );
        }
      } else if (extraOmni.isNotEmpty) {
        confPct = 90;
      }

      for (final omni in extraOmni) {
        lines.add('• ${omni.summaryLineVi}');
      }

      if (lines.isEmpty) {
        lines.add(
          finAnalysis?.nonTransactionReason ??
              'Chưa phát hiện số tiền hoặc tác vụ cụ thể trong câu thử.',
        );
      }

      setState(() {
        _isRunning = false;
        _lastSummary = _SandboxRunSummary(
          input: sampleOrInput,
          totalActionsCount: totalCount,
          confidencePercent: confPct,
          latencyLabel: latencyLabel,
          matchedLearnedRule: matchedRule,
          itemLines: lines,
        );
      });
    } catch (_) {
      sw.stop();
      if (!mounted) return;
      setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final meta = widget.meta;
    final runtimeLabel = meta.isNativeFfiActive
        ? 'Native C++17 FFI'
        : (meta.usingRuleFallback
              ? 'Deterministic Rules'
              : 'Dart Worker Isolate INT8');

    return LifeOsMintHeroCard(
      key: const Key('local_ai_engine_studio_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.memory_rounded, color: c.primary, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Mô hình AI Trên Thiết bị (Agent Local)',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 15.2,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const LifeOsStatusPill(
                icon: Icons.bolt_rounded,
                label: 'Offline · < 2ms',
                tone: LifeOsAccentTone.emerald,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _TabularMetricChip(
                icon: Icons.category_outlined,
                label: '${meta.numClasses} nhóm ngữ nghĩa',
              ),
              _TabularMetricChip(
                icon: Icons.psychology_outlined,
                label: '${widget.rulesCount} quy tắc tự học',
              ),
              const _TabularMetricChip(
                icon: Icons.shield_outlined,
                label: 'Độc lập 100% trên máy',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'Phòng thử nghiệm nhanh',
                softWrap: true,
                style: TextStyle(
                  fontSize: 13.2,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              FilledButton.tonalIcon(
                key: const Key('local_ai_sandbox_run_btn'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _isRunning ? null : () => _runSandbox(),
                icon: _isRunning
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Thử ngay'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _quickSamples.length; i++)
                ActionChip(
                  key: Key('local_ai_sandbox_sample_$i'),
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    _quickSamples[i].$1,
                    style: const TextStyle(
                      fontSize: 11.6,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  onPressed: _isRunning
                      ? null
                      : () => _runSandbox(_quickSamples[i].$2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('local_ai_sandbox_input'),
            controller: _sandboxCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _runSandbox(),
            style: TextStyle(fontSize: 13.5, color: c.textPrimary),
            decoration: InputDecoration(
              hintText: 'VD: Phở 45k, cf 25k',
              hintStyle: TextStyle(fontSize: 12.8, color: c.textSecondary),
              hintMaxLines: 2,
              isDense: true,
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          if (_lastSummary != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('local_ai_sandbox_result'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border.withValues(alpha: 0.75)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _TabularMetricChip(
                        icon: Icons.check_circle_outline_rounded,
                        label:
                            'Bóc tách: ${_lastSummary!.totalActionsCount} tác vụ',
                        highlight: true,
                      ),
                      if (_lastSummary!.confidencePercent > 0)
                        _TabularMetricChip(
                          icon: Icons.verified_outlined,
                          label:
                              'Độ tin cậy: ${_lastSummary!.confidencePercent}%',
                        ),
                      _TabularMetricChip(
                        icon: Icons.timer_outlined,
                        label: 'Độ trễ: ${_lastSummary!.latencyLabel}',
                      ),
                      if (_lastSummary!.matchedLearnedRule)
                        const _TabularMetricChip(
                          icon: Icons.psychology_rounded,
                          label: 'Đã khớp quy tắc tự học',
                          highlight: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final line in _lastSummary!.itemLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        line,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.4,
                          height: 1.32,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          LifeOsDetailsDiscloseSection(
            toggleKey: const Key('toggle_local_ai_model_details'),
            label: 'Chi tiết thông số mô hình',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.76),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border.withValues(alpha: 0.65)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ModelSpecLine(
                    text:
                        'Mã mô hình: ${meta.modelId} (v${meta.modelVersion})',
                  ),
                  _ModelSpecLine(text: 'Kiến trúc: ${meta.architecture}'),
                  _ModelSpecLine(
                    text:
                        'Dung lượng: ${(meta.sizeBytes / 1024).toStringAsFixed(0)} KB',
                  ),
                  _ModelSpecLine(text: 'Chế độ thực thi: $runtimeLabel'),
                  _ModelSpecLine(
                    text:
                        'Nhiệt độ hiệu chuẩn: ${meta.calibratedTemperature.toStringAsFixed(2)}',
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabularMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;

  const _TabularMetricChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: highlight ? c.primarySubtle : c.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: highlight
              ? c.primary.withValues(alpha: 0.35)
              : c.border.withValues(alpha: 0.65),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13.5,
            color: highlight ? c.primary : c.textSecondary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                color: highlight ? c.primary : c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelSpecLine extends StatelessWidget {
  final String text;
  final bool isLast;

  const _ModelSpecLine({required this.text, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
      child: Text(
        text,
        softWrap: true,
        style: TextStyle(
          fontSize: 12,
          height: 1.32,
          color: c.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ConfidenceThresholdSliderSection extends StatefulWidget {
  final UserAiClassificationPreferences prefs;
  final ValueChanged<UserAiClassificationPreferences> onChanged;

  const _ConfidenceThresholdSliderSection({
    required this.prefs,
    required this.onChanged,
  });

  @override
  State<_ConfidenceThresholdSliderSection> createState() =>
      _ConfidenceThresholdSliderSectionState();
}

class _ConfidenceThresholdSliderSectionState
    extends State<_ConfidenceThresholdSliderSection> {
  late double _liveValue;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _liveValue = widget.prefs.minAutoSuggestConfidence.clamp(0.35, 0.85);
  }

  @override
  void didUpdateWidget(covariant _ConfidenceThresholdSliderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging &&
        oldWidget.prefs.minAutoSuggestConfidence !=
            widget.prefs.minAutoSuggestConfidence) {
      _liveValue = widget.prefs.minAutoSuggestConfidence.clamp(0.35, 0.85);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final pct = (_liveValue * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              'Ngưỡng tự tin gợi ý tự động',
              softWrap: true,
              style: TextStyle(
                fontSize: 14.2,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.primarySubtle,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 12.4,
                  fontWeight: FontWeight.w800,
                  color: c.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tự động chọn sẵn danh mục khi độ tin cậy đạt từ $pct% trở lên (mặc định 52%).',
          softWrap: true,
          style: TextStyle(
            fontSize: 12.2,
            color: c.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Slider(
          key: const Key('local_ai_confidence_slider'),
          value: _liveValue,
          min: 0.35,
          max: 0.85,
          divisions: 10,
          label: '$pct%',
          onChangeStart: (_) => setState(() => _isDragging = true),
          onChanged: (val) {
            setState(() => _liveValue = val.clamp(0.35, 0.85));
          },
          onChangeEnd: (val) {
            final clamped = val.clamp(0.35, 0.85);
            setState(() {
              _isDragging = false;
              _liveValue = clamped;
            });
            widget.onChanged(
              widget.prefs.copyWith(minAutoSuggestConfidence: clamped),
            );
          },
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              '35% · Linh hoạt',
              style: TextStyle(
                fontSize: 11.4,
                color: c.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              '85% · Khắt khe',
              style: TextStyle(
                fontSize: 11.4,
                color: c.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AddManualAiRuleSheet extends StatefulWidget {
  final String userId;
  final FinancialAiBloc aiBloc;
  final List<CategoryEntity> userCategories;

  const _AddManualAiRuleSheet({
    required this.userId,
    required this.aiBloc,
    required this.userCategories,
  });

  @override
  State<_AddManualAiRuleSheet> createState() => _AddManualAiRuleSheetState();
}

class _AddManualAiRuleSheetState extends State<_AddManualAiRuleSheet> {
  final TextEditingController _keywordCtrl = TextEditingController();
  String _direction = 'debit';
  late String _selectedCategoryId;

  static const List<String> _merchantExamples = [
    'Circle K',
    'Xanh SM',
    'ShopeeFood',
    'Highlands',
  ];

  List<_StandardCategorySpec> get _availableCategories {
    if (widget.userCategories.isNotEmpty) {
      final mapped = widget.userCategories
          .map(
            (cat) => (
              id: cat.id,
              name: cat.name,
              direction: cat.direction,
              semanticKey: _inferSemanticKeyForCategory(
                categoryId: cat.id,
                categoryName: cat.name,
                direction: cat.direction,
              ),
            ),
          )
          .toList(growable: false);
      if (_direction == 'any') return mapped;
      final filtered = mapped
          .where((c) => c.direction == _direction)
          .toList(growable: false);
      if (filtered.isNotEmpty) return filtered;
      return mapped;
    }

    if (_direction == 'any') return _kStandardLifeOsCategories;
    final filtered = _kStandardLifeOsCategories
        .where((c) => c.direction == _direction)
        .toList(growable: false);
    return filtered.isNotEmpty ? filtered : _kStandardLifeOsCategories;
  }

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = _availableCategories.first.id;
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  void _syncSelectedCategoryWithDirection() {
    final options = _availableCategories;
    if (!options.any((c) => c.id == _selectedCategoryId)) {
      _selectedCategoryId = options.first.id;
    }
  }

  void _submitRule() {
    final kw = _keywordCtrl.text.trim();
    if (kw.length < 2) {
      LifeOsTopToast.show(
        context,
        'Vui lòng nhập tên cửa hàng hoặc từ khóa tối thiểu 2 ký tự.',
        kind: LifeOsToastKind.warning,
      );
      return;
    }
    final options = _availableCategories;
    final chosen = options.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => options.first,
    );

    widget.aiBloc.add(
      FinancialPersonalizationRuleAdded(
        userId: widget.userId,
        merchantKeyword: kw,
        selectedCategoryId: chosen.id,
        selectedCategoryName: chosen.name,
        semanticKey: chosen.semanticKey,
        directionCondition: _direction,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final options = _availableCategories;
    final activeCategoryId = options.any((item) => item.id == _selectedCategoryId)
        ? _selectedCategoryId
        : options.first.id;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: LiquidGlassSheetFrame(
        showHandle: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Dạy quy tắc mới cho Agent Local',
                softWrap: true,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tự động gán đúng danh mục ngay trên thiết bị mỗi khi gặp tên cửa hàng hoặc từ khóa này.',
                softWrap: true,
                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('manual_rule_keyword_input'),
                controller: _keywordCtrl,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitRule(),
                decoration: const InputDecoration(
                  labelText: 'Tên cửa hàng / Từ khóa',
                  hintText: 'VD: Circle K, Xanh SM, ShopeeFood, Highlands',
                  hintMaxLines: 2,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _merchantExamples.map((sample) {
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      sample,
                      style: const TextStyle(fontSize: 11.8),
                    ),
                    onPressed: () {
                      setState(() {
                        _keywordCtrl.text = sample;
                        _keywordCtrl.selection = TextSelection.collapsed(
                          offset: sample.length,
                        );
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text(
                'Chiều giao dịch áp dụng',
                style: TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              LifeOsSegmentedPills<String>(
                key: const Key('manual_rule_direction_selector'),
                selected: _direction,
                onChanged: (nextDir) {
                  setState(() {
                    _direction = nextDir;
                    _syncSelectedCategoryWithDirection();
                  });
                },
                options: const [
                  ('debit', 'Chi tiêu', Icons.north_east_rounded),
                  ('credit', 'Thu nhập', Icons.south_west_rounded),
                  ('any', 'Mọi chiều', Icons.swap_vert_rounded),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('manual_rule_category_dropdown'),
                isExpanded: true,
                initialValue: activeCategoryId,
                decoration: const InputDecoration(
                  labelText: 'Danh mục đích',
                  isDense: true,
                ),
                items: options
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(item.name),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedCategoryId = val);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Hủy'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      key: const Key('btn_save_manual_ai_rule'),
                      onPressed: _submitRule,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Lưu quy tắc'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeminiConnectionStudioCard extends StatefulWidget {
  const _GeminiConnectionStudioCard();

  @override
  State<_GeminiConnectionStudioCard> createState() =>
      _GeminiConnectionStudioCardState();
}

class _GeminiConnectionStudioCardState
    extends State<_GeminiConnectionStudioCard> {
  final TextEditingController _apiKeyCtrl = TextEditingController();
  bool _obscureKey = true;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final timeFmt = DateFormat('HH:mm dd/MM');

    return BlocBuilder<GeminiCopilotBloc, GeminiCopilotState>(
      builder: (context, gState) {
        final cfg = gState.config;
        final isVerifying =
            gState.status == GeminiCopilotStatus.verifyingConnection;
        final bloc = context.read<GeminiCopilotBloc>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LifeOsSectionHeader(
              title: 'Liên kết Gemini AI (Tùy chọn Mở rộng)',
              tone: LifeOsAccentTone.blue,
            ),
            const SizedBox(height: 6),
            LifeOsSoftCard(
              key: const Key('gemini_connection_studio_card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 20,
                            color: cfg.isReadyForCloud
                                ? c.primary
                                : c.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Trợ lý Đa tác vụ Gemini',
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      LifeOsStatusPill(
                        icon: cfg.isReadyForCloud
                            ? Icons.check_circle_outline_rounded
                            : Icons.offline_bolt_outlined,
                        label: cfg.isReadyForCloud
                            ? 'Đã nối Gemini'
                            : 'Chạy 100% Trên máy',
                        tone: cfg.isReadyForCloud
                            ? LifeOsAccentTone.emerald
                            : LifeOsAccentTone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Bóc tách câu ghép đa tác vụ (Thu chi · Lịch hẹn · Việc làm · Đi chợ) và cố vấn chi tiêu thông minh.',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.4,
                      height: 1.35,
                      color: c.textSecondary,
                    ),
                  ),
                  if (cfg.hasApiKey) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('toggle_gemini_enabled'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bật chế độ kết hợp Gemini AI'),
                      subtitle: Text(
                        cfg.lastVerifiedAt != null
                            ? 'Đã lưu khóa kết nối · Kiểm tra lúc ${timeFmt.format(cfg.lastVerifiedAt!)}'
                            : 'Đã lưu khóa kết nối trên thiết bị',
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      value: cfg.enabled,
                      onChanged: (v) => bloc.add(
                        GeminiConnectionSettingsSaved(enabled: v),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('gemini_api_key_input'),
                    controller: _apiKeyCtrl,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'Mã Gemini',
                      hintText: 'Dán mã kết nối',
                      hintMaxLines: 2,
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: _obscureKey ? 'Hiện mã' : 'Ẩn mã',
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: const Key('gemini_model_dropdown'),
                    isExpanded: true,
                    initialValue: GeminiModelPreset.fromId(cfg.modelId).modelId,
                    decoration: const InputDecoration(
                      labelText: 'Phiên bản Gemini',
                      isDense: true,
                    ),
                    items: GeminiModelPreset.values
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.modelId,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(m.labelVi),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        bloc.add(GeminiConnectionSettingsSaved(modelId: val));
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    key: const Key('toggle_gemini_mask_pii'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Ẩn số điện thoại, email & số tài khoản',
                    ),
                    subtitle: const Text(
                      'Tự động che thông tin định danh cá nhân trước khi phân tích',
                    ),
                    value: cfg.maskSensitiveInfo,
                    onChanged: (v) => bloc.add(
                      GeminiConnectionSettingsSaved(maskSensitiveInfo: v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const Key('btn_verify_gemini_connection'),
                        onPressed: isVerifying
                            ? null
                            : () {
                                final typed = _apiKeyCtrl.text.trim();
                                bloc.add(
                                  GeminiConnectionTestRequested(
                                    candidateApiKey: typed.isEmpty
                                        ? null
                                        : typed,
                                    modelId: cfg.modelId,
                                  ),
                                );
                                if (typed.isNotEmpty) {
                                  _apiKeyCtrl.clear();
                                }
                              },
                        icon: isVerifying
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bolt_rounded, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isVerifying
                                ? 'Đang kiểm tra...'
                                : 'Lưu & Kiểm tra kết nối',
                          ),
                        ),
                      ),
                      if (cfg.hasApiKey)
                        OutlinedButton.icon(
                          key: const Key('btn_disconnect_gemini'),
                          onPressed: isVerifying
                              ? null
                              : () {
                                  _apiKeyCtrl.clear();
                                  bloc.add(
                                    const GeminiConnectionDisconnected(),
                                  );
                                },
                          icon: const Icon(Icons.link_off_rounded, size: 17),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Ngắt liên kết'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
